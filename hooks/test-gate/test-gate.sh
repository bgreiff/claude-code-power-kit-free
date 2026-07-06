#!/usr/bin/env bash
# test-gate — Stop hook
#
# When Claude tries to finish its turn, run the test suite. If it fails,
# block the stop and hand the failure output back to Claude so it keeps
# working. If it passes (or nothing changed since the last pass), let go.
#
# Escape hatches (any one of these disables the gate):
#   - env  CLAUDE_TEST_GATE_OFF=1
#   - file .claude/test-gate.off in the project
#   - stop_hook_active=true in the hook input (we already blocked once this
#     cycle — never create an infinite block loop). Claude Code additionally
#     force-overrides a Stop hook after 8 consecutive blocks without progress.
#
# Test command resolution (first match wins):
#   1. env  CLAUDE_TEST_GATE_CMD
#   2. file .claude/test-gate.cmd (first non-comment line)
#   3. autodetect: package.json test script / pytest / dotnet test /
#      go test / cargo test
#
# Cost control: the suite only runs when the working tree differs from the
# state at the last PASS (real tree snapshot via git write-tree, so edits to
# still-untracked files count as changes too). An unchanged tree exits fast.

INPUT=$(cat) || exit 0
command -v jq >/dev/null 2>&1 || exit 0

ROOT="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$ROOT" 2>/dev/null || exit 0

# --- escape hatches ---------------------------------------------------------
[ "${CLAUDE_TEST_GATE_OFF:-0}" = "1" ] && exit 0
[ -f "$ROOT/.claude/test-gate.off" ] && exit 0
if [ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false')" = "true" ]; then
  # We already blocked this stop once and Claude tried to stop again.
  # Let it go rather than loop; the user sees the last failure reason.
  exit 0
fi

# --- resolve the test command ------------------------------------------------
TEST_CMD="${CLAUDE_TEST_GATE_CMD:-}"
if [ -z "$TEST_CMD" ] && [ -f "$ROOT/.claude/test-gate.cmd" ]; then
  TEST_CMD=$(grep -v '^\s*#' "$ROOT/.claude/test-gate.cmd" | grep -v '^\s*$' | head -n1)
fi
if [ -z "$TEST_CMD" ]; then
  if [ -f package.json ] && jq -e '.scripts.test' package.json >/dev/null 2>&1 \
     && ! jq -r '.scripts.test' package.json | grep -q 'no test specified'; then
    TEST_CMD="npm test --silent"
  elif { [ -f pytest.ini ] || [ -f setup.cfg ] || grep -q '^\[tool\.pytest' pyproject.toml 2>/dev/null || [ -d tests ]; } \
       && command -v pytest >/dev/null 2>&1; then
    TEST_CMD="pytest -q -x"
  elif ls ./*.sln >/dev/null 2>&1 || ls ./*.csproj >/dev/null 2>&1; then
    command -v dotnet >/dev/null 2>&1 && TEST_CMD="dotnet test --nologo -v q"
  elif [ -f go.mod ]; then
    command -v go >/dev/null 2>&1 && TEST_CMD="go test ./..."
  elif [ -f Cargo.toml ]; then
    command -v cargo >/dev/null 2>&1 && TEST_CMD="cargo test --quiet"
  fi
fi
[ -n "$TEST_CMD" ] || exit 0   # nothing to gate on

# --- skip if the tree is unchanged since the last pass ------------------------
STATE_DIR="${TMPDIR:-/tmp}/claude-test-gate"
mkdir -p "$STATE_DIR" 2>/dev/null
# shasum is missing on some minimal Linux images; sha256sum is the fallback.
sha256() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256; else sha256sum; fi
}
# Key the state file to project AND test command, so parallel projects don't
# collide and a cached pass under one command can't suppress another.
KEY=$(printf '%s\n%s' "$ROOT" "$TEST_CMD" | sha256 2>/dev/null | cut -c1-16)
STATE_FILE="$STATE_DIR/pass-$KEY"

tree_hash() {
  if git rev-parse --git-dir >/dev/null 2>&1; then
    # Snapshot the REAL tree (tracked + untracked, .gitignore respected) via a
    # throwaway index — same plumbing as checkpoint.sh. Hashing porcelain text
    # instead would miss edits to files that are still untracked.
    local tmpidx tree
    tmpidx=$(mktemp "${TMPDIR:-/tmp}/claude-test-gate-idx.XXXXXX") || { echo "no-idx-$(date +%s)"; return; }
    if GIT_INDEX_FILE="$tmpidx" git read-tree HEAD 2>/dev/null \
       || GIT_INDEX_FILE="$tmpidx" git read-tree --empty 2>/dev/null; then
      GIT_INDEX_FILE="$tmpidx" git add -A . >/dev/null 2>&1
      tree=$(GIT_INDEX_FILE="$tmpidx" git write-tree 2>/dev/null)
    fi
    rm -f "$tmpidx"
    if [ -n "$tree" ]; then echo "$tree"; else echo "no-tree-$$-$(date +%s)"; fi  # plumbing failed: never skip
  else
    echo "no-git-$$-$(date +%s)"   # outside git: never skip ($$ so same-second stops can't collide)
  fi
}
CURRENT_HASH=$(tree_hash)
if [ -f "$STATE_FILE" ] && [ "$(cat "$STATE_FILE" 2>/dev/null)" = "$CURRENT_HASH" ]; then
  exit 0
fi

# --- run the suite ------------------------------------------------------------
OUTPUT=$(eval "$TEST_CMD" 2>&1)
STATUS=$?

if [ "$STATUS" -eq 0 ]; then
  printf '%s' "$CURRENT_HASH" > "$STATE_FILE" 2>/dev/null
  exit 0
fi

# --- block the stop, feed the failure back to Claude ---------------------------
TAIL=$(printf '%s\n' "$OUTPUT" | tail -n 30)
REASON="Test gate: \`$TEST_CMD\` failed (exit $STATUS). Fix the failing tests before finishing. If this is expected, the user can disable the gate with: touch .claude/test-gate.off

Last 30 lines of output:
$TAIL"

jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
exit 0
