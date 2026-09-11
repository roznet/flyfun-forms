# Form System

> Template + JSON mapping + pluggable filler architecture for generating airport-specific customs/immigration forms

## Intent

Enable adding new airport forms **without code changes** — just drop a template file + JSON mapping and redeploy. The mapping system decouples the canonical data model from each form's specific field names, layouts, and formats.

## Architecture

```
src/flightforms/
├── registry.py              # MappingRegistry: discovers and loads configs
├── preview.py               # Dummy data builder + field extractors for testing
├── fillers/
│   ├── pdf_filler.py        # pypdf AcroForm field filling
│   ├── french_customs_filler.py  # French customs PDF (special layout)
│   ├── docx_filler.py       # python-docx template filling
│   ├── xlsx_filler.py       # openpyxl cell filling
│   ├── web_form.py          # Fill plans for official web forms (no file)
│   └── _datetime.py         # Shared UTC→local date/time conversion
├── templates/               # Form template files (PDF/DOCX/XLSX)
│   ├── lsgs_immigration.pdf
│   ├── french_customs.pdf
│   ├── gendec_icao.pdf
│   ├── gendec_form.pdf
│   ├── lfqa_customs_form.pdf
│   ├── lfrm_customs.pdf
│   ├── gar_template.xlsx
│   └── myhandling_request.xlsx
└── mappings/                # JSON mapping configs
    ├── lsgs.json
    ├── french_customs.json    # LF* prefix + 55 airport email_overrides
    ├── gendec_icao.json
    ├── gendec_form.json       # Default form for unmatched airports
    ├── lfqa.json              # icao_list: 11 CODT Metz airports
    ├── lfrm.json              # icao: LFRM (local time, Europe/Paris)
    ├── myhandling.json        # icao_list: 117 airports across EU
    ├── myhandling_fbos.lookup.json  # ICAO → FBO ID lookup data
    ├── gar.json
    ├── redatlas_bookout.json  # web_form: RedAtlas book-out (any RedAtlas airport)
    ├── redatlas_ppr.json      # web_form: RedAtlas PPR request
    ├── egtf_ooh_departure.json # web_form: Fairoaks out-of-hours (Elementor)
    └── egtf_ooh_arrival.json
```

### How It Works

1. **Discovery:** `MappingRegistry` scans `mappings/` at startup, builds ICAO → form config index
2. **Resolution:** Request comes in with airport ICAO → exact match first, then prefix match (e.g., `LFOH` → `LF*` → `french_customs.json`), then default fallback (`"default": true` mappings for airports with no specific form)
3. **Filling:** `generate.py` selects the right filler based on `type` in mapping (`pdf_acroform`, `pdf_acroform_french`, `docx`, `xlsx`)
4. **Output:** Filler reads template, maps canonical fields → template fields using the mapping, writes filled file

