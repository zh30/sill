//! `sill bench --suite=v1` — the release-gate harness (PRD §12 + Appendix A).
//!
//! What runs today without the GUI: a PTY-passthrough throughput proxy, and
//! idle CPU/RSS sampling of a target process (`--pid`). Cases that need the
//! real libghostty surface are reported as `skipped` — never substituted by
//! Terminal Mode numbers (PRD forbids benching the wrong shape).

use serde::Serialize;
use std::fs;
use std::io::Write;
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant};

#[derive(Serialize)]
struct CaseResult {
    case: String,
    status: &'static str, // "ok" | "skipped" | "error"
    #[serde(skip_serializing_if = "Option::is_none")]
    value: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    unit: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    note: Option<String>,
}

const CASES: &[&str] = &[
    "key_to_photon",
    "cat_ascii_150mb",
    "idle_cpu",
    "idle_rss",
    "occluded_rss",
];

fn bench_file() -> PathBuf {
    sill_core::layout::config_dir()
        .join("bench")
        .join("ascii-150mb.txt")
}

fn ensure_150mb_file(path: &PathBuf) -> std::io::Result<()> {
    if path.exists() && path.metadata()?.len() == 150 * 1024 * 1024 {
        return Ok(());
    }
    if let Some(p) = path.parent() {
        fs::create_dir_all(p)?;
    }
    let mut f = fs::File::create(path)?;
    let line = b"the quick brown fox jumps over the lazy dog 0123456789 sill bench line\n";
    let target = 150 * 1024 * 1024usize;
    let mut written = 0usize;
    let chunk = line.repeat(1024);
    while written < target {
        let n = chunk.len().min(target - written);
        f.write_all(&chunk[..n])?;
        written += n;
    }
    Ok(())
}

/// Proxy for `cat_ascii_150mb`: cats the file through a real PTY using the
/// platform `script` command, discarding the transcript. Reports MB/s; the
/// Ghostty-side comparison runs when libghostty is vendored.
fn bench_cat_ascii(path: &PathBuf) -> CaseResult {
    let case = "cat_ascii_150mb".to_string();
    if let Err(e) = ensure_150mb_file(path) {
        return CaseResult {
            case,
            status: "error",
            value: None,
            unit: None,
            note: Some(format!("cannot create bench file: {e}")),
        };
    }
    let cat_cmd = format!("cat {}", path.display());
    let mut cmd = if cfg!(target_os = "macos") {
        // BSD script: `script file command args...` — command and args are
        // separate argv entries.
        let mut c = Command::new("script");
        c.arg("-q").arg("/dev/null").arg("cat").arg(path);
        c
    } else {
        // util-linux script: `script -qec "cmd" file`.
        let mut c = Command::new("script");
        c.args(["-qec", &cat_cmd, "/dev/null"]);
        c
    };
    let t = Instant::now();
    match cmd.output() {
        Ok(out) if out.status.success() => {
            let secs = t.elapsed().as_secs_f64();
            let mb = 150.0 / secs;
            CaseResult {
                case,
                status: "ok",
                value: Some((mb * 100.0).round() / 100.0),
                unit: Some("MB/s (pty passthrough proxy)".into()),
                note: Some(
                    "through `script` pty → /dev/null; libghostty comparison lands with the vendored core"
                        .into(),
                ),
            }
        }
        Ok(out) => CaseResult {
            case,
            status: "error",
            value: None,
            unit: None,
            note: Some(format!("script exited {}", out.status)),
        },
        Err(e) => CaseResult {
            case,
            status: "error",
            value: None,
            unit: None,
            note: Some(format!("cannot run `script`: {e}")),
        },
    }
}

fn read_utime_ticks(pid: u32) -> Option<f64> {
    // `ps -o utime=` prints [[dd-]hh:]mm:ss for the process lifetime.
    let out = Command::new("ps")
        .args(["-o", "utime=", "-p", &pid.to_string()])
        .output()
        .ok()?;
    let s = String::from_utf8_lossy(&out.stdout).trim().to_string();
    let (days, rest) = s.split_once('-').map_or((0.0, s.as_str()), |(d, r)| {
        (d.parse::<f64>().unwrap_or(0.0), r)
    });
    let parts: Vec<f64> = rest.split(':').filter_map(|p| p.parse().ok()).collect();
    let secs = match parts.as_slice() {
        [ss] => *ss,
        [mm, ss] => mm * 60.0 + ss,
        [hh, mm, ss] => hh * 3600.0 + mm * 60.0 + ss,
        _ => return None,
    };
    Some(days * 86400.0 + secs)
}

