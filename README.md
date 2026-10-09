# Sill

**Sill — the attention surface for agents.** A terminal on the libghostty core
with an attention rail, focus ring, dual surface, and a composer that writes
straight into the PTY. Built for running 4–8 agent CLIs in parallel and always
knowing **who is waiting on you**.

> 中文：Sill 是 Agent 终端 —— 用 libghostty 的核，跑并行 Agent 时比 Otty 更清楚、更轻、能带走。界面与文档以英文为主（中文文档随附）。实现以 [`docs/Sill-PRD-v0.4.md`](docs/Sill-PRD-v0.4.md) 为准。

- Platforms: macOS 14+ (first-class today) · Linux chrome planned · no Windows GUI in v1
- Program status: public **OSC 7501** first; official-hook fallback via `sill state`
- No accounts, zero default network, no Electron, no second VT parser

## Layout

| Path | What |
|------|------|
| `core/sill-core` | Rust static C ABI lib: OSC 7501/133/7 scanner, status store, `layout.toml`, Ghostty import |
| `cli/sill` | `sill` binary — `state`, `export`, `import ghostty`, `bench` |
| `apps/macos` | SwiftPM app → `dist/Sill.app` (Rail, Ring, Composer, Dual Surface, Terminal Mode, Palette) |
| `adapters/` | claude-code / codex / grok official-hook adapters → `sill state` |
| `protocols/` | MIT protocol docs (`osc-7501.md`) |
| `docs/` | PRD, architecture, layout format |
| `themes/` | TOML theme packs: `void`, `dayglass` |
| `bench/` | bench contract; `sill bench --suite=v1` is the release gate |
| `vendor/` | libghostty pin (pending; app runs a dev backend meanwhile) |

## Build & run

```bash
make test        # cargo test --workspace
make cli         # builds target/debug/sill
make bundle      # builds apps/macos → dist/Sill.app
make run         # opens dist/Sill.app
```

Requires: Rust toolchain, Xcode 26 / Swift 6 (macOS app), macOS 14+ to run.

## Try it (J1/J2 demo path)

1. `make bundle && make run` → Home Canvas: **New Agent Session** / **Plain Terminal**.
2. Open a Plain Terminal (or a detected provider if `claude`/`codex`/`grok` is on PATH).
3. In the pane's shell, emit a status:

   ```bash
   printf '\e]7501;state=blocked:kind=permission:app=demo\a'
   ```

   The rail row shows `awaiting · permission`, the surface gets a 2px focus ring,
   `Cmd+'` jumps to it, and the Composer is focused — `Cmd+Enter` sends into the
   PTY via bracketed paste, `Esc` hands input back to the terminal.

## Status

Phase A foundation (PRD §17): monorepo scaffold, `sill-core`, `sill` CLI, macOS
app IA on the `SwiftTermSurface` dev backend. Next: vendor pinned libghostty and
swap `LibghosttySurface` in; then Phases B–F.

See `docs/architecture.md` for the seam that makes the backend swap local.
