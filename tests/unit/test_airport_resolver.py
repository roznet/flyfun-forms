"""Tests for AirportResolver — prefix-based fallback (no euro_aip DB needed)."""

import pytest

from flightforms.airport_resolver import AirportResolver, PREFIX_COUNTRIES, _COUNTRY_NAMES


class TestAirportResolverWithoutDB:
    """Tests that work without the euro_aip database (resolver falls back gracefully)."""

    @pytest.fixture
    def resolver(self):
        # Point to a non-existent DB so it uses prefix fallback
        return AirportResolver(airports_db_path="/nonexistent/path.db")

    def test_get_name_unknown_returns_icao(self, resolver):
        assert resolver.get_name("ZZZZ") == "ZZZZ"

    def test_get_country_prefix_fallback(self, resolver):
        assert resolver.get_country("LFXX") == "France"
        assert resolver.get_country("EGXX") == "United Kingdom"
        assert resolver.get_country("LSXX") == "Switzerland"

    def test_get_country_unknown_prefix(self, resolver):
        assert resolver.get_country("ZZZZ") == ""

    def test_get_country_code_unknown(self, resolver):
        assert resolver.get_country_code("ZZZZ") == ""


class TestPrefixCountriesMapping:
    def test_known_prefixes(self):
        assert PREFIX_COUNTRIES["LF"] == "France"
        assert PREFIX_COUNTRIES["EG"] == "United Kingdom"
        assert PREFIX_COUNTRIES["LS"] == "Switzerland"
        assert PREFIX_COUNTRIES["ED"] == "Germany"

    def test_country_names(self):
        assert _COUNTRY_NAMES["FR"] == "France"
        assert _COUNTRY_NAMES["GB"] == "United Kingdom"
        assert _COUNTRY_NAMES["CH"] == "Switzerland"


class TestLanguageResolution:
    """Per-airport overrides take precedence over country-level mapping."""

    @pytest.fixture
    def resolver(self):
        return AirportResolver(airports_db_path="/nonexistent/path.db")

    def test_swiss_french_airports_override_to_fr(self, resolver):
        # Without override, the LS prefix → CH → de.
        for icao in ("LSGG", "LSGS", "LSGL", "LSGN"):
            assert resolver.get_language_code(icao) == "fr", icao

    def test_swiss_italian_airports_override_to_it(self, resolver):
        for icao in ("LSZA", "LSZL"):
            assert resolver.get_language_code(icao) == "it", icao

    def test_swiss_german_airport_falls_back_to_country(self, resolver):
        # No override → CH → de via prefix fallback (no euro_aip DB here).
        assert resolver.get_language_code("LSZH") == "de"  # Zurich

    def test_french_airport_unaffected(self, resolver):
        assert resolver.get_language_code("LFPG") == "fr"  # CDG

    def test_unknown_airport_returns_empty(self, resolver):
        assert resolver.get_language_code("ZZZZ") == ""
