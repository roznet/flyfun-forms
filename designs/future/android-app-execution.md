# Android App: Execution Plan

> **Status: ready to start. Worktree created 2026-09-19 at `../android-app`
> (branch `android-app`, forked from `origin/main`).**
>
> The *what and why* live in [android-app.md](./android-app.md). This document
> is the *how*: one brief per session, each self-contained enough to paste as a
> prompt into a fresh agent that has never seen this project.
>
> **Read only your own session's brief.** That is the point — see §2.

## Related docs

- [Android app](./android-app.md) — feasibility, sizing, the sync gate, portability audit
- [Parity with iOS](./android-parity.md) — **the tracker for remaining gaps after S0–S15**, one brief per batch
- [Move my data](./move-my-data.md) — interchange format; S14 implements the importer
- [iOS app](../ios-app.md) — the reference implementation
- [API](../api.md) — endpoint contract

---

## 1. Before anything: human-gated prerequisites

**All tooling prerequisites are satisfied as of 2026-09-19. S0 is ready to start.**

| Prerequisite | Status |
|---|---|
| JDK 21 (Temurin) | ✓ `21.0.12.1` |
| Android Studio | ✓ installed via Homebrew cask |
| Android SDK | ✓ `~/Library/Android/sdk` (6.4 GB) |
| Platforms | ✓ `android-37.0` (compile/target) + `android-36` (AGP fallback) |
| Build-Tools | ✓ `36.0.0` |
| Platform-Tools / adb | ✓ `37.0.1` |
| `cmdline-tools` | ✓ `latest` — `sdkmanager` is deprecated; the replacement is `android sdk` |
| System image | ✓ `android-37.0;google_apis;arm64-v8a` |
| AVD | ✓ `flyfun_pixel10_api37` (Pixel 10, Android 17 "CinnamonBun") — **boot-verified, ~35 s to `sys.boot_completed`** |
| Physical Android device | Still required from **S13** — emulators are not trustworthy for camera/MRZ or OAuth deep links |
| Play Console account | Required only at **S16**. One-time $25, ~1–2 days ID verification |

**SDK levels — settled 2026-09-19:**

| Setting | Value | Note |
|---|---|---|
| `minSdk` | **33** | [android-app.md §5](./android-app.md) |
| `compileSdk` / `targetSdk` | **37** | Android 17; Play wants a recent target anyway |

`minSdk` does **not** require its own platform to be installed — only
`compileSdk` does. There is no need to download the API 33 platform.

**AGP fallback:** API 37 is very new. If the pinned AGP will not accept
`compileSdk 37`, drop to 36 — the platform is already installed, so this costs
a one-line change rather than a stalled session.

### Driving the UI from a session

`uiautomator dump` + `adb shell input tap` works, with one trap that costs a
confusing half hour: **the soft keyboard shifts the layout between the dump and
the tap**, so coordinates read while the IME is up land somewhere else once it
closes. Send `input keyevent 4` (BACK) to dismiss the IME, wait, re-dump, then
tap. `keyevent 111` (ESC) does not reliably close it.

Two more, both observed:

- Compose's clickable node is the *parent* of the node carrying the text, and
  the text node reports `clickable="false"`. Tapping the centre of the text
  bounds usually still lands inside the button, but match on the clickable
  ancestor when it does not.
- A `TextButton`'s `enabled` state is not reflected on the text node, so a dump
  cannot tell you whether a button is disabled. Check the state that drives it.

For anything load-bearing prefer an instrumented test over poking the UI - the
Room layer's 10 tests run in seconds and do not depend on pixel coordinates.

### Headless emulator recipe

The AVD boots without a GUI, which is what CI and an agent session want:

