# Archive for App Store

Build an Xcode archive ready for App Store upload.

## Arguments

The user may optionally specify the version bump in the command arguments (e.g. `/archive patch`, `/archive build`):
- **build** — only increment `CURRENT_PROJECT_VERSION` (build number), keep `MARKETING_VERSION` unchanged. Use for TestFlight builds or minor fixes.
- **patch** — increment last component of marketing version (1.1 → 1.2) + bump build number
- **minor** — increment middle component (1.1 → 2.0 for two-part, 1.2.3 → 1.3.0) + bump build number
- **major** — increment first component (1.1 → 2.0, 1.2.3 → 2.0.0) + bump build number

If not specified in arguments, ask the user:
> Current version: X.Y (build N). Bump type? [build / patch / minor / major]

## Step 1 — Read current version

Read the current `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from `app/flyfun-forms/flyfun-forms.xcodeproj/project.pbxproj`.

Show the user: "Current version: X.Y (build N)"

## Step 2 — Pre-flight checks

Run these checks and **stop with an error** if any fail:

### 2a — API base URL check

Verify that the Release/production build will NOT use localhost. Check `app/flyfun-forms/flyfun-forms/Services/Environment.swift`:
- The `#else` branch (non-simulator / non-DEBUG) must point to `https://forms.flyfun.aero` (production)
- The localhost URL (`localhost.ro-z.me:8443`) must only appear inside `#if targetEnvironment(simulator)` or `#if DEBUG`
- If localhost is in the production path, **stop and warn the user**

### 2b — App tests

Run the Xcode test suite for the iOS simulator:
```bash
xcodebuild test \
  -project app/flyfun-forms/flyfun-forms.xcodeproj \
  -scheme flyfun-forms \
  -destination "platform=iOS Simulator,name=iPhone 16" \
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

### 2e — Uncommitted changes

Run `git status` — warn the user if there are uncommitted changes beyond the version bump that's about to happen. These would NOT be in the archive since Xcode builds from the working directory, but it's good to flag.

### 2f — Git branch check

Verify we're on `main` branch. Warn (but don't block) if on a different branch.

### 2g — Debug-only code check

Search for common debug patterns that shouldn't ship:
- `#if DEBUG` blocks that contain API URLs or feature flags — verify they have proper `#else` branches
- Any `print(` or `NSLog(` in SwiftUI views (these are noisy in production) — warn but don't block
- Any `TODO` or `FIXME` comments — warn but don't block

### 2h — Info.plist privacy descriptions

Verify all required usage descriptions are present in `app/flyfun-forms/flyfun-forms/Info.plist`:
- `NSCameraUsageDescription` (for document scanning)
- `NSContactsUsageDescription` (for contact import)

If any are missing, stop and warn.

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
  -destination "generic/platform=iOS" \
  -archivePath ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/flyfun-forms-{version}.xcarchive \
  CODE_SIGN_STYLE=Automatic \
  | tail -20
```

The archive path under `~/Library/Developer/Xcode/Archives/` makes it appear in Xcode Organizer automatically.

This may take a few minutes. Run with a generous timeout (600000ms).

## Step 6 — Verify archive

Check that the archive was created and inspect it:
```bash
ls -la ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/flyfun-forms-{version}.xcarchive/
```

Also verify the embedded Info.plist has the correct version:
```bash
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" \
  ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/flyfun-forms-{version}.xcarchive/Info.plist
/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" \
  ~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/flyfun-forms-{version}.xcarchive/Info.plist
```

## Step 7 — Commit version bump

Stage and commit the version bump to `project.pbxproj`:
```
Bump version to X.Y (build N) for App Store release
```

Do NOT push unless the user asks.

## Step 8 — Report

Tell the user:
- Pre-flight check results summary
- Archive created at the path
- Version and build number in the archive
- It should now appear in **Xcode → Window → Organizer**
- From there they can **Distribute App** → **App Store Connect** to upload
- Remind them to push the version bump commit when ready
