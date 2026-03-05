# Flight Forms Generator

## Problem

When flying GA (General Aviation) internationally, each airport requires customs/immigration forms with repetitive data: aircraft info, crew details, passenger details (including sensitive passport numbers). Currently filled by hand in Acrobat/Preview — tedious and error-prone.

## Data Model

### Aircraft
- Registration (e.g. N122DR)
- Type (e.g. S22T)
- Owner name
- Owner/responsible person address (required by GAR)
- isAirplane (vs helicopter)
- Usual base (ICAO code)

### People
- First name, last name
- Date of birth
- Nationality (ISO 3166 alpha-3)
- Passport/ID number ← **sensitive**
- ID type (Passport / Identity card / Other)
- ID expiry date
- ID issuing country
- Sex
- Place of birth
- Role hint (usually Crew or Pax)

### Flight
- Departure date + time (UTC)
- Arrival date + time (UTC)
- Origin airport (ICAO)
- Destination airport (ICAO)
- Aircraft (reference)
- Crew (list of People, with function: Pilot/Captain/Crew)
- Passengers (list of People)
- Nature of flight (Private, Commercial, etc.)
- Observations (e.g. "Nothing to declare")
- Contact info (phone, email)

### Trip (multi-leg)
- Ordered list of Flights (legs)
- Each leg shares the same aircraft, crew, and passengers (with possible variations)
- Forms are generated per-leg, but some forms at intermediate stops may reference the connecting leg

### Form Templates
- Airport ICAO(s) or ICAO prefix this template applies to
- Template file (PDF with AcroForm fields, DOCX, or XLSX)
- Field mapping: which data model fields map to which template fields
- Version identifier (incremented when template or mapping changes)
- Time format: whether the form expects UTC or local time
- Timezone (for local time conversion)
- Extra fields: form-specific fields beyond the core data model (e.g. reason_for_visit)
- Max crew / max passengers capacity

**Direction is derived, not specified.** A form is always generated for a flight from origin to destination. The form's airport determines the direction:
- Form airport == destination → **arrival** form
- Form airport == origin → **departure** form

**Multiple forms per airport.** An airport can have more than one form (e.g. customs + immigration). Each form has its own mapping config and template. The `/airports/{icao}` response lists all available forms, and `/generate` takes a `form` ID to select which one. The `trip` command and iOS app must generate all applicable forms for each leg.

## Form Template Inventory

| Airport(s) | Format | Method | Status |
|---|---|---|---|
| LSGS (Sion) | PDF AcroForm | pypdf field fill | Ready |
| LFRG, LFAC, LFOH | PDF AcroForm | pypdf field fill (same French customs template) | Ready |
| LFRD (Dinard) | PDF AcroForm | pypdf field fill (different layout) | Ready |
| LFQA (Reims) | DOCX | python-docx (append runs + fill table cells) | Ready |
| GAR (UK) | XLSX | openpyxl cell fill | Ready |
| LFQB (Troyes) | PDF flat | Needs fillable AcroForm (recreate in Acrobat) | Not ready |
| EGJB (Guernsey) | PDF signed | Needs fillable AcroForm (recreate in Acrobat) | Not ready |
| EIWT (Weston) | PDF flat | Needs fillable AcroForm (recreate in Acrobat) | Not ready |

**Flat PDF strategy:** For airports with non-fillable PDFs (LFQB, EGJB, EIWT), the templates must be recreated as fillable AcroForm PDFs using Adobe Acrobat. This is manual work but there's no practical alternative — PDF form-filling libraries need AcroForm fields to target.

### GAR XLSX Template Details

Source: `GAR_Template_Nov_2025_v6.7_SDS.xlsx` — 4 sheets (GAR, Declaration, Reporting Goods, Guidance).
Only the GAR sheet needs filling. Extra fields vs other forms: sex, place of birth, ID type, ID issuing country, ID expiry date, usual base, reason for visit, responsible person address.

**Flight header (rows 2-6):**
| Cell | Field |
|---|---|
| A2 | Arrival / Departure (derived from flight direction) |
| A3 | Arrival airport ICAO |
| C3 | Date of arrival (DD/MM/YYYY) |
| E3 | Time of arrival (HH:MM:SS UTC) |
| G3 | Owner/Operator |
| I3 | Contact number & email |
| A4 | Departure airport ICAO |
| C4 | Date of departure |
| E4 | Time of departure |
| A5 | Aircraft registration |
| C5 | Aircraft type |
| E5 | Captain surname |
| G5 | Usual base |
| A6 | Reason for visit |
| C6 | Responsible person address |

**Crew (rows 9-16) and Passengers (rows 20-39):** Same columns per person:
| Column | Field |
|---|---|
| A | TD type (Passport / Identity card) |
| B | Nature of doc (if Other) |
| C | Issuing country (ISO alpha-3) |
| D | TD number |
| E | Surname |
| F | Forenames |
| G | Sex |
| H | DOB (DD/MM/YYYY) |
| I | Place of birth |
| J | Nationality (ISO alpha-3) |
| K | TD expiry date |
| L | Address |

