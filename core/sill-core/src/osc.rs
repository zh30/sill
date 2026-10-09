//! Streaming OSC scanner — a read-only tee on the PTY byte stream.
//!
//! Chrome feeds raw PTY output through `OscScanner::feed` *before* it reaches
//! the VT core; nothing is consumed or rewritten. Runs off the render thread
//! (NFR-P9); callers throttle UI refreshes to ≥ 250ms.
//!
//! Coverage (PRD FR-009): 7501 program status (primary), 133 A/B/C/D command
//! marks, 7 cwd, 8 links, 9/99/777 notifications, 9;4 progress, 52 clipboard.
//! Unknown OSC code points and unknown 7501 keys are ignored — never an error,
//! never a dropped stream byte.

use crate::state::{BlockKind, StateKind, StatusRecord};
use base64::Engine as _;
use serde::Serialize;

/// One structured event emitted from the byte stream.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum OscEvent {
    /// OSC 7501 program status.
    Status {
        state: StateKind,
        #[serde(skip_serializing_if = "Option::is_none")]
        id: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        app: Option<String>,
        #[serde(skip_serializing_if = "Option::is_none")]
        kind: Option<BlockKind>,
        #[serde(skip_serializing_if = "Option::is_none")]
        msg: Option<String>,
    },
    /// OSC 133 command boundary mark.
    CommandMark {
        mark: CommandMark,
        exit_code: Option<i32>,
    },
    /// OSC 7 — current working directory (file:// URL decoded).
    Cwd(String),
    /// OSC 8 — hyperlink.
    Link { uri: String },
    /// OSC 9 / 99 / 777 — notification text.
    Notify { body: String, source: NotifySource },
    /// OSC 9;4 — progress (ConEmu/iTerm2 style).
    Progress {
        state: ProgressKind,
        percent: Option<u8>,
    },
    /// OSC 52 — clipboard write attempt (default off, gated by config).
    ClipboardWrite,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum CommandMark {
    /// A — prompt start.
    PromptStart,
    /// B — command start (input region).
    CommandStart,
    /// C — pre-execution (command sent, output begins).
    PreExec,
    /// D — command finished (carries exit code).
    Done,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum NotifySource {
    Osc9,
    Osc99,
    Osc777,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ProgressKind {
    Clear,
    Set,
    Error,
    Indeterminate,
}

/// Streaming scanner. Feed arbitrary chunks; sequences may split anywhere.
/// An over-long or malformed sequence abandons its buffer and resyncs on the
/// next `ESC ]` — the stream itself is never harmed.
pub struct OscScanner {
    buf: Vec<u8>,
    in_seq: bool,
    /// A feed ended on a bare `ESC` — the next feed's first byte decides
    /// whether it was an `ESC ]` introducer split across chunks.
    pending_esc: bool,
    /// Guard against unbounded sequences (binary dumps, hostile streams).
    max_seq: usize,
}

impl Default for OscScanner {
    fn default() -> Self {
        Self::new()
    }
}

impl OscScanner {
    const MAX_SEQ: usize = 64 * 1024;

    pub fn new() -> Self {
        Self {
            buf: Vec::with_capacity(512),
            in_seq: false,
            pending_esc: false,
            max_seq: Self::MAX_SEQ,
        }
    }

    /// Feed PTY bytes; returns the OSC events completed by this chunk.
    pub fn feed(&mut self, data: &[u8]) -> Vec<OscEvent> {
        let mut out = Vec::new();
        let mut i = 0;
        // A previous chunk ended on bare ESC: ']' now means an introducer.
        if self.pending_esc {
            self.pending_esc = false;
            if data.first() == Some(&b']') {
                self.in_seq = true;
                self.buf.clear();
                i = 1;
            }
        }
        while i < data.len() {
            if !self.in_seq {
                // Look for ESC ] introducer (also accept 0x9d C1 OSC, which
                // terminals translate to ESC ] before this layer anyway).
                if data[i] == 0x1b {
                    if i + 1 < data.len() {
                        if data[i + 1] == b']' {
                            self.in_seq = true;
                            self.buf.clear();
                            i += 2;
                            continue;
                        }
                        // ESC + anything else: stray — drop it.
                        i += 1;
                        continue;
                    }
                    // Trailing ESC: maybe half an introducer — hold it.
                    self.pending_esc = true;
                    i += 1;
                    continue;
                }
                if data[i] == 0x9d {
                    self.in_seq = true;
                    self.buf.clear();
                    i += 1;
                    continue;
                }
                i += 1;
            } else {
                let b = data[i];
                if b == 0x07 {
                    // BEL terminator.
                    self.finish(&mut out);
                    i += 1;
                } else if b == 0x1b {
                    // ST (ESC \) or a stray ESC: if followed by '\' finish,
                    // otherwise abandon this sequence and re-scan from here.
                    if i + 1 < data.len() && data[i + 1] == b'\\' {
                        self.finish(&mut out);
                        i += 2;
                    } else if i + 1 == data.len() {
                        // Split terminator: keep state, decide next feed.
                        self.buf.push(b);
                        i += 1;
                    } else {
                        self.abandon();
                        // do not advance — re-examine this ESC as a possible
                        // new sequence start.
                    }
                } else {
                    // A pending split ESC inside a sequence: '\' ends it (ST),
                    // anything else abandons it — ']' starts a fresh sequence.
                    if self.buf.last() == Some(&0x1b) {
                        self.buf.pop();
                        if b == b'\\' {
                            self.finish(&mut out);
                            i += 1;
                            continue;
                        }
                        self.abandon();
                        if b == b']' {
                            self.in_seq = true;
                            self.buf.clear();
                        }
                        i += 1;
                        continue;
                    }
                    self.buf.push(b);
                    i += 1;
                    if self.buf.len() > self.max_seq {
                        self.abandon();
                    }
                }
            }
        }
        out
    }

    fn finish(&mut self, out: &mut Vec<OscEvent>) {
        let payload = std::mem::take(&mut self.buf);
        self.in_seq = false;
        if let Some(ev) = parse_osc(&payload) {
            out.push(ev);
        }
    }

    fn abandon(&mut self) {
        self.buf.clear();
        self.in_seq = false;
    }
}

/// Parse a complete OSC payload (the bytes between `ESC ]` and ST).
fn parse_osc(payload: &[u8]) -> Option<OscEvent> {
    let text = std::str::from_utf8(payload).ok()?;
    let (code, rest) = match text.find(';') {
        Some(p) => (&text[..p], &text[p + 1..]),
        None => (text, ""),
    };
    match code {
        "7501" => parse_7501(rest),
        "133" => parse_133(rest),
        "7" => Some(OscEvent::Cwd(decode_file_url(rest))),
        "8" => {
            // 8 ; params ; uri — take the uri after the last ';'.
            let uri = rest.rsplit(';').next().unwrap_or(rest);
            if uri.is_empty() {
                None // 8;; — link end marker
            } else {
                Some(OscEvent::Link {
                    uri: uri.to_string(),
                })
            }
        }
        "9" => {
            if let Some(p94) = rest.strip_prefix("4;") {
                parse_94_progress(p94)
            } else {
                Some(OscEvent::Notify {
                    body: rest.to_string(),
                    source: NotifySource::Osc9,
                })
            }
        }
        "99" | "777" => {
            let source = if code == "99" {
                NotifySource::Osc99
            } else {
                NotifySource::Osc777
            };
            let body = rest.rsplit(';').next().unwrap_or(rest).to_string();
            Some(OscEvent::Notify { body, source })
        }
        "52" => Some(OscEvent::ClipboardWrite),
        _ => None, // unknown OSC — ignored by contract
    }
}

/// 7501 payload: `key=value:key=value…`, `state` required.
fn parse_7501(rest: &str) -> Option<OscEvent> {
    let mut state: Option<StateKind> = None;
    let mut id = None;
    let mut app = None;
    let mut kind = None;
    let mut msg = None;
    for pair in rest.split(':') {
        let (k, v) = match pair.split_once('=') {
            Some(kv) => kv,
            None => continue, // malformed pair — skip it, keep parsing
        };
        match k {
            "state" => state = StateKind::parse(v),
            "id" => id = Some(v.to_string()),
            "app" => app = Some(v.to_string()),
            "kind" => kind = BlockKind::parse(v),
            "msg" => {
                // Bad base64 → drop msg, keep everything else (FR-008).
                msg = base64::engine::general_purpose::STANDARD
                    .decode(v)
                    .ok()
                    .and_then(|b| String::from_utf8(b).ok())
            }
            _ => {} // unknown key — ignored, never an error
        }
    }
    // `state` is required: a 7501 sequence without it is dropped entirely.
    state.map(|state| OscEvent::Status {
        state,
        id,
        app,
        kind,
        msg,
    })
}

/// OSC 133: `A`/`B`/`C` prompt+command marks, `D;exitcode`.
fn parse_133(rest: &str) -> Option<OscEvent> {
    let (mark, params) = match rest.find(';') {
        Some(p) => (&rest[..p], &rest[p + 1..]),
        None => (rest, ""),
    };
    let mark = match mark {
        "A" => CommandMark::PromptStart,
        "B" => CommandMark::CommandStart,
        "C" => CommandMark::PreExec,
        "D" => {
            let exit_code = params
                .split(';')
                .find_map(|kv| kv.strip_prefix("exitcode=").and_then(|v| v.parse().ok()));
            return Some(OscEvent::CommandMark {
                mark: CommandMark::Done,
                exit_code,
            });
        }
        _ => return None, // P/S/etc. — not part of the P0 surface
    };
    Some(OscEvent::CommandMark {
        mark,
        exit_code: None,
    })
}

/// OSC 9;4: `st ; pr` — progress state and percent.
fn parse_94_progress(rest: &str) -> Option<OscEvent> {
    let mut it = rest.split(';');
    let st = it.next()?.parse::<u8>().ok()?;
    let percent = it
        .next()
        .and_then(|v| v.parse::<u8>().ok())
        .filter(|p| *p <= 100);
    let state = match st {
        0 => ProgressKind::Clear,
        1 => ProgressKind::Set,
        2 => ProgressKind::Error,
        3 => ProgressKind::Indeterminate,
        _ => return None,
    };
    Some(OscEvent::Progress { state, percent })
}

/// OSC 7 carries `file://host/path`; strip scheme+host, percent-decode.
fn decode_file_url(url: &str) -> String {
    let path = url
        .strip_prefix("file://")
        .and_then(|s| s.find('/').map(|i| &s[i..]))
        .unwrap_or(url);
    percent_decode(path.as_bytes())
}

fn percent_decode(b: &[u8]) -> String {
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() + 1 && i + 2 < b.len() {
            if let Ok(v) =
                u8::from_str_radix(std::str::from_utf8(&b[i + 1..i + 3]).unwrap_or(""), 16)
            {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(b[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

/// Convenience: turn a parsed 7501 event into a store-ready record.
impl OscEvent {
    pub fn status_record(&self) -> Option<StatusRecord> {
        match self {
            OscEvent::Status {
                state,
                app,
                kind,
                msg,
                ..
            } => Some(StatusRecord {
                state: *state,
                app: app.clone(),
                kind: *kind,
                msg: msg.clone(),
                source: Some("osc7501".into()),
            }),
            _ => None,
        }
    }

    pub fn status_id(&self) -> Option<&str> {
        match self {
            OscEvent::Status { id, .. } => id.as_deref(),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn feed_all(s: &mut OscScanner, chunks: &[&[u8]]) -> Vec<OscEvent> {
        chunks.iter().flat_map(|c| s.feed(c)).collect()
    }

    #[test]
    fn parses_7501_bel_and_st() {
        let mut s = OscScanner::new();
        let evs = feed_all(
            &mut s,
            &[
                b"\x1b]7501;state=working:app=claude-code\x07",
                b"\x1b]7501;state=blocked:kind=permission:app=claude-code\x1b\\",
            ],
        );
        assert_eq!(evs.len(), 2);
        assert!(matches!(
            evs[0],
            OscEvent::Status {
                state: StateKind::Working,
                ..
            }
        ));
        match &evs[1] {
            OscEvent::Status {
                state, kind, app, ..
            } => {
                assert_eq!(*state, StateKind::Blocked);
                assert_eq!(*kind, Some(BlockKind::Permission));
                assert_eq!(app.as_deref(), Some("claude-code"));
            }
            _ => panic!(),
        }
    }

    #[test]
    fn drops_7501_without_state() {
        let mut s = OscScanner::new();
        let evs = s.feed(b"\x1b]7501;app=x:kind=permission\x07");
        assert!(evs.is_empty());
    }

    #[test]
    fn ignores_unknown_keys_and_unknown_osc() {
        let mut s = OscScanner::new();
        let evs = feed_all(
            &mut s,
            &[
                b"\x1b]7501;state=idle:future_key=z\x07",
                b"\x1b]4242;whatever\x07",
            ],
        );
        assert_eq!(evs.len(), 1);
        assert!(matches!(
            evs[0],
            OscEvent::Status {
                state: StateKind::Idle,
                ..
            }
        ));
    }

    #[test]
    fn bad_msg_base64_keeps_state() {
        let mut s = OscScanner::new();
        let evs = s.feed(b"\x1b]7501;state=done:msg=!!!notb64\x07");
        match &evs[0] {
            OscEvent::Status { state, msg, .. } => {
                assert_eq!(*state, StateKind::Done);
                assert!(msg.is_none());
            }
            _ => panic!(),
        }
    }

    #[test]
    fn split_esc_bracket_across_feeds() {
        // "ESC" | "]7501;…" — the introducer itself split across chunks.
        let mut s = OscScanner::new();
        assert!(s.feed(b"prompt \x1b").is_empty());
        let evs = s.feed(b"]7501;state=blocked\x07");
        assert_eq!(evs.len(), 1);
        assert!(matches!(
            evs[0],
            OscEvent::Status {
                state: StateKind::Blocked,
                ..
            }
        ));
        // …and a trailing ESC that was NOT an introducer must not eat input.
        let mut s2 = OscScanner::new();
        assert!(s2.feed(b"abc\x1b").is_empty());
        assert!(s2.feed(b"[31m").is_empty());
    }

    #[test]
    fn mid_seq_esc_then_new_sequence() {
        // "ESC ]7501;sta ESC ]7501;state=idle BEL" — the corrupt first
        // sequence abandons; the second still parses.
        let mut s = OscScanner::new();
        let evs = s.feed(b"\x1b]7501;sta\x1b]7501;state=idle\x07");
        assert_eq!(evs.len(), 1);
        assert!(matches!(
            evs[0],
            OscEvent::Status {
                state: StateKind::Idle,
                ..
            }
        ));
        // Same but with the second ESC as the chunk tail.
        let mut s2 = OscScanner::new();
        assert!(s2.feed(b"\x1b]7501;sta\x1b").is_empty());
        let evs2 = s2.feed(b"]7501;state=idle\x07");
        assert_eq!(evs2.len(), 1);
    }

    #[test]
    fn split_sequence_across_feeds() {
        let mut s = OscScanner::new();
        assert!(s.feed(b"\x1b]7501;state=block").is_empty());
        let evs = s.feed(b"ed:kind=auth\x1b\\");
        assert_eq!(evs.len(), 1);
        assert!(matches!(
            evs[0],
            OscEvent::Status {
                state: StateKind::Blocked,
                kind: Some(BlockKind::Auth),
                ..
            }
        ));
    }

    #[test]
    fn stream_bytes_are_untouched_and_resyncs() {
        let mut s = OscScanner::new();
        // Garbage, a stray ESC mid-sequence, then a valid one.
        let evs = feed_all(
            &mut s,
            &[b"hello \x1b]7501;state=worki\x1b[31m ng\x07world \x1b]7501;state=idle\x07"],
        );
        // The corrupted sequence is abandoned; the last one still parses.
        assert!(evs.iter().any(|e| matches!(
            e,
            OscEvent::Status {
                state: StateKind::Idle,
                ..
            }
        )));
    }

    #[test]
    fn osc133_marks() {
        let mut s = OscScanner::new();
        let evs = feed_all(
            &mut s,
            &[b"\x1b]133;A\x07\x1b]133;B\x07\x1b]133;C\x07\x1b]133;D;exitcode=0\x07"],
        );
        assert_eq!(evs.len(), 4);
        assert!(matches!(
            evs[3],
            OscEvent::CommandMark {
                mark: CommandMark::Done,
                exit_code: Some(0)
            }
        ));
    }

    #[test]
    fn osc7_cwd_and_osc8_link() {
        let mut s = OscScanner::new();
        let evs = feed_all(
            &mut s,
            &[
                b"\x1b]7;file://host/Users/h/proj%20x\x07",
                b"\x1b]8;;https://example.com/x\x07text\x1b]8;;\x07",
            ],
        );
        assert_eq!(evs.len(), 2);
        assert!(matches!(&evs[0], OscEvent::Cwd(p) if p == "/Users/h/proj x"));
        assert!(matches!(&evs[1], OscEvent::Link { uri } if uri == "https://example.com/x"));
    }

    #[test]
    fn progress_94() {
        let mut s = OscScanner::new();
        let evs = s.feed(b"\x1b]9;4;1;42\x07");
        assert!(matches!(
            evs[0],
            OscEvent::Progress {
                state: ProgressKind::Set,
                percent: Some(42)
            }
        ));
    }
}
