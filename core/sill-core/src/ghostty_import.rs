//! `sill import ghostty` — map a Ghostty config into Sill's config surface and
//! report every key as mapped / similar / dropped (FR-012). Unknown keys are
//! ignored for config generation but always reported as dropped.

use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Disposition {
    /// Exact equivalent in Sill config.
    Mapped,
    /// Close but not identical — imported with a note.
    Similar,
    /// No Sill equivalent — skipped, reported.
    Dropped,
}

#[derive(Debug, Clone, Serialize)]
pub struct ImportEntry {
    pub key: String,
    pub value: String,
    pub disposition: Disposition,
    /// The emitted sill config key, if any.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub target: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub note: Option<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct ImportReport {
    pub entries: Vec<ImportEntry>,
    pub mapped: usize,
    pub similar: usize,
    pub dropped: usize,
    /// Generated sill config TOML fragment.
    pub config_toml: String,
}

/// Ghostty `keybind` actions Sill understands (subset; the rest are dropped).
const MAPPED_KEYBIND_ACTIONS: &[(&str, &str)] = &[
    ("new_tab", "new_session"),
    ("close_surface", "close_pane"),
    ("toggle_fullscreen", "toggle_fullscreen"),
    ("goto_split:next", "next_pane"),
    ("goto_split:previous", "prev_pane"),
];

