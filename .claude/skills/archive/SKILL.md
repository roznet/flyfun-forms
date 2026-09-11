---
name: archive
description: Archive the iOS or macOS app for the App Store — pre-flight checks, version bump, archive, tag and release notes, then stage it on App Store Connect (version, What's New, upload, build attached) with scripts/asc.py. Never submits for review. Invoke with an optional platform (ios / macos) and bump type (build / patch / minor / major).
disable-model-invocation: true
---

# Archive for App Store

Build an Xcode archive and stage it on App Store Connect, ready for you to press
**Submit for Review**.

## Arguments

The user may specify **platform** and **version bump** in any order (e.g. `/archive build`, `/archive macos patch`, `/archive ios build`):

**Platform** (default: `ios`):
- **ios** — build for iOS App Store
- **macos** — build for Mac App Store

**Version bump** (default: ask the user):
- **build** — only increment `CURRENT_PROJECT_VERSION` (build number), keep `MARKETING_VERSION` unchanged. Use for TestFlight builds or minor fixes.
- **patch** — increment last component of marketing version (1.1 → 1.2) + bump build number
- **minor** — increment middle component (1.1 → 2.0 for two-part, 1.2.3 → 1.3.0) + bump build number
- **major** — increment first component (1.1 → 2.0, 1.2.3 → 2.0.0) + bump build number

If version bump is not specified, ask the user:
> Current version: X.Y (build N). Bump type? [build / patch / minor / major]

## Platform-specific settings

Use these values based on the selected platform:

| Setting | iOS | macOS |
|---------|-----|-------|
| Destination | `generic/platform=iOS` | `generic/platform=macOS` |
| Test destination | `platform=iOS Simulator,name=iPhone 17 Pro` | `platform=macOS` |
| Tag prefix | `ios` | `macos` |
| `asc.py --platform` | `ios` | `macos` |
| Release notes file | `release-notes/ios-{version}.txt` | `release-notes/macos-{version}.txt` |
| Privacy checks | NSCameraUsageDescription, NSContactsUsageDescription | NSCameraUsageDescription, NSContactsUsageDescription |

For the test destination, pick a simulator the machine actually has (`xcrun simctl list devices available`) if `iPhone 17 Pro` isn't present.

## Step 1 — Read current version

Read the current `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `app/flyfun-forms/flyfun-forms.xcodeproj/project.pbxproj`.

Show the user: "Current version: X.Y (build N) — archiving for {platform}"

## Step 2 — Pre-flight checks

Run these checks and **stop with an error** if any fail:

### 2a — API base URL check

Verify that the Release/production build will NOT use localhost. Check `app/flyfun-forms/flyfun-forms/Services/Environment.swift`:
- The `#else` branch (non-simulator / non-DEBUG) must point to `https://forms.flyfun.aero` (production)
- The localhost URL (`localhost.ro-z.me:8443`) must only appear inside `#if targetEnvironment(simulator)` or `#if DEBUG`
- If localhost is in the production path, **stop and warn the user**

### 2b — App tests

Run the Xcode test suite using the platform-appropriate destination:
```bash
xcodebuild test \
  -project app/flyfun-forms/flyfun-forms.xcodeproj \
  -scheme flyfun-forms \
  -destination "{test_destination}" \
  -quiet \
  2>&1 | tail -30
```
If tests fail, stop and show the failures. Use timeout of 300000ms.

### 2c — Backend tests

Run the backend test suite:
```bash
cd $PROJECT_ROOT && venv/bin/python3 -m pytest tests/ -x -q -k "not flatten"
```
If tests fail, stop and show the failures.

### 2d — Uncommitted changes

Run `git status` — warn the user if there are uncommitted changes beyond the version bump that's about to happen. These would NOT be in the archive since Xcode builds from the working directory, but it's good to flag.

### 2e — Git branch check

Verify we're on `main` branch. Warn (but don't block) if on a different branch.

### 2f — Debug-only code check

Search for common debug patterns that shouldn't ship:
- `#if DEBUG` blocks that contain API URLs or feature flags — verify they have proper `#else` branches
- Any `print(` or `NSLog(` in SwiftUI views (these are noisy in production) — warn but don't block
- Any `TODO` or `FIXME` comments — warn but don't block

### 2g — Info.plist

