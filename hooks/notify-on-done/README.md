# notify-on-done

**Events:** `Stop` (turn finished) + `Notification` with matcher
`permission_prompt|idle_prompt|agent_needs_input` (Claude is waiting on you) ·
**Blocking:** never

You kicked off a long task and switched windows. This hook pings you when Claude
finishes a turn or is blocked waiting for input, so the agent never sits idle for
20 minutes because you did not see the permission prompt.

Notification transport, in order of preference:

1. **macOS** — `osascript -e 'display notification ...'` (no extra installs)
2. **Linux** — `notify-send` (package `libnotify-bin` / `libnotify`)
3. **Fallback** — emits the documented `terminalSequence` JSON field with an OSC 9
   sequence so the *terminal emulator* raises the notification. Works in iTerm2,
   Kitty, WezTerm, Ghostty; plain Terminal.app/older terminals ignore it silently.

## Tuning the noise

- The `Notification` matcher in the snippet is deliberately narrow
  (`permission_prompt|idle_prompt|agent_needs_input`). Drop the matcher entirely to get
  every notification type, or remove the `Stop` block if per-turn pings annoy you and
  you only want "Claude is stuck" alerts.
- Message text is sanitized (quotes/backslashes stripped, 200-char cap — counted in
  characters via jq, so umlauts/emoji at the boundary don't garble) before being
  embedded in the notifier command — no quoting injection from notification content.

## Failure modes

- **macOS notification permissions:** if you have never allowed "Script Editor" /
  osascript notifications, macOS may swallow them. System Settings → Notifications.
  The hook cannot detect this; test once with the command below.
- **SSH / headless:** no notification daemon → falls back to `terminalSequence`; if the
  terminal does not support OSC 9 either, nothing happens. That is the correct
  worst case: silence, not errors.
- `NOTIFY_DRY_RUN=1` prints to stderr instead of notifying — handy in CI or for tests.

## Test it right now

```bash
echo '{"hook_event_name":"Notification","message":"Claude needs permission to run npm test","cwd":"'$PWD'"}' \
  | .claude/hooks/notify.sh
```

You should see a desktop notification titled "Claude Code — <project>".

## Test status

Tested with simulated stdin on macOS: real `osascript` notification fired and
delivered for both Stop and Notification payloads; dry-run output verified; message
sanitization (embedded quotes/newlines) verified; fallback `terminalSequence` JSON
branch verified by forcing the no-notifier path (schema-validated output).
`notify-send` branch is config-only — verify on your Linux box.

v1.0.1 regression test (passing): a 300-character multibyte (umlaut) message
truncates to exactly 200 *characters* with no garbled byte at the boundary.