Totals at B17 and B40 are `=COUNTA()` formulas — auto-calculate.

## Architecture: Form Generation API + Multiple Clients

Same infrastructure pattern as [flyfun-weather](~/Developer/public/flyfun-weather/main/designs/architecture.md): FastAPI + Docker + Caddy on the existing DigitalOcean droplet, joining the `shared-services` Docker network with shared MySQL.

```
forms.flyfun.aero (Caddy, auto-TLS)
    → reverse_proxy localhost:8030
        → flightforms Docker container (FastAPI + uvicorn)
            → shared-mysql (Docker network: shared-services)
            → templates/ + mappings/ (bundled in image)

┌──────────────────┐                        ┌────────────────────────────┐
│   CLI Client     │                        │                            │
│                  │    POST /generate      │   Form Generation API      │
│ Reads people     │───────────────────────>│   (FastAPI + uvicorn)      │
│ from spreadsheet │  + API key             │                            │
│ (local CSV/XLSX) │<───────────────────────│   - pypdf + python-docx    │
│                  │    filled form file    │     + openpyxl             │
└──────────────────┘                        │   - Templates + mappings   │
                                            │   - MySQL: users + usage   │
┌──────────────────┐                        │                            │
│   iOS App        │    POST /generate      │   Auth:                    │
│                  │───────────────────────>│   - Apple/Google OAuth     │
│ SwiftData +      │  + JWT cookie or       │     (authlib)              │
│ CloudKit for     │    Bearer token        │   - JWT sessions           │
│ cross-device     │<───────────────────────│   - API key fallback (CLI) │
│ sync of PII      │    filled form file    │                            │
│                  │                        │   Endpoints:               │
└──────────────────┘                        │   GET  /airports           │
                                            │   GET  /airports/{icao}    │
                                            │   POST /generate           │
                                            └────────────────────────────┘
```

**Why this architecture:**
- PII lives only on client (iOS encrypted storage or local CSV). Server sees data transiently over HTTPS, never writes it to disk.
- Server is a form-generation service. No email sending, no PII storage, no side effects. All sending, saving, and exporting is handled by the client.
- Server-side Python gives us pypdf + python-docx + openpyxl — proven, simple, already working from prototyping.
- Adding a new airport template = drop a file on the server + add a mapping JSON. No code changes, no app update.
- Reuses the same infrastructure as flyfun-weather: Caddy, Docker, shared MySQL, same deployment workflow.

**Tech Stack (mirrors flyfun-weather):**

| Component | Choice | Notes |
|-----------|--------|-------|
| API framework | FastAPI + uvicorn | Same as flyfun-weather |
| Auth | authlib (Google + Apple OAuth) | Google flow same as flyfun-weather; add Apple for App Store |
| Sessions | JWT (HS256) in httpOnly cookie | Same pattern as flyfun-weather |
| Database | SQLAlchemy (SQLite dev / MySQL prod) | Same as flyfun-weather |
| Migrations | Alembic | Same as flyfun-weather |
| Form filling | pypdf, python-docx, openpyxl | Specific to this project |
| Containerization | Docker (python:3.13-slim) | Same as flyfun-weather |
| Reverse proxy | Caddy with auto-TLS | Same droplet, new subdomain |
| Dev mode | `ENVIRONMENT=development` → SQLite + auth bypass | Same pattern as flyfun-weather |

