---
name: land-pr
description: Land a PR the user has judged ready — check CI and the review bot, verify locally what CI doesn't (Python tests, macOS build, affected UI journeys, Android tests), merge with rebase, finish every remaining finding directly on main, tidy bookkeeping, and finish with a short landing summary and what /deploy or /archive will need. Invoke with the PR number. Never deploys or archives.
disable-model-invocation: true
---

# Land PR

The user runs this once they have **decided** the PR lands. That decision is theirs:
everything still open — review findings, follow-ups, polish — gets finished with
direct commits on `main` after the merge, not by another PR round. Your job is to
land it cleanly, finish it on main, and hand back a summary they can absorb in a
minute.

**Only two things pause before the merge:**
1. Code that **doesn't build or whose tests fail** (Step 2).
2. Something that **can't be fixed after the merge**: a close keyword that would
   wrongly close an outside reporter's issue, a finding that would leak personal
   data or open a security hole the moment it's live, or a CloudKit schema change
   that looks wrong (production schema can't be rolled back).

When you pause, **never run `/process-review` or anything else yourself.** Report
what you found and offer the options (fix on the branch, land anyway and fix on main,
send it back through `/process-review`), with your recommendation. The user decides.

Run locally on the Mac (iOS/macOS verification needs Xcode). `gh` must run with the
sandbox disabled, otherwise it returns empty with exit 0. Run heavy jobs (xcodebuild,
full pytest, gradle) one at a time, never concurrently.

## Inputs

- `<pr-number>` — required; if missing, use the PR for the current branch, else ask
  and stop.

## Step 1 — Pre-merge checks

Mechanical checks first; only the cases marked **pause** stop the merge:

1. **State:** open, not draft, `mergeStateStatus` not `DIRTY` (conflicts).
   `gh pr view <n> --json state,isDraft,mergeStateStatus,headRefOid,headRefName,baseRefName,body,commits,files`
2. **CI on the head commit:** `gh pr checks <n>`. Only the **iOS unit** workflow
   runs, and only when `app/flyfun-forms/**` changed. Pending → wait (poll in the
   background, ~10 min max); never call a pending run green. A failing check →
   **pause** only if it's a build/test failure in the PR's own code; a flaky or
   unrelated job can be noted and landed.
3. **Review bot:** read **every** round's comment by `claude` whose first line
   contains "Code Review", not just the last. If there's no review on the head
   commit, note it and carry on — the user chose to land.
4. **Triage every finding** still open across all rounds into "fix on main",
   "issue (needs design)" or "skip (why)". **Pause** only for the narrow cases
   above. Regular bugs are fixed on main.
5. **Close keyword.** For each linked issue, check the author
   (`gh issue view <N> --json author`). Issues filed by `roznet` → `Closes #N`.
   Issues from an **outside reporter** → must be `Addresses #N`, in the PR body
   **and** every commit body, because GitHub acts on the commit:
   `git log origin/<base>..<head> --format=%B | grep -inE "close[sd]?|fixe?s?|resolve[sd]?"`.
   A stray `closes #N` for an outside reporter → **pause**.

## Step 2 — Verify what CI didn't

Check the PR head out locally: `git fetch origin && git switch --detach <head-sha>`.
If the checkout has uncommitted changes, don't touch them — stop and say so. Pick
the steps by the files the PR touches:

- **Python (`src/`, `tests/`, mappings, templates)** — CI never runs it, so this is
  the only gate: `./venv/bin/python -m pytest -q` (full suite; 600 s timeout). A
  snapshot failure here means the PR changed form output without updating the
  goldens — **pause**, it's a failing test.
- **iOS / macOS (`app/flyfun-forms/`)**, from that directory:
  1. CI green on the head commit already proves the iOS build and **unit** target —
     don't redo that. Rebuild only if CI didn't run or failed.
  2. **macOS build** — CI never builds it:
     `xcodebuild build -scheme flyfun-forms -project flyfun-forms.xcodeproj -destination 'platform=macOS'`
  3. **UI journeys** (nightly only, not gated): find the XCUI tests that exercise
     the changed views (grep `flyfun-formsUITests` for the touched view names and
     accessibility IDs) and run them by **type** with
     `-only-testing:flyfun-formsUITests/<Type>` and a `-resultBundlePath`. Read the
     count back (`xcrun xcresulttool get test-results summary --path <xcresult>`):
     a filter that matches nothing still prints `TEST SUCCEEDED`. If no UI test
     covers the change, say so.
- **Android (`app/android/`)** — unreleased; just `./gradlew test` in `app/android`.
- **Human-only checks.** List the specific things the user should look at — only
  what this diff could affect: a filled form via `flightforms preview <form>` for
  form-output changes; screens and states in the simulator (iPhone vs iPad vs Mac,
  dark mode, a non-English language for new strings).

A failing build or test → **pause**: report the failure (error excerpt, which test)
and offer the options, with your recommendation — usually a fix pushed to the
branch, since the merge would otherwise break main.

When done, return the checkout to `main` (`git switch main`).

## Step 3 — Merge

`gh pr merge <n> --rebase --delete-branch`. If the rebase doesn't apply, fall back
to `--merge` and say so. Confirm that the linked issues closed (or deliberately did
not, for `Addresses`). Delete the local branch if it exists and is merged.

## Step 4 — Finish it on main

- `git switch main && git pull --rebase origin main`; the checkout must be clean.
  Re-check the branch before committing.
- Apply **all** the "fix on main" findings, plus any small "Follow-ups noticed" from
  the brief. Anything that genuinely needs design thought gets a **detailed issue**
  (root cause, call sites, acceptance criteria) for an implementation agent, not an
  in-session fix.
- Run the targeted tests for what you touched (pytest; for Swift, build + unit
  tests, the macOS build and the affected UI journey; Android `./gradlew test`)
  before pushing.
- One commit, `Follow-up to #<pr>: …`, specific paths only, attribution trailer.
  Push.

## Step 5 — Bookkeeping

- **Memory:** grep the memory dir for the issue/PR numbers. Any note that still
  calls this work pending, open or unmerged → update it to the landed state, or
  delete it if it's now only history.
- **Design docs (safety net):** `/implement-issue` should have updated the docs in
  the PR — check the diff did. If it didn't, or your on-main fixes changed documented
  behaviour or choices, update the affected docs in the follow-up commit, scoped to
  what changed (`/sync-designs <doc path>`, never a full sync). Fix any
  `designs/future/` status line the work made stale.
- **Privacy:** if the PR changed what is collected, sent or synced, check
  `PRIVACY.md` reflects it, and flag whether the App Store privacy labels need an
  update at the next `/archive`.
- **Strings:** new catalog entries have FR/DE/ES translations, not just EN.

## Step 6 — Landing summary

Final message, **≤ ~15 lines**, plain words. A condensed version of the PR's Owner's
brief, updated with what actually happened here:

```
## Landed #<pr> — <title>   (closes #N | addresses #N)

**What it does:** <one line, pilot/owner terms>
**For the pilot:** <visible change on forms / in the app, or "nothing visible">
**Forms affected:** <airports/forms whose output changed, or "none">
**Fixed on main after merge:** <commit sha — what; or "none">
**Verified:** pytest <N passed> · iOS unit <CI / local> · macOS build <ok | n/a> · UI journeys <which, N passed | none cover it> · Android <N passed | n/a>
**Your check:** <filled form to eyeball / simulator screens, or "none needed">
**Ship with:** server `/deploy` <needed | not needed> · `/archive` <iOS/macOS, What's New line | not needed>
**Left open:** <issues opened, deferred findings, decisions still pending — or "none">
```

**Never deploy or archive, and never start `/deploy` or `/archive`.** Shipping is
the user's separate, confirmed step.
