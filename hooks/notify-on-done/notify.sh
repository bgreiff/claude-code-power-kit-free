#!/usr/bin/env bash
# notify-on-done — Stop + Notification hook
#
# Desktop notification when Claude finishes a turn (Stop) or needs your
# attention (Notification: permission prompt, idle, agent needs input).
# macOS: osascript. Linux: notify-send. Fallback: the documented
# `terminalSequence` JSON field (OSC 9), which lets the terminal emulator
# itself raise a notification (works in iTerm2, Kitty, WezTerm, Ghostty...).
#
# NOTIFY_DRY_RUN=1 prints the would-be notification to stderr instead of
# sending it (used for testing). Never blocks; every path exits 0.

INPUT=$(cat) || exit 0
command -v jq >/dev/null 2>&1 || exit 0

EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "${CWD:-${CLAUDE_PROJECT_DIR:-$PWD}}")

case "$EVENT" in
  Notification)
    MSG=$(printf '%s' "$INPUT" | jq -r '.message // "Claude needs your attention"')
    ;;
  Stop)
    MSG="Finished responding"
    ;;
  *)
    MSG="Claude Code"
    ;;
esac
TITLE="Claude Code — $PROJECT"

# Sanitize for embedding in quoted strings (osascript/notify-send):
# strip backslashes and double quotes, collapse newlines, cap length.
CLEAN_MSG=$(printf '%s' "$MSG" | tr '\n' ' ' | tr -d '\\"' | cut -c1-200)
CLEAN_TITLE=$(printf '%s' "$TITLE" | tr -d '\\"' | cut -c1-100)

if [ "${NOTIFY_DRY_RUN:-0}" = "1" ]; then
  printf 'DRY RUN notify: [%s] %s\n' "$CLEAN_TITLE" "$CLEAN_MSG" >&2
  exit 0
fi

if [ "$(uname)" = "Darwin" ] && command -v osascript >/dev/null 2>&1; then
  osascript -e "display notification \"$CLEAN_MSG\" with title \"$CLEAN_TITLE\"" >/dev/null 2>&1
elif command -v notify-send >/dev/null 2>&1; then
  notify-send "$CLEAN_TITLE" "$CLEAN_MSG" >/dev/null 2>&1
else
  # No native notifier: hand the terminal an OSC 9 notification sequence via
  # the documented JSON `terminalSequence` field (supported terminals only).
  jq -n --arg seq "$(printf '\033]9;%s: %s\007' "$CLEAN_TITLE" "$CLEAN_MSG")" \
    '{terminalSequence: $seq}'
fi

exit 0
