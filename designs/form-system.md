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
│   ├── lfqa_customs.docx
│   └── gar_template.xlsx
└── mappings/                # JSON mapping configs
    ├── lsgs.json
    ├── french_customs.json
    ├── lfqa.json
    └── gar.json
```

### How It Works

1. **Discovery:** `MappingRegistry` scans `mappings/` at startup, builds ICAO → form config index
2. **Resolution:** Request comes in with airport ICAO → exact match checked first, then prefix match (e.g., `LFOH` → `LF*` → `french_customs.json`)
3. **Filling:** Registry selects the right filler based on `type` in mapping (`pdf_acroform`, `docx`, `xlsx`)
4. **Output:** Filler reads template, maps canonical fields → template fields using the mapping, writes filled file

### JSON Mapping Structure

```json
{
    "airport": "LSGS",           // or prefix like "LF" for country-level
    "form": "immigration",       // form ID (unique per airport)
    "template": "lsgs_immigration.pdf",
    "type": "pdf_acroform",      // filler type
    "version": "1.0",
    "timezone": "Europe/Zurich", // for local time conversion (null = UTC)
    "required_fields": {
        "flight": true, "aircraft": true,
        "crew": true, "passengers": true
    },
    "extra_fields": {            // form-specific fields beyond core model
        "reason_for_visit": {"type": "string", "default": "Tourism"}
    },
    "max_crew": 8,
    "max_passengers": 20,
    "field_map": {               // canonical name → template field name
        "aircraft_registration": "Registration",
        "crew_0_last_name": "Crew1Surname",
        "departure_date": "DepDate"
    },
    "checkbox_values": {"on": "Yes", "off": "No"},
    "default_observations": "Nothing to declare"
}
```

### Fillers

| Filler | Library | Input | Notes |
|--------|---------|-------|-------|
| `pdf_acroform` | pypdf | PDF with AcroForm fields | Generic; fills named fields. `?flatten=true` removes editability |
| `french_customs` | pypdf | French customs PDF | Subclass of PDF filler with layout-specific handling |
| `docx` | python-docx | DOCX with placeholders | Appends runs, fills table cells |
| `xlsx` | openpyxl | XLSX with named cells | Fills specific cells; preserves formulas |

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
registry = MappingRegistry()
forms = registry.get_forms("LSGS")  # → [{"form": "immigration", ...}]

# Generate a filled form
filler = registry.get_filler("LSGS", "immigration")
filled_bytes = filler.fill(flight_data, aircraft_data, crew, passengers)
```

```json
// Adding a new airport: just create mappings/newairport.json
{
    "airport": "LSZB",
    "form": "immigration",
    "template": "lszb_immigration.pdf",
    "type": "pdf_acroform",
    "version": "1.0",
    "field_map": { "aircraft_registration": "Reg", ... }
}
```

## Current Form Inventory

| Airport(s) | Format | Type | Status |
|------------|--------|------|--------|
| LSGS (Sion, CH) | PDF AcroForm | immigration | Ready |
| LF* (France generic) | PDF AcroForm | customs | Ready |
| LFRD (Dinard) | PDF AcroForm | customs | Ready (different layout) |
| LFQA (Reims) | DOCX | customs | Ready |
| EG* (UK) | XLSX | gar | Ready |
| LFQB, EGJB, EIWT | PDF | — | Not ready (need fillable AcroForm) |

## Key Choices

- **JSON mappings, not code:** New forms don't require Python changes — just template + JSON. This is the core extensibility mechanism.
- **Prefix matching:** Country-level forms (LF* for France, EG* for UK) avoid duplicating configs per airport. Exact match always wins.
- **Separate fillers per format:** PDF, DOCX, XLSX have fundamentally different filling mechanics. No shared abstraction forced.
- **Templates bundled in Docker image:** Templates ship with the code. No external template storage needed.

## Gotchas

- **Flat PDFs can't be filled:** The filler needs AcroForm fields to target. Non-fillable PDFs must be recreated in Adobe Acrobat with form fields.
- **XLSX formulas:** openpyxl preserves but doesn't recalculate `COUNTA()` formulas. They update when opened in Excel.
- **XLSX header_map targets value cells, not label cells:** In templates like GAR, labels are in columns A/C/E/G and values go in the adjacent columns B/D/F/H. The `header_map` must reference the **value** cells (e.g., `B3` not `A3`).
- **Timezone handling:** Some forms want local time, others UTC. The mapping's `timezone` field controls conversion. If null, times stay UTC.
- **Field naming conventions:** Crew/passenger fields use indexed names like `crew_0_last_name`, `pax_2_dob`. The index maps to position in the form.

## References

- [API](./api.md) — endpoint that drives form generation
- Brainstorm: `designs/flight_forms_brainstorm.md` — detailed GAR XLSX cell layout, template inventory
