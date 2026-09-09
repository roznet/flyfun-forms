"""PDF AcroForm filler using pypdf."""

import copy
import re
import unicodedata
from datetime import datetime
from io import BytesIO
from pathlib import Path
from zoneinfo import ZoneInfo

from pypdf import PdfReader, PdfWriter
from pypdf.generic import (
    ArrayObject,
    DecodedStreamObject,
    DictionaryObject,
    FloatObject,
    NameObject,
)

from ..api.models import GenerateRequest
from ..registry import FormMapping


# Characters that don't decompose via NFKD but have obvious Latin base letters.
_LATIN1_FALLBACK: dict[str, str] = {
    "Đ": "D", "đ": "d", "Ħ": "H", "ħ": "h", "Ł": "L", "ł": "l",
    "Ŋ": "N", "ŋ": "n", "Ŧ": "T", "ŧ": "t",
}


def _latin1_safe(text: str) -> str:
    """Ensure *text* can be encoded as latin-1 for standard Type1 fonts.

    Characters that latin-1 supports (é, ü, ñ …) are kept as-is.
    Characters outside latin-1 (ń, ł, č …) are replaced with their
    closest Latin base letter so customs-form names stay as accurate
    as the font allows.
    """
    result: list[str] = []
    for c in text:
        try:
            c.encode("latin-1")
            result.append(c)
        except UnicodeEncodeError:
            if c in _LATIN1_FALLBACK:
                result.append(_LATIN1_FALLBACK[c])
                continue
            decomposed = unicodedata.normalize("NFKD", c)
            fallback = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
            result.append(fallback if fallback else "?")
    return "".join(result)


def _parse_date(date_str: str, fmt: str) -> str:
    """Convert YYYY-MM-DD to the target format."""
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return dt.strftime(fmt)


def _utc_to_local(time_str: str, date_str: str, tz_name: str) -> str:
    """Convert HH:MM UTC to local time in the given timezone."""
    dt = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
    dt_utc = dt.replace(tzinfo=ZoneInfo("UTC"))
    return dt_utc.astimezone(ZoneInfo(tz_name)).strftime("%H:%M")


def _resolve_field_pattern(pattern: str, index: int) -> str:
    """Resolve {i} (0-based) and {n} (1-based) in field name patterns."""
    return pattern.replace("{i}", str(index)).replace("{n}", str(index + 1))


