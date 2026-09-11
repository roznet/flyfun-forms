"""Tests for web-form fill plans (book-out, PPR, out-of-hours)."""

from flightforms.api.models import ConnectingFlightData, GenerateRequest, ReturnFlightData
from flightforms.fillers.web_form import build_fill_plan
from flightforms.registry import FormMapping
from flightforms.validation import validate_request
from tests.conftest import make_aircraft, make_flight, make_passenger, make_pilot

CONTACT = {"telephone": "+00 555 0199", "email": "zara@example.invalid"}


def _request(form: str, origin: str, destination: str, **kwargs) -> GenerateRequest:
    return GenerateRequest(
        airport="EGTF",
        form=form,
        flight=make_flight(origin=origin, destination=destination),
        aircraft=make_aircraft(),
        crew=[make_pilot()],
        passengers=[make_passenger()],
        extra_fields=dict(CONTACT),
        **kwargs,
    )


def _values(plan) -> dict[str, str]:
    return {f.name: f.value for f in plan.fields}


class TestWebFormMapping:
    def test_site_defaults_to_icao(self):
        m = FormMapping({"type": "web_form", "url": "https://{site}.example.invalid/{icao}"}, "w")
        assert m.is_web_form
        assert m.template is None
        assert m.web_url("EGXX") == "https://egxx.example.invalid/EGXX"

    def test_site_override(self):
        m = FormMapping({
            "type": "web_form",
            "url": "https://{site}.example.invalid/",
            "sites": {"EGXX": "other"},
        }, "w")
        assert m.web_url("EGXX") == "https://other.example.invalid/"


class TestRedAtlasBookout:
    def test_departure_plan(self, registry, resolver):
        mapping = registry.get_form("EGTF", "redatlas_bookout")
        plan = build_fill_plan(mapping, _request("redatlas_bookout", "EGTF", "ZZZZ"), resolver)
        assert plan.url == "https://egtf.redatlas.co.uk/public/bookout?embedded=true"
        assert plan.scope is None
        assert _values(plan) == {
            "Registration": "ZZ-TST",
            "AircraftType": "FX99",
            "MovementDate": "2099-06-15",
            "MovementTime": "08:30",
            "DestinationAirfield": "ZZZZ",
            "PeopleOnBoard": "2",
            "PilotName": "Zara Kowalski",
            "Telephone": "+00 555 0199",
            "EmailAddress": "zara@example.invalid",
        }

    def test_return_flight(self, registry, resolver):
        back = ReturnFlightData(
            origin="LFRM", destination="EGTF",
            departure_date="2099-06-16", departure_time_utc="15:00",
            arrival_date="2099-06-16", arrival_time_utc="16:30",
            people_on_board=3,
        )
        request = _request("redatlas_bookout", "EGTF", "LFRM", return_flight=back)
        plan = build_fill_plan(registry.get_form("EGTF", "redatlas_bookout"), request, resolver)
        fields = [(f.name, f.value, f.type) for f in plan.fields]
        returning = fields.index(("Returning", "true", "checkbox"))
        # The tick box enables RedAtlas's return inputs, so it must come first
        assert fields[returning + 1:] == [
            ("ReturnDate", "2099-06-16", "text"),
            ("ReturnTime", "16:30", "text"),
            ("ReturnAirfield", "LFRM", "text"),
            ("ReturnPeopleOnBoard", "3", "text"),
        ]

    def test_return_without_times_is_dropped(self):
        request = GenerateRequest.model_validate({
            **_request("redatlas_bookout", "EGTF", "LFRM").model_dump(),
            "return_flight": {
                "origin": "LFRM", "destination": "EGTF",
                "departure_date": "2099-06-16", "departure_time_utc": "",
                "arrival_date": "2099-06-16", "arrival_time_utc": "",
            },
        })
        assert request.return_flight is None

    def test_local_flight_uses_departure_side(self, registry, resolver):
        # Origin == destination: the airport alone would read as an arrival
        mapping = registry.get_form("EGTF", "redatlas_bookout")
        values = _values(build_fill_plan(mapping, _request("redatlas_bookout", "EGTF", "EGTF"), resolver))
        assert values["MovementTime"] == "08:30"
        assert values["DestinationAirfield"] == "EGTF"

    def test_missing_data_is_left_to_the_page(self, registry, resolver):
        request = _request("redatlas_bookout", "EGTF", "ZZZZ")
        request.crew = []
        request.extra_fields = None
        mapping = registry.get_form("EGTF", "redatlas_bookout")
        values = _values(build_fill_plan(mapping, request, resolver))
        assert "PilotName" not in values
        assert "Telephone" not in values
        assert values["PeopleOnBoard"] == "1"

    def test_rejects_arrivals(self, registry):
        mapping = registry.get_form("EGTF", "redatlas_bookout")
        errors = validate_request(_request("redatlas_bookout", "ZZZZ", "EGTF"), mapping)
        assert [e.field for e in errors] == ["airport"]


class TestRedAtlasPpr:
    def test_arrival_plan_with_departure_estimate(self, registry, resolver):
        next_leg = ConnectingFlightData(
            origin="EGTF", destination="YYYY",
            departure_date="2099-06-16", departure_time_utc="14:00",
            arrival_date="2099-06-16", arrival_time_utc="16:30",
        )
        request = _request("redatlas_ppr", "ZZZZ", "EGTF", connecting_flight=next_leg)
        plan = build_fill_plan(registry.get_form("EGTF", "redatlas_ppr"), request, resolver)
        assert plan.url == "https://egtf.redatlas.co.uk/public/ppr?embedded=true"
        values = _values(plan)
        assert values["MovementDate"] == "2099-06-15"
        assert values["MovementTime"] == "10:45"
        assert values["AirfieldOfDeparture"] == "ZZZZ"
        assert values["AdditionalFields[0].ValueString"] == "2099-06-16 14:00 UTC"

    def test_no_next_leg_skips_estimate(self, registry, resolver):
        request = _request("redatlas_ppr", "ZZZZ", "EGTF")
        values = _values(build_fill_plan(registry.get_form("EGTF", "redatlas_ppr"), request, resolver))
        assert "AdditionalFields[0].ValueString" not in values


class TestFairoaksOutOfHours:
    def test_departure_in_local_time(self, registry, resolver):
        mapping = registry.get_form("EGTF", "egtf_ooh_departure")
        plan = build_fill_plan(mapping, _request("egtf_ooh_departure", "EGTF", "ZZZZ"), resolver)
        assert plan.url == "https://fairoaksairport.uk/out-of-hours-form/"
        assert '"38ad142"' in plan.scope
        values = _values(plan)
        # 08:30Z in June is 09:30 BST
        assert values["form_fields[field_1e1fbe4]"] == "09:30"
        assert values["form_fields[field_9b84682]"] == "2099-06-15"
        assert values["form_fields[field_14c7462]"] == "ZZZZ"
        assert values["form_fields[field_4]"] == "ZZ-TST"
        # The form's phone pattern rejects spaces
        assert values["form_fields[field_ef30f49]"] == "+005550199"

    def test_arrival_targets_second_form(self, registry, resolver):
        mapping = registry.get_form("EGTF", "egtf_ooh_arrival")
        plan = build_fill_plan(mapping, _request("egtf_ooh_arrival", "ZZZZ", "EGTF"), resolver)
        assert '"4793b1f"' in plan.scope
        values = _values(plan)
        assert values["form_fields[field_1e1fbe4]"] == "11:45"
        assert values["form_fields[field_7fca82e]"] == "2099-06-15"
        assert values["form_fields[field_14c7462]"] == "ZZZZ"
