#!/bin/sh
# Install the Sill status hook into Claude Code's settings.json.
# Official-hook path only (FR-010): merges our hook entries without touching
# unrelated settings keys. Requires jq for the merge; otherwise prints the
# JSON block to paste manually.

set -eu

SETTINGS="${HOME}/.claude/settings.json"
ADAPTER="$(cd "$(dirname "$0")" && pwd)/status-hook.sh"
chmod +x "$ADAPTER"

hook_entry() {
cat <<JSON
{
  "hooks": {
    "Notification": [{"matcher": "", "hooks": [{"type": "command", "command": "$ADAPTER Notification"}]}],
    "Stop":         [{"matcher": "", "hooks": [{"type": "command", "command": "$ADAPTER Stop"}]}],
    "SessionStart": [{"matcher": "", "hooks": [{"type": "command", "command": "$ADAPTER SessionStart"}]}],
    "UserPromptSubmit": [{"matcher": "", "hooks": [{"type": "command", "command": "$ADAPTER UserPromptSubmit"}]}]
  }
}
JSON
}

mkdir -p "$(dirname "$SETTINGS")"
if ! command -v jq >/dev/null 2>&1; then
    echo "jq not found — merge this block into $SETTINGS manually:"
    hook_entry
    exit 0
fi

tmp="$(mktemp)"
if [ -f "$SETTINGS" ]; then
    # Deep-merge: keep every existing key; append our commands if absent.
    jq --arg adapter "$ADAPTER" '
      def entry($ev): {"matcher": "", "hooks": [{"type": "command", "command": ($adapter + " " + $ev)}]};
      .hooks //= {} |
      reduce ("Notification","Stop","SessionStart","UserPromptSubmit") as $ev (.;
        .hooks[$ev] //= [] |
        if (.hooks[$ev] | map(.hooks[]?.command // "") | any(. == ($adapter + " " + $ev)))
        then . else .hooks[$ev] += [entry($ev)] end
      )' "$SETTINGS" >"$tmp"
else
    hook_entry | jq . >"$tmp"
fi
mv "$tmp" "$SETTINGS"
echo "Installed Sill status hooks into $SETTINGS"
