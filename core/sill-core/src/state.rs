//! The shared five-point program-status model (PRD FR-008, protocols/osc-7501.md).
//!
//! Wire states (OSC 7501 `state=`): idle, working, done, blocked, error, clear.
//! Adapter statuses (`sill state ... status=`): awaiting → blocked, plus
//! working/done/idle/error/unknown. `unknown` is the absence of information —
//! we never guess (PRD: no 7501 and no hook → `unknown` + process liveness).

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// OSC 7501 wire states.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum StateKind {
    Idle,
    Working,
    Done,
    Blocked,
    Error,
    Clear,
}

impl StateKind {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "idle" => Self::Idle,
            "working" => Self::Working,
            "done" => Self::Done,
            "blocked" => Self::Blocked,
            "error" => Self::Error,
            "clear" => Self::Clear,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Working => "working",
            Self::Done => "done",
            Self::Blocked => "blocked",
            Self::Error => "error",
            Self::Clear => "clear",
        }
    }

    /// Rail badge priority when a pane has layered `id` records:
    /// blocked beats everything; unknown isn't a stored state.
    fn priority(self) -> u8 {
        match self {
            Self::Blocked => 5,
            Self::Error => 4,
            Self::Done => 3,
            Self::Working => 2,
            Self::Idle => 1,
            Self::Clear => 0,
        }
    }
}

/// `kind=` on `state=blocked` (PRD FR-008).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum BlockKind {
    Permission,
    Question,
    Auth,
}

impl BlockKind {
    pub fn parse(s: &str) -> Option<Self> {
        Some(match s {
            "permission" => Self::Permission,
            "question" => Self::Question,
            "auth" => Self::Auth,
            _ => return None,
        })
    }

    pub fn as_str(self) -> &'static str {
        match self {
            Self::Permission => "permission",
            Self::Question => "question",
            Self::Auth => "auth",
        }
    }
}

/// Map an adapter `status=` word (from `sill state`) onto the shared model.
/// Returns None for words that produce no record (`unknown` → liveness only).
pub fn adapter_status(word: &str) -> Option<Option<StateKind>> {
    match word {
        "awaiting" | "blocked" => Some(Some(StateKind::Blocked)),
        "working" => Some(Some(StateKind::Working)),
        "done" | "complete" => Some(Some(StateKind::Done)),
        "idle" => Some(Some(StateKind::Idle)),
        "error" => Some(Some(StateKind::Error)),
        "clear" => Some(Some(StateKind::Clear)),
        "unknown" => Some(None),
        _ => None, // unmapped word: dropped before it reaches the store
    }
}

/// One layered status record (7501 `id=` namespaces records per pane).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct StatusRecord {
    pub state: StateKind,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<BlockKind>,
    /// Decoded `msg` (one line). None when absent or base64 was invalid.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub msg: Option<String>,
    /// Source: "osc7501" or adapter agent name — diagnostics only.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source: Option<String>,
}

/// Per-pane store: `id` → latest record. `clear` deletes records by `id`
/// (an `id`-less `clear` empties the pane, matching the published examples).
#[derive(Debug, Default)]
pub struct StatusStore {
    records: BTreeMap<String, StatusRecord>,
}

impl StatusStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Apply one parsed status. `id = ""` is the default (un-namespaced) layer.
    /// Returns the resulting effective state for the rail.
    pub fn apply(&mut self, id: Option<&str>, rec: StatusRecord) -> EffectiveStatus {
        let key = id.unwrap_or_default().to_string();
        if rec.state == StateKind::Clear {
            if key.is_empty() {
                self.records.clear();
            } else {
                self.records.remove(&key);
            }
        } else {
            self.records.insert(key, rec);
        }
        self.effective()
    }

    /// The badge the rail shows: highest-priority live record, or Unknown.
    pub fn effective(&self) -> EffectiveStatus {
        let best = self
            .records
            .values()
            .max_by_key(|r| r.state.priority())
            .cloned();
        match best {
            Some(r) => EffectiveStatus::Known(r),
            None => EffectiveStatus::Unknown,
        }
    }

    pub fn records(&self) -> &BTreeMap<String, StatusRecord> {
        &self.records
    }
}

/// What the rail/ring consume.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(untagged)]
pub enum EffectiveStatus {
    /// At least one live record.
    Known(StatusRecord),
    /// No data: rail shows `unknown` (+ process liveness from the surface).
    Unknown,
}

impl EffectiveStatus {
    pub fn is_blocked(&self) -> bool {
        matches!(self, Self::Known(r) if r.state == StateKind::Blocked)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rec(state: StateKind) -> StatusRecord {
        StatusRecord {
            state,
            app: None,
            kind: None,
            msg: None,
            source: None,
        }
    }

    #[test]
    fn blocked_beats_working_and_idle() {
        let mut s = StatusStore::new();
        s.apply(None, rec(StateKind::Idle));
        s.apply(None, rec(StateKind::Working));
        s.apply(Some("task-1"), rec(StateKind::Blocked));
        assert!(s.effective().is_blocked());
    }

    #[test]
    fn clear_by_id_keeps_other_records() {
        let mut s = StatusStore::new();
        s.apply(Some("a"), rec(StateKind::Blocked));
        s.apply(Some("b"), rec(StateKind::Done));
        s.apply(Some("a"), rec(StateKind::Clear));
        match s.effective() {
            EffectiveStatus::Known(r) => assert_eq!(r.state, StateKind::Done),
            _ => panic!("expected done"),
        }
    }

    #[test]
    fn clear_without_id_empties() {
        let mut s = StatusStore::new();
        s.apply(None, rec(StateKind::Blocked));
        s.apply(None, rec(StateKind::Clear));
        assert_eq!(s.effective(), EffectiveStatus::Unknown);
    }

    #[test]
    fn adapter_words_map() {
        assert_eq!(adapter_status("awaiting"), Some(Some(StateKind::Blocked)));
        assert_eq!(adapter_status("done"), Some(Some(StateKind::Done)));
        assert_eq!(adapter_status("unknown"), Some(None));
        assert_eq!(adapter_status("bogus"), None);
    }
}
