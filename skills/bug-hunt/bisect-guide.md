# Bisect guide — finding the breaking change fast

Binary search over history: 1,000 commits is ~10 test runs. Almost always faster
than reading code, *if* you have an executable repro (Phase 1's artifact).

## git bisect run (the automated form — prefer it)

```bash
git bisect start
git bisect bad                  # current commit fails
git bisect good v2.3.0          # last known-good tag/commit/SHA
git bisect run ./repro.sh       # git does the rest
# ... git prints "<sha> is the first bad commit"
git bisect reset                # ALWAYS reset when done
```

### Exit-code contract for repro.sh

| Exit code | Meaning to bisect |
| :--- | :--- |
| 0 | good (bug absent) |
| 1–124, 126, 127 | bad (bug present) |
| **125** | skip this commit (can't test — e.g. build broken) |
| ≥ 128 | aborts the bisect |

A robust repro script separates "can't build" from "bug present":

```bash
#!/usr/bin/env bash
npm ci --silent || exit 125          # unbuildable commit != bad commit
npm run build --silent || exit 125
npx vitest run tests/webhook.spec.ts # actual repro: its exit code decides
```

Forgetting the 125 case is the classic bisect mistake: one unbuildable commit in the
range gets marked "bad" and the search converges on the wrong commit.

## Bisecting a flaky failure

A repro that only fails sometimes will randomly mislabel commits and corrupt the
search. Make the script statistical — fail if ANY of N runs fails:

```bash
#!/usr/bin/env bash
npm ci --silent || exit 125
for i in $(seq 20); do
  npx vitest run tests/flaky.spec.ts || exit 1
done
exit 0
```

Pick N so that a truly-bad commit fails with high probability: if the bug shows up
~1 in 5 runs, 20 runs miss it with probability (4/5)^20 ≈ 1%. Slower per step, but
the answer is right.

## Practical notes

- **Test files change across history**: if the repro test didn't exist at the good
  commit, keep `repro.sh` and the test OUTSIDE the repo (e.g. `/tmp/repro/`) and have
  the script copy it in, or invoke the app externally (curl, CLI call).
- **Shortcut when you suspect a subsystem**: `git bisect start -- src/auth/` bisects
  only commits touching that path.
- **First bad commit is a giant merge**: bisect again within the merged branch, or
  read the merge's diff scoped to the suspect path.
- **Check your bounds first**: before starting, run the repro at the "good" commit
  manually. If it fails there too, your good bound is wrong and the whole bisect
  answers the wrong question.

## Bisection beyond git

The same halving logic works on anything orderable:

- **Dependency versions**: bug appeared without code changes? Binary-search the
  package version (`npm i lib@4.2.0`, run repro, halve the range). Lockfile diffs
  between the last-good and first-bad deploy tell you which packages moved.
- **Config/flags**: disable half the middleware/plugins/flags; recurse into the
  failing half.
- **Data**: split the failing input file in half; recurse into the half that still
  fails. Ten steps reduce 100k records to ~100.
