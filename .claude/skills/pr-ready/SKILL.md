---
name: pr-ready
description: Get a Raintile branch ready to be tested by the user or to become a pull request on nightly - checks, builds, docs in sync, a review pass for large changes, the PR text, branch cleanup. Use before asking the user to test a branch, before opening a PR, or when the user asks whether a branch is ready.
---

# Getting a branch ready

Follow `CLAUDE.md`; this is the order of the steps that keep coming back. Report what
passed, what failed and what was not verified.

## 1. Checks and builds
1. `python tools/check.py` (pre-push hook too: `python tools/check.py --install-hook`).
   A fixed bug has a test that fails without the fix (`tests/lua`, `tests/ps`).
2. Anything under `src/Options/` changed: `dotnet build src/Options/RaintileOptions.csproj -c Release`
   (0 errors), then `powershell -NoProfile -ExecutionPolicy Bypass -File tools\dev-build.ps1`
   so the live test runs the new program (close the Options window first).
3. The schema of `Options.ps1` changed: `python tools/gen_options_schema.py --check` when
   `pwsh` exists; otherwise say the `package` check will do it.
4. The layout of the Options window changed: `powershell -NoProfile -ExecutionPolicy Bypass
   -File tools\options-shots.ps1 -Base origin/nightly`, then look at the changed pages in
   `build\options-shots\diff\`. Only for such changes: it takes a few minutes.

## 2. Docs in sync
- A new or changed setting: its comment in `@Resources/Settings.inc` and the "Settings
  reference" in `docs/Guide.md`.
- Changed behaviour: its section of `docs/Guide.md`; a feature: `README.md` too.
- The Options window: `docs/OptionsUI.md` if a rule or a helper changed.
- Widgets: `docs/Widgets.md` for API changes, `widgets/index.json`.
- A new page in `docs/`: `PAGES` of `tools/build_wiki.py`.

## 3. Review pass (large changes)
For a change over many files or several sessions, look for duplicated code, dead code
(fields, helpers, branches no longer reached) and changes made on one side only (the
Options program but not `Options.ps1`). Use `/simplify` or `/code-review`, fix, check
again. Do not restructure code that is not part of the change.

## 4. Hand over
- Commit on the branch (`feature/<name>` or `fix/<name>`, base `nightly`) and push.
- Ask the user to test live, saying what to try (pages, modes, the fallback window).
- Open the PR only when asked. Base `nightly`, in English:
  - one `##` heading per change (several changes in one PR only when the user asked);
  - `## Docs`: the docs changed;
  - `## Verified`: what passed (check.py, build, tests, live), and what was **not**
    verified;
  - the attribution line of the session.

## 5. After the merge
Delete what the merge left behind: branches folded into another PR (local and
`origin`), their worktrees (`git worktree remove`, `.claude/worktrees/`), the local
branch of the merged PR. Never other people's branches; list them and ask.
