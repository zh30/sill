//! `sill state` — the adapter write-path (FR-008).
//!
//! Adapters (official hooks) translate a CLI's lifecycle events into the shared
//! five-point model and call `sill state agent=.. status=.. pid=.. ...`.
//! Records land under `~/.config/sill/state/` — `events.jsonl` (append log)
//! plus `pane-<pid>.json` (latest per pane). Events without `pid` are dropped.

use serde::Serialize;
use sill_core::layout::config_dir;
use sill_core::state::{adapter_status, StatusRecord};
use std::collections::HashMap;
use std::fs;
use std::io::Write;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Serialize)]
struct StateEvent {
    ts_ms: u64,
    agent: String,
    status: String,
    pid: u32,
    #[serde(skip_serializing_if = "Option::is_none")]
    session: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    kind: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    msg: Option<String>,
    /// Effective sill state after mapping (`awaiting` → `blocked`), or null
    /// when the word maps to `unknown` (liveness only).
    state: Option<String>,
    record: Option<StatusRecord>,
}

fn state_dir() -> std::path::PathBuf {
    config_dir().join("state")
}

/// Parse `key=value` args into a map. Non-pairs are ignored (adapters must be
/// tolerant of future keys — same rule as the wire protocol).
pub fn run(pairs: &[String]) -> i32 {
    let mut kv: HashMap<String, String> = HashMap::new();
    for p in pairs {
        if let Some((k, v)) = p.split_once('=') {
            kv.insert(k.to_string(), v.to_string());
        }
    }

    // pid is required — drop the event without it (FR-008).
    let pid = match kv.get("pid").and_then(|p| p.parse::<u32>().ok()) {
        Some(p) => p,
        None => {
            eprintln!("sill state: dropped event (missing/invalid pid)");
            return 0; // adapters must never fail the hook chain
        }
    };

    let agent = kv.get("agent").cloned().unwrap_or_else(|| "unknown".into());
    let status = kv
        .get("status")
        .cloned()
        .unwrap_or_else(|| "unknown".into());

    // Map onto the five-point model; unmapped words are dropped.
    let mapped = match adapter_status(&status) {
        Some(m) => m,
        None => {
            eprintln!("sill state: dropped event (unmapped status '{status}')");
            return 0;
        }
    };

    let kind = kv
        .get("kind")
        .cloned()
        .filter(|k| sill_core::state::BlockKind::parse(k).is_some());
    let record = mapped.map(|state| StatusRecord {
        state,
        app: Some(agent.clone()),
        kind: kind.as_deref().and_then(sill_core::state::BlockKind::parse),
        msg: kv.get("msg").cloned(),
        source: Some(format!("adapter:{agent}")),
    });

    let ev = StateEvent {
        ts_ms: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis() as u64)
            .unwrap_or(0),
        agent,
        status,
        pid,
        session: kv.get("session").cloned(),
        kind,
        msg: kv.get("msg").cloned(),
        state: record.as_ref().map(|r| r.state.as_str().to_string()),
        record,
    };

    let dir = state_dir();
    if let Err(e) = fs::create_dir_all(&dir) {
        eprintln!("sill state: cannot create {}: {e}", dir.display());
        return 0;
    }

    let mut ok = true;
    // Append-only event log.
    let events_path = dir.join("events.jsonl");
    match fs::OpenOptions::new()
        .create(true)
        .append(true)
        .open(&events_path)
    {
        Ok(mut f) => {
            if let Err(e) = writeln!(f, "{}", serde_json::to_string(&ev).unwrap_or_default()) {
                eprintln!("sill state: write failed: {e}");
                ok = false;
            }
        }
        Err(e) => {
            eprintln!("sill state: open {}: {e}", events_path.display());
            ok = false;
        }
    }
    // Latest-per-pane file the app watches.
    let pane_path = dir.join(format!("pane-{pid}.json"));
    if let Err(e) = fs::write(
        &pane_path,
        serde_json::to_string_pretty(&ev).unwrap_or_default(),
    ) {
        eprintln!("sill state: write {}: {e}", pane_path.display());
        ok = false;
    }

    if ok {
        println!(
            "sill state: recorded {} → {}",
            ev.agent,
            ev.state.as_deref().unwrap_or("unknown")
        );
    }
    0 // never a nonzero exit — the hook chain must not break
}
