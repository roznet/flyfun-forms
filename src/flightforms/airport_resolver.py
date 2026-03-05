"""Airport name and country resolution using euro_aip."""

import os
from pathlib import Path
from typing import Optional

# Country code (ISO 2-letter) to country name mapping for common GA destinations
_COUNTRY_NAMES = {
    "CH": "Switzerland", "FR": "France", "GB": "United Kingdom",
    "DE": "Germany", "BE": "Belgium", "NL": "Netherlands",
    "IE": "Ireland", "ES": "Spain", "IT": "Italy", "PT": "Portugal",
    "AT": "Austria", "LU": "Luxembourg", "JE": "Jersey", "GG": "Guernsey",
    "US": "United States",
}

# ICAO prefix to country name for prefix-level fallbacks
PREFIX_COUNTRIES = {
    "EG": "United Kingdom",
    "EI": "Ireland",
    "LF": "France",
    "LS": "Switzerland",
    "ED": "Germany",
    "EB": "Belgium",
    "EH": "Netherlands",
    "LE": "Spain",
    "LI": "Italy",
    "LP": "Portugal",
    "LO": "Austria",
    "EL": "Luxembourg",
}


class AirportResolver:
    """Resolves airport ICAO codes to names and countries."""

    def __init__(self, airports_db_path: Optional[str] = None):
        self._model = None
        self._db_path = airports_db_path or os.environ.get(
            "AIRPORTS_DB",
            str(Path(__file__).parent / "data" / "airports.db"),
        )

    def _ensure_model(self):
        if self._model is None:
            try:
                from euro_aip.storage.database_storage import DatabaseStorage
                storage = DatabaseStorage(self._db_path)
                self._model = storage.load_model()
            except Exception:
                self._model = False  # mark as failed, don't retry

    def get_name(self, icao: str) -> str:
        """Get airport name, or return ICAO code if not found."""
        self._ensure_model()
        if self._model:
            airport = self._model.airports.get(icao)
            if airport and airport.name:
                # Strip common suffixes for cleaner names
                name = airport.name
                for suffix in [" Airport", " Airfield", " Aerodrome"]:
                    if name.endswith(suffix):
                        name = name[: -len(suffix)]
                return name
        return icao

    def get_country(self, icao: str) -> str:
        """Get country name for an airport ICAO code."""
        self._ensure_model()
        if self._model:
            airport = self._model.airports.get(icao)
            if airport and airport.iso_country:
                return _COUNTRY_NAMES.get(airport.iso_country, airport.iso_country)
        # Fallback to ICAO prefix
        prefix = icao[:2]
        return PREFIX_COUNTRIES.get(prefix, "")

    def get_country_code(self, icao: str) -> str:
        """Get ISO 2-letter country code."""
        self._ensure_model()
        if self._model:
            airport = self._model.airports.get(icao)
            if airport and airport.iso_country:
                return airport.iso_country
        return ""