`web_form` mappings take a different path: there is no template, and `POST /prefill` returns a fill plan instead of a file (see [Web Forms](#web-forms-web_form)).

### JSON Mapping Structure

Scope is set by exactly one of `icao`, `icao_list`, `icao_prefix`, or `default`:

```json
{
    "icao": "LSGS",              // exact single-airport match
    "icao_list": ["LFQA","LFQB","LFGJ"], // OR explicit list of airports sharing a template
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
    "send_to": "email@example.com",  // default email recipient
    "email_overrides": {             // per-airport email overrides (to/cc)
        "LFMT": {"to": ["customs@lfmt.example"]},
        "LFOH": {"to": ["ops@lfoh.example"], "cc": ["cc@example"]}
    },
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

### XLSX Column Map (myhandling-style forms)

XLSX forms that represent a single flight movement per row use `column_map` instead of `header_map`/`person_columns`:

```json
{
    "column_map": {"arrival_date": "A", "registration": "E", "fbo_id": "AC"},
    "data_start_row": 4,
    "fbo_lookup": "myhandling_fbos.lookup.json",
    "flight_type_map": {"private": "2|Private", "commercial": "1|Commercial"}
}
```

- `column_map` maps value names to column letters for a single data row
- `fbo_lookup` references a `.lookup.json` file mapping ICAO → FBO ID (path-traversal validated)
- `flight_type_map` maps `nature` values to form-specific enum values

### Web Forms (`web_form`)

Some airports take movements through their own web pages — book-out, PPR, out-of-hours — rather than a document. For those, the mapping describes the page, and `POST /prefill` answers with a **fill plan**: the page URL plus a value for each input, keyed by the input's `name`. The app opens the official page in a web view, applies the plan with a generic script, and the pilot reviews it and submits on the airport's own site. Nothing is posted by us.

Keying fields by input `name` (not a CSS selector) keeps the plan usable for a direct server-side submission later: the names are exactly the POST keys.

```json
{
    "icao_list": ["EGTF"],
    "type": "web_form",
    "direction": "departure",       // pins the form to one side; also validated
    "url": "https://{site}.redatlas.co.uk/public/bookout?embedded=true",
    "sites": {"EGXX": "other"},     // {site} override; defaults to lower-case ICAO
    "scope": "form:has(input[name=\"form_id\"][value=\"38ad142\"])",  // page with several forms
    "note": "Times are filled in UK local time.",  // shown above the page
    "time_reference": "utc",
    "date_format": "%Y-%m-%d",      // HTML date inputs need ISO
    "fields": [
        {"name": "Registration", "value": "aircraft.registration"},
        {"name": "Telephone", "value": "extra.telephone", "transform": "no_spaces"},
        {"name": "Returning", "type": "checkbox", "static": "true"}
    ],
    "airport_fields": {             // appended for that airport only
        "EGTF": [{"name": "AdditionalFields[0].ValueString",
                  "format": "{airport.departure.date} {airport.departure.time} UTC"}]
    }
}
```

- A field takes its value from `value` (a canonical key), `static` (a literal) or `format` (a string with `{canonical.key}` placeholders — skipped unless every placeholder has a value). `transform` is `upper` or `no_spaces`.
- Fields with no value are left out of the plan, so the page keeps its own input rather than being blanked.
- Values come from the same `build_values()` the PDF filler uses (so direction, local time and connecting-flight keys all work), plus three web-only keys: `people.count` (crew + passengers), `pilot.name` (first crew member, "First Last") and `aircraft.callsign` (the registration).
- **Return flight:** `"has_return_flight": true` asks the app to send `return_flight` — the first later flight landing back at the airport, however many legs away (a local flight is its own return). It yields `return.present` ("true", for a checkbox), `return.origin`, `return.date` / `return.time` (arrival back, in the mapping's time reference) and `return.people_on_board`. The RedAtlas book-out lists its `Returning` checkbox before the return inputs: the checkbox's click handler enables them, and disabled inputs aren't submitted.
- `direction` also overrides the airport-based derivation, so a local flight (origin == destination) still gets the side the form asks for.
- One mapping can serve every airport running the same system: `url` takes `{icao}` / `{site}` placeholders. RedAtlas field names come from its server-side model, so they are the same at every RedAtlas airport; only its per-airport "additional fields" differ, which go in `airport_fields`.

### Fillers

| Type key | Filler | Library | Notes |
|----------|--------|---------|-------|
| `pdf_acroform` | `pdf_filler.py` | pypdf | Generic AcroForm filling. Supports `full_name`, routing, direction, nature checkboxes, UTC→local time |
| `pdf_acroform_french` | `french_customs_filler.py` | pypdf | French customs-specific: combined crew/pax list, UTC→local time, role dropdowns |
| `docx` | `docx_filler.py` | python-docx | Fills table cells, auto-adds rows |
| `xlsx` | `xlsx_filler.py` | openpyxl | Fills specific cells; preserves formulas |
| `web_form` | `web_form.py` | — | Returns a JSON fill plan (via `/prefill`), not a file |

### Canonical Field Names

Used in `field_map` to map data to template fields. The PDF filler (`pdf_filler.py`) builds a values dict with these keys:

**Flight/aircraft:** `flight.origin`, `flight.destination`, `flight.departure_date`, `flight.arrival_date`, `flight.departure_time_utc`, `flight.arrival_time_utc`, `flight.remote`, `flight.nature`, `flight.contact`, `flight.observations`, `aircraft.registration`, `aircraft.type`, `aircraft.owner`, `aircraft.owner_address`, `aircraft.usual_base`

**Derived:** `origin.country`, `destination.country`, `remote.country`, `airport.name`, `passengers.count`, `passengers.embarking`, `passengers.disembarking`, `routing.departure_place`, `routing.arrival_place`

**Direction-aware:** `flight.date`, `flight.time` (resolve to arrival or departure based on direction), `arrival.date`, `arrival.time`, `arrival.registration`, `arrival.type`, `arrival.owner`, `arrival.nature`, `arrival.remote`, `arrival.remote_name`, `arrival.remote_country` (only filled when arriving), `departure.*` (same, only filled when departing), `airport.icao` (the form's target airport)

The `*.remote*` triple is the other end of the leg — ICAO, resolved name, country. Use it where a form has an arrival section and a departure section that each name the *other* airport, so only the active side fills (e.g. LFRM's Provenance / Aéroport / Pays). Prefer it over `flight.remote` when the field lives inside a direction-specific section.

**Direction marks:** `direction.inbound`, `direction.outbound` (checkboxes), `direction.arrival_mark`, `direction.departure_mark` (text "X" marks)

**Checkboxes:** `flight.nature.<value>` (e.g., `flight.nature.private`), `aircraft.airplane`, `aircraft.helicopter`

Several enum values can share one box with `|`: `flight.nature.private|business|other`. Do **not** map them as separate `field_map` entries pointing at the same field — entries are applied in order, so the last one would overwrite an earlier "on" with "off".

**Person arrays** (use `{i}` for 0-based, `{n}` for 1-based index): `crew[{i}].full_name`, `crew[{i}].first_name`, `crew[{i}].last_name`, `crew[{i}].function`, `crew[{i}].dob`, `crew[{i}].nationality`, `crew[{i}].id_number`, `crew[{i}].id_type`, `crew[{i}].id_issuing_country`, `crew[{i}].id_expiry`, `crew[{i}].sex`, `crew[{i}].place_of_birth` (same for `passengers[{i}]`)

**Extra/connecting:** `extra.<key>` (text), `extra.<key>.name`, `extra.<key>.address` (person sub-fields), `connecting.origin`, `connecting.destination`, etc.

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
| `french_customs` | LF* (France, 55 airports with email overrides) | PDF AcroForm (french) | Préavis Douane |
| `lfqa` | 11 CODT Metz airports (icao_list) | PDF AcroForm | Préavis Douane (CODT Metz) |
| `lfrm` | LFRM (Le Mans Arnage, FR) | PDF AcroForm | Préavis Douane (Le Mans Arnage) |
| `myhandling` | 117 airports across EU (icao_list) | XLSX (column_map) | Handling Request (myhandling) |
| `gar` | EG* (UK) | XLSX | General Aviation Report |
| `gendec_form` | Default (all others) | PDF AcroForm | General Declaration |
| `gendec_icao` | — (no scope, manually selectable) | PDF AcroForm | ICAO General Declaration |
| `redatlas_bookout` | RedAtlas airports (icao_list: EGTF) — departures | Web form | Book Out |
| `redatlas_ppr` | RedAtlas airports (icao_list: EGTF) — arrivals | Web form | PPR Request |
| `egtf_ooh_departure` | EGTF (Fairoaks) — departures | Web form (Elementor) | Out of Hours — Departure |
| `egtf_ooh_arrival` | EGTF (Fairoaks) — arrivals | Web form (Elementor) | Out of Hours — Arrival |

## Key Choices

- **JSON mappings, not code:** New forms don't require Python changes — just template + JSON. This is the core extensibility mechanism.
- **Four-tier resolution:** Exact ICAO match → `icao_list` match → prefix match → default fallback. `icao_list` allows multiple airports to share one mapping without duplicating JSON files (e.g., LFQA/LFQB/LFGJ share one CODT Metz form, myhandling covers 117 airports).
- **Separate fillers per format:** PDF, DOCX, XLSX have fundamentally different filling mechanics. No shared abstraction forced.
- **Templates bundled in Docker image:** Templates ship with the code. No external template storage needed.
- **Prefill the official page, don't submit for the pilot:** web forms open on the airport's own site with our values in; the pilot checks and submits. No test submissions to arrange with the airport, the pilot sees the site's own confirmation, and page changes are fixed in the mapping on the server rather than in an app release.

## Gotchas

- **Flat PDFs can't be filled:** The filler needs AcroForm fields to target. Non-fillable PDFs must be given form fields first, in Acrobat or LibreOffice.
- **LibreOffice-authored fields need care:** LibreOffice emits some widgets with no appearance stream, and some whose field name (`/T`) lives on a parent node rather than the widget itself. `pdf_filler` handles both, but code that walks `/Annots` looking at `annot["/T"]` will silently skip the latter.
- **Font size must fit the box:** a field whose `/DA` declares a size taller than its own rectangle renders clipped, with the baseline below the box. `_fix_text_appearances` rebuilds the appearance for those (and for auto-size `0 Tf` fields, which pypdf otherwise draws at a flat 12pt). Sizes are read from the *template*, because filling rewrites an inherited auto-size `/DA` into a concrete `12 Tf`. Snapshots compare values only, so they cannot catch a regression here — `TestTextAppearances` in `tests/unit/test_fillers.py` does.
- **XLSX formulas:** openpyxl preserves but doesn't recalculate `COUNTA()` formulas. They update when opened in Excel.
- **XLSX header_map targets value cells, not label cells:** In templates like GAR, labels are in columns A/C/E/G and values go in the adjacent columns B/D/F/H. The `header_map` must reference the **value** cells (e.g., `B3` not `A3`).
- **Timezone handling:** Some forms want local time, others UTC. The mapping's `time_zone` + `time_reference` fields control conversion. If `time_reference` is `"utc"` (default), times stay UTC. Date and time convert **together** (`fillers/_datetime.py`): a late-evening UTC slot falls on the next day locally, and printing a converted time against the UTC date misdates the flight by a day.
- **Elementor field names are generated:** the Fairoaks out-of-hours inputs are `form_fields[field_9d94333]`-style, and change if someone rebuilds the form in WordPress. The app reports fields it couldn't find on the page ("the form may have changed"); fix by re-reading the page's HTML and updating the mapping.
- **Out-of-hours times are an assumption:** the Fairoaks form doesn't say UTC or local. The mapping fills local (UK) time, since the out-of-hours rules are in local time, and says so in its `note`. Confirm with the tower.
- **Field naming conventions:** Canonical names use dot notation (`aircraft.registration`, `crew[{i}].last_name`). Array patterns use `{i}` (0-based) and `{n}` (1-based) for PDF field name resolution.

## Testing Strategy

Field mapping correctness is verified through a **visual check once, then automated snapshots lock it in** approach.

### Preview CLI

`flightforms preview` generates every form with self-describing dummy data (`CrewLast1`, `PaxFirst2`, `AcReg`, etc.) — no API server needed. Each value encodes its canonical field name so you can visually verify placement at a glance.

- Both directions generated for direction-aware forms (arrival + departure)
- `--form <id>` to preview a single form, `--output-dir` to choose output location

### Python snapshot tests (`tests/unit/test_snapshots.py`)

For each form × direction:
1. Generate with the same dummy data as preview
2. Extract field values from the output (PDF AcroForm fields, XLSX cells, DOCX table cells)
3. Compare against golden JSON in `tests/snapshots/`

Any change to a mapping, template, or filler that moves a value to a different field fails the test. Update after intentional changes: `pytest --snapshot-update` (after visual verification).

### Web form fill plans (`tests/unit/test_web_form.py`)

Web forms produce no document, so they aren't in the snapshot suite. Their tests assert the plan's values per input name (direction, local-time conversion, connecting-flight estimate, skipped empty values). To check a mapping against the live page, load the page in a headless browser, run `WebFormFiller.script` (in `WebFormView.swift`) with a plan, and read the inputs back — without submitting.

### Swift payload snapshot test

A test in `APITypesTests` encodes a full `GenerateRequest` with all fields populated and compares against `Snapshots/generate_request.json`. Proves the Swift model produces a stable JSON payload shape.

### End-to-end coverage

```
Swift model → JSON payload (Swift snapshot guards this)
                  ↓
          API receives JSON
                  ↓
    Filler puts values in form fields (Python snapshots guard this)
```

### Adding a new form to the test suite

After adding a new form via the `add-form` skill:
1. Add the form's airport to `FORM_AIRPORTS` in `src/flightforms/preview.py`
2. Add the form ID to `DIRECTION_AWARE_FORMS` if it has direction-dependent fields
3. Run `flightforms preview --form <id>` to visually verify both directions
4. Run `pytest --snapshot-update` to generate golden snapshots
5. Run `pytest tests/unit/test_snapshots.py` to confirm they pass

## References

- [API](./api.md) — endpoint that drives form generation