def fill_pdf(
    template_path: Path,
    mapping: FormMapping,
    request: GenerateRequest,
    airport_resolver,
    flatten: bool = False,
) -> bytes:
    """Fill a PDF AcroForm template and return the filled PDF bytes."""
    reader = PdfReader(str(template_path))
    writer = PdfWriter()
    writer.append(reader)

    # Build map of each checkbox field's "on" value from the template
    checkbox_on_values = {}
    template_fields = reader.get_fields() or {}
    for fname, fdata in template_fields.items():
        if fdata.get("/FT") == "/Btn":
            states = fdata.get("/_States_", [])
            on_val = next((s for s in states if s != "/Off"), mapping.checkbox_on)
            checkbox_on_values[fname] = on_val

    field_map = mapping.raw.get("field_map", {})

    # Determine direction
    is_arrival = request.airport == request.flight.destination
    direction = "inbound" if is_arrival else "outbound"

    # The "remote" airport is the one that isn't request.airport (i.e. the other end)
    remote_icao = request.flight.origin if is_arrival else request.flight.destination
    remote_country = airport_resolver.get_country(remote_icao)

    # Build values dict for simple fields
    observations = request.observations or mapping.default_observations or ""

    # Request times are always UTC.  Forms that ask for the airport's wall
    # clock ("Heure Locale") declare time_reference "local" plus a time_zone;
    # every time value below goes through _time() so the whole form stays in
    # one reference.
    def _time(time_str: str, date_str: str) -> str:
        if mapping.time_reference == "local" and mapping.time_zone:
            return _utc_to_local(time_str, date_str, mapping.time_zone)
        return time_str

    dep_time = _time(request.flight.departure_time_utc, request.flight.departure_date)
    arr_time = _time(request.flight.arrival_time_utc, request.flight.arrival_date)

    # Direction-aware date/time: resolves to arrival or departure based on direction
    local_date = request.flight.arrival_date if is_arrival else request.flight.departure_date
    local_time = arr_time if is_arrival else dep_time

    values = {
        "flight.departure_date": _parse_date(request.flight.departure_date, mapping.date_format),
        "flight.arrival_date": _parse_date(request.flight.arrival_date, mapping.date_format),
        "flight.departure_time_utc": dep_time,
        "flight.arrival_time_utc": arr_time,
        "flight.date": _parse_date(local_date, mapping.date_format),
        "flight.time": local_time,
        "flight.origin": request.flight.origin,
        "flight.destination": request.flight.destination,
        "flight.remote": remote_icao,
        "flight.contact": request.flight.contact or "",
        "flight.nature": request.flight.nature,
        "flight.observations": observations,
        "aircraft.registration": request.aircraft.registration,
        "aircraft.type": request.aircraft.type,
        "aircraft.owner": request.aircraft.owner or "",
        "aircraft.usual_base": request.aircraft.usual_base or "",
        "aircraft.owner_address": request.aircraft.owner_address or "",
        "origin.country": airport_resolver.get_country(request.flight.origin),
        "destination.country": airport_resolver.get_country(request.flight.destination),
        "remote.country": remote_country,
        "passengers.count": str(len(request.passengers)),
        "passengers.embarking": str(len(request.passengers)),
        "passengers.disembarking": str(len(request.passengers)),
        "routing.departure_place": airport_resolver.get_name(request.flight.origin),
        "routing.arrival_place": airport_resolver.get_name(request.flight.destination),
        "routing.embarkation": airport_resolver.get_name(request.flight.origin),
        "routing.disembarkation": airport_resolver.get_name(request.flight.destination),
        # Aliases for multi-page forms where the same data appears on a second
        # page with differently-named fields (e.g. gendec + passenger manifest).
        "manifest.operator": request.aircraft.owner or "",
        "manifest.registration": request.aircraft.registration,
        "manifest.date": _parse_date(request.flight.departure_date, mapping.date_format),
        "airport.name": airport_resolver.get_name(request.airport),
        "airport.icao": request.airport,
        # Direction-dependent text marks (e.g. "X" on the right side)
        "direction.arrival_mark": "X" if is_arrival else "",
        "direction.departure_mark": "X" if not is_arrival else "",
    }

    # Direction-conditional values: arrival.* only filled for arrivals,
    # departure.* only filled for departures.  Lets forms with separate
    # arrival/departure sections fill only the relevant side.
    if is_arrival:
        values.update({
            "arrival.date": _parse_date(request.flight.arrival_date, mapping.date_format),
            "arrival.time": arr_time,
            "arrival.registration": request.aircraft.registration,
            "arrival.type": request.aircraft.type,
            "arrival.owner": request.aircraft.owner or "",
            "arrival.nature": request.flight.nature,
            # The other end of the leg (where the flight came from)
            "arrival.remote": remote_icao,
            "arrival.remote_name": airport_resolver.get_name(remote_icao),
            "arrival.remote_country": remote_country,
        })
    else:
        values.update({
            "departure.date": _parse_date(request.flight.departure_date, mapping.date_format),
            "departure.time": dep_time,
            "departure.registration": request.aircraft.registration,
            "departure.type": request.aircraft.type,
            "departure.owner": request.aircraft.owner or "",
            "departure.nature": request.flight.nature,
            # The other end of the leg (where the flight is going)
            "departure.remote": remote_icao,
            "departure.remote_name": airport_resolver.get_name(remote_icao),
            "departure.remote_country": remote_country,
        })

    # Add extra fields
    if request.extra_fields:
        for key, val in request.extra_fields.items():
            if isinstance(val, dict):
                # Person-type extra: flatten sub-fields (e.g. extra.responsible_person.name)
                for sub_key, sub_val in val.items():
                    values[f"extra.{key}.{sub_key}"] = sub_val
                # Also store the name as the top-level value for simple text fields
                values[f"extra.{key}"] = val.get("name", "")
            else:
                values[f"extra.{key}"] = val

    # Process connecting flight
    if request.connecting_flight:
        cf = request.connecting_flight
        values["connecting.origin"] = cf.origin
        values["connecting.destination"] = cf.destination
        values["connecting.departure_date"] = _parse_date(cf.departure_date, mapping.date_format)
        values["connecting.departure_time_utc"] = _time(cf.departure_time_utc, cf.departure_date)
        values["connecting.arrival_date"] = _parse_date(cf.arrival_date, mapping.date_format)
        values["connecting.arrival_time_utc"] = _time(cf.arrival_time_utc, cf.arrival_date)

    # Airport-centric leg values: for forms that show both an arrival and a
    # departure section at the target airport (e.g. Jersey GenDec).  The
    # arriving leg comes from the main flight when arriving, or from the
    # connecting flight when departing — and vice-versa for the departing leg.
    if is_arrival:
        values["airport.arrival.from"] = request.flight.origin
        values["airport.arrival.from_name"] = airport_resolver.get_name(request.flight.origin)
        values["airport.arrival.date"] = _parse_date(request.flight.arrival_date, mapping.date_format)
        values["airport.arrival.time"] = arr_time
        if request.connecting_flight:
            cf = request.connecting_flight
            values["airport.departure.to"] = cf.destination
            values["airport.departure.to_name"] = airport_resolver.get_name(cf.destination)
            values["airport.departure.date"] = _parse_date(cf.departure_date, mapping.date_format)
            values["airport.departure.time"] = _time(cf.departure_time_utc, cf.departure_date)
    else:
        values["airport.departure.to"] = request.flight.destination
        values["airport.departure.to_name"] = airport_resolver.get_name(request.flight.destination)
        values["airport.departure.date"] = _parse_date(request.flight.departure_date, mapping.date_format)
        values["airport.departure.time"] = dep_time
        if request.connecting_flight:
            cf = request.connecting_flight
            values["airport.arrival.from"] = cf.origin
            values["airport.arrival.from_name"] = airport_resolver.get_name(cf.origin)
            values["airport.arrival.date"] = _parse_date(cf.arrival_date, mapping.date_format)
            values["airport.arrival.time"] = _time(cf.arrival_time_utc, cf.arrival_date)

    # Fill fields
    updates = {}

    for canonical, pdf_field in field_map.items():
        # Skip person array fields (handled below)
        if "[" in canonical and "]" in canonical:
            continue

        # Handle direction text marks (direction.arrival_mark / direction.departure_mark)
        if canonical in ("direction.arrival_mark", "direction.departure_mark"):
            if canonical in values:
                updates[pdf_field] = values[canonical]
            continue

        # Handle direction checkboxes (direction.inbound / direction.outbound)
        if canonical.startswith("direction."):
            check_dir = canonical.split(".")[-1]
            on_val = checkbox_on_values.get(pdf_field, mapping.checkbox_on)
            updates[pdf_field] = on_val if check_dir == direction else mapping.checkbox_off
            continue

        # Handle enum-to-radio (e.g. flight.nature.private=Pleasure)
        # Maps an enum value to a specific radio button state.
        parts = canonical.split(".")
        if len(parts) == 3 and "=" in parts[2] and parts[0] + "." + parts[1] in values:
            enum_key = parts[0] + "." + parts[1]
            enum_val = values[enum_key].lower()
            check_val, radio_state = parts[2].split("=", 1)
            if enum_val == check_val.lower():
                updates[pdf_field] = f"/{radio_state}"
            continue

        # Handle enum-to-checkbox (e.g. flight.nature.private).  Several enum
        # values can share one box via "|" (e.g. flight.nature.private|business
        # for a form whose only distinction is passengers vs cargo) — mapping
        # them as separate entries would make the later one overwrite the
        # earlier one's "on" with "off".
        if len(parts) == 3 and parts[0] + "." + parts[1] in values:
            enum_key = parts[0] + "." + parts[1]
            enum_val = values[enum_key].lower()
            check_vals = parts[2].lower().split("|")
            on_val = checkbox_on_values.get(pdf_field, mapping.checkbox_on)
            updates[pdf_field] = on_val if enum_val in check_vals else mapping.checkbox_off
            continue

        # Handle aircraft.airplane / aircraft.helicopter checkboxes
        if canonical == "aircraft.airplane":
            on_val = checkbox_on_values.get(pdf_field, mapping.checkbox_on)
            updates[pdf_field] = on_val if request.aircraft.is_airplane else mapping.checkbox_off
            continue
        if canonical == "aircraft.helicopter":
            on_val = checkbox_on_values.get(pdf_field, mapping.checkbox_on)
            updates[pdf_field] = mapping.checkbox_off if request.aircraft.is_airplane else on_val
            continue

        # Static checkbox/radio values (e.g. "static./No" → always set to /No)
        if canonical.startswith("static."):
            updates[pdf_field] = canonical[len("static."):]
            continue

        # Simple text field
        if canonical in values:
            updates[pdf_field] = values[canonical]

    # Fill crew array fields
    # Supports two patterns:
    #   - "crew[{i}].field": "PDFField{n}"  (generic, {i}/{n} resolved per index)
    #   - "crew[2].field": "PDFFieldExact"  (literal index for irregular templates)
    person_fields = {k: v for k, v in field_map.items() if "[" in k and "]" in k}
    crew_fields = {k: v for k, v in person_fields.items() if k.startswith("crew[")}
    pax_fields = {k: v for k, v in person_fields.items() if k.startswith("passengers[")}

    for i, crew in enumerate(request.crew):
        _fill_person_fields(crew_fields, "crew", i, crew, mapping, updates,
                            checkbox_on_values, direction)

    for i, pax in enumerate(request.passengers):
        _fill_person_fields(pax_fields, "passengers", i, pax, mapping, updates,
                            checkbox_on_values, direction)

    # Apply all updates
    for page in writer.pages:
        writer.update_page_form_field_values(page, updates, auto_regenerate=flatten)

    # Draw text that fits: pypdf renders auto-size fields at a flat 12pt, and
    # leaves a fixed size alone even when it overflows a short box (which puts
    # the baseline below the box, clipping the value).  We rebuild the
    # appearance for both cases.  Sizes come from the template, because filling
    # rewrites an inherited auto-size /DA to a concrete "12 Tf".
    _fix_text_appearances(writer, updates, _template_font_sizes(reader))

    output = BytesIO()
    writer.write(output)
    return output.getvalue()