Verify in `app/flyfun-forms/flyfun-forms/Info.plist`:
- `NSCameraUsageDescription` (for document scanning)
- `NSContactsUsageDescription` (for contact import)
- `ITSAppUsesNonExemptEncryption` set to `false` — without it every uploaded build stops at "Missing Compliance" until someone answers the export question by hand, and `asc.py` can't attach it

If any are missing, stop and warn.

### 2h — Local package overrides

Check the project for absolute local package paths — anything under `/Users/` pointing at a sibling checkout (e.g. a local `rzflight` or `flyfun-common`). These break builds on other machines and must be reverted to remote SPM references before archiving. **Stop and warn the user** if found:

```bash
grep -n '/Users/' app/flyfun-forms/flyfun-forms.xcodeproj/project.pbxproj || echo "no local package overrides"
```

### 2i — App Store Connect state

If `ASC_KEY_ID` / `ASC_ISSUER_ID` are set in `.env`, show what App Store Connect currently has for this platform:

```bash
venv/bin/python3 scripts/asc.py status --platform {platform}
```

Warn (don't block) if a version for this platform is already `WAITING_FOR_REVIEW` / `IN_REVIEW`: staging in Step 9 will refuse to touch it, and cancelling a submission is the user's call. If the keys aren't set, note that Step 9 will fall back to the manual Organizer route.

Report all checks as a checklist to the user before proceeding.

## Step 3 — Bump version

Always increment `CURRENT_PROJECT_VERSION` by 1.

For `MARKETING_VERSION`, apply the bump type:
- **build**: no change to marketing version
- **patch**: increment the last component (1.1 → 1.2, 1.2.3 → 1.2.4)
- **minor**: increment middle component, reset last (1.1 → 2.0 for two-part, 1.2.3 → 1.3.0)
- **major**: increment first component, reset rest (1.1 → 2.0, 1.2.3 → 2.0.0)

Update ALL occurrences in `project.pbxproj` using the Edit tool with `replace_all`. There are typically 2 occurrences of `MARKETING_VERSION` and 2 of `CURRENT_PROJECT_VERSION` for the main target (Debug + Release).

**Important**: Only update the entries for the main target (flyfun-forms), not the test target. The test target entries typically have different surrounding context. Check line numbers to distinguish them.

Show the user: "Bumped to X.Y (build N)"

## Step 4 — Clean build folder

```bash
xcodebuild clean -project app/flyfun-forms/flyfun-forms.xcodeproj -scheme flyfun-forms -configuration Release
```

## Step 5 — Build archive

```bash
xcodebuild archive \
  -project app/flyfun-forms/flyfun-forms.xcodeproj \
  -scheme flyfun-forms \
  -configuration Release \
  -destination "{destination}" \
  -archivePath ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/flyfun-forms\ $(date +%d-%m-%Y,\ %H.%M).xcarchive \
  CODE_SIGN_STYLE=Automatic \
  | tail -20
```

The archive path under `~/Library/Developer/Xcode/Archives/` makes it appear in Xcode Organizer automatically.

This may take a few minutes. Run with a generous timeout (600000ms).

## Step 6 — Verify archive

The archive path includes a timestamp, so save it to a variable during the build step and reuse it here.

Check that the archive was created and verify the embedded version:
```bash
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$ARCHIVE_PATH/Info.plist"
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$ARCHIVE_PATH/Info.plist"
```

## Step 7 — Commit version bump

Stage and commit the version bump to `project.pbxproj`:
```
Bump version to X.Y (build N) for App Store release
```

Do NOT push unless the user asks.

## Step 8 — Tag and release notes

### Tagging convention

Tags track the **marketing version** only, not the build number. The pattern is `{platform}/{marketing_version}`:
- iOS: `ios/1.2`
- macOS: `macos/1.2`

iOS and macOS tags are independent — each platform has its own tag history.

**Key rules:**
- Tags correspond to `MARKETING_VERSION`, never to `CURRENT_PROJECT_VERSION` (build number)
- Build-only bumps (`/archive build`) do NOT create a new tag — they move the existing tag for that version
- Only patch/minor/major bumps create a genuinely new tag

**When the tag already exists** (i.e. build-only bump for the same marketing version):
```bash
git tag -f {platform}/{version}
```
This moves the existing tag to the new HEAD. When pushing, use `--force`:
```bash
git push origin {platform}/{version} --force
```

**When the tag is new** (patch/minor/major bump):
```bash
git tag {platform}/{version}
git push origin {platform}/{version}
```

### Generate release notes

Find the **previous version** tag for the same platform (not the current one being created/moved):
```bash
git tag -l "{platform}/*" --sort=-version:refname
```
Pick the tag with the previous marketing version (e.g. if current is `ios/1.2`, previous is `ios/1.1`). For build-only bumps, the previous tag is still the prior version — release notes always cover the full version-to-version diff.

Generate a user-facing "What's New" summary from commits between the previous version and the current tag:
```bash
git log {previous_version_tag}..{platform}/{version} --oneline
```

From these commits, write a concise, user-facing release notes summary suitable for the App Store "What's New in This Version" box:
- Group related changes into bullet points
- Use plain language (no commit hashes, no technical jargon)
- Focus on features and fixes the user cares about
- Skip internal changes (test fixes, CI, refactoring, version bumps, doc syncs)
- Keep it to 5-8 bullet points max
- The listing is `en-GB`: write British English

Show the release notes to the user for review. **Wait for approval** — apply any edits they make.

### Save the approved notes

Write the approved text, exactly as it should appear in the App Store, to `release-notes/{platform}-{version}.txt` (plain text, one `- ` bullet per line). Step 9 sends this file as-is, so what the user approved is what Apple gets. For a build-only bump the file may already exist — overwrite it if the notes changed.

Commit it on its own:
```
Release notes for {platform} {version}
```

### Push tags

After the user confirms, push the tag (use `--force` if the tag was moved):
```bash
git push origin {platform}/{version}          # new tag
git push origin {platform}/{version} --force  # moved tag (build-only bump)
```

## Step 9 — Stage on App Store Connect

`scripts/asc.py` creates (or reuses) the App Store version, writes What's New, uploads the archive, waits for Apple to process it, and attaches the build — the steps that used to be Organizer + copy-paste. **It cannot submit for review, by design** (there is no such subcommand); the user presses Submit in App Store Connect.

If `ASC_KEY_ID` / `ASC_ISSUER_ID` are not in `.env`, this step is unavailable — say so, point at the credentials section of `scripts/asc.py`'s docstring, and fall back to the manual route in Step 10.

Offer `--dry-run` first if the user wants to see the calls before anything is sent. Then stage everything in one call:

```bash
venv/bin/python3 scripts/asc.py stage \
  --platform {platform} \
  --version {marketing_version} \
  --build {build_number} \
  --archive "{archive_path}" \
  --notes-file release-notes/{platform}-{version}.txt
```

Only pass `--review-notes "…"` if the user gives you text for the App Review team; reviewers can sign in with Sign in with Apple, so there is no reviewer token to mint for this app.

Notes on behaviour — all three are normal, not errors:

- **Re-running is safe.** `stage` reuses an existing editable version, renames it if the marketing version changed, and overwrites What's New in place. Re-run it to correct a mistake or to push a second binary rather than trying to undo anything.
- **It waits for Apple.** After upload the build sits in processing for ~5–30 minutes before it can be attached. Use a timeout of 600000ms (10 min) and, if it's still going, re-run `venv/bin/python3 scripts/asc.py wait-build --platform {platform} --version X.Y --build N` then `attach-build` with the same arguments — **do not re-upload**.
- **It stops at in-review versions.** If a version for this platform is already `WAITING_FOR_REVIEW` or `IN_REVIEW`, it refuses rather than editing. Cancelling a submission is the user's call.

iOS and macOS are separate App Store versions under the same app. Staging one platform never touches the other.

## Step 10 — Report

Tell the user:
- Pre-flight check results summary
- Platform that was archived (iOS or macOS)
- Archive created at the path
- Version and build number in the archive
- The tag that was created or moved
- The release notes, and the file they were saved to
- **If Step 9 ran:** the version is staged on App Store Connect with What's New and the build attached — they review it in the web UI and press **Submit for Review** themselves. Show the final `asc.py status` output.
- **If Step 9 was skipped** (no API key configured): the archive appears in **Xcode → Window → Organizer**, and from there **Distribute App** → **App Store Connect** uploads it; the What's New text then has to be pasted in by hand.
- Remind them to push the version bump and release-notes commits when ready
