"""CLI client for FlightForms API."""

import argparse
import csv
import json
import os
import sys
from pathlib import Path
from urllib.request import Request, urlopen
from urllib.error import HTTPError


DEFAULT_URL = "http://127.0.0.1:8030"


def _load_people(path: str) -> dict[str, dict]:
    """Load people database from CSV. Keyed by 'First Last' name."""
    people = {}
    with open(path, newline="", encoding="utf-8-sig") as f:
        reader = csv.DictReader(f)
        for row in reader:
            first = row.get("First Name", "").strip()
            last = row.get("Last Name", "").strip()
            if not first or not last:
                continue
            key = f"{first} {last}"
            people[key] = {
                "first_name": first,
                "last_name": last,
                "dob": _convert_date(row.get("DoB", "")),
                "nationality": row.get("Nationality", ""),
                "id_number": row.get("Doc Number", ""),
                "id_type": row.get("Doc Type", ""),
                "id_issuing_country": row.get("Doc Issuing State", ""),
                "id_expiry": _convert_date(row.get("Doc Expiry", "")),
                "sex": _normalize_sex(row.get("Gender", "")),
                "place_of_birth": row.get("Place of Birth", ""),
            }
    return people


def _convert_date(date_str: str) -> str:
    """Try to convert various date formats to YYYY-MM-DD."""
    if not date_str:
        return ""
    date_str = date_str.strip()
    # Try common formats
    from datetime import datetime
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%d-%m-%Y", "%d %b %Y", "%d %B %Y"):
        try:
            return datetime.strptime(date_str, fmt).strftime("%Y-%m-%d")
        except ValueError:
            continue
    return date_str


def _normalize_sex(value: str) -> str:
    v = value.strip().upper()
    if v in ("M", "MALE"):
        return "Male"
    if v in ("F", "FEMALE"):
        return "Female"
    return value


def _resolve_person(name: str, people_db: dict, role_hint: str = "") -> dict:
    """Look up a person by name in the people database.

    Matches by: exact name, case-insensitive, or first+last name
    (ignoring middle names in the CSV).
    """
    # Exact match
    if name in people_db:
        person = dict(people_db[name])
        if role_hint:
            person["function"] = role_hint
        return person
    # Case-insensitive exact match
    name_lower = name.lower()
    for key, data in people_db.items():
        if key.lower() == name_lower:
            person = dict(data)
            if role_hint:
                person["function"] = role_hint
            return person
    # Fuzzy match: input "First Last" matches CSV "First Middle Last"
    parts = name.split()
    if len(parts) >= 2:
        input_first = parts[0].lower()
        input_last = parts[-1].lower()
        for key, data in people_db.items():
            if data["first_name"].lower().startswith(input_first) and data["last_name"].lower() == input_last:
                person = dict(data)
                if role_hint:
                    person["function"] = role_hint
                return person
    # Last-name-only match (single word input)
    if len(parts) == 1:
        for key, data in people_db.items():
            if data["last_name"].lower() == name_lower:
                person = dict(data)
                if role_hint:
                    person["function"] = role_hint
                return person
    # Not found — create minimal entry
    return {
        "first_name": parts[0] if parts else name,
        "last_name": parts[-1] if len(parts) > 1 else "",
        "function": role_hint,
    }


def _api_call(base_url: str, method: str, path: str, body: dict | None = None, api_key: str = "", raw_response: bool = False):
    """Make an API call. If raw_response=True, return (bytes, response) tuple."""
    url = f"{base_url}{path}"
    data = json.dumps(body).encode() if body else None
    headers = {"Content-Type": "application/json"}
    if api_key:
        headers["Authorization"] = f"Bearer {api_key}"
    req = Request(url, data=data, headers=headers, method=method)
    try:
        resp = urlopen(req)
        content = resp.read()
        if raw_response:
            return content, resp
        return content
    except HTTPError as e:
        error_body = e.read().decode()
        print(f"Error {e.code}: {error_body}", file=sys.stderr)
        sys.exit(1)


