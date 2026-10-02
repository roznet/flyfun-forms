---
name: implement-issue
description: Implement a GitHub issue end-to-end — read the thread + design docs, branch, build, verify what this machine can verify, open a PR — and finish with a short owner's brief (what changes on the forms and in the app, privacy and sync impact, what could go wrong, how we know it works, what to ask) plus a "pick up on a Mac" checklist for anything that couldn't be built or tested here. Invoke with the issue number.
disable-model-invocation: true
---

# Implement issue

The user owns an app that fills in **official customs and immigration forms** with
people's passport data, and doesn't review code line by line. The deliverable is
therefore **two things**: a PR that works, and a brief that lets them understand
and own what went in within a couple of minutes — without having to work out what
to ask. Often this runs unattended (cloud / background) while they're away; they'll
read the brief later, possibly on a phone, then do the final testing on a Mac.

## Inputs

- `<issue-number>` — required. If missing, ask for it and stop.

## Step 0 — Know where you are

Detect, don't assume, and remember the answers for the brief:

- **Cloud (Claude Code on the web) or local Mac?** Cloud if `CLAUDE_CODE_REMOTE=true`,
  or `command -v xcodebuild` fails on a non-macOS host. Cloud is an isolated,
  throwaway checkout: no `/devserver`, no simulator.
- **Attended or unattended?** If this is a background/cloud session or the user said
  they're away, run **unattended**: never stop to ask — make the call, prefer the
  most conservative / reversible option, and record it under "Decisions I made for
  you". If attended, you may ask, but only for decisions that are genuinely theirs.
- **Toolchain.** Check each and note what's missing:
  - Python: locally `./venv/bin/python`. In the cloud, whatever the sandbox provides
    (`python -c "import flightforms"`); if missing, `pip install -e .`.
  - iOS/macOS: `command -v xcodebuild`. No Xcode is **fine** — write the Swift
    anyway, carefully, and hand build/test to the Mac checklist.
  - Android: a JDK (`java -version`) for `./gradlew test`. Missing → Mac checklist.
  - `gh` works (locally it must run with the sandbox disabled, else it returns empty
    with exit 0).

## Step 1 — Understand before touching code

1. `gh issue view <n> --comments` — read the **whole thread**; later comments
   supersede the body. Follow linked issues/PRs that the plan depends on. Note the
   issue **author**: anyone other than `roznet` is an outside reporter (Step 5).
2. Check it isn't already done: `git log --oneline --all --grep "#<n>"`, plus
   `git branch -a` for an existing branch. If work exists, say so and build on it
   rather than starting over.
3. Design docs first (`mcp__library-docs__list_libraries` → `get_design_doc`, or
   `designs/INDEX.md`). Honour the "read before you write" docs in CLAUDE.md:
   `form-system.md` for forms, `ios-app.md` for models/sync, `flight-import.md` for
   import sources, `localisation.md` for strings. A **new form** follows `/add-form`.
