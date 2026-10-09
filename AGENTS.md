# AGENTS.md — Sill

Sill is the **attention surface for agents**: a terminal built on libghostty with an
attention rail, focus ring, dual surface, and a composer that writes into the PTY.
Implement against `docs/Sill-PRD-v0.4.md` — it is the source of truth. Anything not
in the PRD is out of scope for v1.

## Non-negotiables (from the PRD)

- libghostty is the only VT core. No second parser, no Electron/WebView for terminal cells.
- Never claim to be faster than Ghostty. Never pass a Terminal Mode bench off as the product shape.
- Program state comes from the public **OSC 7501** protocol first; `sill state` (official hooks)
  is only the fallback. No private state dialect as the primary path.
- stdout is never re-flowed into bubbles/blocks/DOM. A TUI forces Raw mode. No events = empty
  Transcript — do not invent content.
- Default: no account, zero network, update check opt-in. OSC 52 off, remote OSC notify off.
- CJK double-width, IME candidate window, emoji ZWJ are P0 on macOS and Linux.
- Unknown OSC sequences and unknown 7501 keys are ignored — never error, never drop bytes.

## Repo layout

- `core/sill-core` — Rust `staticlib` + `rlib`. Byte-stream OSC scanner, status store,
  layout TOML, Ghostty import mapping, C ABI (`include/sill.h`). Pure logic: no I/O deps.
- `cli/sill` — the `sill` binary: `state`, `export`, `import`, `bench` (FR-018).
- `apps/macos` — SwiftPM executable → `dist/Sill.app`. Terminal surfaces sit behind the
  `SillSurface` protocol; `SwiftTermSurface` is the dev backend until `vendor/libghostty`
  lands (pinned commit — see `vendor/README.md`).
- `adapters/` — official-hook adapters for claude-code / codex / grok. They emit
  `sill state ...` calls only; adapter failures must never block the PTY.
- `protocols/`, `docs/`, `themes/` — MIT-licensed protocol/layout/token docs and theme packs.
- `bench/` — bench suite notes; `sill bench --suite=v1` is the CI contract.

## Conventions

- Rust: `cargo test --workspace` must stay green; `cargo clippy -- -D warnings` in CI.
- Swift: `cd apps/macos && swift build`; package an app with `./bundle.sh`.
- User-facing UI copy is English. Docs are EN first; ZH mirrors welcome alongside.
- Config dir is `~/.config/sill/` everywhere (including macOS — not `~/Library`).
- `TERM=xterm-256color`, `COLORTERM=truecolor`, `TERM_PROGRAM=sill` on every spawned PTY.
- One PR per phase slice. Phase order is PRD §17; Phase A only cuts: embed libghostty,
  Rail, 7501+Ring+`Cmd+'`, Composer→PTY, Dual Surface, layout + official resume.