# Average character width as fraction of font size for Helvetica.
# Helvetica averages ~0.52 of the font size per character; we use a slightly
# wider estimate to leave a small margin.
_HELV_AVG_WIDTH_RATIO = 0.55
_PADDING = 4  # 2px each side


def _widget_field_name(annot, parent):
    """Field name for a widget, looking through to the parent field node."""
    name = annot.get("/T")
    if name is None and parent is not None:
        name = parent.get("/T")
    return name


def _template_font_sizes(reader: PdfReader) -> dict:
    """Font size each field's /DA asks for in the template; 0 means auto-size.

    Fields whose /DA declares no size at all are left out, so callers skip
    them rather than guessing.

    Must be read from the template: filling replaces an inherited auto-size
    /DA with a concrete "/Helv 12 Tf" on the field node, so the same lookup
    against the filled document would report every field as fixed-size.
    """
    acroform = reader.trailer["/Root"].get("/AcroForm")
    form_da = ""
    if acroform is not None:
        form_da = acroform.get_object().get("/DA", "")

    sizes: dict[str, float] = {}
    for page in reader.pages:
        for annot_ref in page.get("/Annots", []) or []:
            annot = annot_ref.get_object()
            if annot.get("/Subtype") != "/Widget":
                continue
            parent = annot.get("/Parent")
            parent = parent.get_object() if parent is not None else None
            name = _widget_field_name(annot, parent)
            if not name:
                continue
            da = annot.get("/DA", "")
            if not da and parent is not None:
                da = parent.get("/DA", "")
            da = da or form_da
            match = re.search(r"([\d.]+)\s+Tf\b", da or "")
            if match:
                sizes[name] = float(match.group(1))
    return sizes


