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
    /// Pane key for the file the app watches (`pane-<key>.json`): the
    /// `pane=` pair, or `SILL_PANE` env (set on every spawned shell), else pid.
    pane: String,
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

    // A pane key (pane= pair or SILL_PANE env) identifies the pane file.
    // pid is required only without one — inside a pane shell SILL_PANE
    // always exists, so hooks don't need a pid (FR-008).
    let pane_key = kv
        .get("pane")
        .cloned()
        .or_else(|| std::env::var("SILL_PANE").ok().filter(|s| !s.is_empty()));
    let pid = match kv.get("pid").and_then(|p| p.parse::<u32>().ok()) {
        Some(p) => p,
        None if pane_key.is_some() => 0,
        None => {
            eprintln!("sill state: dropped event (missing/invalid pid, no pane key)");
            return 0; // adapters must never fail the hook chain
        }
    };

    let agent = kv.get("agent").cloned().unwrap_or_else(|| "unknown".into());
    // `status=` is canonical; `state=` accepted (same word in OSC 7501).
    let status = kv
        .get("status")
        .or_else(|| kv.get("state"))
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

    // Which pane file the app reads. Hooks run inside the pane's shell, which
    // carries SILL_PANE — that beats pid (pid keys only help manual use).
    let pane_key = pane_key.unwrap_or_else(|| pid.to_string());

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
        pane: pane_key.clone(),
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
    let pane_path = dir.join(format!("pane-{}.json", sanitize_file_key(&pane_key)));
    if let Err(e) = fs::write(
        &pane_path,
        serde_json::to_string_pretty(&ev).unwrap_or_default(),
    ) {
        eprintln!("sill state: write {}: {e}", pane_path.display());
        ok = false;
    }
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let _ = fs::set_permissions(&dir, fs::Permissions::from_mode(0o700));
        let _ = fs::set_permissions(&pane_path, fs::Permissions::from_mode(0o600));
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

/// Pane keys become file names — strip anything pathy.
fn sanitize_file_key(key: &str) -> String {
    key.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() || c == '-' || c == '_' {
                c
            } else {
                '_'
            }
        })
        .collect()
}
