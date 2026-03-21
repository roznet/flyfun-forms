"""PDF AcroForm filler using pypdf."""

import copy
import re
from datetime import datetime
from io import BytesIO
from pathlib import Path

from pypdf import PdfReader, PdfWriter
from pypdf.generic import NameObject

from ..api.models import GenerateRequest
from ..registry import FormMapping


def _parse_date(date_str: str, fmt: str) -> str:
    """Convert YYYY-MM-DD to the target format."""
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return dt.strftime(fmt)


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

    # Direction-aware date/time: resolves to arrival or departure based on direction
    local_date = request.flight.arrival_date if is_arrival else request.flight.departure_date
    local_time = request.flight.arrival_time_utc if is_arrival else request.flight.departure_time_utc

    values = {
        "flight.departure_date": _parse_date(request.flight.departure_date, mapping.date_format),
        "flight.arrival_date": _parse_date(request.flight.arrival_date, mapping.date_format),
        "flight.departure_time_utc": request.flight.departure_time_utc,
        "flight.arrival_time_utc": request.flight.arrival_time_utc,
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
            "arrival.time": request.flight.arrival_time_utc,
            "arrival.registration": request.aircraft.registration,
            "arrival.type": request.aircraft.type,
            "arrival.owner": request.aircraft.owner or "",
            "arrival.nature": request.flight.nature,
        })
    else:
        values.update({
            "departure.date": _parse_date(request.flight.departure_date, mapping.date_format),
            "departure.time": request.flight.departure_time_utc,
            "departure.registration": request.aircraft.registration,
            "departure.type": request.aircraft.type,
            "departure.owner": request.aircraft.owner or "",
            "departure.nature": request.flight.nature,
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
        values["connecting.departure_time_utc"] = cf.departure_time_utc
        values["connecting.arrival_date"] = _parse_date(cf.arrival_date, mapping.date_format)
        values["connecting.arrival_time_utc"] = cf.arrival_time_utc

    # Fill fields
    updates = {}

    for canonical, pdf_field in field_map.items():
        # Skip person array fields (handled below)
        if "[{i}]" in canonical:
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

        # Handle enum-to-checkbox (e.g. flight.nature.private)
        parts = canonical.split(".")
        if len(parts) == 3 and parts[0] + "." + parts[1] in values:
            enum_key = parts[0] + "." + parts[1]
            enum_val = values[enum_key].lower()
            check_val = parts[2].lower()
            on_val = checkbox_on_values.get(pdf_field, mapping.checkbox_on)
            updates[pdf_field] = on_val if enum_val == check_val else mapping.checkbox_off
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

        # Simple text field
        if canonical in values:
            updates[pdf_field] = values[canonical]

    # Fill crew array fields
    person_fields = {k: v for k, v in field_map.items() if "[{i}]" in k}
    crew_fields = {k: v for k, v in person_fields.items() if k.startswith("crew[")}
    pax_fields = {k: v for k, v in person_fields.items() if k.startswith("passengers[")}

    for i, crew in enumerate(request.crew):
        _fill_person_fields(crew_fields, "crew", i, crew, mapping, updates)

    for i, pax in enumerate(request.passengers):
        _fill_person_fields(pax_fields, "passengers", i, pax, mapping, updates)

    # Apply all updates
    for page in writer.pages:
        writer.update_page_form_field_values(page, updates, auto_regenerate=flatten)

    # Fix auto-size fields: pypdf uses field height as font size instead of
    # calculating a size that fits the text width.  We rewrite the appearance
    # stream for any field whose original /DA had font size 0.
    if flatten:
        _fix_autosize_fields(writer, updates)

    output = BytesIO()
    writer.write(output)
    return output.getvalue()


# Average character width as fraction of font size for Helvetica.
# Helvetica averages ~0.52 of the font size per character; we use a slightly
# wider estimate to leave a small margin.
_HELV_AVG_WIDTH_RATIO = 0.55
_PADDING = 4  # 2px each side


def _fix_autosize_fields(writer: PdfWriter, updates: dict):
    """Rewrite appearance streams for fields whose template DA had font size 0."""
    for page in writer.pages:
        annots = page.get("/Annots", [])
        for annot_ref in annots:
            annot = annot_ref.get_object()
            field_name = annot.get("/T")
            if not field_name or field_name not in updates:
                continue

            # Check if this field's DA specifies auto-size (font size 0)
            da = annot.get("/DA", "")
            if not re.search(r"\b0\s+Tf\b", da):
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

            # Calculate font size that fits the text width, capped at a
            # sensible default (Acrobat auto-size typically picks ~12pt for
            # standard form fields, never larger than the box allows).
            usable_width = field_width - _PADDING
            size_by_width = usable_width / (len(text) * _HELV_AVG_WIDTH_RATIO)
            max_size = min(field_height - 2, 12)  # cap at 12pt
            font_size = min(size_by_width, max_size)
            font_size = max(font_size, 4)  # floor at 4pt

            # Rebuild the appearance stream
            ap = annot.get("/AP")
            if not ap or "/N" not in ap:
                continue

            stream_obj = ap["/N"].get_object()
            try:
                data = stream_obj.get_data().decode("latin-1")
            except Exception:
                continue

            # Replace the Tf operator with our calculated size (first occurrence only)
            new_data = re.sub(
                r"/Helv\s+[\d.]+\s+Tf",
                f"/Helv {font_size:.2f} Tf",
                data,
                count=1,
            )

            # Fix the Td vertical offset to center text (first occurrence only)
            y_offset = (field_height - font_size) / 2
            new_data = re.sub(
                r"(\d+(?:\.\d+)?)\s+[\d.]+\s+Td",
                f"2 {y_offset:.1f} Td",
                new_data,
                count=1,
            )

            stream_obj.set_data(new_data.encode("latin-1"))


def _fill_person_fields(
    field_patterns: dict,
    prefix: str,
    index: int,
    person,
    mapping: FormMapping,
    updates: dict,
):
    """Fill person (crew/passenger) array fields."""
    person_values = {
        "full_name": f"{person.last_name} {person.first_name}".strip(),
        "function": person.function or "",
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
    }

    for canonical_pattern, pdf_pattern in field_patterns.items():
        # Extract the field name after the last dot
        field_name = canonical_pattern.split(".")[-1]
        if field_name in person_values:
            pdf_field = _resolve_field_pattern(pdf_pattern, index)
            updates[pdf_field] = person_values[field_name]
