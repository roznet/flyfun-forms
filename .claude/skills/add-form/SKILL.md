---
name: add-form
description: Add a new form template from a PDF file and create its field mapping
---

# Add a new form template from a PDF

This skill takes a PDF file path and creates a new form template with its field mapping in the flightforms system.

## Arguments

The user should provide:
- **PDF file path** (required) — path to the source PDF template
- **Scope** (required) — one of:
  - A specific ICAO code (e.g., `LSGS`) for a single airport
  - An ICAO prefix (e.g., `ED`) for a country/region
  - `default` for a catch-all fallback form
- **Label** (required) — human-readable form name (e.g., "Immigration Information", "ICAO General Declaration")

If any of these are missing, ask the user before proceeding.

## Step 1 — Inspect the PDF for form fields

Run a Python script to extract all AcroForm fields from the PDF:

```python
python3 -c "
from pypdf import PdfReader
r = PdfReader('<pdf_path>')
fields = r.get_fields()
if not fields:
    print('ERROR: No form fields found in this PDF')
else:
    for name, field in sorted(fields.items()):
        ft = field.get('/FT', 'unknown')
        print(f'{name}: type={ft}')
"
```

If no fields are found, tell the user the PDF has no fillable AcroForm fields and stop.

Show the user the list of fields and propose a mapping.

## Step 2 — Design the field mapping

Map PDF fields to canonical names using these conventions. Not all fields need to be mapped — only map what makes sense for the form.

### Flight/aircraft fields (simple values)

| Canonical name | Description |
|---|---|
| `flight.origin` | Origin ICAO code |
| `flight.destination` | Destination ICAO code |
| `flight.departure_date` | Departure date (formatted per `date_format`) |
| `flight.arrival_date` | Arrival date |
| `flight.departure_time_utc` | Departure time in UTC |
| `flight.arrival_time_utc` | Arrival time in UTC |
| `flight.remote` | The "other" airport (opposite of `airport` in request) |
| `flight.nature` | Flight nature as text (private, business, etc.) |
| `flight.contact` | Contact info |
| `flight.observations` | Observations/remarks |
| `aircraft.registration` | Aircraft registration |
| `aircraft.type` | Aircraft type |
| `aircraft.owner` | Aircraft owner/operator |
| `aircraft.owner_address` | Owner address |
| `aircraft.usual_base` | Usual base airport |
| `origin.country` | Country of origin airport |
| `destination.country` | Country of destination airport |
| `remote.country` | Country of the remote airport |
| `passengers.count` | Number of passengers (as string) |
| `passengers.embarking` | Number of passengers embarking |
| `passengers.disembarking` | Number of passengers disembarking |
| `routing.departure_place` | Resolved name of origin airport |
| `routing.arrival_place` | Resolved name of destination airport |
| `airport.name` | Resolved name of the form's target airport |

### Direction checkboxes

| Canonical name | Description |
|---|---|
| `direction.inbound` | Checked when airport is destination |
| `direction.outbound` | Checked when airport is origin |

### Nature enum checkboxes

Use `flight.nature.<value>` where `<value>` matches the nature string:
- `flight.nature.private`
- `flight.nature.business`
- `flight.nature.fret`
- `flight.nature.other`

### Aircraft type checkboxes

| Canonical name | Description |
|---|---|
| `aircraft.airplane` | Checked if airplane |
| `aircraft.helicopter` | Checked if helicopter |

### Person array fields (crew and passengers)

Use `{i}` for 0-based index and `{n}` for 1-based index in the PDF field pattern:

| Canonical pattern | Description |
|---|---|
| `crew[{i}].full_name` | Full name ("LastName FirstName") |
| `crew[{i}].first_name` | First name |
| `crew[{i}].last_name` | Last name |
| `crew[{i}].function` | Role (Pilot, Crew) |
| `crew[{i}].dob` | Date of birth |
| `crew[{i}].nationality` | Nationality |
| `crew[{i}].id_number` | ID/passport number |
| `crew[{i}].id_type` | ID type (Passport, Identity card) |
| `crew[{i}].id_issuing_country` | ID issuing country |
| `crew[{i}].id_expiry` | ID expiry date |
| `crew[{i}].sex` | Sex |
| `crew[{i}].place_of_birth` | Place of birth |

Same patterns apply with `passengers[{i}]` prefix.

### Extra fields and connecting flights

