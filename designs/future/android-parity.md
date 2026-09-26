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
| 1 | #29 | Forms come out right and complete | §4 (1a–1e) | Not started |
| 2 | #30 | Getting data in fast | §5 (2a–2e) | Not started — after PR 1 |
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

- [ ] First crew member sent as function `"PIC"`; iOS sends `"Pilot"`, printed on gendec/LSGS. `data/FormRequestBuilder.kt:93` vs `Views/FlightEditView.swift:827`
- [ ] Local flight (origin = destination) hides departure-side forms: `directionFor` returns arrival first and the airport list is `distinct()`. Android also filters *document* forms by direction; iOS filters only web forms (`FlightEditView.swift:421-422`)
- [ ] Sign-in `pendingState` held in memory only (`auth/AuthService.kt:33`) — fails after process death while the Custom Tab is open. Persist with a short TTL
- [ ] No way to sign in after "Enter data without signing in"; a 401 never clears the token or routes to sign-in
- [ ] + saves a blank flight immediately; backing out leaves a "???? → ????" row. Create on first save instead
- [ ] Flight edits lost on Back with no prompt; schedule/aircraft save immediately but route/observations only on Save. Make it consistent
- [ ] `ui/webform/WebFormScreen.kt`: `BackHandler` (WebView history, then close); clear cookies on exit (iOS uses a non-persistent store)
- [ ] Generated PDFs in `cacheDir/forms` carry passport data and are never deleted — clear after share and on start
- [ ] Aircraft `FilterChip` row doesn't scroll; people chips grow unbounded
- [ ] Move my data drops trip extra fields: `data/DataTransfer.kt:160-168` (`TripRecord.toEntity` / `toRecord`)
- [ ] `ui/aircraft/AircraftScreens.kt` lacks `verticalScroll` — fields go under the keyboard

### 1b — Delete account; delete with Undo (S, Sonnet)

- [ ] Delete account in Settings → `DELETE /auth/account` (iOS `ContentView.swift:215-257`). **Play Store requirement**
- [ ] Swipe-to-delete + Undo on people, aircraft, flights (VM `delete` exists, unused). iOS `PeopleListView.swift:68`, `FlightsListView.swift:42,53`
- [ ] Delete in each edit screen's overflow menu

### 1c — Flight fields the forms depend on (M, Opus for logic, Sonnet for UI)

Entity already has `nature`, `reasonForVisit`, `responsiblePersonId` — no migration.

- [ ] Nature (private/commercial) and Reason for Visit picker (`FlightEditView.swift:264-272`)
- [ ] Responsible person picker; sets `contact`, auto-fills telephone/email extras (`:273-294`, `:815-829`)
- [ ] Connecting flight (nearest leg ≤14 days through this airport) and return flight (`has_return_flight`) (`:856-921`) — pure functions in `FormRequestBuilder`, unit-tested
- [ ] Per-form extra fields UI (choice / person / text) from `FormInfo.extraFields` (`:512-570`); `FormRequestBuilder.build` must send them. Needed for LSGS and book-out forms to fill fully

### 1d — Leg actions and schedule sync (S, Sonnet)

- [ ] Return Flight / Next Leg / Duplicate (`FlightEditView.swift:361-376`, `:996-1034`)
- [ ] Arrival date follows departure (`autoSyncArrivalDate`, `:408`)
- [ ] Past flights collapsible, registration on the row (`FlightsListView.swift:49-117`)

### 1e — Email export and form grouping (M, Sonnet)

- [ ] Email: call `/email-text` (in `net/FormsApi.kt`, unused), to/cc from `email`/`send_to`, body in a spoken language (`FlightEditView.swift:702-795`). Check iOS #26 (AIP customs e-mails, form to e-mail first) first
- [ ] "Languages you speak" setting in DataStore (`ContentView.swift:104-190`)
- [ ] Primary form, then web forms, then collapsed "Other forms" (`FlightEditView.swift:418-443`)

---

## 5. PR 2 — Getting data in fast (#30)

Outcome: people, aircraft and flights go in as quickly as on iOS — pickers,
scanning, imports. Starts after PR 1 merges: the people picker and new-flight
flow change the flight editor PR 1 reshapes.

### 2a — People list, people picker, CSV, aircraft editor (S–M, Sonnet)

