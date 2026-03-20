# Archive for App Store

Build an Xcode archive ready for App Store upload.

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
| Privacy checks | NSCameraUsageDescription, NSContactsUsageDescription | NSCameraUsageDescription, NSContactsUsageDescription |

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

Show the release notes to the user for review before proceeding.

### Push tags

After the user confirms, push the tag (use `--force` if the tag was moved):
```bash
git push origin {platform}/{version}          # new tag
git push origin {platform}/{version} --force  # moved tag (build-only bump)
```

## Step 9 — Report

Tell the user:
- Pre-flight check results summary
- Platform that was archived (iOS or macOS)
- Archive created at the path
- Version and build number in the archive
- The tag that was created
- The release notes for the App Store
- It should now appear in **Xcode → Window → Organizer**
- From there they can **Distribute App** → **App Store Connect** to upload
- Remind them to push the version bump commit when ready