| Canonical name | Description |
|---|---|
| `extra.<key>` | Value from extra_fields in the request |
| `connecting.origin` | Connecting flight origin |
| `connecting.destination` | Connecting flight destination |
| `connecting.departure_date` | Connecting flight departure date |
| `connecting.departure_time_utc` | Connecting flight departure time |
| `connecting.arrival_date` | Connecting flight arrival date |
| `connecting.arrival_time_utc` | Connecting flight arrival time |

### Filler types

- `pdf_acroform` — standard PDF AcroForm filler (most common, used for LSGS, ICAO GenDec)
- `pdf_acroform_french` — French customs-specific filler with combined crew/pax list and local time conversion
- `xlsx` — Excel filler (used for GAR)
- `docx` — Word document filler (used for LFQA)

For new PDF templates, use `pdf_acroform` unless there's a special reason not to.

## Step 3 — Confirm the mapping with the user

Present the proposed mapping as a JSON structure and ask the user to confirm or adjust before writing files. Include:
- Which PDF fields map to which canonical names
- The scope (icao, icao_prefix, or default)
- Required fields
- max_crew / max_passengers (based on available array slots in the PDF)
- date_format, time_reference, and other config

## Step 4 — Copy the template and create the mapping

1. Copy the PDF to `src/flightforms/templates/<form_id>.pdf`
2. Create the mapping JSON at `src/flightforms/mappings/<form_id>.json`

The mapping JSON structure:

```json
{
  "icao": "XXXX",           // for exact airport match (omit if using prefix or default)
  "icao_prefix": "XX",      // for country/region match (omit if using icao or default)
  "default": true,           // for catch-all fallback (omit if using icao or prefix)
  "label": "Form Label",
  "template": "<form_id>.pdf",
  "type": "pdf_acroform",
  "version": "1.0",
  "time_reference": "utc",
  "max_crew": 4,
  "max_passengers": 8,
  "date_format": "%d/%m/%Y",
  "has_connecting_flight": false,
  "extra_fields": [],
  "required_fields": {
    "flight": ["origin", "destination", "departure_date"],
    "aircraft": ["registration"],
    "crew": ["first_name", "last_name"],
    "passengers": []
  },
  "field_map": {
    "canonical.name": "PDF Field Name"
  }
}
```

Only include `icao`, `icao_prefix`, OR `default` — never more than one.

## Step 5 — Verify with a test generation

Run a quick Python test to verify the form can be generated:

```python
python3 -c "
from flightforms.registry import MappingRegistry
from flightforms.fillers.pdf_filler import fill_pdf
from flightforms.api.models import GenerateRequest
from pypdf import PdfReader
from io import BytesIO

reg = MappingRegistry('src/flightforms/mappings', 'src/flightforms/templates')

class StubResolver:
    def get_country(self, icao): return 'XX'
    def get_name(self, icao): return icao

req = GenerateRequest(
    airport='<target_icao>',
    form='<form_id>',
    flight={'origin': 'AAAA', 'destination': '<target_icao>',
            'departure_date': '2026-01-15', 'departure_time_utc': '10:00',
            'arrival_date': '2026-01-15', 'arrival_time_utc': '11:30',
            'nature': 'private'},
    aircraft={'registration': 'F-TEST', 'type': 'PA28', 'owner': 'Test Owner'},
    crew=[{'first_name': 'John', 'last_name': 'Doe'}],
    passengers=[{'first_name': 'Jane', 'last_name': 'Smith'}],
)

mapping = reg.get_form('<target_icao>', '<form_id>')
result = fill_pdf(reg.get_template_path(mapping), mapping, req, StubResolver())
print(f'Generated PDF: {len(result)} bytes')

reader = PdfReader(BytesIO(result))
fields = reader.get_fields()
for name, field in sorted(fields.items()):
    val = field.get('/V')
    if val:
        print(f'  {name}: {val}')
"
```

Show the user which fields were filled and their values.

## Step 6 — Run tests

Run the existing test suite to make sure nothing is broken:

```bash
python3 -m pytest tests/ -x -q -k "not flatten"
```

If any tests fail due to the new default/prefix mapping changing behavior (e.g., previously-unknown airports now returning forms), update the tests accordingly.

## Step 7 — Report

Tell the user:
- The template was added at `src/flightforms/templates/<form_id>.pdf`
- The mapping was created at `src/flightforms/mappings/<form_id>.json`
- Which airports/prefixes it applies to
- Remind them to run `/deploy` when ready to push to production
