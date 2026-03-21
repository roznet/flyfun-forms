# iOS App

> SwiftUI app for managing crew/passenger data and generating customs forms via the flyfun-forms API

## Intent

Native iOS/iPadOS/macOS app that lets pilots manage their people database (crew, passengers with passport details), aircraft, and flights — then generate pre-filled customs forms with one tap. PII stays on-device (encrypted SwiftData + CloudKit private DB), only sent transiently to the server for form generation. Data syncs across devices via CloudKit.

## Architecture

```
app/flyfun-forms/flyfun-forms/
├── flyfun_formsApp.swift      # App entry, SwiftData container, migration
├── ContentView.swift          # Tab navigation (People, Aircraft, Flights)
├── Models/
│   ├── Person.swift              # @Model: crew/passenger data
│   ├── TravelDocument.swift      # @Model: passport/ID card (many per Person)
│   ├── Aircraft.swift            # @Model: aircraft details
│   ├── Flight.swift              # @Model: flight leg with relationships
│   ├── Trip.swift                # @Model: multi-leg trip container
│   └── ICAOFlightPlanParser.swift # Parses pasted ICAO FPL text into flight fields
├── Views/
│   ├── LoginView.swift           # Google/Apple OAuth sign-in
│   ├── PeopleListView.swift      # CRUD for people + contact import button
│   ├── PersonEditView.swift      # Person details + document list
│   ├── AircraftListView.swift
│   ├── AircraftEditView.swift
│   ├── FlightsListView.swift
│   ├── FlightEditView.swift      # Flight details + form generation via share/email
│   ├── NewFlightFlow.swift       # Two-step new flight creation (route → people)
│   ├── SinglePersonPickerView.swift # Searchable single-select person picker
│   ├── ContactImportView.swift   # iOS/macOS contact import with fuzzy merge
│   └── ValidationErrorsView.swift
└── Services/
    ├── AppState.swift         # @Observable: JWT auth state, token storage
    ├── Environment.swift      # APIConfig (base URL, simulator vs device)
    ├── AuthService.swift      # Google OAuth + native Apple Sign-In
    ├── FormService.swift      # API client for /airports, /generate, /validate, /email-text; parses 422 into structured errors
    ├── PeopleCSVImporter.swift # CSV parser + SwiftData importer for bulk people entry
    ├── DocumentResolver.swift # Picks best document per person + airport region (active only)
    ├── AirportCatalog.swift   # Airport/form discovery with server sync
    └── APITypes.swift         # Codable request/response models
```

### Data Storage

- **SwiftData** with `ModelContainer` configured for CloudKit sync
- **CloudKit container:** `iCloud.net.ro-z.flyfun-forms` (private database, syncs across iOS + macOS)
- All PII encrypted at rest by Apple (CloudKit private DB guarantee)
- Works offline — form generation requires connectivity

### Auth Flow

Uses [flyfun-common OAuth](../../flyfun-common/designs/auth.md):

**Google:** Web OAuth via `ASWebAuthenticationSession`
1. User taps "Sign in with Google" on `LoginView`
2. `AuthService` opens `ASWebAuthenticationSession` → `https://forms.flyfun.aero/auth/login/google?platform=ios&scheme=flyfunforms`
3. Server handles OAuth, redirects to `flyfunforms://auth/callback?token=<JWT>`
4. `AppState` captures callback URL, extracts JWT, stores in keychain via `CodableSecureStorage` (from RZUtilsSwift)

**Apple:** Native `ASAuthorizationAppleIDProvider`
1. User taps the system "Sign in with Apple" button on `LoginView`
2. `AuthService.signInWithApple()` presents the native Apple Sign-In sheet via `ASAuthorizationController`
3. On success, extracts the identity token and user's name (name only provided on first authorization)
4. POSTs identity token + first/last name to `POST /auth/apple/token`
5. Server validates token against Apple's JWKS keys, creates/updates user (storing name on first login), returns a flyfun JWT

**Common:** All API requests include `Authorization: Bearer <JWT>` header. On logout, JWT cleared from keychain.

### API Integration

`FormService` handles all server communication:
- `GET /airports` — fetches available forms for airport discovery
- `GET /airports/{icao}` — form details (required fields, extra fields). Status-checked: 401 triggers re-auth.
- `POST /generate` — sends flight/people data, receives filled form file
- `POST /validate` — dry-run validation before generation
- `POST /email-text` — fetches localized email subject/body for pre-populating mail composer

