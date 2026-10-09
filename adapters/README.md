# Sill adapters

Adapter = the **fallback** path for CLIs that cannot emit OSC 7501 yet
(PRD FR-008/FR-010). An adapter translates an official hook/notify mechanism
into the shared five-point model and writes it through `sill state`.

Contract:

- Uses the provider's **official** hook mechanism only; never patches the CLI,
  never writes a private state dialect.
- Installs merge into existing config without clobbering unrelated keys.
- Every adapter event carries `pid`; `sill` drops events without one.
- Adapter failure logs to `~/.config/sill/adapter-<name>.log` and exits 0 —
  it must never block the PTY.

| Provider | Mechanism | Install |
|----------|-----------|---------|
| Claude Code | `settings.json` hooks (Notification/Stop/SessionStart/UserPromptSubmit) | `claude-code/install.sh` |
| Codex CLI | `notify` array in `~/.codex/config.toml` | add `codex/status-hook.sh` to `notify` |
| Grok CLI | status bridge; untrusted dirs → `unknown` | `grok/status-hook.sh` |

When a provider starts emitting 7501 natively, its adapter becomes a no-op —
the rail listens to the wire protocol first.
