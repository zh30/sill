#!/bin/sh
# Sill adapter for Claude Code: translates official hook events into
# `sill state` records (the fallback path for CLIs not emitting OSC 7501).
# Hook JSON arrives on stdin; $PPID is the claude process that spawned us —
# sill drops adapter events that have no pid (PRD FR-008), so this is required.
# Adapter failure must never block the PTY: every error exits 0 after logging.

set -u
SILL_LOG="${HOME}/.config/sill/adapter-claude.log"
SILL_BIN="${SILL_BIN:-sill}"

log() { mkdir -p "$(dirname "$SILL_LOG")"; printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$SILL_LOG"; }

payload="$(cat 2>/dev/null || true)"
event="${1:-unknown}"
pid="${PPID:-}"

if [ -z "$pid" ]; then
    log "drop: no pid (event=$event)"
    exit 0
fi

# Map official hook event names onto the shared five-point model.
case "$event" in
    Notification)
        status="awaiting"; kind="permission" ;;
    Stop)
        status="done"; kind="" ;;
    UserPromptSubmit|PreToolUse|PostToolUse)
        status="working"; kind="" ;;
    SessionStart)
        status="idle"; kind="" ;;
    *)
        log "drop: unmapped hook event=$event"
        exit 0 ;;
esac

session="$(printf '%s' "$payload" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"

set -- "$SILL_BIN" state agent=claude status="$status" pid="$pid"
[ -n "$session" ] && set -- "$@" session="$session"
[ -n "$kind" ] && set -- "$@" kind="$kind"

if ! command -v "$SILL_BIN" >/dev/null 2>&1; then
    log "drop: sill binary not on PATH (event=$event)"
    exit 0
fi
"$@" 2>>"$SILL_LOG" || log "sill state failed (event=$event status=$status)"
exit 0