def _filename_from_response(resp, fallback_stem: str) -> str:
    """Extract filename from Content-Disposition header, or build from fallback + content type."""
    cd = resp.headers.get("Content-Disposition", "")
    if 'filename="' in cd:
        return cd.split('filename="')[1].rstrip('"')
    # Fallback: infer extension from Content-Type
    ct = resp.headers.get("Content-Type", "")
    if "spreadsheet" in ct or "xlsx" in ct:
        return f"{fallback_stem}.xlsx"
    if "wordprocessing" in ct or "docx" in ct:
        return f"{fallback_stem}.docx"
    return f"{fallback_stem}.pdf"


def cmd_generate(args):
    people_db = _load_people(args.people_file) if args.people_file else {}

    crew = [_resolve_person(name, people_db, "Pilot" if i == 0 else "Crew") for i, name in enumerate(args.crew)]
    passengers = [_resolve_person(name, people_db) for name in args.pax]

    # Parse extra fields
    extra = {}
    for item in (args.extra or []):
        k, _, v = item.partition("=")
        extra[k] = v

    # Determine which forms to generate
    base_url = args.url or DEFAULT_URL
    api_key = args.api_key or os.environ.get("FLIGHTFORMS_API_KEY", "")

    # Get available forms for this airport
    airport_info = json.loads(_api_call(base_url, "GET", f"/airports/{args.airport}", api_key=api_key))
    form_ids = [f["id"] for f in airport_info["forms"]]

    if args.form:
        form_ids = [args.form]

    for form_id in form_ids:
        body = {
            "airport": args.airport,
            "form": form_id,
            "flight": {
                "origin": args.origin,
                "destination": args.destination,
                "departure_date": args.departure_date,
                "departure_time_utc": args.departure_time,
                "arrival_date": args.arrival_date,
                "arrival_time_utc": args.arrival_time,
                "nature": args.nature,
                "contact": args.contact or "",
            },
            "aircraft": {
                "registration": args.aircraft,
                "type": args.aircraft_type or "",
                "owner": args.owner or "",
                "owner_address": args.owner_address or "",
                "is_airplane": True,
                "usual_base": args.usual_base or "",
            },
            "crew": crew,
            "passengers": passengers,
            "extra_fields": extra or None,
            "observations": args.observations,
        }

        flatten = "flatten=true" if args.flatten else ""
        path = f"/generate?{flatten}" if flatten else "/generate"
        content, resp = _api_call(base_url, "POST", path, body, api_key, raw_response=True)

        # Determine output path
        if args.output:
            out_path = args.output
        else:
            out_path = _filename_from_response(resp, f"{args.departure_date}_{args.airport}_{form_id}")

        with open(out_path, "wb") as f:
            f.write(content)
        print(f"Generated: {out_path}")


