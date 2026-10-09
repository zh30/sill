//! `sill export layout` — dump the workspace canvas plus per-pane official
//! resume commands (FR-011, docs/layout.md). The point: sessions outlive Sill —
//! resume works in any terminal, no Sill UI required.

use sill_core::layout::{last_layout_path, Layout};
use std::path::PathBuf;

pub fn run(path: Option<PathBuf>, out: Option<PathBuf>, shell_only: bool) -> i32 {
    let src = path.unwrap_or_else(last_layout_path);
    if !src.exists() {
        eprintln!("no layout at {}", src.display());
        eprintln!("(the app writes it on quit; nothing to export yet)");
        return 1;
    }
    let layout = match Layout::load(&src) {
        Ok(l) => l,
        Err(e) => {
            eprintln!("cannot parse {}: {e}", src.display());
            return 1;
        }
    };

    if let Some(dst) = out {
        if let Err(e) = layout.save(&dst) {
            eprintln!("cannot write {}: {e}", dst.display());
            return 1;
        }
        eprintln!("layout copied to {}", dst.display());
    }

    if !shell_only {
        println!("# sill export layout — {}", src.display());
        println!("# resume is via each provider's official CLI — Sill is not required.");
        println!("# resume ≠ pixel-level scrollback (FR-011).\n");
    }

    if layout.panes.is_empty() {
        println!("# (layout has no panes)");
        return 0;
    }

    let mut panes: Vec<_> = layout.panes.iter().collect();
    panes.sort_by_key(|p| p.rail_order);
    for p in panes {
        let label = p.title.as_deref().unwrap_or("(untitled)");
        if !shell_only {
            let state = p
                .status
                .as_ref()
                .map(|s| s.state.as_str())
                .unwrap_or("unknown");
            println!("# pane {} — {} [{}]", p.id, label, state);
        }
        println!("{}", Layout::resume_template(p));
        if !shell_only {
            println!();
        }
    }
    0
}
