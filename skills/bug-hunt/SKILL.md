---
name: bug-hunt
description: Systematic root-cause protocol for bugs — reproduce first, then isolate (bisect), instrument to confirm the mechanism, fix the cause, and prove the fix with a fail-before/pass-after check. Use when the user reports a bug, a regression, a failing or flaky test, "this used to work", unexpected behavior, or asks why something is broken.
argument-hint: "[bug description or failing command]"
---

# Bug Hunt

The prime rule: **reproduce before you read code**. A fix without a failing
reproduction is a guess — you cannot prove a guess worked, and "it doesn't happen
anymore" is how the same bug ships twice. Every phase below feeds the next; skipping
one is how debugging turns into thrashing.

Bug under investigation: $ARGUMENTS

## Phase 1 — Reproduce (do this before opening a single source file)

1. Get the exact failure: the command, input, environment, and the verbatim error
   output or wrong value. "It crashes sometimes" is not a bug report yet — extract
   the concrete case.
2. Run it yourself. Observe the failure firsthand; do not proceed on someone's
   description of it.
3. Capture the repro as an executable artifact — a test case if possible, a script
   otherwise — that exits non-zero on failure. This artifact is the backbone of
   everything after; it's what bisect runs and what proves the fix.
4. Make it deterministic and fast. Strip the repro down: smaller input, fewer steps,
   no network if avoidable. A 2-second repro gets run 50 times; a 5-minute one gets
   run twice and you start guessing again.

**If you cannot reproduce it:** do not "fix" anything. Diff the environments instead
(versions, OS, locale/timezone, data shape, concurrency, clock) — the bug lives in
that diff. For intermittent failures, force frequency up: loop it
(`for i in $(seq 100); do <cmd> || break; done`), add load, shrink timeouts.
If it still won't reproduce, the deliverable is added instrumentation at the suspected
site plus a monitoring note — say so honestly.

## Phase 2 — Isolate

Shrink the search space along whichever axis is cheapest:

- **Time (regression?)**: if it used to work, `git bisect` with your repro script is
  usually the fastest possible path to the cause — often minutes to the exact commit.
  See [bisect-guide.md](bisect-guide.md) for `git bisect run` scripting, flaky-test
  bisecting, and exit-code rules.
- **Space**: binary-search the input/config. Delete half the input — still failing?
  Delete half again. Disable plugins/middleware/feature flags in halves. Works in
  isolation but fails in the suite? The suite's ordering or shared state is the lead.
- **Environment**: fails only in CI/prod? Reproduce in the closest environment you
  can reach (container with same image, same env vars). Do not guess-fix from local.

## Phase 3 — Understand the mechanism

Only now read the code — with the repro in hand, you read the failing path, not the
whole codebase.

Work hypothesis-first: state a specific hypothesis ("the cache returns a stale entry
because the key omits the tenant id"), derive an observation that must be true if it
holds, then instrument to check exactly that — a targeted log line, a debugger
breakpoint, an assertion. One hypothesis, one probe, one result. Shotgunning print
statements everywhere produces noise, not knowledge.

You understand the bug when you can explain the full causal chain — trigger →
mechanism → observed failure — and predict variations ("then passing X instead
should also fail"). Test that prediction; if it surprises you, you don't understand
it yet.

## Phase 4 — Fix

- Fix the cause, not the symptom. If the crash is a null deref, the fix is rarely
  "add a null check" — it's "why was that null possible here at all?"
- Smallest change that removes the cause. Resist drive-by refactoring; it obscures
  the fix in review and risks new regressions.
- Hunt siblings: the same mistake pattern usually exists elsewhere. Grep for the
  pattern you just fixed and check each hit.
- Remove your instrumentation (or promote genuinely useful probes to proper
  log/assert statements deliberately — never leave debris by accident).

## Phase 5 — Prove it (fail-before / pass-after)

The non-negotiable, non-vacuous proof — both directions:

1. **Fail-before**: run the repro against the pre-fix code (`git stash` the fix, run,
   confirm it FAILS, `git stash pop`). If the repro passes without the fix, it never
   captured the bug and your green result proves nothing.
2. **Pass-after**: run the repro with the fix. It passes.
3. Run the surrounding test suite for regressions.
4. Keep the repro as a permanent regression test, named after the behavior
   (not `test_bugfix_123`), committed with the fix.

## Edge cases

- **Race conditions / heisenbugs**: widen the race window to make it deterministic —
  insert a sleep at the suspected interleaving point; if the failure rate jumps,
  you've found the window. Stress-loop for statistical repro; treat "1 failure in
  200 runs" as your baseline and require 0-in-500 after the fix.
- **Bug is in a dependency**: prove it by version-bisecting the dependency (pin the
  previous version → passes?). Then upgrade to a fixed release, or pin + link the
  upstream issue. Don't monkey-patch silently.
- **Your fix breaks a different test**: stop. Either that test encoded the buggy
  behavior as expected (update it consciously, and say so), or your fix is wrong.
  Decide which by reading the test's intent — never blindly update assertions to
  match new output.
- **Multiple bugs tangled together**: fix one at a time, re-running the repro after
  each. Two simultaneous changes make the proof in Phase 5 meaningless.

## What NOT to do

- Don't touch source code before a captured, failing reproduction exists.
- Don't apply several candidate fixes at once — you won't know which one worked, or
  whether two of them cancel out somewhere else.
- Don't modify the test to make it pass unless you can articulate why the test —
  not the code — was wrong.
- Don't declare victory on "ran it a few times, seems fine" for anything that was
  intermittent. Numbers or it didn't happen.
- Don't delete the repro after the fix. It's the cheapest regression insurance the
  project will ever get.
- Don't stop at the first plausible explanation. Plausible is not proven — run the
  probe.