**Validation error handling:** 422 responses are parsed into `ServerValidationError` structs (field, error, value). `FormError.validationErrors` carries the structured list. `ServerValidationError.displayField` converts API field paths like `crew[0].id_number` into human-readable labels ("Crew 1 — ID Number"). `ValidationErrorsView` presents them in a sheet.

### SwiftData Models

**Person:** firstName, lastName, dateOfBirth, sex, placeOfBirth, isUsualCrew, phone, email, address. Has many `TravelDocument`s. Legacy flat id fields (idNumber, idType, etc.) kept for migration only — not used in UI or API calls.

**TravelDocument:** docType (Passport/Identity card/Other), docNumber, issuingCountry (ISO alpha-3), expiryDate, isActive (default true). Belongs to Person. Nationality is derived from the selected document's issuingCountry — no person-level nationality. Inactive documents are hidden from the resolver but kept for record.

**Aircraft:** registration, type, owner, ownerAddress, isAirplane, usualBase

**Flight:** departureDate, departureTimeUTC, arrivalDate, arrivalTimeUTC, originICAO, destinationICAO, nature, observations, contact. Relationships: aircraft, crew (→ [Person]), passengers (→ [Person]), responsiblePerson (→ Person), trip, legOrder. `departureDateTime` computed property combines date + UTC time for sorting (uses UTC calendar). `copyCommon(to:)` copies shared properties for flight duplication.

**Trip:** name, createdAt, legs (→ [Flight]), extraFields (JSON-encoded dict for form-specific fields)

### Document Resolution

A person can have multiple travel documents (e.g., French + UK passport). `DocumentResolver` selects the best one at form generation time based on the target airport:

0. **Active filter** — only active documents (`isActive == true`) are considered; inactive ones are skipped
1. **User override** — if the user previously chose a specific document for this airport prefix, use it (stored in UserDefaults)
2. **Region match** — ICAO prefix → region (Schengen/UK/other), prefer document issued by a matching country
3. **Tiebreak** — latest expiry date among matching documents
4. **Fallback** — single document used directly; no documents → nil

The selected document's `issuingCountry` is sent as `nationality` in the API request.

On first launch after migration, existing Person flat id fields are converted to TravelDocument records automatically.

### ICAO Flight Plan Import

`NewFlightFlow` (and `FlightEditView`) supports pasting an ICAO FPL string from the clipboard. `ICAOFlightPlanParser` extracts registration, aircraft type, origin/destination ICAO, departure time, date of flight (DOF), and EET. Arrival time is computed from departure + EET. If no aircraft matches the parsed registration (normalized: dashes stripped, uppercased), a new `Aircraft` is created automatically.

### Contact Import

`ContactImportView` provides iOS (`CNContactPickerViewController`) and macOS (search-based `CNContactFetchRequest`) contact pickers. After picking a contact, `ContactResolveView` shows a resolution screen:
- **Fuzzy matching:** finds existing `Person` records by name similarity (prefix matching + Levenshtein distance ≤ 2)
- **Create new:** creates a fresh `Person` with phone, email, address, DOB from the contact
- **Merge into existing:** either "Fill Missing Only" (preserves existing fields) or "Override All" mode

### Form Export

Two export paths per form: **Share** (generic share sheet) and **Email** (pre-populated mail composer):

- **Share:** `UIActivityViewController` on iOS, custom `MacShareView` (save/copy/Finder reveal) on macOS
- **Email:** `MFMailComposeViewController` on iOS, `NSSharingService.composeEmail` on macOS. Pre-fills to/cc from `email_overrides` or `send_to` in the mapping, subject/body from `POST /email-text` (with language preference: local, English, or both). Falls back to client-side subject/body if the server call fails.

Email language preference is stored in `@AppStorage("emailLanguage")` with options: `.local`, `.english`, `.both`.

### NOTAM Notifications

`FlightEditView` fetches notification info (NOTAMs, airport notices) from `maps.flyfun.aero` for both origin and destination airports. Displayed as collapsible rows in the Route section with summary + expandable detail.

### Flight Actions

Three flight duplication actions share common property copying via `Flight.copyCommon(to:)`:
- **Create Return Flight** — swaps origin/destination, sets departure to arrival date
- **Create Next Leg** — continues from destination, increments `legOrder`, preserves `trip`
- **Duplicate Flight** — exact copy including times and observations

All three navigate to the new flight immediately via `switchToFlight(_:)`.

### Responsible Person & Contact Auto-Fill

The responsible person picker uses `SinglePersonPickerView` (searchable, single-select, sorted by usual crew then recent flights). When a responsible person is set:
- `flight.contact` is set to their `displayName` (sent as `flight.contact` in the API request)
- Extra fields `telephone` and `email` are auto-filled from the person's phone/email if not already set

