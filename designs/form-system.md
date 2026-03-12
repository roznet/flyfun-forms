# Form System

> Template + JSON mapping + pluggable filler architecture for generating airport-specific customs/immigration forms

## Intent

Enable adding new airport forms **without code changes** — just drop a template file + JSON mapping and redeploy. The mapping system decouples the canonical data model from each form's specific field names, layouts, and formats.

## Architecture

```
src/flightforms/
├── registry.py              # MappingRegistry: discovers and loads configs
├── fillers/
│   ├── pdf_filler.py        # pypdf AcroForm field filling
│   ├── french_customs_filler.py  # French customs PDF (special layout)
│   ├── docx_filler.py       # python-docx template filling
│   └── xlsx_filler.py       # openpyxl cell filling
├── templates/               # Form template files (PDF/DOCX/XLSX)
│   ├── lsgs_immigration.pdf
│   ├── french_customs.pdf
│   ├── gendec_icao.pdf
│   ├── lfqa_customs.docx
│   └── gar_template.xlsx
└── mappings/                # JSON mapping configs
    ├── lsgs.json
    ├── french_customs.json
    ├── gendec_icao.json
    ├── lfqa.json
    └── gar.json
```

### How It Works

1. **Discovery:** `MappingRegistry` scans `mappings/` at startup, builds ICAO → form config index
2. **Resolution:** Request comes in with airport ICAO → exact match first, then prefix match (e.g., `LFOH` → `LF*` → `french_customs.json`), then default fallback (`"default": true` mappings for airports with no specific form)
3. **Filling:** `generate.py` selects the right filler based on `type` in mapping (`pdf_acroform`, `pdf_acroform_french`, `docx`, `xlsx`)
4. **Output:** Filler reads template, maps canonical fields → template fields using the mapping, writes filled file

### JSON Mapping Structure

Scope is set by exactly one of `icao`, `icao_prefix`, or `default`:

```json
{
    "icao": "LSGS",              // exact airport match
    "icao_prefix": "LF",         // OR country/region prefix match
    "default": true,             // OR catch-all fallback for unmatched airports
    "label": "Immigration Information",
    "template": "lsgs_immigration.pdf",
    "type": "pdf_acroform",      // filler type
    "version": "1.0",
    "time_reference": "utc",     // "utc" or "local"
    "time_zone": "Europe/Zurich", // for local time conversion (only if time_reference=local)
    "date_format": "%d/%m/%Y",
    "checkbox_on": "/Yes",       // PDF checkbox on value (form-dependent)
    "checkbox_off": "/Off",
    "max_crew": 8,
    "max_passengers": 20,
    "has_connecting_flight": false,
    "default_observations": "Nothing to declare",
    "send_to": "email@example.com",
    "required_fields": {         // arrays of required field names per section
        "flight": ["origin", "destination", "departure_date"],
        "aircraft": ["registration"],
        "crew": ["first_name", "last_name"],
        "passengers": []
    },
    "extra_fields": [],
    "field_map": {               // canonical name → template field name
        "aircraft.registration": "Text7",
        "flight.departure_date": "Text1",
        "crew[{i}].last_name": "LAST NAMERow{n}",
        "crew[{i}].full_name": "NAMES OF CREWRow{n}"
    }
}
```

### Fillers

| Type key | Filler | Library | Notes |
|----------|--------|---------|-------|
| `pdf_acroform` | `pdf_filler.py` | pypdf | Generic AcroForm filling. Supports `full_name`, routing, direction, nature checkboxes |
| `pdf_acroform_french` | `french_customs_filler.py` | pypdf | French customs-specific: combined crew/pax list, UTC→local time, role dropdowns |
| `docx` | `docx_filler.py` | python-docx | Fills table cells, auto-adds rows |
| `xlsx` | `xlsx_filler.py` | openpyxl | Fills specific cells; preserves formulas |

### Canonical Field Names

Used in `field_map` to map data to template fields. The PDF filler (`pdf_filler.py`) builds a values dict with these keys:

**Flight/aircraft:** `flight.origin`, `flight.destination`, `flight.departure_date`, `flight.arrival_date`, `flight.departure_time_utc`, `flight.arrival_time_utc`, `flight.remote`, `flight.nature`, `flight.contact`, `flight.observations`, `aircraft.registration`, `aircraft.type`, `aircraft.owner`, `aircraft.owner_address`, `aircraft.usual_base`

**Derived:** `origin.country`, `destination.country`, `remote.country`, `airport.name`, `passengers.count`, `passengers.embarking`, `passengers.disembarking`, `routing.departure_place`, `routing.arrival_place`

**Checkboxes:** `direction.inbound`, `direction.outbound`, `flight.nature.<value>` (e.g., `flight.nature.private`), `aircraft.airplane`, `aircraft.helicopter`

