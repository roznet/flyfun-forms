# Android App: Feasibility and Plan

> **Status: exploratory. Nothing built. Written 2026-09-18.**
>
> A decision document, not a commitment. Written for a reader with **zero
> Android experience**, so every concept is mapped onto the iOS app that
> already exists in `app/flyfun-forms/`.
>
> Read §3 first. The sync question dominates everything else, and it is the
> one decision that cannot be deferred or cheaply reversed.

## Related docs

- [iOS app](../ios-app.md) — the reference implementation this would mirror
- [API](../api.md) — the endpoint contract a second client would consume
- [Execution plan](./android-app-execution.md) — **session-by-session briefs**; start there once the gates below are cleared
- [Move my data](./move-my-data.md) — **the only iOS↔Android bridge**, and a prerequisite for this plan
- [flyfun-weather's Android plan](../../../flyfun-weather/main/designs/future/android-app-plan.md) — the same question for the sibling app, with a very different answer (see §1)

---

## 1. The cost picture, measured

Measured 2026-09-18 on `main`:

| Surface | Size |
|---|---|
| iOS app, total Swift | **9,180 lines** across 51 files |
| of which `Views/` | 5,493 lines (26 files) |
| of which `Services/` | 2,679 lines (17 files) |
| of which `Models/` | 587 lines (6 files) |
| Unit tests | 1,631 lines |

### Why this answer differs from flyfun-weather's

The weather app asked the same question and the answer was effectively "no":
**42,224 lines** of Swift across 205 files, plus a Skew-T thermodynamics engine
(`RZSkewT`) that would need re-implementing *including the meteorology*.

flyfun-forms is **~22% of that size**, has no rendering engine, no meteorology,
and no cross-section canvas. Its server is already stateless and
platform-neutral. The two conclusions should not be conflated: a forms Android
app is a genuinely tractable project, a weather Android app is not.

### Complexity, not just size

Line count understates the gap. The *kind* of UI differs, measured the same day:

| | forms `Views/` | weather `Views/` |
|---|---|---|
| Lines | 5,493 | 20,680 |
| `Canvas` | **0** | 19 |
| `Path(` | **0** | 47 |
| `GraphicsContext` | **0** | 43 |
| `GeometryReader` | 1 | 2 |

**There is no custom drawing anywhere in flyfun-forms** — 111 custom-rendering
call sites in weather, none here. The UI is 103 Buttons, 46 Sections, 39 sheets,
21 Pickers, 20 TextFields, 18 Lists, 10 Forms and 5 DatePickers: selecting
people, dates and places. Standard components end to end.

This matters more than the 22% figure. Compose is strongest at exactly this kind
of screen, and the Android work that genuinely requires judgement — custom
layout, canvas drawing, gesture-driven scrubbing — is entirely absent. The
`Views/` port is therefore **high-volume, low-risk, and highly delegable**,
which is not true of a weather Android client.

Two honest qualifications:

- It is **not** a 1:1 transliteration. SwiftUI's `Form`/`Section` has no exact
  Material equivalent; grouped-inset forms are rebuilt with `LazyColumn` plus
  Material list items, and the iOS look is not idiomatic Android anyway. The
  screens get rebuilt in the platform's own idiom — real work, but well-trodden.
- The one UI area with genuine subtlety is **date/time/timezone entry**
  (`Views/FlightDateTimeField.swift`, 161 lines, over `ZonedWallClock`'s 255).
  DST correctness and midnight-crossing edits are the fiddly part, and they are
  logic rather than rendering — port `ZonedWallClock`'s semantics with its tests,
  do not re-derive them against `java.time` from scratch.

### The one permanent cost

Two clients is one pair to keep in sync. Three is three pairs. Every future
feature — the planned document-override UI, promoting web forms past prototype —
doubles in cost, forever. **This is the real long-run price, and it is larger
than the build itself.** Price it in before, not after.

---

## 2. What the server already gives you for free

The server is stateless, stores no PII, and returns binary files. It is already
a perfectly good Android backend.

| Capability | Endpoint |
|---|---|
| Form generation, validation | `POST /generate`, `POST /validate` |
| Web-form prefill plans | `POST /prefill` |
| Localized email text | `POST /email-text` |
| Airport + form discovery | `GET /airports`, `GET /airports/{icao}` |
| Auth (Google, magic-link, Apple-web) | `/auth/login/{provider}` → `POST /auth/exchange` |
| Account deletion (Play requires it) | `DELETE /auth/account` |
| Autorouter recent routes | mounted at `api/app.py:123` |

**Total server change required for Android: one env var.** Add the Android
scheme to `OAUTH_ALLOWED_SCHEMES` (`flyfun_common/auth/config.py:25-33`).

Two optional server additions worth considering (§4, §7):

- `POST /flightplan/parse` — move ICAO FPL parsing server-side rather than writing a third copy
- `GET /account/export` — the server half of the GDPR export ([move-my-data.md](./move-my-data.md) §3)

---

## 3. GATE: the sync model

**This is the decision that dominates the project. Decide it before Phase 1.**

On iOS, CloudKit is not a convenience bolted onto the database — it *is* the
persistence and cross-device story, bought with one line at
`flyfun_formsApp.swift:20`:

```swift
cloudKitDatabase: .private("iCloud.net.ro-z.flyfun-forms")
```

**Android has no equivalent.** Room is SQLite plus an ORM; it has no cloud
component, no account binding, no sync. An Android device would hold its own
independent database — its own people, flights and passports — and nothing
converges, not even between two Android devices owned by the same person.

### Options

| Option | What it really is | Syncs two live devices? | Can you see the data? |
|---|---|---|---|
| **A. Room alone** | Local SQLite | No | No |
| Android Auto Backup | Daily snapshot, restored at *install* | **No** | No (sits in user's Google backup) |
| **B. Drive `appDataFolder`** | Hidden per-app folder in the user's own Drive | Yes, if you write the sync | **No** — scoped to app+user |
| **C. Firebase Firestore** | A database *you operate* | Yes, well | **Yes — you become controller** |

**Auto Backup is not sync.** It runs roughly daily, only when idle, charging and
on Wi-Fi, caps at 25 MB, and restores only at app-install time. Two devices that
both have the app installed never converge. It is also the `allowBackup` footgun
in §6.

**Option C is refused.** Passport numbers in a Google-hosted database under our
project makes us the controller: `PRIVACY.md` rewrite, GDPR Art. 30 record
update, `legal/PROCESSOR_TERMS.md` revisit, and breach exposure on passport data.
E2EE mitigates it, but cross-platform key transfer is then a UX problem designed
from scratch — **and iOS would have to be rewritten off CloudKit to participate
at all.** If cross-platform sync is ever the goal it is its own project, larger
than the Android app.

### Option chosen: **A, local-only, with the door left open to B**

1. Room, local-only. Say so plainly in the Play listing and in-app — expectation
   management is cheaper than the review you otherwise get.
2. Give every entity a **UUID primary key** and **`updatedAt` / `deletedAt`
   (tombstone)** from day one, and put all access behind a repository interface.
   These cost nothing now and are the entire prerequisite for adding B later.
3. Drive `appDataFolder` (B) only if multi-Android-device users actually appear.

**Neither A nor B bridges iOS↔Android.** That is what
[move-my-data.md](./move-my-data.md) is for, and it is why that document is a
prerequisite rather than a nice-to-have.

### What gets *easier* than iOS

Read the comment block at `Models/Flight.swift:7-27`: the `departureInstant` /
`departureDate` dual-write, `backfillScheduleInstants()` at every launch, the
three-release plan to flip precedence then drop the pair. **All of it exists
because CloudKit syncs the store between devices running different app
versions.** With a local-only Room database there is no older device writing
into your store. A migration is one `Migration(4, 5)` class run at open. That
entire category of pain disappears.

---

## 4. Portability audit

| iOS piece | LOC | Android equivalent | Difficulty |
|---|---|---|---|
| `Views/` (SwiftUI) | 5,493 | Jetpack Compose | **bulk of the work, but low-risk** — no custom drawing (§1) |
| `Models/` (SwiftData) | 587 | Room entities | medium |
| `MRZParser` + `MRZResultProcessor` | 529 (+324 tests) | pure Kotlin | mechanical |
| `DocumentResolver` | 112 (+185 tests) | pure Kotlin | mechanical |
| `PeopleCSVImporter` | 168 (+416 tests) | pure Kotlin | mechanical |
| `ICAOFlightPlanParser` (RZFlight) | 642 (+579 tests) | **move server-side** — see below | medium |
| `KnownAirports` + bundled `airports.db` | 600 + db | same SQLite file via Room | easy-medium |
| `FormService` + `APITypes` | 458 | Retrofit + kotlinx.serialization | easy |
| `FlyFunAuthService` | 307 | AppAuth + Chrome Custom Tabs | medium, security-sensitive |
| `ZonedWallClock` | 255 | `java.time` — port the semantics | medium (DST / midnight-crossing is subtle) |
| Vision OCR | — | ML Kit Text Recognition | easy swap, tuning needed |
| AVFoundation camera | 221 | CameraX | medium |
| Contacts + fuzzy merge | 354 | `ContactsContract` | medium |
| MessageUI composer | — | `ACTION_SENDTO` + FileProvider | easy |
| PDFKit / QuickLook preview | — | `PdfRenderer` or view intent | easy |
| WKWebView + JS prefill | 229 | Android WebView — **injected JS is identical** | easy |
| `Localizable.xcstrings` (~95 × 4 langs) | — | `strings.xml` × 4 | scriptable |

### The 1,631 lines of existing tests are the most valuable asset here

They cover exactly the fiddly logic — MRZ check digits, FPL parsing, document
resolution, CSV import. **Port the tests to Kotlin first, then make them pass.**
That converts the highest-risk work into mechanical work with a built-in oracle.

### Do not write a third flight-plan parser

`designs/ios-app.md` already warns: *"do not reimplement it locally: forms
carried a second copy for a while, and it was the weaker one."* A Kotlin copy
would be the **third**, repeating a documented mistake.

Prefer `POST /flightplan/parse` → `FlightDraft` on the forms server, reusing
`euro_aip`'s Python parser. Android gets it free and iOS can converge onto it
later, rather than diverging further. This also matches the CLAUDE.md principle
about pushing complexity into shared, well-tested code.

### Losing the live object graph

On iOS `flight.crew` is a list of live `Person` references — mutate one and it
persists, and every view showing it updates. Room hands back **immutable
snapshots**; every mutation is an explicit DAO call. `Person.coTravelers(...)`
and `Person.lastFlightDate` currently walk that live graph in memory; in Room
they become SQL aggregates (faster, and they don't load every flight into RAM)
— but they are *rewrites*, not ports.

This is the main reason `Views/` is the bulk of the work rather than a
transliteration: the views bind directly to `@Model` objects, and Compose wants
ViewModels over immutable state with explicit saves. Note the distinction from
§1 though — this is *volume* of straightforward state-plumbing work, not
*difficulty*. There is no custom rendering to re-derive.

### The many-to-many SwiftData gave you for free

`Flight.crew: [Person]?` plus `@Relationship(inverse:)` is a many-to-many that
SwiftData materialises implicitly. In Room you write the junction:

```kotlin
@Entity(
    tableName = "flight_person",
    primaryKeys = ["flightId", "personId", "role"],
    indices = [Index("personId"), Index("flightId")]
)
data class FlightPersonCrossRef(
    val flightId: String,
    val personId: String,
    val role: String            // "crew" | "passenger"
)
```

One junction with a `role` column is cleaner than iOS's two separate
relationships. **Gotcha:** Room's `@Relation` with `Junction` cannot filter on
the junction's own columns, so "crew only" needs an explicit query:

```kotlin
@Query("""
  SELECT p.* FROM person p
  JOIN flight_person fp ON fp.personId = p.id
  WHERE fp.flightId = :flightId AND fp.role = :role
  ORDER BY p.lastName, p.firstName
""")
suspend fun peopleOn(flightId: String, role: String): List<PersonEntity>
```

---

## 5. Stack decisions

| Concern | Choice | Note |
|---|---|---|
| UI | Jetpack Compose | Declarative, closest mental model to SwiftUI |
| Persistence | Room | §3 |
| Networking | Retrofit + kotlinx.serialization | Mirrors `APITypes.swift` |
| Auth | AppAuth + Chrome Custom Tabs | Never an embedded WebView (§6) |
| Token storage | EncryptedSharedPreferences / Keystore | Keychain equivalent |
| OCR | ML Kit Text Recognition | Vision equivalent |
| Camera | CameraX | AVFoundation equivalent |
| Crypto | Tink | Cross-platform consistency with iOS CryptoKit |
| Min SDK | **GATE** — decide before Phase 1 | Compose + CameraX are comfortable at API 26+; higher reduces device-fragmentation testing |

**Structure the ported logic (MRZ, resolver, CSV, merge) as a pure Kotlin module
with no Android dependencies.** That keeps Kotlin Multiplatform available later
without committing to it now.

---

## 6. Android-specific risks that have no iOS analogue

1. **`android:allowBackup` defaults to `true`.** Passport numbers would silently
   flow into Google's cloud backup, contradicting `PRIVACY.md:11-16`. Set
   `allowBackup="false"` or full `dataExtractionRules`. **This is the single
   highest-risk default in the entire port.**
2. **Custom schemes are hijackable.** Any app can register `flyfunforms://`.
   Use `POST /auth/exchange` (code + state), never a token-in-URL redirect. The
   H8 hardening already shipped that endpoint, so this is free *if used*.
   Stronger still: Android App Links over HTTPS, needing a small server change
   (allow an `https` native redirect) plus `.well-known/assetlinks.json` on
   `forms.flyfun.aero`.
3. **Sign in with Apple on Android is web-flow only.** Google + magic-link is the
   natural pairing; `magic-link/consume-code` needs no deep link at all, making
   it a bulletproof fallback during development.
4. **Play Data Safety declaration** with passport data needs care. Account
   deletion is already satisfied by `DELETE /auth/account`.
5. **No macOS dividend.** One Xcode target currently ships iOS *and* macOS.
   Android gives nothing on desktop.
6. **Encryption at rest is weaker than the iOS claim.** Android app-private
   storage is Credential-Encrypted — decrypted after the first unlock following
   boot, and accessible while the device is later locked. `PRIVACY.md:13` claims
   the database is encrypted "when the device is locked". For parity, use
   SQLCipher with a Keystore-held key. **Worth verifying what protection class
   SwiftData actually uses on iOS before restating that line for a second
   platform** — the claim may already be generous on both.
7. **Camera/OCR fragmentation.** MRZ scan quality varies far more across Android
   devices than across iPhones. A physical device is mandatory for this phase.

---

## 7. Phase split

| Phase | Scope | Agent-time |
|---|---|---|
| **0. Spike** | Empty Compose app → Google sign-in via Custom Tabs → `/auth/exchange` → `GET /airports` → hardcoded flight → `POST /generate` → open the PDF. Proves the whole server story end-to-end. | ~1 session |
| **1. Data + people/aircraft** | Room entities (UUID + `updatedAt` + `deletedAt`), CRUD screens, CSV import, `DocumentResolver` + ported tests | ~2–3 |
| **2. Flights + generation (MVP)** | Flight list/edit, crew/pax pickers, 422 validation surfacing, share + email export. **First genuinely usable build.** | ~3–4 |
| **3. Import paths** | FPL paste (via new server endpoint), previous flight, weather, autorouter, airport picker + timezone cache | ~2–3 |
| **4. Scanning + contacts** | CameraX + ML Kit MRZ, `MRZParser` port, contact import with fuzzy merge | ~2–3 |
| **5. Web forms, i18n, release** | WebView prefill (JS reused verbatim), `.xcstrings`→`strings.xml`, Play Console, data safety, internal track | ~2 |

**~12–16 focused sessions to a Play Store beta.** Phase 2 is the real milestone;
everything after is enrichment.

These phases are broken into paste-ready session briefs — with agent
assignment, exact inputs to read and a definition of done — in
[android-app-execution.md](./android-app-execution.md).

**Prerequisite, before Phase 1:** ship [move-my-data.md](./move-my-data.md) on
iOS. It defines the interchange format, produces real test fixtures for the
Android importer, and forces the UUID migration while CloudKit is still the only
consumer.

Separately gated, not agent-time: Play Console account (one-time $25, ~1–2 days
ID verification), Play review (hours to days, first submission slowest), and **a
physical Android device** — camera/MRZ and OAuth deep links are not trustworthy
on the emulator alone.

---

## 8. Explicitly out of scope

- iOS↔Android live sync (§3, Option C — refused)
- Drive `appDataFolder` sync (Option B — deferred until multi-device Android users exist)
- A macOS/desktop counterpart
- Kotlin Multiplatform adoption (kept *possible* by §5, not pursued)
- Sharing crew between pilots — see [move-my-data.md](./move-my-data.md) §8

---

## 9. Decision gates

| Gate | Question | Blocks |
|---|---|---|
| **G1** | Who is the Android user — new pilots, or existing iOS users wanting a second device? | Everything. If the latter, Option A cannot serve them and the economics change |
| **G2** | Sync model (§3) | Phase 1 schema |
| **G3** | Min SDK (§5) | Phase 1 scaffolding |
| **G4** | FPL parsing: Kotlin port or server endpoint (§4) | Phase 3 |
| **G5** | Is the permanent two-release-train cost (§1) acceptable? | Go/no-go |

**G1 is the one that matters.** The build is tractable and the risky logic is
test-covered, but a permanent second release train only pays for itself if there
is a real Android audience. Phase 0 is worth doing either way — one session, and
it de-risks everything downstream.

---

## 10. References

- [iOS app](../ios-app.md) — as-built feature status, the scope baseline
- [API](../api.md) — endpoint contract
- [Move my data](./move-my-data.md) — interchange format, encryption, GDPR export
- [flyfun-common auth](../../../flyfun-common/designs/auth.md) — OAuth flow, scheme allowlist
- [oauth-deeplink-hardening](../../../flyfun-common/designs/oauth-deeplink-hardening.md) — why `/auth/exchange` and not a token redirect
- `PRIVACY.md`, `legal/GDPR.md`, `legal/PROCESSOR_TERMS.md` — the posture any sync option must not break
