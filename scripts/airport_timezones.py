#!/usr/bin/env python3
"""Regenerate the Android app's airport time zone table.

The Android app shows a flight's schedule in the origin or destination's local
time, which needs each airport's IANA zone. iOS reverse-geocodes the airport's
position at run time (``AirportTimezoneCache``); Android's Geocoder has no time
zone, so the zone is worked out here, once, from the positions in the bundled
``airports.db``, and shipped as ``icao,zone`` lines.

Run it whenever ``app/flyfun-forms/flyfun-forms/airports.db`` changes, and
commit the result:

    pip install timezonefinder
    python scripts/airport_timezones.py

An airport missing from the table (added to the database without re-running
this) is still usable: the app just offers UTC for it.
"""

import argparse
import sqlite3
import sys
from pathlib import Path

from timezonefinder import TimezoneFinder

ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "app" / "flyfun-forms" / "flyfun-forms" / "airports.db"
OUT = ROOT / "app" / "android" / "app" / "src" / "main" / "assets" / "airport_timezones.csv"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--db", type=Path, default=DB)
    parser.add_argument("--out", type=Path, default=OUT)
    args = parser.parse_args()

    finder = TimezoneFinder()
    rows = sqlite3.connect(args.db).execute(
        "SELECT icao_code, latitude_deg, longitude_deg FROM airports "
        "WHERE latitude_deg IS NOT NULL AND longitude_deg IS NOT NULL ORDER BY icao_code"
    )
    lines = []
    missing = []
    for icao, lat, lon in rows:
        # timezone_at covers land; the nearest zone covers an airfield on a
        # coast or an island that the land polygons just miss.
        zone = finder.timezone_at(lng=lon, lat=lat) or finder.timezone_at_land(lng=lon, lat=lat)
        if zone is None:
            missing.append(icao)
            continue
        lines.append(f"{icao},{zone}")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(lines) + "\n")
    print(f"{len(lines)} airports written to {args.out.relative_to(ROOT)}")
    if missing:
        print(f"{len(missing)} without a zone (UTC only in the app): {', '.join(missing[:20])}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
