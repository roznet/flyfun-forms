"""Tests for validation.validate_request."""

import pytest

from flightforms.api.models import GenerateRequest, PersonData
from flightforms.registry import FormMapping
from flightforms.validation import validate_request
from tests.conftest import (
    make_aircraft,
    make_crew_member,
    make_flight,
    make_passenger,
    make_pilot,
)


def _mapping_with(**overrides) -> FormMapping:
    """Create a minimal FormMapping for validation tests."""
    data = {
        "template": "test.pdf",
        "type": "pdf_acroform",
        "max_crew": 4,
        "max_passengers": 8,
        "extra_fields": [],
        "required_fields": {
            "flight": ["origin", "destination"],
            "aircraft": ["registration"],
            "crew": ["first_name", "last_name"],
            "passengers": ["first_name", "last_name"],
        },
    }
    data.update(overrides)
    return FormMapping(data, "test")


def _request(**overrides) -> GenerateRequest:
    defaults = dict(
        airport="ZZZZ",
        form="test",
        flight=make_flight(origin="YYYY", destination="ZZZZ"),
        aircraft=make_aircraft(),
        crew=[make_pilot()],
        passengers=[make_passenger()],
    )
    defaults.update(overrides)
    return GenerateRequest(**defaults)


# ── Valid request ─────────────────────────────────────────────────────────────

class TestValidRequest:
    def test_valid_arrival(self):
        errors = validate_request(_request(), _mapping_with())
        assert errors == []

    def test_valid_departure(self):
        req = _request(
            airport="YYYY",
            flight=make_flight(origin="YYYY", destination="ZZZZ"),
        )
        errors = validate_request(req, _mapping_with())
        assert errors == []


# ── Airport direction ─────────────────────────────────────────────────────────

class TestAirportDirection:
    def test_airport_not_in_route(self):
        req = _request(airport="XXXX")
        errors = validate_request(req, _mapping_with())
        assert any(e.field == "airport" for e in errors)


# ── Crew / passenger counts ──────────────────────────────────────────────────

class TestCounts:
    def test_crew_exceeds_max(self):
        req = _request(crew=[make_pilot()] * 5)
        errors = validate_request(req, _mapping_with(max_crew=2))
        assert any(e.field == "crew" for e in errors)

    def test_passengers_exceeds_max(self):
        req = _request(passengers=[make_passenger()] * 10)
        errors = validate_request(req, _mapping_with(max_passengers=3))
        assert any(e.field == "passengers" for e in errors)

    def test_exact_max_is_ok(self):
        req = _request(crew=[make_pilot()] * 4)
        errors = validate_request(req, _mapping_with(max_crew=4))
        assert not any(e.field == "crew" for e in errors)


# ── Required fields ──────────────────────────────────────────────────────────

class TestRequiredFields:
    def test_missing_flight_field(self):
        flight = make_flight(origin="YYYY", destination="ZZZZ")
        flight.departure_date = ""
        req = _request(flight=flight)
        mapping = _mapping_with(required_fields={
            "flight": ["origin", "departure_date"],
            "aircraft": [],
            "crew": [],
            "passengers": [],
        })
        errors = validate_request(req, mapping)
        assert any(e.field == "flight.departure_date" for e in errors)

    def test_missing_aircraft_field(self):
        from flightforms.api.models import AircraftData
        aircraft = AircraftData(registration="", type="FX99")
        req = _request(aircraft=aircraft)
        errors = validate_request(req, _mapping_with())
        assert any(e.field == "aircraft.registration" for e in errors)

    def test_missing_crew_field(self):
        crew = PersonData(first_name="Zara", last_name="")
        req = _request(crew=[crew])
        errors = validate_request(req, _mapping_with())
        assert any("crew[0].last_name" in e.field for e in errors)

    def test_missing_passenger_field(self):
        pax = PersonData(first_name="", last_name="Petrova")
        req = _request(passengers=[pax])
        errors = validate_request(req, _mapping_with())
        assert any("passengers[0].first_name" in e.field for e in errors)

    def test_no_required_fields_section(self):
        """Mapping with empty required_fields should pass anything."""
        req = _request()
        mapping = _mapping_with(required_fields={})
        errors = validate_request(req, mapping)
        # Only airport direction could fail, and it won't here
        assert errors == []


# ── Extra fields ─────────────────────────────────────────────────────────────

class TestExtraFields:
    def test_missing_required_extra_text(self):
        mapping = _mapping_with(extra_fields=[
            {"key": "remarks", "type": "text", "required": True},
        ])
        req = _request()
        errors = validate_request(req, mapping)
        assert any(e.field == "extra_fields.remarks" for e in errors)

    def test_choice_wrong_option(self):
        mapping = _mapping_with(extra_fields=[
            {"key": "reason", "type": "choice", "options": ["Alpha", "Beta"], "required": True},
        ])
        req = _request(extra_fields={"reason": "Gamma"})
        errors = validate_request(req, mapping)
        assert any(e.field == "extra_fields.reason" for e in errors)

    def test_choice_valid_option(self):
        mapping = _mapping_with(extra_fields=[
            {"key": "reason", "type": "choice", "options": ["Alpha", "Beta"], "required": True},
        ])
        req = _request(extra_fields={"reason": "Alpha"})
        errors = validate_request(req, mapping)
        assert not any(e.field == "extra_fields.reason" for e in errors)

    def test_person_missing_name(self):
        mapping = _mapping_with(extra_fields=[
            {"key": "contact", "type": "person", "required": True},
        ])
        req = _request(extra_fields={"contact": {"address": "42 Street"}})
        errors = validate_request(req, mapping)
        assert any(e.field == "extra_fields.contact" for e in errors)

    def test_person_valid(self):
        mapping = _mapping_with(extra_fields=[
            {"key": "contact", "type": "person", "required": True},
        ])
        req = _request(extra_fields={"contact": {"name": "Zara K", "address": "42 St"}})
        errors = validate_request(req, mapping)
        assert not any(e.field == "extra_fields.contact" for e in errors)

    def test_optional_extra_not_required(self):
        mapping = _mapping_with(extra_fields=[
            {"key": "notes", "type": "text", "required": False},
        ])
        req = _request()
        errors = validate_request(req, mapping)
        assert not any(e.field == "extra_fields.notes" for e in errors)
