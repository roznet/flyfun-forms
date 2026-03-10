"""Tests for Pydantic API models — serialization round-trips."""

import pytest

from flightforms.api.models import (
    AircraftData,
    AirportDetail,
    AirportInfo,
    AirportsResponse,
    ConnectingFlightData,
    FlightData,
    FormInfo,
    GenerateRequest,
    PersonData,
    PrefixInfo,
    ValidateResponse,
    ValidationError,
)
from tests.conftest import make_aircraft, make_flight, make_passenger, make_pilot


class TestPersonData:
    def test_minimal(self):
        p = PersonData(first_name="Zara", last_name="Kowalski")
        assert p.dob is None
        assert p.nationality is None
        assert p.function is None

    def test_full(self):
        p = make_pilot()
        d = p.model_dump()
        roundtrip = PersonData(**d)
        assert roundtrip.first_name == "Zara"
        assert roundtrip.id_number == "PP-999001"


class TestFlightData:
    def test_defaults(self):
        f = FlightData(
            origin="ZZZZ",
            destination="YYYY",
            departure_date="2099-01-01",
            departure_time_utc="08:00",
            arrival_date="2099-01-01",
            arrival_time_utc="10:00",
        )
        assert f.nature == "private"
        assert f.contact is None

    def test_roundtrip(self):
        f = make_flight()
        d = f.model_dump()
        f2 = FlightData(**d)
        assert f2.origin == f.origin


class TestGenerateRequest:
    def test_roundtrip(self):
        req = GenerateRequest(
            airport="ZZZZ",
            form="test",
            flight=make_flight(origin="YYYY", destination="ZZZZ"),
            aircraft=make_aircraft(),
            crew=[make_pilot()],
            passengers=[make_passenger()],
            extra_fields={"note": "test value"},
            observations="Fictional observation",
        )
        d = req.model_dump()
        req2 = GenerateRequest(**d)
        assert req2.airport == "ZZZZ"
        assert req2.crew[0].first_name == "Zara"
        assert req2.extra_fields["note"] == "test value"

    def test_minimal(self):
        req = GenerateRequest(
            airport="ZZZZ",
            form="test",
            flight=make_flight(),
            aircraft=make_aircraft(),
            crew=[PersonData(first_name="A", last_name="B")],
        )
        assert req.passengers == []
        assert req.connecting_flight is None
        assert req.extra_fields is None

    def test_with_connecting_flight(self):
        from tests.conftest import make_connecting_flight
        req = GenerateRequest(
            airport="ZZZZ",
            form="test",
            flight=make_flight(),
            aircraft=make_aircraft(),
            crew=[make_pilot()],
            connecting_flight=make_connecting_flight(),
        )
        assert req.connecting_flight.destination == "YYYY"

    def test_extra_fields_person_type(self):
        req = GenerateRequest(
            airport="ZZZZ",
            form="test",
            flight=make_flight(),
            aircraft=make_aircraft(),
            crew=[make_pilot()],
            extra_fields={"responsible": {"name": "Zara K", "address": "7 Birch Lane"}},
        )
        assert req.extra_fields["responsible"]["name"] == "Zara K"


class TestValidateResponse:
    def test_valid(self):
        r = ValidateResponse(valid=True)
        assert r.errors == []

    def test_with_errors(self):
        r = ValidateResponse(
            valid=False,
            errors=[ValidationError(field="crew[0].last_name", error="required for this form")],
        )
        assert len(r.errors) == 1
        assert r.errors[0].field == "crew[0].last_name"


class TestAirportsResponse:
    def test_structure(self):
        resp = AirportsResponse(
            airports=[AirportInfo(icao="ZZZZ", name="Nowherton", forms=["test"])],
            prefixes=[PrefixInfo(prefix="ZZ", country="Nomania", forms=["test"])],
        )
        assert resp.airports[0].icao == "ZZZZ"
        assert resp.prefixes[0].country == "Nomania"


class TestFormInfo:
    def test_structure(self):
        fi = FormInfo(
            id="test",
            label="Test Form",
            version="1.0",
            required_fields={"flight": ["origin"]},
            max_crew=4,
            max_passengers=8,
            has_connecting_flight=False,
            time_reference="utc",
        )
        assert fi.send_to is None
        assert fi.extra_fields == []
