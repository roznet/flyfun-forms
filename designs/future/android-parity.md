# Android App: Parity with iOS

> Tracker for closing the gaps between the Android port (`app/android/`) and the
> iOS app (`app/flyfun-forms/flyfun-forms/`) after the S0–S15 port in
> [android-app-execution.md](./android-app-execution.md).
>
> The work ships as **three PRs, each with a GitHub issue**. The issue says what
> and why; this doc holds the item-level checklist and the decisions made along
> the way. Tick items and log decisions **in the same commit** as the code.

## Related docs

- [Execution plan](./android-app-execution.md) — session rules (§2), emulator recipe (§1), gates
- [Android app](./android-app.md) — feasibility, the sync gate, decision gates G1–G5
- [iOS app](../ios-app.md) — the reference behaviour

---

## 1. Status

Gap survey of 2026-09-26, verified against the code. Size: S small, M medium, L large.

| PR | Issue | Scope | Sections | State |
|---|---|---|---|---|
| 1 | #29 | Forms come out right and complete | §4 (1a–1e) | Merged (#33); unit + instrumented tests pass, manual emulator drive still owed (§8) |
| 2 | #30 | Getting data in fast | §5 (2a–2e) | Code done; `:core-logic` tests pass, app compiled against stubs, emulator drive owed (§8) |
| 3 | #31 | Platform and integrations | §6 (3a–3d) | Not started — after PR 2 |
| — | — | Blocked follow-ups | §7 | Blocked (G4, translator, device) |

Already done before this tracker: person details (DOB, place of birth, sex,
address), full document editor, scan fills empty person fields — `4ee86c6`.

## 2. How to work

- **Order is 1 → 2 → 3.** PR 1 and PR 2 both reshape the flight editor;
  running them in parallel means constant conflicts.
- **Branches.** Each PR gets its own branch from `main`, cut once the previous PR
  has merged. The old `android-app` branch is retired; everything lives on `main`.
- **One fresh session per lettered section, one commit (or a few) per section.**
  A PR is big, but its history reads section by section. Follow the session rules
  in the execution plan §2: read only what the section lists, stop at Done.
- **Done for every section:** `./gradlew :app:testDebugUnitTest :core-logic:test`
  green, and the change driven on the emulator (execution plan §1).
