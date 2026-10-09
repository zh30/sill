#!/bin/sh
# Sill adapter for Grok CLI. Grok's trust model: when the project directory is
# not trusted the CLI must report `unknown`, never crash (PRD FR-010).
# Install as Grok's status/notification hook per its official docs, or wrap
# launches: `grok status-bridge` inside a sill pane.
set -u
SILL_LOG="${HOME}/.config/sill/adapter-grok.log"
SILL_BIN="${SILL_BIN:-sill}"

log() { mkdir -p "$(dirname "$SILL_LOG")"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$SILL_LOG"; }

pid="${PPID:-}"
[ -z "$pid" ] && { log "drop: no pid"; exit 0; }

event="${1:-unknown}"
case "$event" in
    awaiting|blocked) status="awaiting" ;;
    done|complete)    status="done" ;;
    working|start)    status="working" ;;
    *)                status="unknown" ;;
esac

# Untrusted dirs still get a safe record: `unknown` with liveness only.
command -v "$SILL_BIN" >/dev/null 2>&1 || { log "drop: sill not on PATH"; exit 0; }
"$SILL_BIN" state agent=grok status="$status" pid="$pid" 2>>"$SILL_LOG" || log "sill state failed"
exit 0
