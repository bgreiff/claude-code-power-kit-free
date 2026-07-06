# test-gate

**Event:** `Stop` (no matcher — Stop hooks fire whenever Claude finishes a turn) ·
**Blocking:** yes, via `{"decision": "block", "reason": ...}`

Claude is not allowed to declare itself done while the test suite is red. When Claude
tries to finish, this hook runs your tests; on failure it blocks the stop and feeds the
last 30 lines of test output back to Claude, which then keeps working on the failures.

## Choosing the test command

First match wins:

1. `CLAUDE_TEST_GATE_CMD` environment variable
2. `.claude/test-gate.cmd` — first non-comment line, e.g. `pytest -q tests/unit`
   (**recommended**: explicit beats autodetection)
3. Autodetect: `npm test` (if `package.json` has a real test script), `pytest -q -x`,
   `dotnet test`, `go test ./...`, `cargo test --quiet`

No test command found → the gate is inert (exit 0).

## Escape hatches — read this before installing

A Stop-blocking hook is the sharpest tool in this pack. Three ways out:

- `touch .claude/test-gate.off` — persistent off switch (delete the file to re-arm)
- `CLAUDE_TEST_GATE_OFF=1` in the environment
- The hook honors `stop_hook_active`: if it already blocked this stop cycle once, it
  lets the next stop through instead of looping. (Claude Code itself also
  force-overrides a Stop hook after 8 consecutive blocks without progress.)

## Cost control

`Stop` fires at the end of *every* turn, including "explain this function" turns.
Running a full suite each time would be miserable, so the hook hashes
`HEAD + git status + git diff` and **skips the suite when the tree is unchanged since
the last pass**. First green run caches; subsequent stops are near-instant until you
actually change something. Outside a git repo it runs every time.

Keep the suite the gate runs *fast* (unit tier). Point `.claude/test-gate.cmd` at a
subset if your full suite takes minutes, and raise/lower the snippet's `timeout: 300`
to fit. If the hook times out, Claude Code cancels it — the stop proceeds (fails open).

## Failure modes

- **Slow suite + impatient you:** the gate runs synchronously; you wait. Use the
  fast-subset advice above.
- **Flaky tests:** a flaky red blocks the stop and sends Claude off to "fix" a test
  that isn't broken. Gate only on your deterministic tier.
- **`eval` of the command string:** the test command is executed via `eval`, exactly as
  written by *you* in the config file/env var. Do not point it at untrusted content.

## Test status

Tested with simulated stdin on macOS: failing command → JSON `{"decision":"block",...}`
with output tail; passing command → silent exit 0 and pass-hash cached;
unchanged-tree skip verified; `stop_hook_active: true` → immediate exit 0;
`.claude/test-gate.off` → immediate exit 0. Autodetect tested for the
package.json branch; other detectors are config-only — verify in your setup.