**Person arrays** (use `{i}` for 0-based, `{n}` for 1-based index): `crew[{i}].full_name`, `crew[{i}].first_name`, `crew[{i}].last_name`, `crew[{i}].function`, `crew[{i}].dob`, `crew[{i}].nationality`, `crew[{i}].id_number`, `crew[{i}].id_type`, `crew[{i}].id_issuing_country`, `crew[{i}].id_expiry`, `crew[{i}].sex`, `crew[{i}].place_of_birth` (same for `passengers[{i}]`)

**Extra/connecting:** `extra.<key>`, `connecting.origin`, `connecting.destination`, etc.

### Direction Derivation

Direction is **never specified by the user** — it's derived:
- Form airport == flight destination → **arrival** (inbound)
- Form airport == flight origin → **departure** (outbound)
- Connecting flight → both directions shown (for intermediate stops)

The filler also computes `flight.remote` (the airport at the other end) and `remote.country`. Use these in field_map when the form's FROM/TO field should show the remote airport, not origin/destination (e.g., LSGS immigration uses `flight.remote` for the ICAO column).

### PDF Flattening

When `?flatten=true`, the PDF filler uses pypdf's built-in flatten parameter on `update_page_form_field_values(page, updates, flatten=True)` to bake appearance streams into page content, then calls `writer.remove_annotations(subtypes="/Widget")` to strip interactive form widgets. Do NOT just delete `/Annots` — that removes the visual content too.

## Usage Examples

```python
# Registry discovers all available forms
registry = MappingRegistry("src/flightforms/mappings", "src/flightforms/templates")
forms = registry.get_forms_for_airport("LSGS")  # → [FormMapping(id="lsgs", ...)]
forms = registry.get_forms_for_airport("EDDF")  # → [FormMapping(id="gendec_icao", ...)] (default)

# Get a specific form mapping
mapping = registry.get_form("LSGS", "lsgs")
template_path = registry.get_template_path(mapping)

# Filling is dispatched in generate.py based on mapping.filler_type
from flightforms.fillers.pdf_filler import fill_pdf
filled_bytes = fill_pdf(template_path, mapping, request, airport_resolver)
```

```json
// Adding a new airport: just create mappings/newairport.json + template
{
    "icao": "LSZB",
    "label": "Immigration Form",
    "template": "lszb_immigration.pdf",
    "type": "pdf_acroform",
    "version": "1.0",
    "field_map": { "aircraft.registration": "Reg", "crew[{i}].last_name": "NameRow{n}" }
}
```

## Current Form Inventory

| Mapping ID | Scope | Format | Label |
|------------|-------|--------|-------|
| `lsgs` | LSGS (Sion, CH) | PDF AcroForm | Immigration Information |
| `french_customs` | LF* (France) | PDF AcroForm (french) | Préavis Douane |
| `lfqa` | LFQA (Reims) | DOCX | Customs Declaration |
| `gar` | EG* (UK) | XLSX | General Aviation Report |
| `gendec_icao` | Default (all others) | PDF AcroForm | ICAO General Declaration |

## Key Choices

- **JSON mappings, not code:** New forms don't require Python changes — just template + JSON. This is the core extensibility mechanism.
- **Three-tier resolution:** Exact ICAO match → prefix match → default fallback. Covers specific airports, country-level forms, and a universal ICAO GenDec for everything else.
- **Separate fillers per format:** PDF, DOCX, XLSX have fundamentally different filling mechanics. No shared abstraction forced.
- **Templates bundled in Docker image:** Templates ship with the code. No external template storage needed.

## Gotchas

- **Flat PDFs can't be filled:** The filler needs AcroForm fields to target. Non-fillable PDFs must be recreated in Adobe Acrobat with form fields.
- **XLSX formulas:** openpyxl preserves but doesn't recalculate `COUNTA()` formulas. They update when opened in Excel.
- **XLSX header_map targets value cells, not label cells:** In templates like GAR, labels are in columns A/C/E/G and values go in the adjacent columns B/D/F/H. The `header_map` must reference the **value** cells (e.g., `B3` not `A3`).
- **Timezone handling:** Some forms want local time, others UTC. The mapping's `time_zone` + `time_reference` fields control conversion. If `time_reference` is `"utc"` (default), times stay UTC.
- **Field naming conventions:** Canonical names use dot notation (`aircraft.registration`, `crew[{i}].last_name`). Array patterns use `{i}` (0-based) and `{n}` (1-based) for PDF field name resolution.

## References

- [API](./api.md) — endpoint that drives form generation
- Brainstorm: `designs/flight_forms_brainstorm.md` — detailed GAR XLSX cell layout, template inventory
