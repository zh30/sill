#!/bin/sh
# Sill adapter for OpenAI Codex CLI: wire via `notify` in ~/.codex/config.toml:
#   notify = ["/path/to/adapters/codex/status-hook.sh"]
# Codex passes one JSON argument describing the turn; $PPID is the codex pid.
set -u
SILL_LOG="${HOME}/.config/sill/adapter-codex.log"
SILL_BIN="${SILL_BIN:-sill}"

log() { mkdir -p "$(dirname "$SILL_LOG")"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$SILL_LOG"; }

payload="${1:-}"
pid="${PPID:-}"
[ -z "$pid" ] && { log "drop: no pid"; exit 0; }

# turn-complete notification → done; anything else → idle heartbeat.
status="done"
case "$payload" in
    *'"type":"agent-turn-complete"'*|*'"type": "agent-turn-complete"'*) status="done" ;;
    *) status="idle" ;;
esac

command -v "$SILL_BIN" >/dev/null 2>&1 || { log "drop: sill not on PATH"; exit 0; }
"$SILL_BIN" state agent=codex status="$status" pid="$pid" 2>>"$SILL_LOG" || log "sill state failed"
exit 0
