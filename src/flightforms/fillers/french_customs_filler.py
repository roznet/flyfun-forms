"""French customs PDF filler (LFOH/LFRG/LFAC style).

This template uses a shared crew/pax list with a dropdown for role,
and French field names ("Zone de texte", "Zone de liste", "Case a cocher").
Different enough from the generic PDF filler to warrant its own module.
"""

from datetime import datetime
from io import BytesIO
from pathlib import Path

from pypdf import PdfReader, PdfWriter

from ..api.models import GenerateRequest
from ..registry import FormMapping


def _parse_date(date_str: str, fmt: str) -> str:
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    return dt.strftime(fmt)


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
    is_arrival = request.airport == request.flight.destination

    observations = request.observations or mapping.default_observations or ""

    # Build header values
    header_values = {
        "origin": request.flight.origin,
        "destination": request.flight.destination,
        "registration": request.aircraft.registration,
        "aircraft_type": request.aircraft.type,
        "departure_date": _parse_date(request.flight.departure_date, mapping.date_format),
        "arrival_date": _parse_date(request.flight.arrival_date, mapping.date_format),
        "departure_time": request.flight.departure_time_utc,
        "arrival_time": request.flight.arrival_time_utc,
        "contact": request.flight.contact or "",
        "airport": request.airport,
        "observations": observations,
        "owner": request.aircraft.owner or "",
        "flight_number": "",
    }

    updates = {}

    # Fill header fields from mapping
    for canonical, pdf_field in field_map.items():
        if canonical.startswith("header.") and canonical[7:] in header_values:
            updates[pdf_field] = header_values[canonical[7:]]

    # Direction checkboxes
    arrival_field = field_map.get("direction.arrival")
    departure_field = field_map.get("direction.departure")
    if arrival_field:
        updates[arrival_field] = mapping.checkbox_on if is_arrival else mapping.checkbox_off
    if departure_field:
        updates[departure_field] = mapping.checkbox_off if is_arrival else mapping.checkbox_on

    # Nature checkboxes
    nature = request.flight.nature.lower()
    for key in ["nature.commercial", "nature.private"]:
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
        writer.update_page_form_field_values(page, updates)

    if flatten:
        for page in writer.pages:
            if "/Annots" in page:
                del page["/Annots"]

    output = BytesIO()
    writer.write(output)
    return output.getvalue()
