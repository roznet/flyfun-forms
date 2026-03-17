"""Shared fixtures for all tests — uses entirely fictional data."""

import pytest
from pathlib import Path

from flightforms.api.models import (
    AircraftData,
    ConnectingFlightData,
    FlightData,
    GenerateRequest,
    PersonData,
)
from flightforms.registry import FormMapping, MappingRegistry

# ── Paths ────────────────────────────────────────────────────────────────────
SRC_DIR = Path(__file__).parent.parent / "src" / "flightforms"
TEMPLATES_DIR = SRC_DIR / "templates"
MAPPINGS_DIR = SRC_DIR / "mappings"


# ── Fictional people ─────────────────────────────────────────────────────────
# All names, dates, ID numbers, and addresses are purely fictional.

def make_pilot() -> PersonData:
    return PersonData(
        function="Pilot",
        first_name="Zara",
        last_name="Kowalski",
        dob="1985-03-22",
        nationality="XYZ",
        id_number="PP-999001",
        id_type="Passport",
        id_issuing_country="XYZ",
        id_expiry="2030-06-15",
        sex="Female",
        place_of_birth="Northville",
        address="7 Birch Lane, Northville",
    )


def make_crew_member() -> PersonData:
    return PersonData(
        function="Crew",
        first_name="Tariq",
        last_name="Bergström",
        dob="1990-11-07",
        nationality="ABC",
        id_number="PP-999002",
        id_type="Passport",
        id_issuing_country="ABC",
        id_expiry="2029-01-20",
        sex="Male",
        place_of_birth="Easthaven",
    )


def make_passenger() -> PersonData:
    return PersonData(
        first_name="Lina",
        last_name="Petrova",
        dob="1978-08-14",
        nationality="DEF",
        id_number="ID-887766",
        id_type="Identity card",
        id_issuing_country="DEF",
        id_expiry="2028-12-31",
        sex="Female",
        place_of_birth="Westford",
        address="42 Maple Street, Westford",
    )


def make_second_passenger() -> PersonData:
    return PersonData(
        first_name="Nico",
        last_name="Tanaka",
        dob="2001-04-30",
        nationality="GHI",
        id_number="PP-112233",
        id_type="Passport",
        id_issuing_country="GHI",
        id_expiry="2031-09-01",
        sex="Male",
        place_of_birth="Southton",
    )


# ── Fictional aircraft ───────────────────────────────────────────────────────

def make_aircraft() -> AircraftData:
    return AircraftData(
        registration="ZZ-TST",
        type="FX99",
        owner="Skybird Holdings Ltd",
        owner_address="100 Cloud Ave, Airtown",
        is_airplane=True,
        usual_base="ZZZZ",
    )


# ── Fictional flight data ────────────────────────────────────────────────────

def make_flight(origin: str = "ZZZZ", destination: str = "ZZZZ") -> FlightData:
    return FlightData(
        origin=origin,
        destination=destination,
        departure_date="2099-06-15",
        departure_time_utc="08:30",
        arrival_date="2099-06-15",
        arrival_time_utc="10:45",
        nature="private",
        contact="+00-555-0199",
    )


def make_connecting_flight() -> ConnectingFlightData:
    return ConnectingFlightData(
        origin="ZZZZ",
        destination="YYYY",
        departure_date="2099-06-16",
        departure_time_utc="14:00",
        arrival_date="2099-06-16",
        arrival_time_utc="16:30",
    )


# ── Request builders ─────────────────────────────────────────────────────────

@pytest.fixture
def sample_request_lsgs() -> GenerateRequest:
    """A complete request targeting LSGS (PDF acroform)."""
    return GenerateRequest(
        airport="LSGS",
        form="lsgs",
        flight=make_flight(origin="ZZZZ", destination="LSGS"),
        aircraft=make_aircraft(),
        crew=[make_pilot()],
        passengers=[make_passenger()],
    )


@pytest.fixture
def sample_request_french(request) -> GenerateRequest:
    """A complete request targeting a French LF* airport (French customs PDF)."""
    return GenerateRequest(
        airport="LFAC",
        form="french_customs",
        flight=make_flight(origin="ZZZZ", destination="LFAC"),
        aircraft=make_aircraft(),
        crew=[make_pilot()],
        passengers=[make_passenger(), make_second_passenger()],
    )


@pytest.fixture
def sample_request_lfqa() -> GenerateRequest:
    """A complete request targeting LFQA (DOCX filler)."""
    return GenerateRequest(
        airport="LFQA",
        form="lfqa",
        flight=make_flight(origin="ZZZZ", destination="LFQA"),
        aircraft=make_aircraft(),
        crew=[make_pilot()],
        passengers=[make_passenger()],
    )


@pytest.fixture
def sample_request_gar() -> GenerateRequest:
    """A complete request targeting a UK EG* airport (XLSX filler)."""
    return GenerateRequest(
        airport="EGKA",
        form="gar",
        flight=make_flight(origin="ZZZZ", destination="EGKA"),
        aircraft=make_aircraft(),
        crew=[make_pilot(), make_crew_member()],
        passengers=[make_passenger()],
        extra_fields={
            "reason_for_visit": "Based",
            "responsible_person": {"name": "Zara Kowalski", "address": "7 Birch Lane"},
        },
    )


# ── Registry fixture ─────────────────────────────────────────────────────────

@pytest.fixture
def registry() -> MappingRegistry:
    return MappingRegistry(str(MAPPINGS_DIR), str(TEMPLATES_DIR))


# ── Stub airport resolver ────────────────────────────────────────────────────

class StubAirportResolver:
    """Deterministic resolver that returns fictional names without needing euro_aip DB."""

    _NAMES = {
        "LSGS": "Testville",
        "LFAC": "Plage-sur-Mer",
        "LFQA": "Champs-Dorés",
        "EGKA": "Greenwick",
        "ZZZZ": "Nowherton",
        "YYYY": "Farburg",
    }
    _COUNTRIES = {
        "LSGS": "Testland",
        "LFAC": "Republica",
        "LFQA": "Republica",
        "EGKA": "Islandia",
        "ZZZZ": "Nomania",
        "YYYY": "Farlandia",
    }

    def get_name(self, icao: str) -> str:
        return self._NAMES.get(icao, icao)

    def get_country(self, icao: str) -> str:
        return self._COUNTRIES.get(icao, "")

    def get_country_code(self, icao: str) -> str:
        return ""


@pytest.fixture
def resolver() -> StubAirportResolver:
    return StubAirportResolver()