```sh
export ANDROID_HOME=~/Library/Android/sdk
$ANDROID_HOME/emulator/emulator -avd flyfun_pixel10_api37 \
    -no-window -no-audio -no-snapshot -gpu swiftshader_indirect &
$ANDROID_HOME/platform-tools/adb wait-for-device
# then poll: adb shell getprop sys.boot_completed  -> 1
$ANDROID_HOME/platform-tools/adb emu kill          # shut down
```

---|---|
| JDK 21 (Temurin) | **Installed** ✓ |
| Android Studio | **Installed** ✓ (cask, 2026-09-19) |
| Android SDK | **Installed** ✓ — `~/Library/Android/sdk`, platform android-37.0, build-tools 36.0.0, adb 37.0.1 |
| System image + AVD | **Missing** ✗ — the emulator binary ships with the wizard but no image or AVD does; create one from Device Manager |
| `cmdline-tools` | **Missing** ✗ — not needed for `./gradlew`, but required for `sdkmanager`/`avdmanager` and CI licence acceptance |
| Gradle | Not needed — the wrapper handles it |
| Physical Android device | **Required from S13**; emulator is not trustworthy for camera/MRZ or OAuth deep links |
| Play Console account | Required only at S16. One-time $25, ~1–2 days ID verification |

**S0 is blocked until the Android Studio first-run wizard has been completed**
and `~/Library/Android/sdk` exists. Installing the cask is not sufficient — it
ships the IDE only, and the wizard is what downloads the SDK. Nothing else in
this plan can start first; every later session needs a working `./gradlew`.

**SDK levels — settled 2026-09-19:**

| Setting | Value | Note |
|---|---|---|
| `minSdk` | **33** | [android-app.md §5](./android-app.md) |
| `compileSdk` / `targetSdk` | **37** | android-37.0 is installed; Play wants a recent target anyway |

`minSdk` does **not** require its own platform to be installed — only
`compileSdk` does. There is no need to download the API 33 platform.

**AGP fallback:** API 37 is very new. If the pinned AGP will not accept
`compileSdk 37`, drop to 36 rather than fighting it — install the API 36
platform up front so S0 cannot stall on this.

---

## 2. How to run these sessions

Measured from eight real flyfun-forms sessions (2026-09): **cost ≈ turns ×
context size**, and 96.7% of spend was cache reads. A session that bloated to
285k context cost **~285k tokens per turn**; one that stayed at 45k cost
**~51k per turn** — 6x cheaper for the same kind of work.

The rules that follow from that:

1. **One session per brief. Start fresh.** Do not continue a previous session
   into the next brief.
2. **Read only what the brief lists.** The briefs name their inputs precisely so
   no agent has to explore the repo to find them.
3. **Stop at the Definition of Done.** If a brief finishes early, end the
   session rather than starting the next one.
4. **If a session passes ~150 turns, stop and split it.** Commit what works,
   write down what is left, start fresh. That is cheaper than pushing through.
5. **Model assignment matters more than anything else here.** All eight measured
   sessions ran on Opus — including three App Store archive runs. Opus weekly
   hours are the scarcest resource in a Max subscription; spend them on
   architecture, auth and debugging only.

### Where work happens

| Work | Location |
|---|---|
| All Android code | worktree `../android-app`, branch `android-app`, under `app/android/` |
| Server changes (S1 env var, S12 endpoint, S17 export) | **`main`, not this worktree** — they ship independently and on a different cadence |
| iOS export/import (move-my-data) | `main` — see [move-my-data.md §9](./move-my-data.md) |

Keeping server work off the `android-app` branch means the branch stays a pure
client addition and can merge whenever it is ready.

---

## 2b. Status, 2026-09-19

Built on branch `android-app`: **6,532 lines of Kotlin, 112 JVM tests and 17
instrumented tests**, all green on an API 37 emulator.

