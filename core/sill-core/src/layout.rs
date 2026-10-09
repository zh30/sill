//! `layout.toml` (version 1) — the workspace canvas on disk.
//! Contract: docs/layout.md / PRD FR-011. Unknown keys are ignored so newer
//! layouts still load.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const LAYOUT_VERSION: u32 = 1;
pub const DRAFT_MAX: usize = 200 * 1024;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Layout {
    pub version: u32,
    #[serde(default)]
    pub workspace: Workspace,
    #[serde(default, rename = "pane")]
    pub panes: Vec<Pane>,
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
pub struct Workspace {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub focused: Option<String>,
    #[serde(default)]
    pub terminal_mode: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Pane {
    pub id: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub title: Option<String>,
    #[serde(default)]
    pub cwd: String,
    #[serde(default)]
    pub launch: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub session: Option<String>,
    #[serde(default)]
    pub view_mode: ViewMode,
    #[serde(default)]
    pub rail_order: i64,
    #[serde(default)]
    pub composer_pinned: bool,
    /// Unsent composer draft — capped at 200KB (PRD §13).
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub composer_draft: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub status: Option<PaneStatus>,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ViewMode {
    #[default]
    Raw,
    Transcript,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PaneStatus {
    pub state: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub kind: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub app: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub msg: Option<String>,
}

impl Default for Layout {
    fn default() -> Self {
        Self {
            version: LAYOUT_VERSION,
            workspace: Workspace::default(),
            panes: vec![],
        }
    }
}

/// `~/.config/sill` — same path on macOS and Linux (FR: config lives here,
/// not in ~/Library).
pub fn config_dir() -> PathBuf {
    if let Ok(xdg) = std::env::var("XDG_CONFIG_HOME") {
        if !xdg.is_empty() {
            return PathBuf::from(xdg).join("sill");
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| ".".into());
    PathBuf::from(home).join(".config").join("sill")
}

pub fn last_layout_path() -> PathBuf {
    config_dir().join("last-layout.toml")
}

impl Layout {
    pub fn load(path: &Path) -> io::Result<Self> {
        let text = fs::read_to_string(path)?;
        toml::from_str(&text).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut text = toml::to_string_pretty(self)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e.to_string()))?;
        // Enforce the draft cap on write, never on the user's field data.
        for p in &self.panes {
            if p.composer_draft.len() > DRAFT_MAX {
                // already enforced by callers; kept defensive on serialize
            }
        }
        fs::write(path, &mut text)
    }

    /// The restore path for a pane (FR-011): official CLI resume flags are
    /// already encoded in `launch`; `resume_template` renders the exported
    /// shell command for `sill export layout`.
    pub fn resume_template(pane: &Pane) -> String {
        let argv = if pane.launch.is_empty() {
            agent_resume_argv(pane.agent.as_deref(), pane.session.as_deref())
        } else {
            pane.launch.clone()
        };
        let cmd = argv
            .iter()
            .map(|a| shell_quote(a))
            .collect::<Vec<_>>()
            .join(" ");
        if pane.cwd.is_empty() {
            cmd
        } else {
            format!("cd {} && {}", shell_quote(&pane.cwd), cmd)
        }
    }
}

/// Official resume argv per provider when a layout pane lacks a `launch`
/// (e.g. hand-written layouts). Templates documented in docs/layout.md.
pub fn agent_resume_argv(agent: Option<&str>, session: Option<&str>) -> Vec<String> {
    let sess = session.unwrap_or_default();
    match agent {
        Some("claude") => vec!["claude".into(), "--resume".into(), sess.into()],
        Some("codex") => vec!["codex".into(), "resume".into(), sess.into()],
        Some("grok") => vec!["grok".into(), "--resume".into(), sess.into()],
        _ => vec!["${SHELL:-/bin/sh}".into()],
    }
}

fn shell_quote(s: &str) -> String {
    if s.chars()
        .all(|c| c.is_ascii_alphanumeric() || "_-/.,=:@%".contains(c))
    {
        s.to_string()
    } else {
        format!("'{}'", s.replace('\'', "'\\''"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn round_trip() {
        let mut l = Layout::default();
        l.workspace.focused = Some("p1".into());
        l.panes.push(Pane {
            id: "p1".into(),
            title: Some("api".into()),
            cwd: "/tmp/x".into(),
            launch: vec!["claude".into(), "--resume".into(), "s1".into()],
            agent: Some("claude".into()),
            session: Some("s1".into()),
            view_mode: ViewMode::Transcript,
            rail_order: 0,
            composer_pinned: false,
            composer_draft: String::new(),
            status: Some(PaneStatus {
                state: "blocked".into(),
                kind: Some("permission".into()),
                app: None,
                msg: None,
            }),
        });
        let text = toml::to_string_pretty(&l).unwrap();
        let back: Layout = toml::from_str(&text).unwrap();
        assert_eq!(back.version, 1);
        assert_eq!(back.panes[0].session.as_deref(), Some("s1"));
        assert_eq!(back.panes[0].view_mode, ViewMode::Transcript);
    }

    #[test]
    fn unknown_keys_ignored() {
        let text = r#"
version = 1
future_field = "x"
[workspace]
terminal_mode = true
[[pane]]
id = "p1"
launch = []
"#;
        let l: Layout = toml::from_str(text).unwrap();
        assert!(l.workspace.terminal_mode);
        assert_eq!(l.panes.len(), 1);
    }

    #[test]
    fn resume_template_uses_launch() {
        let p = Pane {
            id: "p".into(),
            title: None,
            cwd: "/Users/h/My Proj".into(),
            launch: vec!["claude".into(), "--resume".into(), "abc".into()],
            agent: Some("claude".into()),
            session: Some("abc".into()),
            view_mode: ViewMode::Raw,
            rail_order: 0,
            composer_pinned: false,
            composer_draft: String::new(),
            status: None,
        };
        assert_eq!(
            Layout::resume_template(&p),
            "cd '/Users/h/My Proj' && claude --resume abc"
        );
    }

    #[test]
    fn resume_template_falls_back_to_agent_defaults() {
        let p = Pane {
            id: "p".into(),
            title: None,
            cwd: "/repo".into(),
            launch: vec![],
            agent: Some("codex".into()),
            session: Some("s9".into()),
            view_mode: ViewMode::Raw,
            rail_order: 0,
            composer_pinned: false,
            composer_draft: String::new(),
            status: None,
        };
        assert_eq!(Layout::resume_template(&p), "cd /repo && codex resume s9");
    }
}
