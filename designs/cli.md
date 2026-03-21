# CLI

> Command-line client for batch form generation from local CSV files

## Intent

Provide a local, scriptable way to generate customs forms without the iOS app. Aimed at pilots who prefer managing crew/passenger data in spreadsheets and generating forms from the command line or scripts.

## Architecture

Single file: `src/flightforms/cli.py` using stdlib only (urllib, csv, argparse).

### Commands

- **`generate`** — Generate a single form for one flight
- **`trip`** — Generate all applicable forms for a multi-leg trip
- **`airports`** — List available airports/forms or show details for a specific ICAO
- **`preview`** — Generate all forms with self-describing dummy data for visual verification (runs locally, no API server needed)

### Auth

Uses API tokens (not OAuth):
1. Admin creates token: `python -m flightforms.manage create-token --email user@example.com`
2. Token (`ff_<random>`) provided via `--api-key` flag or `FLIGHTFORMS_API_KEY` env var
3. Sent as `Authorization: Bearer ff_<token>`

### Data Input

- **People:** CSV file with columns matching PersonData fields
- **Aircraft:** CLI flags (`--registration`, `--type`, `--owner`, etc.)
- **Flight:** CLI flags (`--origin`, `--destination`, `--date`, `--time`, etc.)

## Usage Examples

```bash
# Generate a single form
python -m flightforms.cli generate \
    --api-url https://forms.flyfun.aero \
    --api-key ff_abc123 \
    --airport LSGS --form immigration \
    --origin LFPG --destination LSGS \
    --date 2024-03-15 --time 10:00 \
    --registration N122DR --type S22T --owner "John Doe" \
    --crew crew.csv --passengers pax.csv \
    -o filled_form.pdf

# List available airports
python -m flightforms.cli airports --api-url https://forms.flyfun.aero

# Trip mode: generate all forms for all legs
python -m flightforms.cli trip \
    --api-url https://forms.flyfun.aero \
    --api-key ff_abc123 \
    --legs LFPG,LSGS,EGTF \
    --crew crew.csv --passengers pax.csv \
    --registration N122DR --type S22T --owner "John Doe"
```

## Key Choices

- **Stdlib only:** No external HTTP library. Uses urllib for simplicity and zero dependencies.
- **CSV for people data:** Simple, universal format. Easy to maintain in any spreadsheet app.
- **API tokens, not OAuth:** CLI doesn't need a browser. Admin provisions tokens offline.

## References

- [API](./api.md) — endpoints the CLI calls
- `src/flightforms/manage.py` — token management commands
