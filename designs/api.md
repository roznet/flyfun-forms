# API

> FastAPI backend for generating customs/immigration forms — stateless, PII-transient

## Intent

Central form-generation service that multiple clients (iOS app, CLI) call. Receives flight + people data, returns a filled form file, discards all PII immediately. Same infrastructure pattern as flyfun-weather: FastAPI + Docker + Caddy on the shared DigitalOcean droplet.

**Privacy principle:** PII is never stored server-side. No request body logging. The only persistence is usage metrics (which airport, which form, when).

## Architecture

```
src/flightforms/
├── api/
│   ├── app.py          # FastAPI factory, lifespan, router mounting
│   ├── generate.py     # POST /generate — fills and returns form file
│   ├── validate.py     # POST /validate — dry-run validation
│   ├── airports.py     # GET /airports, GET /airports/{icao}
│   ├── email_text.py   # POST /email-text — localized email subject/body
│   └── models.py       # Pydantic request/response schemas (with date/time/ICAO validation)
├── db/
│   ├── models.py       # Usage table (app-specific)
│   ├── engine.py       # Shim → flyfun-common.db
│   └── deps.py         # Shim → flyfun-common.db deps
├── registry.py         # MappingRegistry: discovers form configs
├── airport_resolver.py # ICAO → airport name/country (via rzflight)
├── validation.py       # Shared validation logic
├── cli.py              # CLI client
└── manage.py           # Admin commands (create-token, list-tokens)
```

### Auth

Uses [flyfun-common auth](../../flyfun-common/designs/auth.md):
- **Browser/iOS:** Google/Apple OAuth → JWT cookie on `.flyfun.aero` (SSO with flyfun-weather)
- **iOS native:** `ASWebAuthenticationSession` → server redirects to `flyfunforms://auth/callback?token=<JWT>`
- **CLI:** API token (`ff_<random>`, SHA256-hashed in DB) via `Authorization: Bearer` header
- **Dev mode:** `ENVIRONMENT=development` bypasses auth, uses SQLite

Auth priority: dev-mode → cookie JWT → Bearer JWT → Bearer API token (`ff_` prefix) → 401.

See [flyfun-common auth design](link) for full OAuth flow details.

### Database

Shared MySQL (prod) / SQLite (dev) with flyfun-common:
- **Shared tables:** `users`, `api_tokens` (from flyfun-common)
- **App-specific:** `usage` table (user_id, endpoint, airport_icao, form_id, timestamp)

## Endpoints

### `GET /airports`
Returns all airports with available forms, grouped by exact ICAO match, prefix fallback, and default forms (catch-all for unmatched airports).

### `GET /airports/{icao}`
Returns form details for a specific airport: required fields, extra fields, max crew/pax, version, send_to email. Falls back to default forms (e.g., ICAO GenDec) for airports without specific mappings.

### `POST /generate`
Accepts `GenerateRequest`, returns binary file (PDF/DOCX/XLSX).
- `?flatten=true` flattens editable PDF fields (for sharing/printing)
- **Direction derived automatically:** form airport == destination → arrival; form airport == origin → departure
- **Connecting flight:** optional, for forms at intermediate stops that reference both arrival and departure

### `POST /email-text`
Returns localized email subject and body text for a form submission. Used by the iOS app to pre-populate the mail composer. Returns both English and local-language versions (based on the airport's country). Templates are defined per-language in `registry.py` (DEFAULT_EMAIL_TEMPLATES) and can be overridden per-mapping.

### `POST /validate`
Same body as `/generate`, returns validation errors without generating. Each `ValidationError` includes `field`, `error`, and optional `value` (the submitted value that failed). The 422 response body is `{"detail": [ValidationError, ...]}` — the iOS app parses this into structured UI.

### `DELETE /auth/account`
Deletes the authenticated user's account and all associated data (usage records, API tokens, user record). Returns 204 No Content on success. Used by the iOS app's Settings screen for Apple App Store guideline 5.1.1(v) compliance.

### `GET /health`
Returns `{"status": "ok"}`.

## Usage Examples

```python
# GenerateRequest body
{
    "airport": "LSGS",
    "form": "immigration",
    "flight": {
        "origin": "LFPG", "destination": "LSGS",
        "departure_date": "2024-03-15", "departure_time_utc": "10:00",
        "arrival_date": "2024-03-15", "arrival_time_utc": "11:30",
        "nature": "Private"
    },
    "aircraft": {"registration": "N122DR", "type": "S22T", "owner": "..."},
    "crew": [{"first_name": "John", "last_name": "Doe", "dob": "1980-01-01", ...}],
    "passengers": [...]
}
```

```python
# App startup (lifespan)
from flyfun_common.db import init_shared_db
from flightforms.db.models import AppBase
init_shared_db()
AppBase.metadata.create_all(get_engine())
```

## Key Choices

- **Stateless form generation:** No server-side storage of flight/people data. Each request is self-contained. This simplifies GDPR compliance and means the server can't leak PII.
- **Direction derived, not specified:** Avoids user confusion and errors. The server compares the form's airport against origin/destination.
- **Multiple forms per airport:** An airport can have customs + immigration. Each is a separate form ID.
- **Exact match over prefix match:** LFQA uses its specific PDF form; other LF* airports fall back to the generic French customs PDF.
- **Localized email templates:** `POST /email-text` returns subject/body in English + local language (fr/de/es/it/nl/pt based on airport country). iOS app lets user choose language preference.
- **Input validation at boundary:** Date (`YYYY-MM-DD`), time (`HH:MM`), and ICAO format validated by Pydantic validators on request models — malformed values return 422 instead of causing 500s in fillers.
- **JWT secret fail-fast:** Production JWT secret check runs in `create_app()` before middleware setup, not in async lifespan.

## Deployment

- **URL:** `forms.flyfun.aero` (port 8030)
- **Stack:** Docker (python:3.13-slim) + Caddy reverse proxy + shared MySQL
- **Docker network:** `shared-services` (same as flyfun-weather)
- **Config:** See `.env.sample` for required env vars

## Gotchas

- `SessionMiddleware` required for OAuth state (added in `app.py`)
- Airport names resolved via `rzflight` euro-aip library — requires airport DB
- PDF flattening uses pypdf and removes form field editability
- XLSX formulas (crew/pax counts) are preserved — openpyxl doesn't recalculate them but Excel does on open

## References

- [flyfun-common auth](../../flyfun-common/designs/auth.md) — OAuth, JWT, SSO
- [flyfun-common db](../../flyfun-common/designs/db.md) — UserRow, ApiTokenRow, shared DB
- [Form system](./form-system.md) — template/mapping/filler architecture
- [iOS app](./ios-app.md) — native client