4. **Classify the change** — this sets how careful the brief must be:
   - **Plumbing** — bug fix, refactor, infra. Nothing visible changes.
   - **Form output** — a mapping, template or filler change: what an officer sees
     on the filed form. Remember mapping match order (exact ICAO → `icao_list` →
     prefix → default): a prefix or default change hits **many airports**.
   - **Privacy / PII** — what is collected, sent to the server, logged, synced or
     exported. The server-never-stores-PII invariant lives here; so do `PRIVACY.md`
     and the App Store privacy labels.
   - **Sync / user data** — SwiftData/CloudKit schema, tombstones, move-my-data,
     anything that migrates or deletes what users created. CloudKit schema is
     effectively permanent once deployed to production.
   - **User-facing** — UI, wording (EN/FR/DE/ES), flows.

   These are a starting vocabulary, **not a closed list**. If part of the change
   carries a kind of risk they don't name, add your own label — e.g. **security /
   auth**, **cost** (API quotas, droplet), **third-party** (Autorouter, FlyFun
   Weather, an airport's email). A new label is a signal to the owner, so prefer
   naming it over folding it into "plumbing". Most issues are a mix; estimate the
   split.
5. **A real product choice, attended** — a CloudKit schema change, a newly collected
   personal field, a form whose official requirements you haven't seen, or a
   departure from the issue: before implementing, give a 5-line plan (what you'll
   change, the 1–3 choices that are theirs, your recommendation) and wait.
   Unattended: implement the conservative option and flag it prominently.

## Step 2 — Branch

- **Cloud:** if the session already put you on a working branch, use it; otherwise
  `git checkout -b issue-<n>-<slug> origin/main`.
- **Local:** `git fetch origin` then `git switch -c issue-<n>-<slug> origin/main`.
  If the checkout has uncommitted changes that aren't yours, don't touch them —
  attended: ask; unattended: stop and report. Re-check HEAD and branch before every
  commit (other sessions may share the checkout).

## Step 3 — Implement

Follow CLAUDE.md principles (enhance flyfun-common / rzflight / euro-aip over
wrapping them; search before duplicating; update **all** callers on a signature
change; no function both `Depends(fn)` and called directly). Add or update tests
next to the change.

- **Test data and placeholders** use self-describing dummy data (as `flightforms
  preview` does) — never real-looking names, passport numbers or registrations.
- **Privacy invariant:** never log request bodies or persist people/document data
  server-side. If what is collected or where it goes changes, update `PRIVACY.md`
  in this PR.
- **Strings:** new user-facing text goes in the String Catalogs with FR/DE/ES
  entries (see `localisation.md`); say in the brief if any are machine-drafted.
- **Parity:** if a server DTO or a shared behaviour changes, check the iOS/macOS app
  and the Android app use it consistently, or say which side is left.

Keep scope to the issue. Things you notice but don't do go under "Follow-ups" in the
brief rather than into the diff.

### Design docs, in the same PR

Once the code is settled, update the design docs **for the code you touched**, not
the whole set: what the change made stale — architecture, key exports, gotchas, and
above all **choices and their rationale** (the decisions in your brief belong here
too, so the next agent doesn't redo or contradict them). New component with no doc →
add one and its `INDEX.md` entry; work that completes something in `designs/future/`
→ fix its status line. Keep docs < ~300 lines, written as notes for a future agent,
not a changelog. Locally, `/sync-designs <doc path>` does this well — point it at
specific docs, never a full sync. No doc needed updating? Say so; don't invent edits.

## Step 4 — Verify what this machine can verify

Run only what's relevant, once each, and record the real outcome (counts, not
"looks good"). **Only iOS unit tests run in CI** — for Python and Android, what you
run here is the only evidence the PR will have.

- **Python:** `./venv/bin/python -m pytest <targeted paths> -q` (600 s timeout, no
  `| tail`). Full suite if the change touches mappings, fillers or the API.
- **Form output:** `tests/unit/test_snapshots.py` is the guard. A failing snapshot is
  a finding, not an obstacle: regenerate with `--snapshot-update` **only** when the
  change is intended, then read the JSON diff and list in the brief which snapshot
  files (= which airports/forms) moved and how. Never regenerate to turn red green.
  Generate the affected forms with `flightforms preview` and put "look at the filled
  form" in the Mac checklist with the exact command.
- **iOS / macOS, if Xcode is present:** from `app/flyfun-forms/`:
  - build + unit tests:
    `xcodebuild test -scheme flyfun-forms -project flyfun-forms.xcodeproj -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:flyfun-formsTests -resultBundlePath <tmp>/unit.xcresult`
  - **macOS build** — the app ships on macOS and CI never builds it:
    `xcodebuild build -scheme flyfun-forms -project flyfun-forms.xcodeproj -destination 'platform=macOS'`
  - a changed UI journey → also `-only-testing:flyfun-formsUITests/<Type>` (CI
    doesn't gate these).
  - read the test count back from the `.xcresult`
    (`xcrun xcresulttool get test-results summary --path <xcresult>`); a filter
    matching nothing still prints `TEST SUCCEEDED`.
- **No Xcode:** don't pretend. Re-read every Swift file you touched for type and
  optional mistakes, grep that new types/APIs exist, and put the exact commands in
  the Mac checklist.
- **Android, only if `app/android/` changed:** `./gradlew test` in `app/android`.
  The app is unreleased — unit tests are enough; no emulator or release checks.

Anything you could not run is **unverified** — the brief must say so.

## Step 5 — PR

- Stage specific paths only (never `git add -A`). Commit messages carry the
  attribution trailer; no personal details.
- **Close keyword:** issue by `roznet` → `Closes #<n>`. Issue by an **outside
  reporter** → `Addresses #<n>` in the PR body **and** every commit message
  (GitHub acts on commits too), so it isn't closed before they can use the fix.
- `gh pr create` with a body = short summary of the change + **the full Owner's
  brief below**. The PR is where the user will read it later, so it must stand alone.
- Pushing triggers the review bot. Don't wait on it here — point to `/process-review`.
- If the change carries **form output, privacy, sync / user data** or another risk
  label, end by suggesting `/brief-check <pr>` for an independent second opinion.

## Step 6 — The Owner's brief

Print it as your final message **and** put it in the PR body. Keep it to what fits
on one phone screen or two — **≤ ~30 lines**, plain words, no code unless a name is
the clearest handle. The user will ask for detail; this is the map, not the
territory. Omit a section only when it is genuinely empty, and then say "none".

**Before writing it, re-read your own diff against this checklist** — gaps an honest
agent still misses because they live outside what it set out to do:

1. **Mapping blast radius.** For any form-output change: which airports and forms
   now produce different output — via `icao_list`, prefix or default matching, not
   just the one in the issue. The snapshot diff is the evidence; name the files.
2. **Data leaving the device.** Every new or changed field sent to the server,
   logged, synced to CloudKit, written to a form, emailed or exported. Server side,
   confirm it stays in memory only. Did `PRIVACY.md` need a change?
3. **Departures from the issue.** Every place the implementation differs from what
   the issue or its thread asked — including *reversals*, not just changes of
   approach. Each is a decision for the owner.
4. **Inherited facts.** Any field rule, format or contact copied from an old
   comment, doc or an airport's PDF/website: re-derive it from the code or cite the
   source, rather than repeating it.
5. **Other surfaces.** If you changed how a value is computed or shown, grep for
   every other place it appears — PDF/DOCX/XLSX fillers, `/email-text`, the CLI,
   iOS vs macOS layout, the Android app — and say whether they now disagree.
6. **Verified vs claimed.** Only count what's reproducible: tests in the diff, and
   CI on the **head** commit (only iOS unit runs there — say "pending" if it is).
   Live checks you did in the session are "checked once, not in the repo".

```
## Owner's brief — #<n> <title>

**Kind:** ~50% form output · 30% plumbing · 20% user-facing   (rough split; use whichever labels fit, incl. new ones)
**In one line:** <what this PR does, in pilot/owner terms>

**What changes for the pilot**
- <on the filed form / in the app, or "Nothing visible — internal only">

**Forms affected:** <airports/forms whose output changed (snapshot files), or "none">
**Privacy & sync:** <new data collected/sent/synced, CloudKit schema change, PRIVACY.md — or "no change">

**Decisions I made for you**   (the ones you might have made differently)
- <choice> — over <alternative>, because <reason>. <"Easy to flip" / "Hard to undo">

**How it could go wrong**
- <concrete failure> → you'd notice it as <symptom: a field blank on the form, a sync conflict, an error>

**How we know it works**
- Verified: <what ran, with counts — e.g. "pytest: 42 passed (tests/unit)", "iOS unit: 118 passed, macOS build ok">
- Not verified: <what didn't, and why>

**Worth making sure you understand**   (2–4 questions you'd want answered)
- <e.g. "Why does the LF prefix mapping now apply to LFQA too?">

**Design docs:** <docs updated + what was recorded, or "none needed — why">
**Release notes:** <server /deploy · iOS/macOS /archive (What's New line) · none>

**Pick up on a Mac**   (only what wasn't run here)
- [ ] <exact command, e.g. iOS unit tests + macOS build>
- [ ] <e.g. `flightforms preview <form>` and check fields X, Y on the PDF>
- [ ] <e.g. run journey X in the simulator, iPhone + iPad + Mac>

**Follow-ups noticed (not done):** <or "none">
```

Rules for the brief:
- **Lead with what matters to the owner**, not the order you worked in.
- **Questions must be specific to this diff** — the places where your judgement
  replaced theirs, a field rule you picked, a behaviour that changed silently.
  Never generic ("Do the tests pass?").
- **Depth follows the classification:** pure plumbing can be a few lines; anything
  touching form output, privacy, sync or a risk label you added gets the full
  treatment, with the decisions spelled out.
- Be honest: an unverified Swift change is "written, not compiled", not "done".
