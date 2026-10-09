//! `sill` — the Sill CLI (FR-018): `sill`, `sill state`, `sill export`,
//! `sill import ghostty`, `sill bench`.

mod bench_cmd;
mod export_cmd;
mod import_cmd;
mod state_cmd;

use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::process::Command;

#[derive(Parser)]
#[command(
    name = "sill",
    version,
    about = "Sill — the attention surface for agents"
)]
struct Cli {
    #[command(subcommand)]
    cmd: Option<Cmd>,
}

#[derive(Subcommand)]
enum Cmd {
    /// Write a program-status record (adapter/hook write-path, FR-008).
    ///
    /// Usage: sill state agent=claude status=awaiting pid=41220 session=s1 [kind=permission]
    State {
        /// key=value pairs: agent, status, pid (required), session, kind, msg
        #[arg(trailing_var_arg = true, allow_hyphen_values = true)]
        pairs: Vec<String>,
    },
    /// Export the workspace canvas + official resume commands.
    Export {
        /// What to export (only `layout` exists today).
        what: String,
        /// Layout file to read (default: ~/.config/sill/last-layout.toml).
        #[arg(long)]
        path: Option<PathBuf>,
        /// Also copy the raw layout file here.
        #[arg(long)]
        out: Option<PathBuf>,
        /// Print only the shell resume commands.
        #[arg(long)]
        shell: bool,
    },
    /// Import settings from another terminal.
    Import {
        /// Source to import from (only `ghostty` exists today).
        source: String,
        /// Config file to read (default: ~/.config/ghostty/config).
        #[arg(long)]
        path: Option<PathBuf>,
        /// Merge the generated fragment into ~/.config/sill/config.toml.
        #[arg(long)]
        write: bool,
    },
    /// Run the release-gate bench suite (PRD §12 + Appendix A).
    Bench {
        /// Suite name.
        #[arg(long, default_value = "v1")]
        suite: String,
        /// Emit JSON.
        #[arg(long)]
        json: bool,
        /// Process to sample for idle_cpu/idle_rss.
        #[arg(long)]
        pid: Option<u32>,
    },
}

/// `sill` with no subcommand launches the app (J1). If Sill.app isn't built
/// yet, says exactly how to build it.
fn launch_app() -> i32 {
    #[cfg(target_os = "macos")]
    {
        let candidates = [
            PathBuf::from("dist/Sill.app"),
            PathBuf::from("/Applications/Sill.app"),
        ];
        for app in candidates {
            if app.exists() {
                let status = Command::new("open").arg(&app).status();
                return match status {
                    Ok(s) if s.success() => 0,
                    _ => {
                        eprintln!("failed to open {}", app.display());
                        1
                    }
                };
            }
        }
        eprintln!("Sill.app not found — build it first: make bundle");
        1
    }
    #[cfg(not(target_os = "macos"))]
    {
        eprintln!("sill GUI is macOS-first; Linux chrome lands in Phase D (PRD §17)");
        1
    }
}

fn main() {
    let cli = Cli::parse();
    let code = match cli.cmd {
        None => launch_app(),
        Some(Cmd::State { pairs }) => state_cmd::run(&pairs),
        Some(Cmd::Export {
            what,
            path,
            out,
            shell,
        }) => {
            if what != "layout" {
                eprintln!("unknown export target '{what}' (available: layout)");
                2
            } else {
                export_cmd::run(path, out, shell)
            }
        }
        Some(Cmd::Import {
            source,
            path,
            write,
        }) => {
            if source != "ghostty" {
                eprintln!("unknown import source '{source}' (available: ghostty)");
                2
            } else {
                import_cmd::run(path, write)
            }
        }
        Some(Cmd::Bench { suite, json, pid }) => bench_cmd::run(&suite, json, pid),
    };
    std::process::exit(code);
}