fn read_rss_kb(pid: u32) -> Option<f64> {
    let out = Command::new("ps")
        .args(["-o", "rss=", "-p", &pid.to_string()])
        .output()
        .ok()?;
    String::from_utf8_lossy(&out.stdout).trim().parse().ok()
}

/// `idle_cpu`: sample a target process's utime delta over 5s (NFR-P4 budget ≤2%).
fn bench_idle_cpu(pid: Option<u32>) -> CaseResult {
    let case = "idle_cpu".to_string();
    let Some(pid) = pid else {
        return CaseResult {
            case,
            status: "skipped",
            value: None,
            unit: None,
            note: Some("pass --pid <pane-pid or app-pid> to sample".into()),
        };
    };
    let t0 = read_utime_ticks(pid);
    std::thread::sleep(Duration::from_secs(5));
    let t1 = read_utime_ticks(pid);
    match (t0, t1) {
        (Some(a), Some(b)) => {
            let pct = ((b - a) / 5.0) * 100.0;
            CaseResult {
                case,
                status: "ok",
                value: Some((pct * 100.0).round() / 100.0),
                unit: Some("% cpu over 5s".into()),
                note: Some("NFR-P4 budget: ≤ 2% after 5s idle".into()),
            }
        }
        _ => CaseResult {
            case,
            status: "error",
            value: None,
            unit: None,
            note: Some(format!("pid {pid} not running")),
        },
    }
}

fn bench_idle_rss(pid: Option<u32>) -> CaseResult {
    let case = "idle_rss".to_string();
    let Some(pid) = pid else {
        return CaseResult {
            case,
            status: "skipped",
            value: None,
            unit: None,
            note: Some("pass --pid <app-pid> to sample".into()),
        };
    };
    match read_rss_kb(pid) {
        Some(kb) => CaseResult {
            case,
            status: "ok",
            value: Some((kb / 1024.0 * 100.0).round() / 100.0),
            unit: Some("MB RSS".into()),
            note: Some("NFR-P5 budget: macOS ≤90MB · Linux ≤120MB".into()),
        },
        None => CaseResult {
            case,
            status: "error",
            value: None,
            unit: None,
            note: Some(format!("pid {pid} not running")),
        },
    }
}

fn skipped(case: &str, why: &str) -> CaseResult {
    CaseResult {
        case: case.to_string(),
        status: "skipped",
        value: None,
        unit: None,
        note: Some(why.into()),
    }
}

pub fn run(suite: &str, json: bool, pid: Option<u32>) -> i32 {
    if suite != "v1" {
        eprintln!("unknown suite '{suite}' (available: v1)");
        return 2;
    }
    let file = bench_file();
    let results: Vec<CaseResult> = CASES
        .iter()
        .map(|c| match *c {
            "key_to_photon" => skipped(c, "needs libghostty surface + compositor timestamps"),
            "cat_ascii_150mb" => bench_cat_ascii(&file),
            "idle_cpu" => bench_idle_cpu(pid),
            "idle_rss" => bench_idle_rss(pid),
            "occluded_rss" => skipped(c, "needs 8 live surfaces — runs in the app harness"),
            _ => unreachable!(),
        })
        .collect();

    if json {
        println!(
            "{}",
            serde_json::to_string_pretty(&results).unwrap_or_default()
        );
        return 0;
    }

    println!("sill bench --suite=v1");
    println!(
        "{:>2} {:<18} {:<8} {:<14} note",
        "#", "case", "status", "value"
    );
    for (i, r) in results.iter().enumerate() {
        let value = match (&r.value, &r.unit) {
            (Some(v), Some(u)) => format!("{v} {u}"),
            _ => "-".into(),
        };
        let note = r.note.clone().unwrap_or_default();
        println!(
            "{:>2} {:<18} {:<8} {:<14.40} {}",
            i + 1,
            r.case,
            r.status,
            value,
            note
        );
    }
    0
}