## Usage Examples

```swift
// API call to generate a form
let request = GenerateRequest(
    airport: "LSGS", form: "immigration",
    flight: flightData, aircraft: aircraftData,
    crew: crewList, passengers: paxList
)
let fileData = try await formService.generate(request, flatten: true)
```

```swift
// Auth state check
if appState.isAuthenticated {
    ContentView()
} else {
    LoginView()
}
```

## Key Choices

- **SwiftData over Core Data:** Modern API, native CloudKit integration, less boilerplate. Requires iOS 17+.
- **CloudKit private DB for PII:** Apple handles encryption. No custom encryption layer needed. Cross-device sync is automatic.
- **Native Apple Sign-In:** Uses `ASAuthorizationAppleIDProvider` for polished system UI. Identity token exchanged server-side via `POST /auth/apple/token`. Name captured and stored on first authorization only.
- **ASWebAuthenticationSession for Google:** System-provided OAuth UI. Handles Safari cookie sharing and secure callback. No embedded WebView.
- **JWT in keychain:** Using RZUtilsSwift's `CodableSecureStorage` for secure, typed token storage.
- **URL scheme `flyfunforms://`:** For OAuth callback redirect from server back to app.
- **Multi-document per person:** Real pilots carry multiple passports/IDs. Document selection is automatic per region but overridable. Nationality derived from document, not stored on person.
- **Share sheet over fileExporter:** `UIActivityViewController` (iOS) / custom save/copy/reveal view (macOS) gives users more export options than the file-save dialog.
- **Dev vs prod base URL:** `#if targetEnvironment(simulator) || os(macOS)` switches to `localhost.ro-z.me:8443` for local dev server testing. Physical iOS devices use `forms.flyfun.aero`.

## Gotchas

- CloudKit sync requires iCloud to be enabled on the device and a signed-in Apple ID
- **CloudKit container must match bundle ID convention:** Container `iCloud.net.ro-z.flyfun-forms` matches bundle `net.ro-z.flyfun-forms`. Using a non-matching name (e.g., `iCloud.aero.flyfun.flightforms`) causes "Invalid bundle ID for container" errors.
- SwiftData + CloudKit doesn't support unique constraints — deduplication must be handled in code if needed
- The `isUsualCrew` flag on Person is a UI convenience — it doesn't affect the data model or API
- Flight relationships to Person are many-to-many (a person can be on multiple flights)
- Extra fields (form-specific like `reason_for_visit`) are stored as JSON in Trip, not as typed properties
- **macOS platform guards:** iOS-only APIs need `#if os(iOS)` guards: `.textInputAutocapitalization`, `.listStyle(.insetGrouped)` (use `.inset` on macOS), `.topBarLeading` toolbar placement (use `.navigation`), `.navigationBarTitleDisplayMode`
- **macOS sheet sizing:** Sheets presented on macOS need explicit `.frame(minWidth:minHeight:)` or they render too small to be usable
- **macOS sandbox:** Requires `com.apple.security.network.client` entitlement for outbound network (API calls + CloudKit sync)

## Status

- Models, CRUD UI, auth flow, API integration: **complete**
- CSV import for bulk people entry: **complete**
- Multi-document per person with auto-resolve: **complete**
- PDF preview via QuickLook: **complete**
- Extra fields dynamic UI (choice, person, text): **complete**
- macOS compilation and CloudKit sync: **complete**
- Navigate to edit on create (people, aircraft): **complete**
- Active/inactive flag on travel documents: **complete**
- Human-readable validation error display: **complete**
- ICAO flight plan paste import (with auto-create aircraft): **complete**
- Share sheet for form export (iOS + macOS): **complete**
- Email with pre-populated composer (to/cc/subject/body/attachment): **complete**
- Localized email text with language preference (local/English/both): **complete**
- NOTAM notification display in route section: **complete**
- Collapsible flight detail sections (schedule, details, crew, passengers): **complete**
- Next Leg / Return Flight / Duplicate with shared property copying: **complete**
- Past/upcoming flight split with collapsible past section: **complete**
- Searchable responsible person picker with contact auto-fill: **complete**
- Contact import from device contacts with fuzzy merge: **complete**
- Account deletion (App Store guideline 5.1.1(v)): **complete**
- Document override UI (tap to switch per airport): **planned**

## References

- [API](./api.md) — backend endpoints the app calls
- [flyfun-common auth](../../flyfun-common/designs/auth.md) — OAuth flow (iOS variant with `?platform=ios`)
- [RZUtilsSwift](../../rzutils/designs/rzutils-swift.md) — `CodableSecureStorage` for keychain