/// Parse Ghostty config text (`key = value` lines, `#` comments, `key` alone
/// means `key = true`) into an import report + sill config fragment.
pub fn import_ghostty_config(text: &str) -> ImportReport {
    let mut entries = Vec::new();
    // Accumulators for the emitted config.
    let mut font_family: Option<String> = None;
    let mut font_size: Option<String> = None;
    let mut theme: Option<String> = None;
    let mut padding_x: Option<String> = None;
    let mut padding_y: Option<String> = None;
    let mut colors: Vec<(String, String)> = Vec::new();
    let mut keybinds: Vec<(String, String)> = Vec::new();

    for raw in text.lines() {
        let line = raw.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let (key, value) = match line.split_once('=') {
            Some((k, v)) => (k.trim(), v.trim().to_string()),
            None => (line, "true".to_string()),
        };
        // Strip one layer of surrounding quotes so emitted TOML doesn't
        // double-quote (ghostty accepts both bare and quoted values).
        let value = if value.len() >= 2 && value.starts_with('"') && value.ends_with('"') {
            value[1..value.len() - 1].to_string()
        } else {
            value
        };

        let mut entry = ImportEntry {
            key: key.to_string(),
            value: value.clone(),
            disposition: Disposition::Dropped,
            target: None,
            note: None,
        };

        match key {
            "font-family" => {
                entry.disposition = Disposition::Mapped;
                entry.target = Some("terminal.font_family".into());
                font_family = Some(value);
            }
            "font-size" => {
                entry.disposition = Disposition::Mapped;
                entry.target = Some("terminal.font_size".into());
                font_size = Some(value.trim_end_matches("pt").to_string());
            }
            "theme" => {
                entry.disposition = Disposition::Similar;
                entry.target = Some("theme".into());
                entry.note = Some("mapped onto sill theme-pack name; system keeps dynamic".into());
                theme = Some(value);
            }
            "background"
            | "foreground"
            | "cursor-color"
            | "selection-background"
            | "selection-foreground" => {
                entry.disposition = Disposition::Mapped;
                entry.target = Some(format!("terminal.{key}"));
                colors.push((key.to_string(), value));
            }
            k if k.starts_with("palette=") || k == "palette" => {
                entry.disposition = Disposition::Mapped;
                entry.target = Some("terminal.palette".into());
                colors.push(("palette".into(), value));
            }
            "window-padding-x" | "window-padding-y" => {
                entry.disposition = Disposition::Mapped;
                entry.target = Some(format!("terminal.{key}"));
                if key.ends_with('x') {
                    padding_x = Some(value);
                } else {
                    padding_y = Some(value);
                }
            }
            "window-padding-balance" | "window-padding-color" => {
                entry.disposition = Disposition::Dropped;
                entry.note = Some("sill uses a single uniform padding".into());
            }
            "cursor-style" | "cursor-style-blink" => {
                entry.disposition = Disposition::Similar;
                entry.target = Some(format!("terminal.{key}"));
                entry.note = Some("style set accepted; blink honored on supported backends".into());
            }
            "keybind" => {
                if let Some((trigger, action)) = value.split_once('=') {
                    let act = action.trim();
                    if let Some((_, target)) =
                        MAPPED_KEYBIND_ACTIONS.iter().find(|(a, _)| *a == act)
                    {
                        entry.disposition = Disposition::Mapped;
                        entry.target = Some(format!("keybind.{target}"));
                        keybinds.push((target.to_string(), trigger.trim().to_string()));
                    } else {
                        entry.disposition = Disposition::Dropped;
                        entry.note = Some(format!("no sill action for ghostty `{act}`"));
                    }
                } else {
                    entry.disposition = Disposition::Dropped;
                    entry.note = Some("malformed keybind line".into());
                }
            }
            // Known-but-dropped: app-level features sill intentionally lacks.
            "macos-icon"
            | "macos-icon-frame"
            | "macos-titlebar-style"
            | "window-theme"
            | "gtk-titlebar" => {
                entry.disposition = Disposition::Dropped;
                entry.note = Some("platform chrome is sill-owned".into());
            }
            "clipboard-write" | "clipboard-read" => {
                entry.disposition = Disposition::Similar;
                entry.target = Some("clipboard-write".into());
                entry.note =
                    Some("sill maps to off/confirm/allow; unknown values become off".into());
            }
            _ => {}
        }
        entries.push(entry);
    }

    let mut config = String::from("# Imported from Ghostty config by `sill import ghostty`\n");
    if let Some(f) = font_family {
        config.push_str(&format!("terminal.font_family = \"{f}\"\n"));
    }
    if let Some(s) = font_size {
        config.push_str(&format!("terminal.font_size = {s}\n"));
    }
    if let Some(t) = theme {
        config.push_str(&format!("theme = \"{t}\"\n"));
    }
    if padding_x.is_some() || padding_y.is_some() {
        config.push_str(&format!(
            "terminal.padding = \"{}x{}\"\n",
            padding_x.unwrap_or_else(|| "0".into()),
            padding_y.unwrap_or_else(|| "0".into())
        ));
    }
    for (k, v) in &colors {
        if k == "palette" {
            config.push_str(&format!("terminal.palette += \"{v}\"\n"));
        } else {
            config.push_str(&format!("terminal.{k} = \"{v}\"\n"));
        }
    }
    for (k, v) in &keybinds {
        config.push_str(&format!("keybind.{k} = \"{v}\"\n"));
    }

    let mapped = entries
        .iter()
        .filter(|e| e.disposition == Disposition::Mapped)
        .count();
    let similar = entries
        .iter()
        .filter(|e| e.disposition == Disposition::Similar)
        .count();
    let dropped = entries
        .iter()
        .filter(|e| e.disposition == Disposition::Dropped)
        .count();

    ImportReport {
        entries,
        mapped,
        similar,
        dropped,
        config_toml: config,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn report_counts_and_targets() {
        let cfg = r#"
# ghostty config
font-family = "JetBrains Mono"
font-size = 13pt
theme = catppuccin-mocha
background = #1e1e2e
window-padding-x = 8
keybind = cmd+t=new_tab
keybind = cmd+w=close_surface
keybind = super+alt+i=inspector:toggle
scrollback-limit = 1000000
"#;
        let r = import_ghostty_config(cfg);
        assert_eq!(r.mapped, 6); // font-family, font-size, background, pad-x, 2 keybinds
        assert_eq!(r.similar, 1); // theme
        assert_eq!(r.dropped, 2); // inspector keybind + scrollback-limit
        assert!(r
            .config_toml
            .contains("terminal.font_family = \"JetBrains Mono\""));
        assert!(r.config_toml.contains("keybind.new_session = \"cmd+t\""));
    }

    #[test]
    fn bare_key_means_true() {
        let r = import_ghostty_config("copy-on-select\n");
        assert_eq!(r.entries[0].value, "true");
        assert_eq!(r.entries[0].disposition, Disposition::Dropped);
    }
}
