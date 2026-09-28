## Always start here

Design docs give you architecture, key exports, and non-obvious decisions faster than grepping. For any task that touches code (features, bug fixes, UX questions, "how does X work", refactors), BEFORE reading or grepping:

1. Call the `mcp__library-docs__list_libraries` MCP tool (or read `designs/INDEX.md` if the server is unavailable). It is an MCP tool, not a skill — do NOT invoke it via `Skill`.
2. If a relevant module appears, call `mcp__library-docs__get_design_doc` (or read `designs/<module>.md`).
3. Only then explore with Grep/Read.

For `[library]` entries: import and reuse. For `[project]` entries: follow the patterns. Skip this only for trivial edits (typo, one-line change in a file already in context).

## Read the design doc before you write

- **Adding or changing a form** → `/add-form`, and `designs/form-system.md` (mapping match order: exact ICAO → `icao_list` → prefix → default).
- **Touching the iOS models or sync** → `designs/ios-app.md` (SwiftData + CloudKit; schema changes must stay CloudKit-compatible).
- **A new flight import source** → `designs/flight-import.md` (every source produces a `FlightDraft`).
- **User-facing strings** → `designs/localisation.md` (EN/FR/DE/ES String Catalogs).

## Privacy invariant

The server never stores PII. Passenger and crew data lives only in memory during `/generate`, `/prefill` and `/validate`; the database holds only user accounts and usage counts. Never log request bodies or persist people/document data server-side. If a change affects what is collected or where it goes, update `PRIVACY.md` (served at `/privacy`).

## Working from a GitHub issue

Read the full comment thread (`gh issue view <n> --comments`), not just the body — planning and design decisions land in comments and supersede the original description.

## Finding the code-review bot's review on a PR

The bot posts an ordinary **comment on the PR's conversation tab** — not a GitHub "Review", not inline diff comments. Look in `gh pr view <n> --comments` for a comment by `claude` whose **first line contains "Code Review"**. Match on the text, not the markdown decoration.

## Code Design Principles

- When adding logic around a library call (flyfun-common, rzflight, euro-aip), first consider enhancing the library instead of wrapping it in client code.
- Prefer pushing complexity into well-tested, reusable library code over ad-hoc client-side handling.
- Search for existing logic before duplicating.

## Changing Function Signatures

- Grep for ALL callers across the codebase and update them — not just the obvious ones.
- Avoid a function used both as `Depends(fn)` and called directly: `Depends()` defaults silently become real values outside DI. If unavoidable, split into a pure logic function and a thin DI wrapper.

## Testing

- Form output is covered by golden files in `tests/snapshots/`. When a mapping or template change is intentional, regenerate with `pytest tests/unit/test_snapshots.py --snapshot-update` and review the JSON diff. Don't regenerate just to turn a red test green.
- `flightforms preview` produces forms filled with self-describing dummy data for visual checks. Never use real-looking personal data in examples or placeholders.
- **CI runs the iOS unit target only** (`flyfun-formsTests`) — the XCUI tests run nightly via `.github/workflows/ios-ui-nightly.yml`. Run `-only-testing:flyfun-formsUITests` locally before merging a UI change.

## Setup

- **Each worktree (including `main/`) has its own venv at `./venv`**, so a worktree can `pip install -e` a local checkout of a library (flyfun-common, rzflight, euro-aip) and change it without affecting other worktrees. Never fall back to `../main/venv`. Missing venv → `python -m venv venv && source venv/bin/activate && pip install -e .`.
- `/devserver` runs the backend in tmux session `flightforms` at `https://localhost.ro-z.me:8443` for the iOS simulator.

## Release & deploy

- `/deploy` → forms.flyfun.aero. Only when asked.
- `/archive` → iOS/macOS App Store staging; never submits for review. Tags are `ios/{version}` / `macos/{version}` without the build number; release notes go in `release-notes/<platform>-<version>.txt`.
