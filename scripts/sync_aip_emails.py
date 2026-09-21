#!/usr/bin/env python3
"""Regenerate the per-airport customs e-mails from the AIP.

Mappings opt in with ``"email_lookup": "<file>.lookup.json"``.  For every
airport such a mapping covers (its ``icao``, ``icao_list`` or ``icao_prefix``),
this reads the AIP "Customs and immigration" field (302) from the euro_aip
database, extracts the addresses with euro_aip's CustomInterpreter and writes
them to the lookup file: the first address as ``to``, the others as ``cc``,
plus the subject when the AIP mandates one.

Run it after each AIRAC update of the airports database, review the printed
changes, and commit the lookup file:

    python scripts/sync_aip_emails.py --db ~/Developer/public/flyfun-apps/main/data/airports.db

Airports whose AIP gives no address keep any hand-written entry in the
mapping's ``email_overrides``, which the registry layers on top.
"""

import argparse
import json
import os
import sys
from pathlib import Path

from euro_aip.interp.interp_custom import CustomInterpreter
from euro_aip.storage.database_storage import DatabaseStorage

MAPPINGS_DIR = Path(__file__).resolve().parent.parent / "src" / "flightforms" / "mappings"
CUSTOMS_FIELD = 302


def load_opted_in_mappings() -> dict[str, list[dict]]:
    """lookup filename -> mappings that read it."""
    by_lookup: dict[str, list[dict]] = {}
    for path in sorted(MAPPINGS_DIR.glob("*.json")):
        if ".lookup." in path.name:
            continue
        data = json.loads(path.read_text())
        if data.get("email_lookup"):
            by_lookup.setdefault(data["email_lookup"], []).append(data)
    return by_lookup


def covers(mapping: dict, icao: str) -> bool:
    return (
        icao == mapping.get("icao")
        or icao in mapping.get("icao_list", [])
        or bool(mapping.get("icao_prefix")) and icao.startswith(mapping["icao_prefix"])
    )


def build_lookup(model, interpreter: CustomInterpreter, mappings: list[dict]) -> tuple[dict, set[str]]:
    """(icao -> {to, cc, subject?}, countries covered)."""
    airports: dict[str, dict] = {}
    countries: set[str] = set()
    for airport in sorted(model.airports, key=lambda a: a.ident):
        icao = airport.ident
        if not any(covers(m, icao) for m in mappings):
            continue
        entry = airport.get_aip_entry_for_field(CUSTOMS_FIELD)
        if not entry or not entry.value:
            continue
        countries.add(airport.iso_country)
        contacts = interpreter.interpret_field_value(entry.value, airport)
        emails = contacts["contact_emails"] if contacts else []
        if not emails:
            continue
        email = {"to": emails[:1], "cc": emails[1:]}
        if contacts["email_subject"]:
            email["subject"] = contacts["email_subject"]
        airports[icao] = email
    return airports, countries


def airac_by_country(storage: DatabaseStorage, countries: set[str]) -> dict[str, str]:
    return {
        row["country_iso"]: row["airac_date"]
        for row in storage.get_country_coverage()
        if row["country_iso"] in countries
    }


def render(airac: dict[str, str], airports: dict[str, dict]) -> str:
    """JSON with one airport per line, so an AIRAC update reads as a short diff."""
    lines = [
        "{",
        '  "_generated_by": "scripts/sync_aip_emails.py from AIP field 302 (Customs and immigration)",',
        f'  "airac": {json.dumps(airac, sort_keys=True)},',
        '  "airports": {',
    ]
    rows = [f"    {json.dumps(icao)}: {json.dumps(email, ensure_ascii=False)}" for icao, email in airports.items()]
    lines.append(",\n".join(rows))
    lines += ["  }", "}", ""]
    return "\n".join(lines)


def report(name: str, old: dict, new: dict) -> None:
    added = sorted(set(new) - set(old))
    removed = sorted(set(old) - set(new))
    changed = sorted(i for i in set(old) & set(new) if old[i] != new[i])
    print(f"{name}: {len(new)} airports ({len(added)} added, {len(changed)} changed, {len(removed)} removed)")
    for icao in added:
        print(f"  + {icao} {new[icao]}")
    for icao in changed:
        print(f"  ~ {icao} {old[icao]}\n       -> {new[icao]}")
    for icao in removed:
        print(f"  - {icao} {old[icao]}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--db", default=os.environ.get("AIRPORTS_DB"),
                        help="euro_aip airports database (default: $AIRPORTS_DB)")
    parser.add_argument("--dry-run", action="store_true", help="report changes without writing")
    args = parser.parse_args()
    if not args.db or not Path(args.db).exists():
        parser.error(f"airports database not found: {args.db!r}")

    storage = DatabaseStorage(args.db)
    model = storage.load_model()
    interpreter = CustomInterpreter(model)
    if "contact_emails" not in interpreter.get_structured_fields():
        sys.exit("euro_aip is too old: CustomInterpreter has no contact_emails (need euro-aip>=0.18.0)")

    for lookup_name, mappings in load_opted_in_mappings().items():
        airports, countries = build_lookup(model, interpreter, mappings)
        if not airports:
            sys.exit(f"{lookup_name}: no AIP e-mails found in {args.db} — wrong database?")
        path = MAPPINGS_DIR / lookup_name
        old = json.loads(path.read_text())["airports"] if path.exists() else {}
        report(lookup_name, old, airports)
        if not args.dry_run:
            path.write_text(render(airac_by_country(storage, countries), airports))
    return 0


if __name__ == "__main__":
    sys.exit(main())
