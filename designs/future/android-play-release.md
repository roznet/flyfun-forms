# Android App: Google Play Release

> Everything between a working build and the app on Google Play: what exists,
> what is missing, and what only the owner can do. Expands S16 in
> [android-app-execution.md](./android-app-execution.md). Survey of 2026-09-27.

## 1. Status

| Area | State |
|---|---|
| Launcher icon | Done: adaptive icon from the iOS artwork, with a themed-icon layer (PR 37) |
| Backup opt-out | Done: `allowBackup="false"` and `data_extraction_rules.xml` |
| In-app account deletion | Done: Settings → Delete account (`DELETE /auth/account`) |
| Privacy policy URL | Done: `https://forms.flyfun.aero/privacy`, rendered from `PRIVACY.md` |
| Web account-deletion URL | Text on `/privacy` points to `privacy@flyfun.aero`. **Owner:** create the address, then deploy; see §4 |
| Release signing | Build side done: `bundleRelease` signs with the key in `keystore.properties`. **Owner:** create the upload key; see §3 |
| Code shrinking (R8) | Off; see §3 |
| Play Console account | **Owner**: personal account decided, not created; see §2 |
| Store listing assets | Icon and draft text done; feature graphic and screenshots missing; see §5 |
| Data safety, content rating, app access | **Owner**, answers drafted in §6 |

## 2. Play Console account (owner, blocks everything)

- One-time $25, identity verification takes 1–2 days.
- **Personal account** (decided 2026-09-27). A personal account created after
  November 2023 must run a **closed test with at least 12 testers opted in for
  14 continuous days** before production access can be requested. Recruit the
  testers early, from pilots who already use the iOS app or FlyFun Weather:
  the 14 days are the longest item on this list. Testers join through an
  opt-in link and need a Google account on an Android phone.
- The package name `aero.flyfun.forms` is permanent once uploaded.

## 3. Build: signing, size, versions

- **Play App Signing** (mandatory for new apps): Google holds the app signing
  key; we sign uploads with an *upload key*. Generate it once
  (`keytool -genkeypair -v -keystore upload.jks -keyalg RSA -keysize 2048
  -validity 10000 -alias upload`), keep it and its passwords outside the repo,
  and back it up. A lost upload key can be reset through Play support, but that
  takes days.
- `app/android/keystore.properties` (gitignored) holds `storeFile`,
  `storePassword`, `keyAlias` and `keyPassword`. When it is present,
  `./gradlew :app:bundleRelease` writes a signed
  `app/build/outputs/bundle/release/app-release.aab`; without it the bundle is
  unsigned. Play takes app bundles only, not APKs.
- **Size.** The debug APK is 130 MB: about 80 MB of unshrunk code (mostly
  `material-icons-extended`), ML Kit's OCR library for four CPU types (about 11 MB
  each), and the 10 MB `airports.db`. The unshrunk release bundle is 40 MB,
  and Play ships each device only its own CPU type, so a phone downloads one
  copy of ML Kit. Turning on R8
  (`isMinifyEnabled`, `isShrinkResources`) should cut most of the code, but it
  can break kotlinx-serialization and Retrofit at runtime. Enable it only with a
  full drive of the release build: sign-in, generation, import, scan.
- **Versions.** `versionCode` must go up with every upload, including test
  tracks; `versionName` is what users see. Start the first upload at `1.0`.
- `targetSdk = 37` satisfies Play's target-API rule. Bump it each year.

## 4. Web account deletion

Play requires a public web page where a user can **request account deletion
without reinstalling the app**, which the Data safety form links to. The
`/privacy` page's "Deleting Your Data" section has a "Without the app" route:
email `privacy@flyfun.aero` from the sign-in address. The URL to give Play is
`https://forms.flyfun.aero/privacy#deleting-your-data`.

- **Owner:** create `privacy@flyfun.aero` in Proton Mail (the domain's mail
  host). Until then the address bounces, so do not deploy the privacy change
  before it exists.
- It goes live with the next server deploy, which bundles `PRIVACY.md` into the
  image.
- Keep private addresses and account details out of the repo; owner-only notes
  go in the untracked `app/android/play/private-notes.md`.
- Handle each request by deleting the account from the admin side, the same
  effect as `DELETE /auth/account`. That removes the shared FlyFun user, so the
  pilot's FlyFun Weather sign-in goes too.

## 5. Store listing

Listing assets live in `app/android/play/`: `icon-512.png`, and the draft text
and screenshot plan in `listing.md`.

| Item | Spec | Source |
|---|---|---|
| App name | ≤30 chars | "FlyFun Forms" (as iOS and the launcher) |
| Short description | ≤80 chars | new |
| Full description | ≤4000 chars | adapt the App Store text |
| App icon | 512×512 PNG, 32-bit | `app/android/play/icon-512.png`, the iOS artwork resized; Play applies its own mask |
| Feature graphic | 1024×500 PNG/JPEG | new, required |
| Phone screenshots | 2–8, 16:9 or 9:16, 320–3840 px | emulator, using fictional data (ZZ- registrations, made-up names) |
| Tablet screenshots | optional | worth adding: the list-beside-detail layout is a selling point |
| Category / contact | Travel & Local, or Productivity; support email | owner |

## 6. App content forms (drafted answers)

- **Privacy policy:** `https://forms.flyfun.aero/privacy`.
- **App access:** generating forms requires signing in, so reviewers need a
  way in. Either give credentials for a test account, or say that data entry
  works without an account and generation needs Google sign-in. A
  reviewer token like FlyFun Weather's for App Store review would work here too.
- **Ads:** none. **Target audience:** 18+. **News app:** no.
  **Government app:** no. **Financial or health features:** none.
- **Content rating (IARC):** a utility with no user-generated content, no
  gambling, no violence, so expect a rating of Everyone / PEGI 3.
- **Data safety:**
  - *Collected:* name and email address (account, app functionality);
    passport and personal details such as nationality and date of birth,
    sent to the server to fill a form and **processed ephemerally**, never
    stored (`PRIVACY.md`, "Server-Side Processing"); app diagnostics and a
    per-install ID, collected by the ML Kit SDK once the scanner has been
    used (`PRIVACY.md`, "Passport Scanning").
  - *Shared:* none. Google receiving ML Kit metrics as the SDK provider
    counts as a service provider, not sharing.
  - *Encrypted in transit:* yes. *Deletion:* yes, in-app plus the §4 URL.
  - Data kept only on the device is not "collected" and is not declared.

## 7. Release path

1. Internal testing track: the first signed `.aab`, owner-only, to check the
   Play-signed build installs and signs in (OAuth callback, Keystore token).
2. Closed testing: the 12 testers for 14 days on a personal account.
3. Production, as a staged rollout. The first review takes hours to days.
4. Release notes: `release-notes/android-<version>.txt`, alongside the iOS ones.

## 8. Still owed before a public release

From [android-parity.md](./android-parity.md): a real-passport scan on a
physical device, sign-in on a physical device, Weather import and Apple sign-in
against real accounts, and the untranslated strings.