def _fix_text_appearances(writer: PdfWriter, updates: dict, template_sizes: dict):
    """Rebuild appearance streams for text that would not fit its field box."""
    acroform = writer._root_object.get("/AcroForm")
    form_resources = None
    if acroform:
        af = acroform.get_object() if hasattr(acroform, "get_object") else acroform
        dr = af.get("/DR")
        if dr is not None:
            form_resources = dr.get_object()

    for page in writer.pages:
        annots = page.get("/Annots", [])
        for annot_ref in annots:
            annot = annot_ref.get_object()

            # A widget may carry the field name itself, or be the kid of a
            # separate field node that holds /T (how LibreOffice emits some
            # fields).  Look through to the parent in that case.
            parent = annot.get("/Parent")
            parent = parent.get_object() if parent is not None else None
            field_name = _widget_field_name(annot, parent)
            if not field_name or field_name not in updates:
                continue
            declared_size = template_sizes.get(field_name)
            if declared_size is None:
                continue

            text = updates[field_name]
            if not text:
                continue

            # Get field rectangle
            rect = annot.get("/Rect")
            if not rect:
                continue
            x1, y1, x2, y2 = [float(v) for v in rect]
            field_width = abs(x2 - x1)
            field_height = abs(y2 - y1)

            if field_width <= 0 or field_height <= 0:
                continue

            # A fixed size that already fits its box is left as authored.
            if 0 < declared_size <= field_height - 2:
                continue

            # Calculate font size that fits the text width, capped by the box
            # height and by the authored size (auto-size fields cap at 12pt,
            # what Acrobat typically picks for a standard form field).
            usable_width = field_width - _PADDING
            size_by_width = usable_width / (len(text) * _HELV_AVG_WIDTH_RATIO)
            max_size = min(field_height - 2, declared_size or 12)
            font_size = min(size_by_width, max_size)
            font_size = max(font_size, 4)  # floor at 4pt

            # Rebuild the appearance stream.  Fields authored without one
            # (again, common from LibreOffice) get a fresh stream rather than
            # being left to whatever the viewer decides to draw.
            ap = annot.get("/AP")
            stream_obj = ap["/N"].get_object() if ap and "/N" in ap else None
            # A button's /N is a dictionary of appearance states keyed by
            # value, not a text stream — nothing to re-draw.
            if stream_obj is not None and not hasattr(stream_obj, "set_data"):
                continue

            # Build a clean appearance stream from scratch.  pypdf encodes
            # text as UTF-16BE hex (<0041…>) but /Helv is a standard Type1
            # font that expects single-byte codes.  Viewers fall back to
            # wider CID default widths for 2-byte codes, causing clipping.
            # Writing a simple single-byte stream avoids this entirely.
            y_offset = (field_height - font_size) / 2
            # Escape PDF string special chars; ensure latin-1 safe for Type1 font
            safe_text = _latin1_safe(text)
            escaped = safe_text.replace("\\", "\\\\").replace("(", "\\(").replace(")", "\\)")
            new_data = (
                "q\n"
                "/Tx BMC \n"
                "q\n"
                f"1 1 {field_width - 2:.2f} {field_height - 2:.2f} re\n"
                "W\n"
                "BT\n"
                f"/Helv {font_size:.2f} Tf 0 g\n"
                f"2 {y_offset:.1f} Td\n"
                f"({escaped}) Tj\n"
                "ET\n"
                "Q\n"
                "EMC\n"
                "Q\n"
            )

            if stream_obj is not None:
                stream_obj.set_data(new_data.encode("latin-1"))
            else:
                stream_obj = DecodedStreamObject()
                stream_obj.set_data(new_data.encode("latin-1"))
                stream_obj[NameObject("/Type")] = NameObject("/XObject")
                stream_obj[NameObject("/Subtype")] = NameObject("/Form")
                stream_obj[NameObject("/BBox")] = ArrayObject(
                    [FloatObject(0), FloatObject(0),
                     FloatObject(field_width), FloatObject(field_height)]
                )
                if form_resources is not None:
                    stream_obj[NameObject("/Resources")] = form_resources
                annot[NameObject("/AP")] = DictionaryObject(
                    {NameObject("/N"): writer._add_object(stream_obj)}
                )