def cmd_trip(args):
    people_db = _load_people(args.people_file) if args.people_file else {}
    crew = [_resolve_person(name, people_db, "Pilot" if i == 0 else "Crew") for i, name in enumerate(args.crew)]
    passengers = [_resolve_person(name, people_db) for name in args.pax]

    extra = {}
    for item in (args.extra or []):
        k, _, v = item.partition("=")
        extra[k] = v

    base_url = args.url or DEFAULT_URL
    api_key = args.api_key or os.environ.get("FLIGHTFORMS_API_KEY", "")

    # Parse legs
    legs = args.legs.split(",")
    dates = args.dates.split(",")
    times = (args.times or "").split(",") if args.times else ["08:00>09:00"] * len(legs)

    if len(dates) != len(legs):
        print("Error: number of dates must match number of legs", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir or ".")
    output_dir.mkdir(parents=True, exist_ok=True)

    for i, leg in enumerate(legs):
        origin, _, dest = leg.partition(">")
        dep_time, _, arr_time = times[i].partition(">") if i < len(times) else ("08:00", ">", "09:00")

        # Get forms for both origin and destination airports
        for airport in [origin, dest]:
            try:
                info = json.loads(_api_call(base_url, "GET", f"/airports/{airport}", api_key=api_key))
            except SystemExit:
                continue  # No forms for this airport

            for form in info["forms"]:
                # Build connecting flight if next/prev leg exists
                connecting = None
                if form.get("has_connecting_flight"):
                    if airport == dest and i + 1 < len(legs):
                        next_origin, _, next_dest = legs[i + 1].partition(">")
                        next_dep, _, next_arr = (times[i + 1].partition(">") if i + 1 < len(times)
                                                 else ("08:00", ">", "09:00"))
                        connecting = {
                            "origin": next_origin,
                            "destination": next_dest,
                            "departure_date": dates[i + 1],
                            "departure_time_utc": next_dep,
                            "arrival_date": dates[i + 1],
                            "arrival_time_utc": next_arr,
                        }

                body = {
                    "airport": airport,
                    "form": form["id"],
                    "flight": {
                        "origin": origin,
                        "destination": dest,
                        "departure_date": dates[i],
                        "departure_time_utc": dep_time,
                        "arrival_date": dates[i],
                        "arrival_time_utc": arr_time,
                        "nature": args.nature,
                        "contact": args.contact or "",
                    },
                    "aircraft": {
                        "registration": args.aircraft,
                        "type": args.aircraft_type or "",
                        "owner": args.owner or "",
                        "owner_address": args.owner_address or "",
                        "is_airplane": True,
                        "usual_base": args.usual_base or "",
                    },
                    "crew": crew,
                    "passengers": passengers,
                    "extra_fields": extra or None,
                    "observations": args.observations,
                    "connecting_flight": connecting,
                }

                content, resp = _api_call(base_url, "POST", "/generate", body, api_key, raw_response=True)
                filename = _filename_from_response(resp, f"{dates[i]}_{airport}_{form['id']}")
                out_path = output_dir / filename
                with open(out_path, "wb") as f:
                    f.write(content)
                print(f"Generated: {out_path}")