| # | Session | State |
|---|---|---|
| S0 | Bootstrap | **Done** |
| S1 | Auth + generate spike | **Done** — Custom Tabs + `/auth/exchange`. No server change was needed: `flyfunforms` is already allowlisted |
| S2 | MRZ parser | **Done** — 20 tests |
| S3 | People CSV | **Done** — 18 tests; fixed an escaped-quote bug present in the Swift original |
| S4 | DocumentResolver | **Done** — 14 tests |
| S5 | ZonedWallClock + schedule editing | **Done** — 12 tests incl. both DST directions |
| S6 | Room schema | **Done** — 10 instrumented tests |
| S7 | API client + repositories | **Done** — 8 wire-format tests |
| S8–S11 | People, aircraft, flights, form generation | **Done** — driven end to end on device |
| S12 | Flight import paths | **Not done** — see below |
| S13 | MRZ scanning | **Done** (camera + ML Kit); contact import **not done** |
| S14 | Move my data | **Done** — 7 instrumented round-trip tests; file verified by decrypting it independently in Python |
| S15 | Web forms | **Done**; localisation **not done** |
| S16 | Play Store | **Blocked** — needs a Play Console account |

### What is deliberately not done, and why

- **S12 flight import.** The ICAO flight-plan path depends on the
  `POST /flightplan/parse` endpoint this plan recommends adding server-side
  (gate G4). Writing a third Kotlin copy of the parser is the mistake
  `designs/ios-app.md` already records making once. The autorouter and weather
  import paths are server-backed and would be small once G4 is settled.
- **Localisation.** The infrastructure is a mechanical refactor, but only 18 of
  51 user-facing strings have an exact match in `Localizable.xcstrings`, and
  several of those have no French translation. The remaining ~33 need real
  aviation French, German and Spanish. These are documents a border officer
  reads; inventing the terminology is not appropriate, so the strings stay
  English pending a translator.
- **Contact import.** The fuzzy-merge resolution screen is a genuine piece of
  UI design, not a port, and nothing else depends on it.
- **A real MRZ scan.** Verified as far as an emulator goes: permission gate,
  CameraX binding and preview all work. Reading an actual passport needs the
  physical device S13 always required.

---

## 3. Session briefs

Legend — **O** = Claude Opus, **S** = Claude Sonnet, **C** = Codex.

| # | Session | Agent | Depends on |
|---|---|---|---|
| S0 | Bootstrap the Gradle project | O | Android Studio installed |
| S1 | Auth + generate spike | O | S0 |
| S2–S5 | Pure-logic ports (parallel) | **C** | S0 |
| S6 | Room schema | O | S0 |
| S7 | API client + repository | S | S6 |
| S8–S11 | Compose screens (parallel) | S | S6, S7 |
| S12 | Flight import paths | O | S11 |
| S13 | MRZ scanning + contacts | O | S2, S11 |
| S14 | Move-my-data import | S | S6, iOS export shipped |
| S15 | Web forms + localisation | S | S11 |
| S16 | Play Store release prep | S | all |

---

### S0 — Bootstrap (Opus)

**Goal:** an empty Compose app that builds and launches.

**Read:** [android-app.md §5](./android-app.md) (stack decisions) only.

**Build:**
- Gradle project at `app/android/` in the `android-app` worktree
- Two modules:
  - `:core-logic` — **pure Kotlin/JVM, no Android dependencies.** This is where
    S2–S5 land. Keeping it Android-free makes those tests run on the JVM and
    keeps Kotlin Multiplatform possible later.
  - `:app` — Compose + Room
- Kotlin, Compose BOM, Material 3, min SDK per §1
- A Gradle task that copies `app/flyfun-forms/flyfun-forms/airports.db` into
  `:app` assets at build time. **Do not commit a second copy** — it is 10 MB and
  a hand-copied duplicate is exactly the drift this project has been bitten by
  before
- Extend `.gitignore`: `.gradle/`, `local.properties`, `.idea/`, `*.iml`
  (`build/` is already covered)
- Optional: a `gradle test` GitHub workflow. The repo has no build CI today
  (only the two Claude bots), so there is nothing to break