def _fill_person_fields(
    field_patterns: dict,
    prefix: str,
    index: int,
    person,
    mapping: FormMapping,
    updates: dict,
    checkbox_on_values: dict | None = None,
    direction: str = "inbound",
):
    """Fill person (crew/passenger) array fields."""
    person_type = "Crew" if prefix == "crew" else "Passenger"
    person_values = {
        "full_name": f"{person.last_name} {person.first_name}".strip(),
        "function": person.function or "",
        "type": person_type,
        "first_name": person.first_name,
        "last_name": person.last_name,
        "dob": _parse_date(person.dob, mapping.date_format) if person.dob else "",
        "nationality": person.nationality or "",
        "id_number": person.id_number or "",
        "id_type": person.id_type or "",
        "id_issuing_country": person.id_issuing_country or "",
        "id_expiry": _parse_date(person.id_expiry, mapping.date_format) if person.id_expiry else "",
        "sex": person.sex or "",
        "place_of_birth": person.place_of_birth or "",
        "address": person.address or "",
    }

    for canonical_pattern, pdf_field_name in field_patterns.items():
        # Resolve the PDF field name for this index
        if "[{i}]" in canonical_pattern:
            pdf_field = _resolve_field_pattern(pdf_field_name, index)
        else:
            bracket_content = canonical_pattern.split("[")[1].split("]")[0]
            if not (bracket_content.isdigit() and int(bracket_content) == index):
                continue
            pdf_field = pdf_field_name

        # Per-person direction checkboxes (e.g. crew[{i}].direction.inbound)
        field_suffix = canonical_pattern.split(".")[-1]
        if ".direction." in canonical_pattern:
            check_dir = field_suffix  # "inbound" or "outbound"
            on_val = (checkbox_on_values or {}).get(pdf_field, mapping.checkbox_on)
            updates[pdf_field] = on_val if check_dir == direction else mapping.checkbox_off
            continue

        if field_suffix not in person_values:
            continue
        updates[pdf_field] = person_values[field_suffix]
