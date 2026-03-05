"""XLSX filler for GAR (General Aviation Report)."""

from datetime import datetime
from io import BytesIO
from pathlib import Path

from openpyxl import load_workbook

from ..api.models import GenerateRequest
from ..registry import FormMapping


def _parse_date(date_str: str, fmt: str) -> str:
    dt = datetime.strptime(date_str, "%Y-%m-%d")
    # Convert Python strftime format
    if fmt == "DD/MM/YYYY":
        return dt.strftime("%d/%m/%Y")
    return dt.strftime(fmt)


def _format_time(time_str: str, fmt: str) -> str:
    """Format HH:MM to HH:MM:SS if needed."""
    if fmt == "HH:MM:SS" and len(time_str) == 5:
        return time_str + ":00"
    return time_str


def fill_xlsx(
    template_path: Path,
    mapping: FormMapping,
    request: GenerateRequest,
    airport_resolver,
) -> bytes:
    wb = load_workbook(str(template_path))
    ws = wb["GAR"]

    header_map = mapping.raw.get("header_map", {})
    person_columns = mapping.raw.get("person_columns", {})
    crew_start = mapping.raw.get("crew_start_row", 9)
    pax_start = mapping.raw.get("pax_start_row", 20)
    date_fmt = mapping.raw.get("date_format", "DD/MM/YYYY")
    time_fmt = mapping.raw.get("time_format", "HH:MM:SS")

    is_arrival = request.airport == request.flight.destination

    # Header fields
    direction_text = "ARRIVAL" if is_arrival else "DEPARTURE"
    captain = request.crew[0].last_name if request.crew else ""
    observations = request.observations or mapping.default_observations or ""

    header_values = {
        "direction": direction_text,
        "arrival_icao": request.flight.destination if is_arrival else request.flight.origin,
        "arrival_date": _parse_date(
            request.flight.arrival_date if is_arrival else request.flight.departure_date,
            date_fmt,
        ),
        "arrival_time": _format_time(
            request.flight.arrival_time_utc if is_arrival else request.flight.departure_time_utc,
            time_fmt,
        ),
        "departure_icao": request.flight.origin if is_arrival else request.flight.destination,
        "departure_date": _parse_date(
            request.flight.departure_date if is_arrival else request.flight.arrival_date,
            date_fmt,
        ),
        "departure_time": _format_time(
            request.flight.departure_time_utc if is_arrival else request.flight.arrival_time_utc,
            time_fmt,
        ),
        "owner": request.aircraft.owner or "",
        "contact": request.flight.contact or "",
        "registration": request.aircraft.registration,
        "aircraft_type": request.aircraft.type,
        "captain_surname": captain,
        "usual_base": request.aircraft.usual_base or "",
        "reason_for_visit": (request.extra_fields or {}).get("reason_for_visit", ""),
        "responsible_address": request.aircraft.owner_address or "",
    }

    for field_name, cell_ref in header_map.items():
        if field_name in header_values:
            ws[cell_ref] = header_values[field_name]

    # Fill crew
    for i, crew in enumerate(request.crew):
        row = crew_start + i
        _fill_person_row(ws, row, person_columns, crew, date_fmt)

    # Fill passengers
    for i, pax in enumerate(request.passengers):
        row = pax_start + i
        _fill_person_row(ws, row, person_columns, pax, date_fmt)

    output = BytesIO()
    wb.save(output)
    return output.getvalue()


def _fill_person_row(ws, row: int, columns: dict, person, date_fmt: str):
    """Fill a single person row in the spreadsheet."""
    field_values = {
        "id_type": person.id_type or "",
        "id_type_other": "",
        "id_issuing_country": person.id_issuing_country or "",
        "id_number": person.id_number or "",
        "last_name": person.last_name,
        "first_name": person.first_name,
        "sex": person.sex or "",
        "dob": _parse_date(person.dob, date_fmt) if person.dob else "",
        "place_of_birth": person.place_of_birth or "",
        "nationality": person.nationality or "",
        "id_expiry": _parse_date(person.id_expiry, date_fmt) if person.id_expiry else "",
        "address": "",
    }

    for field_name, col_letter in columns.items():
        if field_name in field_values:
            ws[f"{col_letter}{row}"] = field_values[field_name]