**Definition of done:** `./gradlew assembleDebug` succeeds; `./gradlew test`
runs green with zero tests; the app launches to a blank screen on an emulator.

---

### S1 — Auth + generate spike (Opus)

**Goal:** prove the entire server story end-to-end. This is the single most
valuable session in the plan — it de-risks everything downstream for one
session's spend.

**Read:** [android-app.md §2 and §6](./android-app.md), `Services/FormService.swift`,
`Services/APITypes.swift`.

**Build:** a single throwaway screen that walks the whole chain:
Google sign-in via **Chrome Custom Tabs** (never an embedded WebView) →
`POST /auth/exchange` with code + state → `GET /airports` → a hardcoded flight →
`POST /generate` → open the returned PDF.

**Server prerequisite (do on `main`, not here):** add the Android scheme to
`OAUTH_ALLOWED_SCHEMES` (`flyfun_common/auth/config.py:25-33`) in the dev and
prod env. Until that lands, use the magic-link `consume-code` flow, which needs
no deep link at all and is the reliable fallback while redirect config is being
sorted out.

**Security, non-negotiable:** use the code+state exchange. Never a
token-in-URL redirect — any Android app can register `flyfunforms://`. See
[oauth-deeplink-hardening](../../../flyfun-common/designs/oauth-deeplink-hardening.md).

**Definition of done:** a real filled PDF opens on a real device, from a real
signed-in account.

---

### S2–S5 — Pure-logic ports (Codex, parallel)

**These four are the cheapest work in the plan and should not run on Claude.**
Each is one Swift file plus its existing test file, ported into `:core-logic`.
The tests are the specification: **port the tests first, then make them pass.**

| # | Source | Swift LOC | Test oracle |
|---|---|---:|---:|
| S2 | `Services/MRZParser.swift` + `MRZResultProcessor.swift` | 529 | 324 lines |
| S3 | `Services/PeopleCSVImporter.swift` | 168 | 416 lines |
| S4 | `Services/DocumentResolver.swift` | 112 | 185 lines |
| S5 | `flyfun-common/Sources/FlyFunCommon/DateTime/ZonedWallClock.swift` | 255 | 243 lines |

**Brief template — paste this, substituting the row:**

> Port `<SwiftFile>` to Kotlin in the `:core-logic` module of
> `app/android/` (pure Kotlin, no Android dependencies). Its Swift tests are at
> `<TestFile>`. Port the tests first as JUnit tests, then port the
> implementation until `./gradlew :core-logic:test` passes. Keep the same public
> function names and semantics; do not redesign the API. Use `java.time` for
> dates. Do not read any other file in the repository.

**S5 deserves particular care.** `ZonedWallClock` is DST-correct wall-clock
arithmetic where editing a time can move the day. The iOS app had a real bug
here (see the comment block at `Models/Flight.swift:7-27`). **Port the
semantics with the tests — do not re-derive them against `java.time` from
scratch.**

**Definition of done (each):** `./gradlew :core-logic:test` green, with the
ported test count matching the Swift original.

---

### S6 — Room schema (Opus) — **freeze this before any UI**

**Goal:** the persistence layer, correct the first time. Every UI session
depends on it, so schema churn here is the most expensive mistake available.

**Read:** [android-app.md §3 and §4](./android-app.md),
[move-my-data.md §4](./move-my-data.md), and `Models/*.swift` (all six, 587 lines).

**Build:**
- Room entities for Person, TravelDocument, Aircraft, Flight, Trip
- **Every entity gets:** `id: String` (UUID) primary key, `updatedAt`,
  `deletedAt` (nullable tombstone). Non-negotiable — these are the prerequisite
  for both S14 and any future Drive sync ([android-app.md §3](./android-app.md))
- One `FlightPersonCrossRef` junction with a `role` column ("crew"/"passenger"),
  not two relationships. Note the `@Relation`/`Junction` gotcha in
  [android-app.md §4](./android-app.md) — role filtering needs explicit `@Query`
