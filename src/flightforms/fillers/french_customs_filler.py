"""French customs PDF filler (LFOH/LFRG/LFAC style).

This template uses a shared crew/pax list with a dropdown for role,
and French field names ("Zone de texte", "Zone de liste", "Case a cocher").
Different enough from the generic PDF filler to warrant its own module.
"""

from datetime import datetime
from io import BytesIO
from pathlib import Path
from zoneinfo import ZoneInfo

from pypdf import PdfReader, PdfWriter

from ..api.models import GenerateRequest
from ..registry import FormMapping


def _parse_date(date_str: str, fmt: str) -> str:
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return dt.strftime(fmt)


def _utc_to_local(time_str: str, date_str: str, tz_name: str) -> str:
    """Convert HH:MM UTC to local time in the given timezone."""
    dt = datetime.strptime(f"{date_str} {time_str}", "%Y-%m-%d %H:%M")
    dt_utc = dt.replace(tzinfo=ZoneInfo("UTC"))
    dt_local = dt_utc.astimezone(ZoneInfo(tz_name))
    return dt_local.strftime("%H:%M")


def _suffix(index: int) -> str:
    """Row 0 = no suffix, row 1 = '_2', row 2 = '_3', etc."""
    if index == 0:
        return ""
    return f"_{index + 1}"


def fill_french_customs(
    template_path: Path,
    mapping: FormMapping,
    request: GenerateRequest,
    airport_resolver,
    flatten: bool = False,
) -> bytes:
    reader = PdfReader(str(template_path))
    writer = PdfWriter()
    writer.append(reader)

    field_map = mapping.raw.get("field_map", {})
    tz_name = mapping.raw.get("time_zone", "Europe/Paris")

    observations = request.observations or mapping.default_observations or ""

    # Convert UTC times to local
    dep_time_local = _utc_to_local(
        request.flight.departure_time_utc, request.flight.departure_date, tz_name
    )
    arr_time_local = _utc_to_local(
        request.flight.arrival_time_utc, request.flight.arrival_date, tz_name
    )

    # Build contact from pilot (first crew member) name + flight contact
    pilot = request.crew[0] if request.crew else None
    contact_parts = []
    if pilot:
        contact_parts.append(f"{pilot.first_name} {pilot.last_name}")
    if request.flight.contact:
        contact_parts.append(request.flight.contact)
    contact = ", ".join(contact_parts)

    # Build header values
    header_values = {
        "origin": request.flight.origin,
        "destination": request.flight.destination,
        "registration": request.aircraft.registration,
        "aircraft_type": request.aircraft.type,
        "departure_date": _parse_date(request.flight.departure_date, mapping.date_format),
        "arrival_date": _parse_date(request.flight.arrival_date, mapping.date_format),
        "departure_time": dep_time_local,
        "arrival_time": arr_time_local,
        "contact": contact,
        "airport": request.airport,
        "observations": observations,
        "airline": "",
        "flight_number": "",
    }

    updates = {}

    # Fill header fields from mapping
    for canonical, pdf_field in field_map.items():
        if canonical.startswith("header.") and canonical[7:] in header_values:
            updates[pdf_field] = header_values[canonical[7:]]

    # Nature/type of flight checkboxes
    nature = request.flight.nature.lower()
    for key in ["nature.private", "nature.business", "nature.fret", "nature.other"]:
        if key in field_map:
            check_val = key.split(".")[-1]
            updates[field_map[key]] = mapping.checkbox_on if nature == check_val else mapping.checkbox_off

    # Build combined person list: crew first, then passengers
    all_people = []
    for crew in request.crew:
        all_people.append(("Crew", crew))
    for pax in request.passengers:
        all_people.append(("Pax", pax))

    # Fill person fields
    person_prefix = field_map.get("_person_prefix", "Zone de texte")
    role_prefix = field_map.get("_role_prefix", "Zone de liste 1")

    for i, (role, person) in enumerate(all_people):
        sfx = _suffix(i)
        # Role dropdown
        role_field = f"{role_prefix}{sfx}"
        updates[role_field] = role

        # Person data fields
        last_name_field = field_map.get("person.last_name", "Zone de texte 1")
        first_name_field = field_map.get("person.first_name", "Zone de texte 2")
        nationality_field = field_map.get("person.nationality", "Zone de texte 3")
        id_number_field = field_map.get("person.id_number", "Zone de texte 4")

        updates[f"{last_name_field}{sfx}"] = person.last_name
        updates[f"{first_name_field}{sfx}"] = person.first_name
        updates[f"{nationality_field}{sfx}"] = person.nationality or ""
        updates[f"{id_number_field}{sfx}"] = person.id_number or ""

    # Apply updates
    for page in writer.pages:
        writer.update_page_form_field_values(page, updates, auto_regenerate=flatten)

    output = BytesIO()
    writer.write(output)
    return output.getvalue()
