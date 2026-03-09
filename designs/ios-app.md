# iOS App

> SwiftUI app for managing crew/passenger data and generating customs forms via the flyfun-forms API

## Intent

Native iOS/iPadOS/macOS app that lets pilots manage their people database (crew, passengers with passport details), aircraft, and flights — then generate pre-filled customs forms with one tap. PII stays on-device (encrypted SwiftData + CloudKit private DB), only sent transiently to the server for form generation.

## Architecture

```
app/flyfun-forms/flyfun-forms/
├── flyfun_formsApp.swift      # App entry, SwiftData container setup
├── ContentView.swift          # Tab navigation (People, Aircraft, Flights)
├── Models/
│   ├── Person.swift           # @Model: crew/passenger data + passport
│   ├── Aircraft.swift         # @Model: aircraft details
│   ├── Flight.swift           # @Model: flight leg with relationships
│   └── Trip.swift             # @Model: multi-leg trip container
├── Views/
│   ├── LoginView.swift        # Google/Apple OAuth sign-in
│   ├── PeopleListView.swift   # CRUD for people
│   ├── PersonEditView.swift
│   ├── AircraftListView.swift
│   ├── AircraftEditView.swift
│   ├── FlightsListView.swift
│   └── FlightEditView.swift
└── Services/
    ├── AppState.swift         # @Observable: JWT auth state, token storage
    ├── Environment.swift      # APIConfig (base URL per environment)
    ├── AuthService.swift      # OAuth via ASWebAuthenticationSession
    ├── FormService.swift      # API client for /airports, /generate, /validate
    └── APITypes.swift         # Codable request/response models
```

### Data Storage

- **SwiftData** with `ModelContainer` configured for CloudKit sync
- **CloudKit container:** `iCloud.aero.flyfun.flightforms` (private database)
- All PII encrypted at rest by Apple (CloudKit private DB guarantee)
- Works offline — form generation requires connectivity

### Auth Flow

Uses [flyfun-common OAuth](../../flyfun-common/designs/auth.md) with iOS-specific redirect:

1. User taps "Sign in with Google" on `LoginView`
2. `AuthService` opens `ASWebAuthenticationSession` → `https://forms.flyfun.aero/auth/login/google?platform=ios&scheme=flyfunforms`
3. Server handles OAuth, redirects to `flyfunforms://auth/callback?token=<JWT>`
4. `AppState` captures callback URL, extracts JWT, stores in keychain via `CodableSecureStorage` (from RZUtilsSwift)
5. All API requests include `Authorization: Bearer <JWT>` header
6. On logout, JWT cleared from keychain

### API Integration

`FormService` handles all server communication:
- `GET /airports` — fetches available forms for airport discovery
- `GET /airports/{icao}` — form details (required fields, extra fields)
- `POST /generate` — sends flight/people data, receives filled form file
- `POST /validate` — dry-run validation before generation

### SwiftData Models

**Person:** firstName, lastName, dateOfBirth, nationality, idNumber, idType, idIssuingCountry, idExpiry, sex, placeOfBirth, isUsualCrew (flag for quick crew selection)

**Aircraft:** registration, type, owner, ownerAddress, isAirplane, usualBase

**Flight:** departureDate, departureTimeUTC, arrivalDate, arrivalTimeUTC, originICAO, destinationICAO, nature, observations, contact. Relationships: aircraft, crew (→ [Person]), passengers (→ [Person]), trip, legOrder

**Trip:** name, createdAt, legs (→ [Flight]), extraFields (JSON-encoded dict for form-specific fields)

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
- **ASWebAuthenticationSession:** System-provided OAuth UI. Handles Safari cookie sharing and secure callback. No embedded WebView.
- **JWT in keychain:** Using RZUtilsSwift's `CodableSecureStorage` for secure, typed token storage.
- **URL scheme `flyfunforms://`:** For OAuth callback redirect from server back to app.

## Gotchas

- CloudKit sync requires iCloud to be enabled on the device and a signed-in Apple ID
- SwiftData + CloudKit doesn't support unique constraints — deduplication must be handled in code if needed
- The `isUsualCrew` flag on Person is a UI convenience — it doesn't affect the data model or API
- Flight relationships to Person are many-to-many (a person can be on multiple flights)
- Extra fields (form-specific like `reason_for_visit`) are stored as JSON in Trip, not as typed properties

## Status

- Models, CRUD UI, auth flow, API integration: **complete**
- CSV import for bulk people entry: **complete**
- Extra fields dynamic UI: **in progress**
- Share sheet / document handling: **planned**
- PDF preview: **planned**

## References

- [API](./api.md) — backend endpoints the app calls
- [flyfun-common auth](../../flyfun-common/designs/auth.md) — OAuth flow (iOS variant with `?platform=ios`)
- [RZUtilsSwift](../../rzutils/designs/rzutils-swift.md) — `CodableSecureStorage` for keychain
