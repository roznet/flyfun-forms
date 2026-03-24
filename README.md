# FlightForms

General aviation customs and immigration form generator. Enter your flight details, crew, and passengers — get back pre-filled official forms ready for submission.

## Overview

FlightForms has three components:

- **API server** (FastAPI) — stateless form generation service that accepts flight data and returns filled PDF, DOCX, or XLSX forms
- **iOS/macOS app** (SwiftUI) — manage crew, passengers, aircraft, and trips with CloudKit sync across devices
- **CLI** — batch form generation from the command line

PII is never stored server-side. Passenger and crew data exists only in memory during form generation.

## Supported Forms

| Region | Form | Format |
|--------|------|--------|
| LSGS (Sion, Switzerland) | Immigration | PDF |
| LF* (France) | Customs declaration (Préavis Douane) | PDF |
| LFQA + 10 airports (CODT Metz) | Customs declaration | PDF |
| EG* (United Kingdom) | General Aviation Report (GAR) | XLSX |
| 50+ European airports | MyHandling FBO Request | XLSX |
| All other airports | General Declaration (3 variants) | PDF |

New forms are added by dropping a template file and a JSON mapping into `src/flightforms/templates/` and `src/flightforms/mappings/` — no code changes required.

## API

Base URL: `https://forms.flyfun.aero`

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/airports` | GET | List airports with available forms |
| `/airports/{icao}` | GET | Form details for an airport (required fields, max crew/pax) |
| `/generate` | POST | Generate a filled form (returns the file) |
| `/validate` | POST | Dry-run validation without generating |
| `/email-text` | POST | Localized email subject and body for a form |
| `/health` | GET | Health check |

## Getting Started

### Prerequisites

- Python 3.11+
- (Optional) Docker for containerized deployment

### Local Development

```bash
cp .env.sample .env
# Edit .env with your settings (ENVIRONMENT=development for SQLite)

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

# Generate a single form
flightforms generate --origin LFPB --destination LSGS \
  --registration HB-ABC --aircraft-type PA28 \
  --crew crew.csv --passengers pax.csv \
  --date 2026-03-15 --time 14:30

# Generate forms for a multi-leg trip
flightforms trip --trip trip.json --people people.csv

# Preview all forms with self-describing dummy data
flightforms preview --output-dir previews/
```

## iOS/macOS App

The SwiftUI app lives in `app/flyfun-forms/` and requires:

- Xcode 15+, iOS 17+ / macOS 14+
- Dependencies: [RZUtils](https://github.com/roznet/rzutils), [RZFlight](https://github.com/roznet/rzflight)

Features include passport MRZ scanning, multi-document support per person, timezone-aware time entry, and CSV import for bulk data entry.

## Project Structure

```
src/flightforms/
├── api/            # FastAPI endpoints and Pydantic models
├── fillers/        # PDF, DOCX, XLSX form filler modules
├── templates/      # Blank form template files
├── mappings/       # JSON field mappings per airport/form
├── registry.py     # Discovers and loads form configurations
└── cli.py          # Command-line interface

app/flyfun-forms/   # iOS/macOS SwiftUI application
```

## Architecture

The form system follows a **template + mapping + filler** pattern:

1. **Registry** loads all JSON mappings at startup
2. **Resolver** matches an ICAO code to available forms (exact match → prefix match → default)
3. **Filler** reads the template, maps canonical field names to template-specific fields, and writes the filled file

This makes the system extensible — adding a new airport or country requires only a template file and a JSON mapping.

## Privacy

FlightForms is designed with privacy as a core principle. See [PRIVACY.md](PRIVACY.md) for full details.

## License

This project is licensed under the MIT License — see [LICENSE](LICENSE) for details.
