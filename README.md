# FlightForms

General aviation customs and immigration form generator. Enter your flight details, crew, and passengers — get back pre-filled official forms ready for submission.

## Overview

FlightForms has three components:

- **API server** (FastAPI) — form generation service that accepts flight data and returns filled forms, or a fill plan for an airport's own web form
- **iOS/macOS app** (SwiftUI) — manage crew, passengers, aircraft, and trips with CloudKit sync across devices
- **CLI** — batch form generation from the command line

PII is never stored server-side. Passenger and crew data exists only in memory during form generation; the server's database holds only user accounts and usage counts.

## Supported Forms

The set of forms grows continuously — `GET /airports` (or `flightforms airports`) returns the current list. They fall into a few kinds:

- **Airport-specific PDFs** — an airport's or authority's own customs/immigration form, e.g. LSGS (Sion) immigration, LFQA (CODT Metz) customs declaration, the French Préavis Douane
- **Upload files (XLSX)** — spreadsheets to upload to an online service, e.g. the UK General Aviation Report (GAR) or a MyHandling FBO request
- **Web forms** — airports that only take an online form (e.g. EGTF Fair Oaks out-of-hours and PPR): the app opens the airport's page and pre-fills it
- **Generic forms** — the General Declaration (GenDec) in several variants, available for any airport without a dedicated form

Forms are resolved per ICAO code: an exact airport match, then a list of airports, then a country prefix (e.g. `LF*`, `EG*`), then the generic defaults. Where the AIP publishes a customs e-mail address, it is used to prefill the submission e-mail.

Adding a form of an existing kind only needs a template file and a JSON mapping in `src/flightforms/templates/` and `src/flightforms/mappings/`.

## API

Base URL: `https://forms.flyfun.aero`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/airports` | GET | List airports with available forms |
| `/airports/{icao}` | GET | Form details for an airport (required fields, max crew/pax) |
| `/generate` | POST | Generate a filled form (returns the file) |
| `/prefill` | POST | Fill plan for an airport's web form |
| `/validate` | POST | Dry-run validation without generating |
| `/email-text` | POST | Localized email subject and body for a form |
| `/health` | GET | Health check |

`/generate`, `/prefill` and `/validate` require a signed-in user. Authentication (Google, Apple, magic link — `/auth/*`) and the Autorouter route import are provided by the shared [flyfun-common](https://github.com/roznet/flyfun-common) routers.

## Getting Started

### Prerequisites

- Python 3.11+
- (Optional) Docker for containerized deployment

### Local Development

```bash
cp .env.sample .env
# Edit .env: ENVIRONMENT=development for a local SQLite database,
# plus OAuth credentials and (optionally) AIRPORTS_DB for airport names

pip install -e .
uvicorn flightforms.api.app:create_app --factory --port 8030 --reload
```

### Docker

```bash
docker compose up --build
```

The service runs on port 8030 behind a Caddy reverse proxy in production.

### CLI

```bash
# List available airports and forms
flightforms airports

# Generate the forms for one airport (omit --form to get them all)
flightforms generate --airport LSGS --origin LFPB --destination LSGS \
  --departure-date 2026-03-15 --departure-time 14:30 \
  --arrival-date 2026-03-15 --arrival-time 15:45 \
  --aircraft HB-ABC --aircraft-type PA28 \
  --crew "Jane Pilot" --pax "John Doe" --people-file people.csv

# Generate forms for a multi-leg trip
flightforms trip --legs "LFPB>LSGS,LSGS>LFPB" \
  --dates 2026-03-15,2026-03-18 --times "14:30>15:45,10:00>11:15" \
  --aircraft HB-ABC --crew "Jane Pilot" --people-file people.csv

# Preview all forms with self-describing dummy data
flightforms preview --output-dir previews/
```

The CLI talks to the API (`--url`, default `http://127.0.0.1:8030`). Person details (passport, nationality, …) for the names passed to `--crew`/`--pax` come from `--people-file`.

### Tests

```bash
pytest tests/
```

CI builds and unit-tests the iOS app on every PR (`.github/workflows/ios.yml`); the XCUI journeys run nightly (`ios-ui-nightly.yml`).

### AIP customs e-mails

Customs e-mail addresses are extracted from the AIP into `src/flightforms/mappings/aip_customs_emails.lookup.json`. Re-run after each AIRAC update of the airports database, review, and commit:

```bash
python scripts/sync_aip_emails.py --db path/to/airports.db
```

## iOS/macOS App

The SwiftUI app lives in `app/flyfun-forms/` and requires:

- Xcode 26+, iOS 18.6+ / macOS 26+
- Dependencies: [RZUtils](https://github.com/roznet/rzutils), [RZFlight](https://github.com/roznet/rzflight), [flyfun-common](https://github.com/roznet/flyfun-common)

Features include passport MRZ scanning, multi-document support per person, timezone-aware time entry, CSV import for bulk data entry, flight import (pasted ICAO flight plan, FlyFun Weather, Autorouter), web-form prefill, and localisation in English, French, German and Spanish.

## Project Structure

```
src/flightforms/
├── api/                 # FastAPI endpoints and Pydantic models
├── db/                  # Usage tracking (users/auth via flyfun-common)
├── fillers/             # PDF, XLSX, DOCX and web-form fillers
├── templates/           # Blank form template files
├── mappings/            # JSON field mappings per airport/form, e-mail lookups
├── registry.py          # Loads mappings and resolves forms for an ICAO code
├── airport_resolver.py  # Airport names from the euro_aip database
├── validation.py        # Field validation
├── preview.py           # Dummy-data previews
└── cli.py               # Command-line interface

app/flyfun-forms/   # iOS/macOS SwiftUI application
designs/            # Design docs (start at designs/INDEX.md)
deploy/             # Caddy config for forms.flyfun.aero
scripts/            # AIP e-mail sync, App Store Connect tooling
tests/              # Unit and integration tests
```

## Architecture

The form system follows a **template + mapping + filler** pattern:

1. **Registry** loads all JSON mappings at startup and matches an ICAO code to its forms (exact match → airport list → country prefix → default)
2. **Filler** reads the template, maps canonical field names to template-specific fields, and writes the filled file — or, for web forms, returns a fill plan the app applies to the airport's page

Adding a new airport or country with an existing filler type requires only a template file and a JSON mapping; a new kind of form needs a new filler.

## Privacy

FlightForms is designed with privacy as a core principle: passport and passenger data lives
on your device and in your own iCloud, and reaches the server only in memory, for the one
request it takes to fill a form. See [PRIVACY.md](PRIVACY.md) for full details.

- [legal/GDPR.md](legal/GDPR.md) — the full GDPR compliance record, including open items
- [legal/PROCESSOR_TERMS.md](legal/PROCESSOR_TERMS.md) — Art. 28 data processing terms, for
  organisations whose passengers' data we handle on their behalf (*draft*)
- [SECURITY_AUDIT.md](SECURITY_AUDIT.md) — the standing security review

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
