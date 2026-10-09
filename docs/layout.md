# Sill layout format — `layout.toml` (version 1)

License: MIT. Sill persists the workspace canvas so it can be restored on launch,
and exports it (`sill export layout`) so the same sessions can be resumed with the
official agent CLIs in any terminal — no Sill UI required.

Live file: `~/.config/sill/last-layout.toml`.

```toml
version = 1

[workspace]
focused = "pane-uuid"
terminal_mode = false

[[pane]]
id = "pane-uuid"               # stable pane id
title = "api-server"           # rail label; defaults to command basename
cwd = "/Users/h/proj"          # working directory at spawn time
launch = ["claude", "--resume", "sess_01"]  # argv
agent = "claude"               # adapter id: claude | codex | grok | custom
session = "sess_01"            # provider session id, if known
view_mode = "raw"              # raw | transcript (TUI may force raw)
rail_order = 0                 # rail position; drag reorders
composer_pinned = false        # composer dock pinned (P1)
composer_draft = ""            # unsent draft, ≤ 200KB

[pane.status]                  # last known program status (see protocols/osc-7501.md)
state = "blocked"
kind = "permission"
app = "claude-code"
msg = ""
```

## Restore contract (FR-011)

- On launch, if `last-layout.toml` exists the canvas is restored; otherwise the
  Home Canvas is shown.
- A pane with a `session` resumes through the **official CLI resume path**
  (`launch` argv is written at spawn/exit so it already encodes `--resume`-style
  flags per provider).
- Resume failure → empty Raw surface + error strip + Retry; the `session` id is
  kept. **Resume is not pixel-level scrollback** — the UI says so.
- Unknown TOML keys are ignored so newer layouts still load in older builds.

## Official resume templates (written by `sill export layout`)

| Provider | Resume template                                  |
|----------|--------------------------------------------------|
| claude   | `cd <cwd> && claude --resume <session>`          |
| codex    | `cd <cwd> && codex resume <session>`             |
| grok     | `cd <cwd> && grok --resume <session>`            |
| custom   | `cd <cwd> && <launch argv>`                      |