- **Store schedule as instants**, not the legacy `departureDate` +
  `departureTimeUTC` pair. Android is a new store with no legacy rows; there is
  no reason to inherit a representation iOS is migrating away from
- DAOs returning `Flow<List<T>>` for observation
- `Person.lastFlightDate` and `coTravelers(...)` become SQL, not graph walks

**Definition of done:** tests that insert a flight with crew and passengers,
read it back with the right people in the right roles, and round-trip a
tombstoned delete.

---

### S7 — API client + repository (Sonnet)

**Read:** `Services/FormService.swift`, `Services/APITypes.swift`,
[api.md](../api.md). S1's spike code for the auth header.

**Build:** Retrofit + kotlinx.serialization mirroring `APITypes`; repository
interfaces over Room + network (the interface boundary that
[android-app.md §3](./android-app.md) requires so Drive sync stays additive);
422 → structured `ServerValidationError` with the `displayField` humanisation
(`crew[0].id_number` → "Crew 1 — ID Number").

**Definition of done:** unit tests against recorded JSON responses, including a
422 body rendering to human-readable field labels.

---

### S8–S11 — Compose screens (Sonnet, parallel once S6 and S7 land)

Per [android-app.md §1](./android-app.md), this is **high-volume, low-risk**
work: the iOS UI has zero `Canvas`, zero `Path`, one `GeometryReader`. It is
Buttons, Sections, sheets, Pickers and Lists. Rebuild in Material 3 idiom —
this is not a transliteration, and grouped-inset iOS forms are not idiomatic
Android.

| # | Screens | iOS reference | LOC |
|---|---|---|---:|
| S8 | People list, person edit, documents | `PeopleListView`, `PersonEditView` | 628 |
| S9 | Aircraft list/edit, flight list | `AircraftListView`, `AircraftEditView`, `FlightsListView` | 326 |
| S10 | **Flight edit** — the big one | `FlightEditView` | 1,187 |
| S11 | New flight flow, pickers | `NewFlightFlow`, `*PickerView`, `FlightDateTimeField` | ~900 |

**S10 is oversized on purpose-check:** `FlightEditView` is 1,187 lines and will
likely exceed one session. Split it by section (schedule / details / crew+pax /
forms list) and commit between them.

**S11 depends on S5** — the date/time/timezone field is the one genuinely
subtle piece of UI in the app, and it should sit on the ported `ZonedWallClock`
rather than new `java.time` logic.

**Definition of done (each):** screens render, navigate, and persist through the
S6 DAOs; no business logic added in the composables.

---

### S12 — Flight import paths (Opus)

**Read:** [flight-import.md](../flight-import.md), `Services/FlightImportMethod.swift`,
`Services/AutorouterImportService.swift`, `Services/WeatherImportService.swift`.

**Decision required first — [android-app.md G4](./android-app.md):** the ICAO
flight-plan parser. **Strong recommendation: add `POST /flightplan/parse` to the
forms server** (work done on `main`) rather than writing a Kotlin parser. A
Kotlin copy would be the *third* implementation, and `designs/ios-app.md`
already records that the second copy "was the weaker one".

Autorouter and weather import are already server-side and come essentially free
over HTTP.

**Definition of done:** all four import paths produce a `FlightDraft` equivalent
that populates the S11 form.

---

### S13 — MRZ scanning + contacts (Opus) — **physical device required**

**Read:** `Services/CameraOCRManager.swift`, `Services/ImageOCRManager.swift`,
`Views/MRZScannerView.swift`, `Views/ContactImportView.swift`.

**Build:** CameraX preview + ML Kit Text Recognition feeding the **already-ported
S2 parser** (do not re-implement parsing here); contact import via
`ContactsContract` with the fuzzy-merge resolution screen.