- [ ] People search (M3 `SearchBar`), "Sort by recent" (SQL `MAX(departureInstant)`), crew pill (`PeopleListView.swift:24-70`)
- [ ] People picker as a full-screen sheet: search, crew/passenger toggle per person, usual crew first, "Frequent with X" groups, reorderable crew (PIC first) (`PeoplePickerView.swift`). One person cannot be both crew and passenger
- [ ] CSV import UI over the ported `PeopleCsv`, with an "N imported, M existed" result (`PeopleListView.swift:128,215`); CSV export via `CreateDocument`
- [ ] CSV rows matched by name + date of birth across the file and the app; a match adds its document to that person unless they already hold that number (iOS `1173620`, `Services/PeopleCSVImporter.swift`). Port into `PeopleCsv.plan` with the new Swift tests
- [ ] Per-flight document choice: when a person has more than one active document, their row on the flight offers Automatic or a specific document, stored on the flight by number and winning over the region pick; carried to duplicated legs (iOS `1173620`, `Flight.chosenDocNumbers`, `Services/DocumentResolver.swift`). Needs a Room migration adding a column to `flight` (first schema change since S6 — write a real `Migration`, not destructive fallback)
- [ ] Aircraft editor: category (`SegmentedButton`), company operator + name, owner picked from People syncing owner/address, usual base (`AircraftEditView.swift`)

### 2b — Scan decisions and sources (M, Opus)

- [ ] Port `Services/MRZResultProcessor.swift` (`findDuplicateDocument` across **all** people, `namesMatch`, `findMatchingPeople`) to `:core-logic` with its Swift tests. Replace the silent upsert in `ui/people/PeopleViewModel.applyScan`
- [ ] Result bottom sheet: duplicate warning, name-mismatch choices (update name / document only / new person) (`Views/MRZResultActionView.swift`)
- [ ] Standalone "Scan document" from the People list (FAB menu: Add / Scan / Contact / CSV)
- [ ] Scan from photo or PDF (Photo Picker, `PdfRenderer`); evaluate `GmsDocumentScanning`

### 2c — Airports and local time (M, Opus)

- [ ] Airport search picker over the bundled `airports.db` (10 MB, currently unread), with recent routes (`AirportPickerView.swift`, `SingleAirportPickerView.swift`)
- [ ] ICAO→IANA timezone column in `airports.db` at build time (or from the server)
- [ ] Schedule in UTC or origin/destination local time (`FlightDateTimeField.swift`); `ui/flights/ScheduleField.kt` is UTC-only
- [ ] NOTAM / notification rows from `maps.flyfun.aero/api/notifications/{icao}` (`FlightEditView.swift:626`)

### 2d — New-flight flow (M, Sonnet)

- [ ] Two-step New Flight: route/schedule/aircraft → people (`Views/NewFlightFlow.swift`)
- [ ] "Same crew as…" suggestion (`Services/PeopleSuggestion.swift`, `CrewSourcePickerView`)
- [ ] Import from a previous flight (`Services/FlightImportMethod.swift`)

### 2e — Contact import (M, Sonnet)

- [ ] `PickContact()` → resolve screen: Levenshtein ≤2 matching, Fill Missing Only / Override All (`Views/ContactImportView.swift:106,145-199`). Matching logic in `:core-logic` with tests

---

## 6. PR 3 — Platform and integrations (#31)

Outcome: the app looks and behaves like an Android app, not a port, and reaches
the other FlyFun services.

### 3a — Look and layout (S–M, Sonnet)

- [ ] Dark theme + dynamic colour; a real launcher icon (currently `sym_def_app_icon`)
- [ ] Adaptive layout: `NavigationSuiteScaffold` + `ListDetailPaneScaffold`

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

---

## 8. Decisions log

Newest last. One line per decision: date, section, what was decided, why.

- 2026-09-26 — structure — Three PRs by outcome rather than one per gap; sections become commits.
- 2026-09-26 — branches — `android-app` retired; parity work lands on `main` through per-PR branches.
- 2026-09-26 — survey — iOS `1173620` (per-flight document choice, CSV name+DOB matching) added to 2a after the survey.
- 2026-09-26 — pre-work — `PeopleViewModel.applyScan` upserts by document number on the same person only; cross-person duplicates are left to 2b.