**Security & Auth:**
- HTTPS only in production (Caddy auto-TLS). HTTP allowed only for local development/testing
- **Sign in with Apple / Google:** authlib OAuth flow, same pattern as flyfun-weather's Google OAuth. Apple OAuth added for App Store requirement (must offer Apple sign-in if any third-party sign-in is offered). Both flows: redirect → consent → callback → JWT cookie
- **Users table (MySQL):** stores user ID, provider (apple/google), provider_sub, display name, approved flag, created_at. No passwords, minimal PII (just what the OAuth provider gives). Auto-approved on signup; admin can revoke
- **Rate limiting per user:** request counts tracked in `usage` table (persistent, for analytics) + in-memory sliding window counters (for enforcement, e.g. 60 requests/minute)
- **CLI auth:** static API key (same as flyfun-weather's `wb_` token pattern). Server accepts both JWT cookies (iOS) and Bearer API key (CLI)
- **Dev mode:** `ENVIRONMENT=development` → auth middleware auto-injects dev user, no login needed. SQLite instead of MySQL. Same pattern as flyfun-weather
- No request body logging, no PII retention — form data is processed in memory and never written to disk
- Request payload size limit (reject abnormally large payloads)

**Database Schema (SQLAlchemy — SQLite dev / MySQL prod):**

### users

| Column | Type | Notes |
|--------|------|-------|
| id | VARCHAR(36) PK | UUID |
| provider | VARCHAR(20) | `google`, `apple`, or `api` (CLI) |
| provider_sub | VARCHAR(255) UNIQUE | OAuth subject ID |
| email | VARCHAR(255) NULL | From OAuth profile (optional) |
| display_name | VARCHAR(255) | |
| approved | BOOLEAN DEFAULT TRUE | Admin can revoke |
| created_at | DATETIME | |
| last_login_at | DATETIME | |

### usage

| Column | Type | Notes |
|--------|------|-------|
| id | INT AUTO_INCREMENT PK | |
| user_id | VARCHAR(36) FK | |
| endpoint | VARCHAR(50) | `generate`, `airports`, etc. |
| airport_icao | VARCHAR(4) NULL | Which airport form was generated |
| timestamp | DATETIME | |

Lightweight — just enough for rate limiting and basic analytics (which airports/forms are most used).

## API Design

**Airport name resolution:** Airport names (e.g. "Sion", "Le Touquet") are resolved from the `airports.db` database via the euro_aip Python model (server-side) and KnownAirports (iOS-side via rzflight Swift package). Names are not hardcoded in mapping configs.

### `GET /airports`

Returns list of airports that have form templates available, plus country-level fallback prefixes.

```json
{
  "airports": [
    {"icao": "LSGS", "name": "Sion", "forms": ["immigration"]},
    {"icao": "LFAC", "name": "Le Touquet", "forms": ["customs"]},
    {"icao": "LFRG", "name": "Deauville", "forms": ["customs"]},
    {"icao": "LFOH", "name": "Le Havre", "forms": ["customs"]},
    {"icao": "LFRD", "name": "Dinard", "forms": ["customs"]},
    {"icao": "LFQA", "name": "Reims Prunay", "forms": ["customs"]},
    {"icao": "EGTF", "name": "Fairoaks", "forms": ["gar"]},
    {"icao": "EGJB", "name": "Guernsey", "forms": ["gar"]}
  ],
  "prefixes": [
    {"prefix": "EG", "country": "United Kingdom", "forms": ["gar"]},
    {"prefix": "LF", "country": "France", "forms": ["customs"]}
  ]
}
```

### `GET /airports/{icao}`

Returns template details, required fields, and form-specific extra fields for a specific airport.

```json
{
  "icao": "LSGS",
  "name": "Sion",
  "forms": [
    {
      "id": "immigration",
      "label": "Immigration Information",
      "version": "1.0",
      "required_fields": {
        "flight": ["origin", "destination", "departure_date", "departure_time_utc", "arrival_date", "arrival_time_utc"],
        "aircraft": ["registration", "type"],
        "crew": ["function", "first_name", "last_name", "dob", "id_number", "nationality"],
        "passengers": ["first_name", "last_name", "dob", "id_number", "nationality"]
      },
      "extra_fields": [],
      "max_crew": 4,
      "max_passengers": 8,
      "has_connecting_flight": false,
      "time_reference": "utc",
      "send_to": "aeroport@sion.ch"
    }
  ]
}
```

Example for GAR with extra fields:
```json
{
  "icao": "EGTF",
  "name": "Fairoaks",
  "forms": [
    {
      "id": "gar",
      "label": "General Aviation Report",
      "version": "6.7",
      "required_fields": {
        "flight": ["origin", "destination", "departure_date", "departure_time_utc", "arrival_date", "arrival_time_utc"],
        "aircraft": ["registration", "type", "owner", "usual_base", "owner_address"],
        "crew": ["function", "first_name", "last_name", "dob", "id_number", "nationality", "id_type", "id_issuing_country", "id_expiry", "sex", "place_of_birth"],
        "passengers": ["first_name", "last_name", "dob", "id_number", "nationality", "id_type", "id_issuing_country", "id_expiry", "sex", "place_of_birth"]
      },
      "extra_fields": [
        {"key": "reason_for_visit", "label": "Reason for visit", "type": "text"}
      ],
      "max_crew": 8,
      "max_passengers": 20,
      "has_connecting_flight": true,
      "time_reference": "utc",
      "send_to": null
    }
  ]
}
```

The `extra_fields` array tells the client which additional form-specific fields to collect. The client UI adapts dynamically — only showing these fields when generating forms that require them. The `send_to` field is informational for the client (to pre-populate email recipients); the server never sends email.

### `POST /generate`

Generate a filled form. Returns the filled document as a binary download.

**Direction is derived:** The server determines arrival vs departure from the flight's origin/destination relative to the form airport. No explicit `direction` parameter needed.

```json
{
  "airport": "LSGS",
  "form": "immigration",
  "flight": {
    "origin": "LFQA",
    "destination": "LSGS",
    "departure_date": "2025-09-07",
    "departure_time_utc": "08:00",
    "arrival_date": "2025-09-07",
    "arrival_time_utc": "09:00",
    "nature": "private",
    "contact": "+44000000000, pilot@example.com"
  },
  "aircraft": {
    "registration": "N999XX",
    "type": "S22T",
    "owner": "Jane Doe",
    "owner_address": "123 Aviation Way, Anytown, UK",
    "is_airplane": true,
    "usual_base": "EGTF"
  },
  "crew": [
    {
      "function": "Pilot",
      "first_name": "Jane",
      "last_name": "Doe",
      "dob": "1980-01-01",
      "nationality": "FRA",
      "id_number": "XX0000001",
      "id_type": "Passport",
      "id_issuing_country": "FRA",
      "id_expiry": "2035-01-01",
      "sex": "Female",
      "place_of_birth": "Lyon"
    }
  ],
  "passengers": [
    {
      "first_name": "John",
      "last_name": "Doe",
      "dob": "1982-06-15",
      "nationality": "FRA",
      "id_number": "XX0000002",
      "id_type": "Passport",
      "id_issuing_country": "FRA",
      "id_expiry": "2032-06-15",
      "sex": "Male",
      "place_of_birth": "Marseille"
    }
  ],
  "connecting_flight": {
    "origin": "LSGS",
    "destination": "LFQA",
    "departure_date": "2025-09-08",
    "departure_time_utc": "10:00",
    "arrival_date": "2025-09-08",
    "arrival_time_utc": "11:00"
  },
  "extra_fields": {
    "reason_for_visit": "Tourism"
  },
  "observations": "Nothing to declare"
}
```

**Direction derivation logic:**
- `airport` == `flight.destination` → arrival form (flight is arriving at this airport)
- `airport` == `flight.origin` → departure form (flight is departing from this airport)
- `airport` matches neither → **400 error**: airport must be either origin or destination

**Connecting flight (optional):** For forms that capture both arrival and departure info at a given airport (e.g. tech stops where a single form covers the full visit), the `connecting_flight` provides the other leg. If the primary flight is arriving, the connecting flight is the departure (and vice versa). Ignored by forms that don't use it (`has_connecting_flight: false`).

**Validation errors:**
- Crew count exceeds `max_crew` → **422 error**: "Too many crew members (max: {n})"
- Passenger count exceeds `max_passengers` → **422 error**: "Too many passengers (max: {n})"
- Missing required fields → **422 error** with list of missing fields
- Unknown airport/form → **404 error**

**PDF flattening (optional):** Add `?flatten=true` query parameter. When set, filled PDF AcroForm fields are flattened (made non-editable) in the output. Default is `false` — the user gets an editable form they can continue to modify manually. Ignored for DOCX and XLSX formats.

**Response:** Binary file with appropriate Content-Type:
- `application/pdf` for PDF forms
- `application/vnd.openxmlformats-officedocument.wordprocessingml.document` for DOCX
- `application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` for XLSX (GAR)

With `Content-Disposition: attachment; filename="20250907_LSGS_immigration.pdf"`

Note: Person fields like `id_type`, `id_issuing_country`, `id_expiry`, `sex`, `place_of_birth` are only required by GAR. Other forms ignore them if present. The API accepts the superset; each filler uses what it needs.

### `POST /validate`

Accepts the same request body as `/generate` but does not produce a form. Returns validation results: missing required fields, crew/passenger count issues, unknown airport/form errors. Useful for the iOS app to validate input before committing to form generation.

```json
// Success response
{ "valid": true }

// Error response
{
  "valid": false,
  "errors": [
    {"field": "crew[0].id_expiry", "error": "required for this form"},
    {"field": "passengers", "error": "count 25 exceeds max 20"}
  ]
}
```

## Server Internals

```
src/flightforms/
├── api/
│   ├── app.py                # FastAPI app, lifespan (DB init), CORS
│   ├── auth.py               # OAuth login/callback/logout (Apple + Google), JWT cookie
│   ├── auth_config.py        # JWT secret, dev mode detection, admin emails
│   ├── generate.py           # POST /generate endpoint
│   ├── validate.py           # POST /validate endpoint (dry-run validation)
│   └── airports.py           # GET /airports, GET /airports/{icao}
├── db/
│   ├── models.py             # SQLAlchemy ORM (User, Usage)
│   ├── engine.py             # Singleton engine, init_db(), dev user
│   └── deps.py               # FastAPI deps: get_db(), current_user_id()
├── templates/                # Form template files
│   ├── lsgs_immigration.pdf
│   ├── french_customs.pdf    # Shared: LFRG, LFAC, LFOH
│   ├── lfrd_customs.pdf
│   ├── lfqa_customs.docx
│   └── gar_template.xlsx
├── mappings/                 # Field mapping configs (JSON)
│   ├── lsgs.json
│   ├── french_customs.json
│   ├── lfrd.json
│   ├── lfqa.json
│   └── gar.json
└── fillers/                  # Form filling logic
    ├── pdf_filler.py         # pypdf-based AcroForm filler
    ├── docx_filler.py        # python-docx filler
    └── xlsx_filler.py        # openpyxl filler (GAR)
```

**Template + mapping approach:**
- Each mapping JSON defines: which template file to use, filler type, version, timezone, and a map from the API's canonical field names to the template's actual field names
- The filler reads the mapping, opens the template, fills fields, converts times if needed, returns bytes
- Adding a new airport = add template file + mapping JSON, no code changes
- Templates and mappings should be volume-mounted in Docker (not just bundled in the image) so they can be updated without rebuilding

**Filler conventions:**
- **Enum-to-checkbox mapping:** When the API sends a string value like `flight.nature = "private"`, the filler maps it to checkboxes via dotted field names in the mapping (e.g. `flight.nature.private` → check, `flight.nature.commercial` → uncheck). The filler iterates over `flight.nature.*` keys in the field_map, checking the one that matches the value and unchecking the rest.
- **Direction checkboxes:** Similarly, `direction.inbound` / `direction.outbound` are set based on the derived arrival/departure direction.

**Timezone handling:**
- The API always accepts times in UTC
- Each mapping config specifies `time_reference`: either `"utc"` or `"local"`
- If `"local"`, the mapping also includes `time_zone` (e.g. `"Europe/Zurich"`) and the filler converts UTC → local time before filling the form
- If `"utc"`, times are used as-is

**Default observations:** Each mapping config can include a `default_observations` field (e.g. `"Nothing to declare"`). If the client doesn't supply `observations` in the request, the filler uses this default. This reduces repetitive input for forms where the same boilerplate is always needed.

Example mapping (`mappings/lsgs.json`):
```json
{
  "template": "lsgs_immigration.pdf",
  "type": "pdf_acroform",
  "version": "1.0",
  "time_reference": "utc",
  "field_map": {
    "flight.departure_date": "Text1",
    "flight.departure_time_utc": "Text2",
    "aircraft.registration": "Text7",
    "flight.origin": "Text8",
    "origin.country": "Text9",
    "direction.inbound": "undefined",
    "direction.outbound": "undefined_2",
    "aircraft.airplane": "Check Box1",
    "aircraft.helicopter": "Check Box2",
    "flight.nature.commercial": "Check Box3",
    "flight.nature.private": "Check Box4",
    "passengers.count": "PAX NUMBER",
    "crew[{i}].function": "FONCTIONRow{n}",
    "crew[{i}].first_name": "FIRST NAMERow{n}",
    "crew[{i}].last_name": "LAST NAMERow{n}",
    "crew[{i}].dob": "DOBRow{n}",
    "crew[{i}].id_number": "ID NUMBERRow{n}",
    "crew[{i}].nationality": "NATIONALITYRow{n}",
    "passengers[{i}].first_name": "FIRST NAMERow{n}_2",
    "passengers[{i}].last_name": "LAST NAMERow{n}_2",
    "passengers[{i}].dob": "DOBRow{n}_2",
    "passengers[{i}].id_number": "ID NUMBERRow{n}_2",
    "passengers[{i}].nationality": "NATIONALITYRow{n}_2"
  },
  "checkbox_on": "/Oui",
  "date_format": "%-d-%b-%Y",
  "default_observations": "Nothing to declare"
}
```

Example mapping (`mappings/gar.json`):
```json
{
  "template": "gar_template.xlsx",
  "type": "xlsx",
  "version": "6.7",
  "time_reference": "utc",
  "extra_fields": ["reason_for_visit"],
  "header_map": {
    "direction": "A2",
    "arrival_icao": "A3",
    "arrival_date": "C3",
    "arrival_time": "E3",
    "owner": "G3",
    "contact": "I3",
    "departure_icao": "A4",
    "departure_date": "C4",
    "departure_time": "E4",
    "registration": "A5",
    "aircraft_type": "C5",
    "captain_surname": "E5",
    "usual_base": "G5",
    "reason_for_visit": "A6",
    "responsible_address": "C6"
  },
  "crew_start_row": 9,
  "crew_max": 8,
  "pax_start_row": 20,
  "pax_max": 20,
  "person_columns": {
    "id_type": "A",
    "id_type_other": "B",
    "id_issuing_country": "C",
    "id_number": "D",
    "last_name": "E",
    "first_name": "F",
    "sex": "G",
    "dob": "H",
    "place_of_birth": "I",
    "nationality": "J",
    "id_expiry": "K",
    "address": "L"
  },
  "date_format": "DD/MM/YYYY",
  "time_format": "HH:MM:SS"
}
```

## CLI Client

Simple Python script that reads a flight spec and a people spreadsheet:

```bash
# Generate LSGS immigration form for arriving flight
./flightforms generate \
  --airport LSGS \
  --origin LFQA --destination LSGS \
  --departure-date 2025-09-07 --departure-time 08:00 \
  --arrival-date 2025-09-07 --arrival-time 09:00 \
  --aircraft N999XX \
  --crew "Jane Doe" \
  --pax "John Doe" \
  --people-file ~/people.csv \
  --output 20250907_LSGS.pdf

# Generate GAR for UK arrival
./flightforms generate \
  --airport EGTF \
  --origin LFQA --destination EGTF \
  --departure-date 2025-08-01 --departure-time 08:00 \
  --arrival-date 2025-08-01 --arrival-time 10:00 \
  --aircraft N999XX \
  --crew "Jane Doe" \
  --pax "John Doe" \
  --people-file ~/people.csv \
  --extra reason_for_visit=Tourism \
  --output 20250801_GAR.xlsx

# Generate all forms for a multi-leg trip
./flightforms trip \
  --legs "EGTF>LFQA,LFQA>LSGS,LSGS>LFQA,LFQA>EGTF" \
  --dates "2025-09-06,2025-09-07,2025-09-08,2025-09-09" \
  --aircraft N999XX \
  --crew "Jane Doe" \
  --pax "John Doe" \
  --people-file ~/people.csv \
  --output-dir ./trip_forms/
```

The `trip` command generates all required forms for each leg by making multiple `/generate` calls. It automatically links connecting flights for forms that need them, and generates **all** forms for airports that have multiple forms (e.g. both customs and immigration).

The `--people-file` CSV/XLSX contains the full details keyed by name, so the CLI just needs names on the command line and looks up the rest.

```csv
name,first_name,last_name,dob,nationality,id_number,id_type,id_issuing_country,id_expiry,sex,place_of_birth
Jane Doe,Jane,Doe,1980-01-01,FRA,XX0000001,Passport,FRA,2035-01-01,Female,Lyon
John Doe,John,Doe,1982-06-15,FRA,XX0000002,Passport,FRA,2032-06-15,Male,Marseille
```

## iOS / iPadOS / macOS App

**SwiftData + CloudKit** for cross-device sync (iPhone, iPad, Mac — single SwiftUI codebase).

PII is stored in Apple's ecosystem (SwiftData + CloudKit private database). Apple encrypts data in transit and at rest. Users who are comfortable using their iPhone for banking and passport apps should be comfortable here. Users who aren't can use the CLI with a local CSV instead.

```swift
let config = ModelConfiguration(
    cloudKitDatabase: .private("iCloud.aero.flyfun.flightforms")
)
let container = try ModelContainer(
    for: Person.self, Aircraft.self, Flight.self, Trip.self,
    configurations: config
)
```

**How it works:**
- SwiftData manages the local persistent store (SQLite under the hood)
- `cloudKitDatabase: .private(...)` automatically mirrors to the user's private CloudKit database
- Sync is automatic, bidirectional, and conflict-resolved by Apple
- Data is encrypted in transit and at rest by iCloud
- Only the signed-in iCloud user can access their private database
- Works offline with local cache, syncs when back online (form generation requires connectivity)

**Requirements:**
- CloudKit capability + iCloud entitlement in Xcode
- All `@Model` properties must be optional or have defaults (CloudKit constraint)
- Relationships must be optional

**SwiftData Models:**

```swift
@Model
class Person {
    var firstName: String = ""
    var lastName: String = ""
    var dateOfBirth: Date?
    var nationality: String?        // ISO alpha-3
    var idNumber: String?           // passport / CI
    var idType: String?             // "Passport", "Identity card"
    var idIssuingCountry: String?   // ISO alpha-3
    var idExpiry: Date?
    var sex: String?                // "Male", "Female"
    var placeOfBirth: String?
    var isUsualCrew: Bool = false

    var fullName: String { "\(firstName) \(lastName)" }
}

@Model
class Aircraft {
    var registration: String = ""   // e.g. "N122DR"
    var type: String = ""           // e.g. "S22T"
    var owner: String?
    var ownerAddress: String?       // responsible person address (GAR)
    var isAirplane: Bool = true     // vs helicopter
    var usualBase: String?          // ICAO code
}

@Model
class Flight {
    var departureDate: Date = .now
    var departureTimeUTC: String = ""   // "08:00"
    var arrivalDate: Date = .now
    var arrivalTimeUTC: String = ""     // "09:00"
    var originICAO: String = ""
    var destinationICAO: String = ""
    var nature: String = "private"
    var observations: String?
    var contact: String?

    var aircraft: Aircraft?
    var crew: [Person] = []
    var passengers: [Person] = []

    // Trip relationship
    var trip: Trip?
    var legOrder: Int = 0               // position within trip
}

@Model
class Trip {
    var name: String = ""               // e.g. "September France trip"
    var createdAt: Date = .now
    var legs: [Flight] = []             // ordered by legOrder
    var extraFields: [String: String]?  // e.g. {"reason_for_visit": "Tourism"}
}
```

**App UI flow:**
1. **People tab** — list/add/edit people with passport details
2. **Aircraft tab** — list/add/edit aircraft
3. **Flights tab** — create individual flights or multi-leg trips. Pick dates, airports, aircraft, then select crew & pax from saved people
4. **Generate** — tap a flight or trip → app calls the form API (one call per form) → receives filled forms → share sheet / email directly to airport
5. **Extra fields** — when generating forms for airports that require extra fields (fetched from `/airports/{icao}`), the app prompts for them dynamically

The app fetches `/airports` to know which airports have forms and `/airports/{icao}` to learn what extra fields each form needs. This allows the UI to adapt without app updates when new form requirements are added server-side.

## Implementation Plan

### Phase 1: API + CLI (get it working)
1. Build FastAPI server with `/generate` and `/validate` endpoints
2. Implement PDF AcroForm filler (LSGS + French customs + LFRD) with optional `?flatten=true`
3. Implement DOCX filler (LFQA) — fallback to PDF if too fragile
4. Implement XLSX filler (GAR)
5. Create field mapping JSONs for each airport (with version, timezone, default_observations)
6. Add `/airports` and `/airports/{icao}` discovery endpoints (names from airports.db / euro_aip)
7. Build CLI client with people CSV lookup (static API key auth)
8. Dev mode: SQLite, auth bypass, local HTTP — same pattern as flyfun-weather
9. Deploy to Digital Ocean: Docker + Caddy (forms.flyfun.aero), shared MySQL, volume-mount templates/mappings

### Phase 2: Auth + Multi-user
1. Add Google OAuth via authlib (same flow as flyfun-weather)
2. Add Apple OAuth via authlib (required for App Store — more complex, test thoroughly)
3. SQLAlchemy users + usage tables, Alembic migrations
4. JWT cookie sessions, API key fallback for CLI
5. Per-user rate limiting (in-memory + usage table for analytics)
6. Add `trip` command to CLI for multi-leg form generation (handles connecting flights, multiple forms per airport)
7. Collect/create fillable AcroForm templates for remaining airports (LFQB, EGJB, EIWT — manual Acrobat work)
8. Add extra_fields support to mappings and fillers

### Phase 3: iOS App
1. SwiftData models (Person, Aircraft, Flight, Trip) + CloudKit sync (prototype Person sync early to validate)
2. Sign in with Apple / Google integration (ASAuthorizationController + Google Sign-In SDK)
3. CRUD UI for people, aircraft
4. Flight and trip creation flow with airport picker (names from rzflight KnownAirports)
5. API integration for form generation (batch calls for trips — all forms per airport per leg)
6. Dynamic extra fields UI driven by `/airports/{icao}` response
7. Share sheet / Mail integration for sending forms to airports

### Deployment

Same workflow as flyfun-weather:
```bash
# First time
docker compose up -d --build
docker exec flightforms alembic upgrade head
cp deploy/forms.flyfun.aero.caddy /etc/caddy/sites-enabled/
caddy reload --config /etc/caddy/Caddyfile

# Updates
git pull && docker compose up -d --build
# If new migrations: docker exec flightforms alembic upgrade head
```

Port 8030 (avoids conflicts: 8000=maps, 8002=mcp, 8010=boarding, 8020=weather).

**Environment variables:**

| Variable | Required | Notes |
|----------|----------|-------|
| `ENVIRONMENT` | No (default: development) | `production` for Docker/MySQL |
| `DATABASE_URL` | Prod only | MySQL connection string |
| `JWT_SECRET` | Prod only | HS256 signing key |
| `GOOGLE_CLIENT_ID` | Prod only | Google OAuth |
| `GOOGLE_CLIENT_SECRET` | Prod only | Google OAuth |
| `APPLE_CLIENT_ID` | Prod only | Apple OAuth (Services ID) |
| `APPLE_TEAM_ID` | Prod only | Apple Developer Team ID |
| `APPLE_KEY_ID` | Prod only | Apple Sign-In private key ID |
| `APPLE_PRIVATE_KEY` | Prod only | Apple Sign-In private key (PEM) |
| `API_KEY` | No | Static key for CLI auth |
| `ADMIN_EMAILS` | Prod only | Comma-separated admin emails |

## Design Decisions

### Direction is derived, not explicit
A form is always generated in the context of a flight from origin to destination. The server determines direction by comparing the form airport to the flight's origin/destination. This eliminates a source of user error and keeps the API clean.

### Country-level fallback templates
Some forms are not airport-specific but country-wide. The mapping system supports both specific airport mappings and country-level fallbacks using ICAO prefixes:

- **`EG` (UK)** → GAR (XLSX)
- **`LF` (France)** → French customs "préavis douane" (PDF AcroForm, same as LFRG/LFAC/LFOH)
- **`LS` (Switzerland)** → could add a generic Swiss form later

When a request comes in for an airport, the resolver checks in order:
1. **Exact ICAO match** — e.g. LSGS has its own immigration form, LFQA has its own DOCX
2. **ICAO prefix match** — e.g. any `LF*` airport without a specific template gets the French customs form; any `EG*` airport gets the GAR

This means an unknown French airport like LFPB automatically gets the generic French customs form, and an unknown UK airport like EGLL automatically gets the GAR.

The mapping config uses `icao_prefix` for country-level templates and `icao` for specific ones:
```json
// gar.json — matches any EG* airport
{ "icao_prefix": "EG", "template": "gar_template.xlsx", "type": "xlsx", ... }

// french_customs.json — matches any LF* airport without a specific template
{ "icao_prefix": "LF", "template": "french_customs.pdf", "type": "pdf_acroform", ... }

// lsgs.json — exact match takes priority
{ "icao": "LSGS", "template": "lsgs_immigration.pdf", "type": "pdf_acroform", ... }

// lfqa.json — exact match takes priority over LF* fallback
{ "icao": "LFQA", "template": "lfqa_customs.docx", "type": "docx", ... }
```

### One API call = one form
The server generates exactly one form per `/generate` call. For multi-leg trips or round trips, the **client** makes multiple API calls — one per form needed. This keeps the server dead simple and stateless.

For multi-leg trips, the CLI `trip` command and the iOS app both handle the orchestration: iterating over legs, determining which airports need forms, linking connecting flights, and making the appropriate `/generate` calls.

### Connecting flights for combined forms
Some forms at intermediate airports have space for both the incoming and outgoing flight (e.g. arrival info + departure info on the same form). The optional `connecting_flight` field in the API request provides this data. The mapping config indicates whether a form uses connecting flight data via `has_connecting_flight`. Forms that don't need it simply ignore the field.

**Trip command logic:** For a trip like `EGTF>LFQA>LSGS>LFQA>EGTF`, the connecting flight at each intermediate stop is the immediately adjacent leg in the opposite direction. At LFQA outbound (arriving from EGTF), the connecting flight is the next leg (LFQA>LSGS). At LFQA return (arriving from LSGS), the connecting flight is the next leg (LFQA>EGTF). The CLI `trip` command and iOS app both handle this linking automatically when iterating over legs.

### Multiple forms per airport
An airport can have multiple forms (e.g. customs + immigration). Each form has its own template file and mapping config. The `/generate` endpoint takes a `form` ID to select which form to fill. When generating forms for a trip, the client must iterate over all forms for each airport at each leg — not just one per airport.

### One template per form
Each form has exactly one template (PDF, DOCX, or XLSX). No dual-format support, no conversion. The API returns the filled file in its native format: PDF templates return PDF, DOCX returns DOCX, XLSX returns XLSX. All formats are viewable natively on iOS/Mac and can be emailed directly to airports.

### Template versioning
Each mapping config includes a `version` field (e.g. `"1.0"`, `"6.7"`). This version is exposed via `/airports/{icao}` so clients can detect when a template has been updated (new fields, layout changes). The iOS app can cache form metadata and refresh when versions change, ensuring it always prompts for the right fields.

### Form-specific extra fields
Fields like `reason_for_visit` (GAR) are not part of the core data model — they're specific to certain forms or countries. Rather than bloating the core Flight/Person models, these are declared as `extra_fields` in the mapping config and exposed via `/airports/{icao}`. The client UI adapts dynamically: only showing these fields when generating forms that require them. The API request passes them in a generic `extra_fields` dict.

### Timezone-aware time handling
The API always accepts times in UTC. Each mapping config declares whether the form expects UTC or local time:
- `"time_reference": "utc"` — times used as-is
- `"time_reference": "local"` + `"time_zone": "Europe/Zurich"` — filler converts UTC to local before filling

This keeps the API simple (always UTC) while handling forms that expect local time (some French customs forms use local time).

### Authentication: Sign in with Apple / Google
Same auth pattern as [flyfun-weather](~/Developer/public/flyfun-weather/main/designs/multi-user-deployment.md): authlib OAuth flow → JWT cookie. Google OAuth is identical to the existing flyfun-weather implementation. Apple OAuth is added for App Store compliance (Apple requires it when any third-party sign-in is offered).

The server maintains a **users table** (same schema pattern as flyfun-weather) with: UUID, provider, provider_sub, display name, approved flag. Auto-approved on signup; admin can revoke. A **usage table** logs each `/generate` call for rate limiting and analytics.

**Rate limiting** uses both in-memory sliding window counters (for enforcement) and the persistent usage table (for analytics — which airports/forms are most popular). The CLI uses a static API key; the server accepts both JWT cookies and Bearer API keys.

### Server is form-generation only
The server's primary responsibility is generating filled forms. The only persistent state is the users table (no PII, just provider IDs). It never sends emails, never stores form data or request bodies. All sending (email, AirDrop, share sheet), saving (to files, cloud storage), and exporting is entirely the client's responsibility. The `send_to` field in airport metadata is informational — the client uses it to pre-populate the email recipient, but the server never touches it.

### No offline form generation
The iOS app requires network connectivity to generate forms. There are no mature PDF/DOCX/XLSX form-filling libraries on iOS that match the Python ecosystem (pypdf, python-docx, openpyxl). This is an acceptable trade-off for a GA customs tool — you're planning flights with internet access, not filling forms in the cockpit.

### DOCX filler: try first, fallback to PDF
The python-docx filler (LFQA) appends runs and fills table cells. DOCX formatting can be fragile — fonts/styles may not be perfectly preserved. If this proves too complex or unreliable for a given template, the fallback is to recreate the form as a fillable AcroForm PDF and use the PDF filler instead.

### Apple OAuth deferred to Phase 2
Apple Sign-In is required for App Store compliance but adds significant complexity (JWT client secret generation, identity token only sent on first auth). Google OAuth alone is sufficient for Phase 1 (API + CLI). Apple OAuth is implemented in Phase 2 alongside multi-user support, before the iOS app goes to the App Store in Phase 3.

## Testing

**All test data must use clearly fake data.** Never use real names, passport numbers, or personal information in test fixtures, example payloads, or documentation samples. Use obviously fictional data (e.g. "Jane Doe", passport "XX0000000", DOB "2000-01-01").