- **Before starting PR 2 and PR 3, re-sync with iOS.** iOS keeps moving (#26 AIP
  customs e-mails, #28 fix-in-sheet landed the week of this survey). Diff
  `app/flyfun-forms` since the last sync and add any new gaps here first.
- **Record decisions in §8**, and any deliberate departure from iOS in §3.

Paths are relative to `app/android/app/src/main/kotlin/aero/flyfun/forms/`
(Android) and `app/flyfun-forms/flyfun-forms/` (iOS) unless absolute.

---

## 3. Native divergences (decided — do not "fix" back to iOS)

| Surface | iOS | Android | Why |
|---|---|---|---|
| Date entry | Inline `DatePicker` | M3 `DatePickerDialog` opened in **input** mode | Dates are copied off a document; typing beats paging a calendar |
| Delete | Swipe `.onDelete`, immediate | `SwipeToDismissBox` + Snackbar **Undo** | Tombstones make undo free; Android convention |
| Contacts | `CNContactPicker` | `ActivityResultContracts.PickContact()` | Per-contact URI grant, no `READ_CONTACTS` |
| CSV / files | `.fileImporter` | SAF `OpenDocument` / `CreateDocument` | No storage permission |
| Photo scan | Photos + Files via `ImageOCRManager` | Photo Picker (+ `PdfRenderer`), optionally ML Kit `GmsDocumentScanning` | No permission; edge-detected capture |
| Airport timezone | Reverse geocoding (`AirportTimezoneCache`) | ICAO→IANA column in bundled `airports.db` (or server) | Android `Geocoder` has no timezone |
| Email | Mail composer | `ACTION_SEND` with `EXTRA_EMAIL/CC/SUBJECT/TEXT/STREAM`, `setSelector(mailto:)` | Standard intent, any mail app |
| FPL import | Clipboard read | Explicit Paste button + `ACTION_SEND text/plain` share target | Android 13+ clipboard toast; share from SkyDemon/Garmin |
| Language | In-app strings | `locales_config.xml` → system per-app language | Free on minSdk 33 |
| Tablet | `NavigationSplitView` | `NavigationSuiteScaffold` + `ListDetailPaneScaffold` | Adaptive rail/drawer is the Android idiom |
| Sync | CloudKit | Local-only + Move my data | Gate decision, [android-app.md §3](./android-app.md) |

---

## 4. PR 1 — Forms come out right and complete (#29)

Outcome: every form Android generates is correct and as complete as iOS's, and
can be e-mailed. Almost all of it touches the flight editor, `FormRequestBuilder`
and Settings, which is why it is one PR.

### 1a — Correctness fixes (S, Sonnet)

- [x] First crew member sent as function `"PIC"`; iOS sends `"Pilot"`, printed on gendec/LSGS. `data/FormRequestBuilder.kt:93` vs `Views/FlightEditView.swift:827`
- [x] Local flight (origin = destination) hides departure-side forms: `directionFor` returns arrival first and the airport list is `distinct()`. Android also filters *document* forms by direction; iOS filters only web forms (`FlightEditView.swift:421-422`)
- [x] Sign-in `pendingState` held in memory only (`auth/AuthService.kt:33`) — fails after process death while the Custom Tab is open. Persist with a short TTL
- [x] No way to sign in after "Enter data without signing in"; a 401 never clears the token or routes to sign-in
- [x] + saves a blank flight immediately; backing out leaves a "???? → ????" row. Create on first save instead
- [x] Flight edits lost on Back with no prompt; schedule/aircraft save immediately but route/observations only on Save. Make it consistent
- [x] `ui/webform/WebFormScreen.kt`: `BackHandler` (WebView history, then close); clear cookies on exit (iOS uses a non-persistent store)
- [x] Generated PDFs in `cacheDir/forms` carry passport data and are never deleted — clear after share and on start
- [x] Aircraft `FilterChip` row doesn't scroll; people chips grow unbounded
- [x] Move my data drops trip extra fields: `data/DataTransfer.kt:160-168` (`TripRecord.toEntity` / `toRecord`)
- [x] `ui/aircraft/AircraftScreens.kt` lacks `verticalScroll` — fields go under the keyboard

### 1b — Delete account; delete with Undo (S, Sonnet)

- [x] Delete account in Settings → `DELETE /auth/account` (iOS `ContentView.swift:215-257`). **Play Store requirement**
- [x] Swipe-to-delete + Undo on people, aircraft, flights (VM `delete` exists, unused). iOS `PeopleListView.swift:68`, `FlightsListView.swift:42,53`
- [x] Delete in each edit screen's overflow menu

### 1c — Flight fields the forms depend on (M, Opus for logic, Sonnet for UI)

Entity already has `nature`, `reasonForVisit`, `responsiblePersonId` — no migration.

- [x] Nature (private/commercial) and Reason for Visit picker (`FlightEditView.swift:264-272`)
- [x] Responsible person picker; sets `contact`, auto-fills telephone/email extras (`:273-294`, `:815-829`)
- [x] Connecting flight (nearest leg ≤14 days through this airport) and return flight (`has_return_flight`) (`:856-921`) — pure functions in `FormRequestBuilder`, unit-tested
- [x] Per-form extra fields UI (choice / person / text) from `FormInfo.extraFields` (`:512-570`); `FormRequestBuilder.build` must send them. Needed for LSGS and book-out forms to fill fully

### 1d — Leg actions and schedule sync (S, Sonnet)

- [x] Return Flight / Next Leg / Duplicate (`FlightEditView.swift:361-376`, `:996-1034`)
- [x] Arrival date follows departure (`autoSyncArrivalDate`, `:408`)
- [x] Past flights collapsible, registration on the row (`FlightsListView.swift:49-117`)

### 1e — Email export and form grouping (M, Sonnet)

- [x] Email: call `/email-text` (in `net/FormsApi.kt`, unused), to/cc from `email`/`send_to`, body in a spoken language (`FlightEditView.swift:702-795`). Check iOS #26 (AIP customs e-mails, form to e-mail first) first
- [x] "Languages you speak" setting in DataStore (`ContentView.swift:104-190`)
- [x] Primary form, then web forms, then collapsed "Other forms" (`FlightEditView.swift:418-443`)

---

## 5. PR 2 — Getting data in fast (#30)

Outcome: people, aircraft and flights go in as quickly as on iOS — pickers,
scanning, imports. Starts after PR 1 merges: the people picker and new-flight
flow change the flight editor PR 1 reshapes.

Re-sync with iOS before starting (2026-09-26, `a644c0d..83e47fd`): `83e47fd`
(add a person from the crew/passenger picker) and `20065ae` (document menu on
crew rows) fold into 2a; `7af8d61`/`b5bc3f8` (fix validation errors in place
from the errors sheet) are a new gap, outside "getting data in", listed in §7.

### 2a — People list, people picker, CSV, aircraft editor (S–M, Sonnet)

- [x] People search (M3 `SearchBar`), "Sort by recent" (SQL `MAX(departureInstant)`), crew pill (`PeopleListView.swift:24-70`)
- [x] People picker as a full-screen sheet: search, crew/passenger toggle per person, usual crew first, "Frequent with X" groups, reorderable crew (PIC first) (`PeoplePickerView.swift`). One person cannot be both crew and passenger
- [x] CSV import UI over the ported `PeopleCsv`, with an "N imported, M existed" result (`PeopleListView.swift:128,215`); CSV export via `CreateDocument`
- [x] CSV rows matched by name + date of birth across the file and the app; a match adds its document to that person unless they already hold that number (iOS `1173620`, `Services/PeopleCSVImporter.swift`). Port into `PeopleCsv.plan` with the new Swift tests
- [x] Per-flight document choice: when a person has more than one active document, their row on the flight offers Automatic or a specific document, stored on the flight by number and winning over the region pick; carried to duplicated legs (iOS `1173620`, `Flight.chosenDocNumbers`, `Services/DocumentResolver.swift`). Needs a Room migration adding a column to `flight` (first schema change since S6 — write a real `Migration`, not destructive fallback)
- [x] Aircraft editor: category (`SegmentedButton`), company operator + name, owner picked from People syncing owner/address, usual base (`AircraftEditView.swift`)

### 2b — Scan decisions and sources (M, Opus)

- [x] Port `Services/MRZResultProcessor.swift` (`findDuplicateDocument` across **all** people, `namesMatch`, `findMatchingPeople`) to `:core-logic` with its Swift tests. Replace the silent upsert in `ui/people/PeopleViewModel.applyScan`
- [x] Result bottom sheet: duplicate warning, name-mismatch choices (update name / document only / new person) (`Views/MRZResultActionView.swift`)
- [x] Standalone "Scan document" from the People list (FAB menu: Add / Scan / Contact / CSV)
- [x] Scan from photo or PDF (Photo Picker, `PdfRenderer`); evaluate `GmsDocumentScanning`

### 2c — Airports and local time (M, Opus)

- [x] Airport search picker over the bundled `airports.db` (10 MB, currently unread), with recent routes (`AirportPickerView.swift`, `SingleAirportPickerView.swift`)
- [x] ICAO→IANA timezone column in `airports.db` at build time (or from the server)
- [x] Schedule in UTC or origin/destination local time (`FlightDateTimeField.swift`); `ui/flights/ScheduleField.kt` is UTC-only
- [x] NOTAM / notification rows from `maps.flyfun.aero/api/notifications/{icao}` (`FlightEditView.swift:626`)

### 2d — New-flight flow (M, Sonnet)

- [x] Two-step New Flight: route/schedule/aircraft → people (`Views/NewFlightFlow.swift`)
- [x] "Same crew as…" suggestion (`Services/PeopleSuggestion.swift`, `CrewSourcePickerView`)
- [x] Import from a previous flight (`Services/FlightImportMethod.swift`)

### 2e — Contact import (M, Sonnet)

- [x] `PickContact()` → resolve screen: Levenshtein ≤2 matching, Fill Missing Only / Override All (`Views/ContactImportView.swift:106,145-199`). Matching logic in `:core-logic` with tests

---

## 6. PR 3 — Platform and integrations (#31)

Outcome: the app looks and behaves like an Android app, not a port, and reaches
the other FlyFun services.

### 3a — Look and layout (S–M, Sonnet)

- [x] Dark theme + dynamic colour; a real launcher icon (currently `sym_def_app_icon`)
- [x] Adaptive layout: `NavigationSuiteScaffold` + `ListDetailPaneScaffold`

### 3b — Auth and platform (S–M, Sonnet)

- [ ] Apple sign-in through the web flow (`provider="apple"` in `AuthService.startSignIn`) if the server path supports it
- [ ] `TokenStore` off deprecated `EncryptedSharedPreferences` to Keystore-wrapped DataStore
- [ ] Static app shortcuts (New flight, Scan passport)

### 3c — Server-backed imports (M, Opus)

- [ ] FlyFun Weather import (`WeatherImportService.swift`)
- [ ] Autorouter import (`AutorouterImportService.swift`)

### 3d — Localisation infrastructure (M, Sonnet)

- [ ] Extract every literal to `strings.xml`; reuse the existing translated `Localizable.xcstrings` entries
- [ ] `locales_config.xml` for the system per-app language picker

---

## 7. Blocked follow-ups (outside the three PRs)

- [ ] **ICAO flight-plan paste + share target** — blocked on gate G4 (`POST /flightplan/parse` on `main`; see [android-app.md §4](./android-app.md))
- [ ] **Remaining translations** — ~33 strings need real aviation fr/de/es; blocked on a translator (execution plan §2b)
- [ ] **Real-passport scan test** — needs a physical device; does not block merging PR 2 once photo scan works on the emulator
- [ ] **Fix validation errors in place** (iOS `7af8d61`, `b5bc3f8`, `Services/ValidationFix.swift`, `Views/ValidationErrorsView.swift`) — found in PR 2's re-sync; Android still lists the server's 422 errors in a dialog. Not blocked, just not in PR 2's scope; a candidate for PR 3
- [ ] **Contact fields beyond the name on a real device** — 2e reads phones, e-mails, addresses and birthday through the picked contact's entity URI; the emulator's provider must be checked to honour the picker's grant for it (§8)

---

## 8. Decisions log

Newest last. One line per decision: date, section, what was decided, why.

- 2026-09-26 — structure — Three PRs by outcome rather than one per gap; sections become commits.
- 2026-09-26 — branches — `android-app` retired; parity work lands on `main` through per-PR branches.
- 2026-09-26 — survey — iOS `1173620` (per-flight document choice, CSV name+DOB matching) added to 2a after the survey.
- 2026-09-26 — pre-work — `PeopleViewModel.applyScan` upserts by document number on the same person only; cross-person duplicates are left to 2b.
- 2026-09-26 — 1a — The flight editor edits a draft held by the ViewModel; Save stores the flight, crew and passengers together, and Back with unsaved changes asks Save / Discard. iOS autosaves through SwiftData; a draft is the Android idiom for a screen that already had a Save button, and it is what makes "create on first save" possible.
- 2026-09-26 — 1a — + opens `flight/new`, a draft that exists only in the ViewModel until saved. Backing out of an untouched one asks nothing and stores nothing.
- 2026-09-26 — 1a — Generated forms and data exports share `cacheDir/forms`, cleared on every cold start and, on returning to the app, of anything older than 15 minutes. Deleting right after the share intent would break mail apps that read the attachment later.
- 2026-09-26 — 1a — The OAuth `state` nonce lives in app-private SharedPreferences with a 10-minute TTL. It is a one-use anti-forgery value, not a credential.
- 2026-09-26 — 1a — A 401 to a request that carried a token clears it; the UI observes `TokenStore.signedIn` and returns to sign-in. The nav controller sits above the sign-in screen so a flight draft survives signing in again. Settings offers "Sign in" after "Enter data without signing in".
- 2026-09-26 — 1a — Pure logic this PR needs (`FormSides`, `TripExtras`, and later sections' leg and e-mail helpers) goes in `:core-logic`, so it is tested on the JVM without the Android SDK.
- 2026-09-26 — 1a — Built in a cloud session with no route to Google Maven (`dl.google.com`), so `./gradlew :app:…` could not run and nothing was driven on the emulator. Checked instead by compiling `app/src/main` against Compose Multiplatform 1.6 desktop plus stubs for the Android APIs, and running `app/src/test` and `:core-logic:test` on the JVM. Emulator runs are still owed before merge.
- 2026-09-26 — 1b — Deletes run on the app's scope against the repositories, with one app-level Snackbar for Undo. A delete from an edit screen pops the screen, and a ViewModel-scoped Undo would be cancelled with it. Restore clears the tombstone and bumps `updatedAt`, so the restore wins a later merge.
- 2026-09-26 — 1b — List rows are keyed on id + `updatedAt`, so a restored row gets fresh swipe state instead of coming back already swiped away.
- 2026-09-26 — 1b — Delete account keeps people, aircraft and flights on the device: they were never on the server.
- 2026-09-26 — 1c — Connecting and return legs are found by `FlightLegs` in `:core-logic` over a plain `Leg`, matching the iOS rules: 14 days either side, by airport, no trip linkage; a local flight connects as an arrival and is its own return. Forms are built from the draft, and other legs as stored.
- 2026-09-26 — 1c — An untouched choice extra field sends the option it shows. iOS shows the first option but sends nothing until it is changed, which the server rejects as missing when the field is required. Deliberate departure; the iOS side needs the same fix.
- 2026-09-26 — 1c — Per-form extra values live in the flight screen's ViewModel only, keyed by airport + form as on iOS, and are not stored.
- 2026-09-26 — 1d — Return / Next leg / Duplicate store the current flight, then open the new leg as a draft marked unsaved, so Back asks before dropping it. iOS inserts the new leg straight away. The leg actions sit in an Actions section at the foot of the editor, as on the iPhone; Delete stays in the overflow menu.
- 2026-09-26 — 1d — Upcoming flights stay sorted soonest first (iOS sorts newest first); past flights are newest first, collapsed by default.
- 2026-09-26 — 1e — "Languages you speak" is stored in SharedPreferences under the iOS key `spokenLanguageCodes`, same comma-separated format, rather than DataStore: one string does not justify a new dependency.
- 2026-09-26 — 1e — E-mail is `ACTION_SEND` with a `mailto:` selector and the file as `EXTRA_STREAM` + ClipData, falling back to the share sheet when no mail app answers (iOS falls back the same way without a mail account). The subject is the server's local subject, or the English one when that is empty; the body is local only when the pilot speaks the airport's language. #26 needed nothing client-side: the server already lists the form to e-mail first, and the primary form is simply the first document form.
- 2026-09-26 — 1e — Document forms keep their "Generate" button (file, then a Share dialog) next to the new "Email"; iOS's "Share" opens the share sheet directly.
- 2026-09-26 — merge — Before merging #33: `:core-logic:test` + `:app:testDebugUnitTest` (170 tests), `assembleDebug`, and the 19 instrumented tests on the API 37 emulator all pass. The manual drive (Save/Discard, leg actions, Email, swipe + Undo, Delete account) was not done.
- 2026-09-26 — review — The flight draft (new flight, edit or new leg) is not saved across process death: the ViewModel keeps no `SavedStateHandle`, and a restored new-leg screen shows the leg it came from, already stored. Accepted for now; persisting drafts would cover all three at once.
- 2026-09-26 — review — A Delete account refused with 401 (expired session) now tells the pilot on the sign-in screen that the account was not deleted. The interceptor has already dropped the token, so Settings is gone before its own error could show.
- 2026-09-26 — review — `contact` stores the responsible person's phone, as iOS `setResponsiblePerson` does; both builders send the person's name and fall back to the stored `contact` only when there is no responsible person. Kept as iOS for interchange; `designs/ios-app.md` corrected.
- 2026-09-26 — 2a — CSV import matches rows by name + date of birth against the app and earlier rows (`PeopleCsv.plan`, iOS `1173620`); the plan is pure and the app writes it in one transaction. Android keeps no nationality on the person, so a row's `Nationality` fills the document's issuing country when `Doc Issuing State` is empty, and export writes the document's issuing country as the nationality. `M`/`F` become `Male`/`Female`, the editor's words.
- 2026-09-26 — 2a — The per-flight document choice is `flight.chosenDocNumbers`, a JSON array column added by `MIGRATION_1_2` (the first real migration), carried by Move my data as an optional field and by every leg action, as iOS `copyCommon` does. `app/schemas/…/2.json` is written by the next real build (KSP); it could not be generated here.
- 2026-09-26 — 2a — The people picker is a full screen inside the flight route (like the web form), editing the draft directly; Done only closes it and Save stores the flight. Crew is reordered with up/down buttons, the first labelled pilot in command; someone moved to crew leaves the passengers (`PeopleRanking.withoutDuplicates`). A person created from the picker's + menu comes back to the flight through the back-stack entry's saved state and joins it, as in iOS `83e47fd`.
- 2026-09-26 — 2a — Search is a text field over the list, not M3 `SearchBar`: the expanding search bar is for app-wide search, not for filtering the list under it.
- 2026-09-26 — 2a — The draft's people are refreshed from storage whenever the people list changes, so a person edited from the picker is generated with their new details; the baseline is refreshed too, so that is not an unsaved change.
- 2026-09-26 — 2a — Aircraft owner is picked from People and `owner`/`ownerAddress` are kept in step with the choice (company or person), as iOS's `onChange` handlers do. An owner typed before this, with no person, is kept until one is picked.
- 2026-09-26 — 2b — `MRZResultProcessor` is ported to `:core-logic` over plain values; duplicates are searched across everyone's live documents. The result is a bottom sheet over the camera. Android adds one action iOS lacks: a scan of a document the person already holds offers "Update the document", which the pre-work upsert did silently. The document-editor scan context is ported but not offered: Android scans from the person.
- 2026-09-26 — 2b — Photo and PDF scans use the Photo Picker and SAF `OpenDocument` with `PdfRenderer` (about 300 dpi, first five pages), no permission and no new dependency. ML Kit `GmsDocumentScanning` was not adopted: it is a Play Services module this build cannot fetch or check here, and the two pickers already cover the case. Worth revisiting once the flow has been used.
- 2026-09-26 — 2c — Airport time zones are an `icao,zone` table (`assets/airport_timezones.csv`, 8,474 rows, 180 KB) generated from `airports.db` by `scripts/airport_timezones.py` (timezonefinder), not a column added to the database at build time: adding one would need SQLite and a time zone library in the Gradle build. Re-run the script when `airports.db` changes; an airport missing from it only loses the local-time option.
- 2026-09-26 — 2c — The route is picked from the database (the route card replaces the two ICAO text fields); a four-letter code the database lacks can still be used as typed. The database is copied out of the APK to no-backup storage once per app update, since SQLite cannot open an asset.
- 2026-09-26 — 2c — The schedule field starts in UTC and moves to the airport's zone once it is known, unless the pilot picked a zone; iOS moves only while the selection is still the default, and Android also never overrides a choice. The date picker is fed the shown day as UTC midnight so a local date does not shift through the device zone.
- 2026-09-26 — 2c — Airport notices come from `maps.flyfun.aero` through their own client, so the forms token is never sent there; a notice that fails to load is left out, as on iOS.
- 2026-09-26 — 2d — + opens the two-step flow on the same draft; Create Flight stores it and the editor takes over in place. Leg actions still open the editor directly. Only "Previous Flight" is offered as an import: FPL paste is blocked on G4, Weather and Autorouter are PR 3. Repeating a flight also carries reason for visit and the document choices, which iOS's draft leaves out.
- 2026-09-26 — 2e — The contact is read through the picked contact's entity directory, with no READ_CONTACTS; the display name is read from the contact itself and is enough on its own. Merging is iOS's Fill Missing Only / Override All, in `ContactImport` with tests.
- 2026-09-26 — PR 2 — Built in a cloud session with no route to Google Maven, as 1a was: `:core-logic` tests run on the JVM, and `app/src/main` was type-checked against Compose Multiplatform desktop plus stubs for the Android APIs. Room's generated code, the migration and every screen still need the emulator run (execution plan §1) before merge.
- 2026-09-26 — PR 3 — Re-sync with iOS (`83e47fd..7595b4f`): only `8b2f018` (Flights first in the tab bar), which Android already does. No new gaps.
- 2026-09-26 — 3a — The launcher icon is the iOS artwork, whole, as the adaptive icon's background layer, with a transparent foreground and a monochrome layer cut from its white parts for themed icons. `scripts/android_launcher_icon.py` writes it; re-run it when the iOS icon changes. Splitting the artwork into layers would have needed a redraw, and parallax would pull its parts apart.
- 2026-09-26 — 3a — Dynamic colour only, no fallback palette: it needs API 31 and the app's minimum is 33, and the app has no brand colour beyond its icon.
- 2026-09-26 — 3a — `ListDetailPaneScaffold` lays out the navigation back stack rather than driving its own navigator: a tab's list route shows the list (and a placeholder beside it when there is room), an item's route shows the item (and the list beside it). On a phone that is one screen per route, as before; ViewModels stay scoped to routes, and Back, pickers and the unsaved-changes prompt work unchanged. The list shows beside an item only when the item was opened from that list: a person opened from a flight's picker shows alone. Picking another flight from the side list while the open one has edits asks Save / Discard, as Back does; the person and aircraft editors do not ask on Back either, so neither does switching.
- 2026-09-26 — 3a — `NavigationSuiteScaffold` gives a bar on a phone (on the lists only, as before) and a rail on a tablet, where it stays beside open items since the list does. Route changes do not fade when two panes show, so the list does not flash.
