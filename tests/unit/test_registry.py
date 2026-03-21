"""Tests for FormMapping and MappingRegistry."""

import json
import tempfile
from pathlib import Path

import pytest

from flightforms.registry import FormMapping, MappingRegistry
from tests.conftest import MAPPINGS_DIR, TEMPLATES_DIR


# ── FormMapping construction ─────────────────────────────────────────────────

class TestFormMapping:
    def test_from_icao_mapping(self):
        data = {
            "icao": "ZZZZ",
            "template": "test.pdf",
            "type": "pdf_acroform",
            "max_crew": 5,
            "max_passengers": 12,
            "label": "Test Form",
        }
        m = FormMapping(data, "test_form")
        assert m.id == "test_form"
        assert m.icao == "ZZZZ"
        assert m.icao_prefix is None
        assert m.template == "test.pdf"
        assert m.filler_type == "pdf_acroform"
        assert m.max_crew == 5
        assert m.max_passengers == 12

    def test_from_prefix_mapping(self):
        data = {
            "icao_prefix": "ZZ",
            "template": "test.xlsx",
            "type": "xlsx",
        }
        m = FormMapping(data, "test_prefix")
        assert m.icao is None
        assert m.icao_prefix == "ZZ"

    def test_defaults(self):
        data = {"template": "t.pdf", "type": "pdf_acroform"}
        m = FormMapping(data, "defaults")
        assert m.version == "1.0"
        assert m.max_crew == 4
        assert m.max_passengers == 8
        assert m.checkbox_on == "/Yes"
        assert m.checkbox_off == "/Off"
        assert m.time_reference == "utc"
        assert m.extra_fields == []
        assert m.has_connecting_flight is False

    def test_required_fields(self):
        data = {
            "template": "t.pdf",
            "type": "pdf_acroform",
            "required_fields": {"flight": ["origin"], "crew": ["last_name"]},
        }
        m = FormMapping(data, "req")
        assert m.required_fields["flight"] == ["origin"]
        assert m.required_fields["crew"] == ["last_name"]


# ── MappingRegistry ──────────────────────────────────────────────────────────

class TestMappingRegistry:
    def test_loads_real_mappings(self, registry: MappingRegistry):
        """Ensure the production mappings directory loads without error."""
        airports = registry.all_airports()
        prefixes = registry.all_prefixes()
        # We expect at least our known airports and prefixes
        assert "LSGS" in airports
        assert "LFQA" in airports
        assert "LF" in prefixes
        assert "EG" in prefixes

    def test_exact_icao_match(self, registry):
        forms = registry.get_forms_for_airport("LSGS")
        assert len(forms) >= 1
        assert forms[0].id == "lsgs"

    def test_prefix_fallback(self, registry):
        """An LF airport should include french_customs via prefix match."""
        forms = registry.get_forms_for_airport("LFOH")
        form_ids = [f.id for f in forms]
        assert "french_customs" in form_ids

    def test_prefix_fallback_eg(self, registry):
        forms = registry.get_forms_for_airport("EGLL")
        assert len(forms) >= 1
        assert forms[0].id == "gar"

    def test_unknown_airport_returns_default(self, registry):
        forms = registry.get_forms_for_airport("XXXX")
        assert len(forms) >= 1
        assert forms[0].id == "gendec_form"

    def test_get_form_by_id(self, registry):
        m = registry.get_form("LSGS", "lsgs")
        assert m is not None
        assert m.filler_type == "pdf_acroform"

    def test_get_form_returns_none_for_bad_id(self, registry):
        assert registry.get_form("LSGS", "nonexistent") is None

    def test_get_template_path(self, registry):
        m = registry.get_form("LSGS", "lsgs")
        path = registry.get_template_path(m)
        assert path.exists()
        assert path.suffix == ".pdf"

    def test_lfqa_exact_overrides_prefix(self, registry):
        """LFQA has an exact mapping that should take priority over LF prefix."""
        forms = registry.get_forms_for_airport("LFQA")
        assert any(f.id == "lfqa" for f in forms)

    def test_empty_directory(self, tmp_path):
        """Registry with empty dirs should work without errors."""
        mappings = tmp_path / "mappings"
        templates = tmp_path / "templates"
        mappings.mkdir()
        templates.mkdir()
        reg = MappingRegistry(str(mappings), str(templates))
        assert reg.all_airports() == {}
        assert reg.all_prefixes() == {}

    def test_custom_mapping(self, tmp_path):
        """Registry loads a custom JSON mapping."""
        mappings = tmp_path / "mappings"
        templates = tmp_path / "templates"
        mappings.mkdir()
        templates.mkdir()
        (mappings / "custom.json").write_text(json.dumps({
            "icao": "ZZZZ",
            "template": "custom.pdf",
            "type": "pdf_acroform",
        }))
        reg = MappingRegistry(str(mappings), str(templates))
        assert "ZZZZ" in reg.all_airports()
        forms = reg.get_forms_for_airport("ZZZZ")
        assert forms[0].id == "custom"
