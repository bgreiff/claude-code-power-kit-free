# CLAUDE.md — <project name>

<!-- customize: one factual line about what this system is. -->
Python <service/library/CLI> for <purpose>. Python 3.12, uv-managed.
<!-- customize: pin your actual minimum Python version; several rules below assume 3.10+. -->

## Environment & tooling — uv only

- **Every command runs through uv.** `uv run pytest`, `uv run python -m app`,
  `uv run ruff check`. Bare `pytest`/`python` resolves whatever your shell has
  active — that is exactly how "passes locally, fails in CI" happens.
- Add deps with `uv add <pkg>` (dev: `uv add --dev <pkg>`). **Never `pip install`** —
  it bypasses `pyproject.toml` and the lockfile, so the dependency silently exists
  on one machine only.
- Sync after pulling: `uv sync`.
- Format + lint: `uv run ruff format . && uv run ruff check --fix .`
- Types: `uv run mypy src/` <!-- customize: or pyright/ty; align with CI. -->
- Tests: `uv run pytest` · one file: `uv run pytest tests/test_foo.py -x` ·
  one test: `uv run pytest tests/test_foo.py::test_bar`

## Project layout

```
pyproject.toml
src/<package>/        # all importable code lives here
tests/                # mirrors src/ structure; not a package inside src
```

- **src layout is deliberate.** Code imports from the *installed* package, never
  from the cwd, so packaging errors surface immediately instead of in prod.
- `tests/` must not shadow real modules or stdlib names: no `tests/logging.py`,
  no `tests/types.py`. Shadowing produces import errors that look like framework bugs.

## Agent failure modes — read before touching anything

These are the mistakes coding agents make repeatedly in Python repos. All banned:

1. **Import error → new file.** If `from app.services import billing` fails, the fix
   is *finding* the real module or fixing the environment (`uv sync`), never creating
   a fresh `billing.py` next to the caller. Duplicated modules diverge silently.
2. **Import error → `sys.path` hack.** No `sys.path.append`, no `PYTHONPATH` exports,
   no conftest path munging. The src layout + `uv sync` makes imports work; if they
   don't, packaging is broken and that is the actual bug.
3. **`pip install` to "unblock".** See tooling section. The dependency must land in
   `pyproject.toml` or it does not exist.
4. **Silencing exceptions to make tests green.** Wrapping failing code in
   `try/except` or loosening an assertion is not a fix. Find the cause.
5. **Circular import → inline imports everywhere.** One documented local import as a
   stopgap is tolerable; three means the module boundary is wrong. Say so and
   propose the restructure instead of spreading the workaround.
6. **Wrong entry point.** Run modules as `uv run python -m <package>.<module>`,
   not `python src/<package>/module.py` — file-path execution breaks relative
   imports and creates cwd-dependent behavior.

## Typing

- Type hints on **all** public functions/methods; the type checker runs in CI and
  failures block merge.
- 3.10+ syntax: `str | None`, `list[int]` — not `Optional`, `List` from `typing`.
- `Any` is an escape hatch, not a type. Reach for `object` + narrowing, a
  `Protocol`, a `TypeVar`, or `TypedDict` first. Any surviving `Any` gets a comment.
- Data crossing a boundary (API payloads, queue messages, config) gets a shape:
  pydantic model <!-- customize: or dataclass/TypedDict/msgspec --> — not a raw dict
  passed four layers deep.
- Don't add `# type: ignore` without an error code and a reason:
  `# type: ignore[arg-type]  # upstream stub is wrong, see #123`.

## Errors

- **Never `except Exception: pass`.** Catch the narrowest exception you can handle
  meaningfully; everything else propagates. Log-and-continue in library code hides
  corruption — handle at the entry point (CLI main, request handler, worker loop).
- Re-raising with context: `raise AppError("syncing invoices") from exc` — keep the
  chain; a bare `raise NewError(...)` amputates the traceback you'll need at 3 a.m.
- Raise specific exception types from `<package>.exceptions`; never raise bare
  `Exception`. Callers can't catch what they can't name.
- Validate inputs at the boundary and fail loud and early. A function that
  quietly substitutes a default for an invalid value is a data-corruption engine.

## Idioms this repo enforces

- No mutable default arguments (`def f(items: list = [])`) — ruff flags it (B006);
  fix with `None` + assignment, don't suppress the rule.
- `pathlib.Path` over `os.path` string surgery.
- `datetime.now(timezone.utc)` — never naive `datetime.now()` in domain logic, and
  never `utcnow()` (deprecated, returns a *naive* datetime; classic silent bug).
- Logging via module logger (`logger = logging.getLogger(__name__)`), never `print`.
  Lazy formatting: `logger.info("user %s", user_id)` — not f-strings, which
  evaluate even when the level is off and break log aggregation on the message key.
- Comprehensions for transforms; explicit loops once logic needs branches. No
  clever one-liners that need a comment to decode.
- Module-level code runs at import time. No I/O, no client construction at import —
  it makes imports slow, order-dependent, and untestable. Use factories or lazy init.

## Async (delete this section if the codebase is sync) <!-- customize -->

- No blocking calls in async paths: `requests`, `time.sleep`, sync DB drivers are
  banned inside `async def`. Use httpx.AsyncClient / `asyncio.sleep` / async driver.
- `asyncio.run()` appears exactly once, at the entry point — never inside library code.
- Every created task is awaited or held: fire-and-forget `create_task` without a
  reference gets garbage-collected mid-flight and swallows its exceptions.

## Testing (pytest)

- pytest style: plain functions + fixtures + `assert`. No `unittest.TestCase`
  boilerplate in new code.
- **Bug fixes are test-first:** write the test, run it, watch it fail on current
  code, then fix. A regression test that never saw the bug proves nothing.
- `@pytest.mark.parametrize` over copy-pasted test bodies.
- Filesystem via `tmp_path`, never hardcoded `/tmp`. Time via freezegun
  <!-- customize: or time-machine --> — never assert on real "now".
- **No `time.sleep` in tests.** Poll with a timeout or use fakes; sleeps are flakes
  with a delay fuse.
- Mock at the boundary (HTTP via respx/responses, external SDKs) — **never mock the
  module under test** or internal collaborators; those tests pass forever and catch
  nothing. Prefer fakes over `MagicMock` where a call signature matters:
  `MagicMock` happily accepts calls that would `TypeError` in prod.
- Tests are independent: no shared module-level mutable state, no order dependence.
  Anything global a test changes, a fixture restores.

## Git & PR rules

<!-- customize: branch naming, commit convention, CI gates. -->
- Branch: `feat/<ticket>-slug`, `fix/<ticket>-slug`; squash-merge to `main`.
- Before every commit: `uv run ruff format . && uv run ruff check . && uv run mypy src/ && uv run pytest`
- Lockfile (`uv.lock`) changes only in PRs that are *about* dependencies.
- Keep PRs single-purpose; drive-by refactors go in their own PR.

## Known traps in this repo

<!-- customize: highest-value section — the 3-6 things that actually burned someone.
     Replace these placeholders. -->
- Integration tests need Postgres up: `docker compose up -d db` first, or the suite
  hangs (not fails) at the first connection.
- `settings.py` reads env at import time (legacy); tests must use the
  `override_settings` fixture instead of setting `os.environ` directly.
- The retry decorator in `<package>.http` deliberately does not retry POST —
  do not "fix" that; it prevents duplicate side effects.
