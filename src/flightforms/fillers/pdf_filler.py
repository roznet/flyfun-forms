"""PDF AcroForm filler using pypdf."""

import copy
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
    values = {
        "flight.departure_date": _parse_date(request.flight.departure_date, mapping.date_format),
        "flight.arrival_date": _parse_date(request.flight.arrival_date, mapping.date_format),
        "flight.departure_time_utc": request.flight.departure_time_utc,
        "flight.arrival_time_utc": request.flight.arrival_time_utc,
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
        "airport.name": airport_resolver.get_name(request.airport),
    }

    # Add extra fields
    if request.extra_fields:
        for key, val in request.extra_fields.items():
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

        # Handle direction checkboxes
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

    output = BytesIO()
    writer.write(output)
    return output.getvalue()


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