def cmd_preview(args):
    from .preview import (
        DIRECTION_AWARE_FORMS,
        FILLER_EXTENSIONS,
        FORM_AIRPORTS,
        PreviewAirportResolver,
        _find_mapping_by_id,
        generate_preview,
    )
    from .registry import MappingRegistry

    src_dir = Path(__file__).parent
    registry = MappingRegistry(str(src_dir / "mappings"), str(src_dir / "templates"))
    resolver = PreviewAirportResolver()

    output_dir = Path(args.output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Determine which forms to preview
    if args.form:
        form_ids = [args.form]
    else:
        form_ids = list(FORM_AIRPORTS.keys())

    for form_id in form_ids:
        airport = FORM_AIRPORTS.get(form_id, "ZZZZ")
        mapping = registry.get_form(airport, form_id)
        if mapping is None:
            mapping = _find_mapping_by_id(registry, form_id)
        if mapping is None:
            print(f"Skipping unknown form: {form_id}", file=sys.stderr)
            continue

        ext = FILLER_EXTENSIONS.get(mapping.filler_type, ".bin")

        # Generate both directions for direction-aware forms
        directions = ["arrival", "departure"] if form_id in DIRECTION_AWARE_FORMS else ["arrival"]
        for direction in directions:
            doc_bytes = generate_preview(registry, form_id, resolver, direction=direction)
            suffix = f"_{direction}" if len(directions) > 1 else ""
            out_path = output_dir / f"preview_{form_id}{suffix}{ext}"
            with open(out_path, "wb") as f:
                f.write(doc_bytes)
            print(f"Generated: {out_path}")


def cmd_airports(args):
    base_url = args.url or DEFAULT_URL
    api_key = args.api_key or os.environ.get("FLIGHTFORMS_API_KEY", "")
    data = json.loads(_api_call(base_url, "GET", "/airports", api_key=api_key))
    print("\nAirports with specific forms:")
    for a in data["airports"]:
        print(f"  {a['icao']} ({a['name']}): {', '.join(a['forms'])}")
    print("\nCountry-level fallbacks:")
    for p in data["prefixes"]:
        print(f"  {p['prefix']}* ({p['country']}): {', '.join(p['forms'])}")


def main():
    parser = argparse.ArgumentParser(prog="flightforms", description="Flight Forms Generator CLI")
    parser.add_argument("--url", help=f"API base URL (default: {DEFAULT_URL})")
    parser.add_argument("--api-key", help="API key for authentication")

    sub = parser.add_subparsers(dest="command")

    # generate command
    gen = sub.add_parser("generate", help="Generate a single form")
    gen.add_argument("--airport", required=True, help="Airport ICAO code")
    gen.add_argument("--form", help="Form ID (omit to generate all forms for airport)")
    gen.add_argument("--origin", required=True)
    gen.add_argument("--destination", required=True)
    gen.add_argument("--departure-date", required=True)
    gen.add_argument("--departure-time", default="08:00")
    gen.add_argument("--arrival-date", required=True)
    gen.add_argument("--arrival-time", default="09:00")
    gen.add_argument("--aircraft", required=True, help="Aircraft registration")
    gen.add_argument("--aircraft-type", default="")
    gen.add_argument("--owner", default="")
    gen.add_argument("--owner-address", default="")
    gen.add_argument("--usual-base", default="")
    gen.add_argument("--nature", default="private")
    gen.add_argument("--contact", default="")
    gen.add_argument("--observations", default=None)
    gen.add_argument("--crew", nargs="+", required=True, help="Crew member names")
    gen.add_argument("--pax", nargs="*", default=[], help="Passenger names")
    gen.add_argument("--people-file", help="CSV file with people details")
    gen.add_argument("--extra", nargs="*", help="Extra fields as key=value")
    gen.add_argument("--flatten", action="store_true")
    gen.add_argument("--output", "-o", help="Output file path")
    gen.set_defaults(func=cmd_generate)

    # trip command
    trip = sub.add_parser("trip", help="Generate forms for a multi-leg trip")
    trip.add_argument("--legs", required=True, help="Comma-separated legs: ORIG>DEST,...")
    trip.add_argument("--dates", required=True, help="Comma-separated dates: YYYY-MM-DD,...")
    trip.add_argument("--times", help="Comma-separated times: HH:MM>HH:MM,...")
    trip.add_argument("--aircraft", required=True)
    trip.add_argument("--aircraft-type", default="")
    trip.add_argument("--owner", default="")
    trip.add_argument("--owner-address", default="")
    trip.add_argument("--usual-base", default="")
    trip.add_argument("--nature", default="private")
    trip.add_argument("--contact", default="")
    trip.add_argument("--observations", default=None)
    trip.add_argument("--crew", nargs="+", required=True)
    trip.add_argument("--pax", nargs="*", default=[])
    trip.add_argument("--people-file", help="CSV file with people details")
    trip.add_argument("--extra", nargs="*", help="Extra fields as key=value")
    trip.add_argument("--output-dir", default=".")
    trip.set_defaults(func=cmd_trip)

    # preview command
    preview = sub.add_parser("preview", help="Generate all forms with self-describing dummy data for visual inspection")
    preview.add_argument("--output-dir", default=".", help="Output directory (default: current dir)")
    preview.add_argument("--form", help="Generate only this form ID (default: all forms)")
    preview.set_defaults(func=cmd_preview)

    # airports command
    airports_cmd = sub.add_parser("airports", help="List available airports and forms")
    airports_cmd.set_defaults(func=cmd_airports)

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(1)

    args.func(args)


if __name__ == "__main__":
    main()
