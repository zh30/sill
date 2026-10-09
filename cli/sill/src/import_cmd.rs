//! `sill import ghostty` — map a Ghostty config into Sill's surface and print
//! the mapped/similar/dropped report (FR-012). `--write` merges the generated
//! fragment into `~/.config/sill/config.toml`.

use sill_core::ghostty_import::{import_ghostty_config, Disposition};
use sill_core::layout::config_dir;
use std::fs;
use std::path::PathBuf;

fn default_ghostty_config() -> PathBuf {
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home)
        .join(".config")
        .join("ghostty")
        .join("config")
}

pub fn run(path: Option<PathBuf>, write: bool) -> i32 {
    let src = path.unwrap_or_else(default_ghostty_config);
    let text = match fs::read_to_string(&src) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("cannot read {}: {e}", src.display());
            return 1;
        }
    };
    let report = import_ghostty_config(&text);

    println!("# sill import ghostty — {}", src.display());
    for e in &report.entries {
        let mark = match e.disposition {
            Disposition::Mapped => "mapped  ",
            Disposition::Similar => "similar ",
            Disposition::Dropped => "dropped ",
        };
        let target = e
            .target
            .as_ref()
            .map(|t| format!(" → {t}"))
            .unwrap_or_default();
        let note = e
            .note
            .as_ref()
            .map(|n| format!(" ({n})"))
            .unwrap_or_default();
        println!("{mark} {} = {}{}{}", e.key, e.value, target, note);
    }
    println!(
        "\n{} mapped · {} similar · {} dropped",
        report.mapped, report.similar, report.dropped
    );

    if write {
        let dst = config_dir().join("config.toml");
        if let Err(e) = fs::create_dir_all(config_dir()) {
            eprintln!("cannot create config dir: {e}");
            return 1;
        }
        let mut merged = fs::read_to_string(&dst).unwrap_or_default();
        if !merged.is_empty() && !merged.ends_with('\n') {
            merged.push('\n');
        }
        merged.push('\n');
        merged.push_str(&report.config_toml);
        if let Err(e) = fs::write(&dst, merged) {
            eprintln!("cannot write {}: {e}", dst.display());
            return 1;
        }
        eprintln!("\nmerged into {}", dst.display());
    } else {
        println!("\n# generated config (pass --write to merge into ~/.config/sill/config.toml):");
        print!("{}", report.config_toml);
    }
    0
}