**Expect tuning.** MRZ capture quality varies far more across Android devices
than across iPhones — this is the session most likely to need a second pass.

**Definition of done:** a real passport scans and pre-fills a person on a
physical device.

---

### S14 — Move-my-data import (Sonnet)

**Depends on the iOS export shipping first** — see
[move-my-data.md §9](./move-my-data.md). That session produces the real fixture
files this one is built against.

**Read:** [move-my-data.md §4, §5, §6](./move-my-data.md) only.

**Build:** decrypt (AES-256-GCM, Argon2id via Tink), parse, and the per-record
merge — match on `id`, newer `updatedAt` wins, never delete local records absent
from the file, honour tombstones. Preview sheet before applying. Wrong password
must fail cleanly, not half-import.

**Definition of done:** a file exported from the iOS app imports onto Android
with the preview counts correct, and a re-import is a no-op.

---

### S15 — Web forms + localisation (Sonnet)

**Read:** `Views/WebFormView.swift` (229 lines) and its `WebFormFiller.script`.

Android `WebView` runs **the same injected JavaScript verbatim** — this is the
easiest port in the plan. Preserve the fill-only-after-first-load rule: a
submitted RedAtlas form loads a confirmation page that must not be refilled.

Localisation: script `Localizable.xcstrings` (92 KB, ~95 entries × en/fr/de/es)
into four `strings.xml` files. Mechanical.

---

### S16 — Play Store release prep (Sonnet)

- **`android:allowBackup="false"`** or full `dataExtractionRules`. This is the
  highest-risk default in the whole port — see
  [android-app.md §6](./android-app.md). Passport numbers must not enter Google
  backup, which would contradict `PRIVACY.md:11-16`
- Data Safety declaration covering passport data
- Account deletion is already satisfied by `DELETE /auth/account`
- Internal testing track first, not production

---

## 4. Server-side work, tracked separately

These ship from `main` on their own cadence and are **not** part of the
`android-app` branch:

| Work | Needed by | Where |
|---|---|---|
| `OAUTH_ALLOWED_SCHEMES` += Android scheme | S1 | env / `auth/config.py:25-33` |
| `POST /flightplan/parse` | S12 | `src/flightforms/api/` |
| iOS export + UUID migration | S14 | [move-my-data.md §9](./move-my-data.md) |
| `GET /account/export` (GDPR) | independent | [move-my-data.md §3](./move-my-data.md) |

---

## 5. Cost expectation

From the measured baseline in §2, and assuming the session discipline holds:

| Band | Condition |
|---|---|
| **200–300M billable-equivalent tokens** | Briefs respected, Sonnet for S7–S11 and S14–S16, Codex for S2–S5 |
| **800M–1B** | Sessions allowed to run 400–600 turns at 200k+ context, everything on Opus |

The difference is entirely session hygiene, not model capability.

**Calibrate after S1.** Measure that session's real cost from its transcript
before committing to the rest — one session's spend buys a grounded estimate for
the other fifteen, on the real stack rather than an analogy.

---

## 6. Gates that can still stop this

| Gate | Question | Stops |
|---|---|---|
| **G1** | Who is the Android user — new pilots, or existing iOS users wanting a second device? | If the latter, local-only cannot serve them and S14 carries far more weight than planned |
| **G4** | FPL parsing: Kotlin port or server endpoint | S12 |
| **G5** | Is a permanent second release train acceptable? | Everything |

G1 and G5 are product decisions, not engineering ones, and neither S0 nor S1
depends on them. **Both spike sessions are worth running regardless** — they
cost two sessions and convert the whole estimate from analogy into measurement.

---

## 7. References

- [Android app](./android-app.md) — the feasibility case and the decisions behind this plan
- [Move my data](./move-my-data.md) — format, encryption, merge semantics
- [iOS app](../ios-app.md) — reference implementation
- [flight-import](../flight-import.md) — S12 source material
- [API](../api.md) — endpoint contract
