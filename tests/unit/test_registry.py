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

    def test_aip_email_puts_customs_before_handling(self, registry):
        """LFOH's AIP says to e-mail customs: the customs notice comes first."""
        forms = [f.id for f in registry.get_forms_for_airport("LFOH")]
        assert forms[:2] == ["french_customs", "myhandling"]

    def test_no_aip_email_keeps_handling_first(self, registry):
        """LFMD's AIP says only "On request"; LFOT's says "Via My Handling"."""
        for icao in ("LFMD", "LFOT"):
            forms = [f.id for f in registry.get_forms_for_airport(icao)]
            assert forms[:2] == ["myhandling", "french_customs"], icao

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


# ── Per-airport e-mail and the order it sets ─────────────────────────────────

def _write_registry(tmp_path, mappings: dict, lookup: dict | None = None) -> MappingRegistry:
    mappings_dir = tmp_path / "mappings"
    templates_dir = tmp_path / "templates"
    mappings_dir.mkdir()
    templates_dir.mkdir()
    for name, data in mappings.items():
        (mappings_dir / f"{name}.json").write_text(json.dumps(data))
    if lookup is not None:
        (mappings_dir / "emails.lookup.json").write_text(json.dumps({"airports": lookup}))
    return MappingRegistry(str(mappings_dir), str(templates_dir))


class TestEmailFor:
    def test_layers_send_to_then_lookup_then_override(self, tmp_path):
        reg = _write_registry(tmp_path, {
            "customs": {
                "icao_prefix": "ZZ", "template": "t.pdf", "type": "pdf_acroform",
                "send_to": "default@example.com",
                "email_lookup": "emails.lookup.json",
                "email_overrides": {"ZZBB": {"cc": ["hand@example.com"]}},
            },
        }, lookup={
            "ZZAA": {"to": ["aip@example.com"], "cc": ["aip-cc@example.com"], "subject": "ppf zzaa"},
            "ZZBB": {"to": ["aip@example.com"], "cc": ["aip-cc@example.com"]},
        })
        m = reg.get_form("ZZAA", "customs")
        assert m.email_for("ZZAA") == {
            "to": ["aip@example.com"], "cc": ["aip-cc@example.com"], "subject": "ppf zzaa",
        }
        # The hand-written override replaces only the key it sets
        assert m.email_for("ZZBB") == {
            "to": ["aip@example.com"], "cc": ["hand@example.com"], "subject": None,
        }
        assert m.email_for("ZZCC") == {"to": ["default@example.com"], "cc": [], "subject": None}

    def test_no_address_is_none(self, tmp_path):
        reg = _write_registry(tmp_path, {
            "handling": {"icao_list": ["ZZAA"], "template": "t.xlsx", "type": "xlsx"},
        })
        assert reg.get_form("ZZAA", "handling").email_for("ZZAA") is None

    def test_lookup_outside_mappings_dir_rejected(self, tmp_path):
        with pytest.raises(ValueError):
            _write_registry(tmp_path, {
                "customs": {"icao_prefix": "ZZ", "template": "t.pdf", "type": "pdf_acroform",
                            "email_lookup": "../outside.lookup.json"},
            })


class TestEmailOrdering:
    def _registry(self, tmp_path):
        return _write_registry(tmp_path, {
            "airport": {"icao": "ZZAA", "template": "t.pdf", "type": "pdf_acroform"},
            "handling": {"icao_list": ["ZZAA", "ZZBB"], "template": "t.xlsx", "type": "xlsx"},
            "customs": {"icao_prefix": "ZZ", "template": "t.pdf", "type": "pdf_acroform",
                        "email_lookup": "emails.lookup.json"},
            "fallback": {"default": True, "template": "t.pdf", "type": "pdf_acroform"},
        }, lookup={"ZZAA": {"to": ["c@example.com"], "cc": []}})

    def test_form_with_email_outranks_listed_form(self, tmp_path):
        forms = [f.id for f in self._registry(tmp_path).get_forms_for_airport("ZZAA")]
        # The airport's own form stays first
        assert forms == ["airport", "customs", "handling", "fallback"]

    def test_without_email_listed_form_first(self, tmp_path):
        forms = [f.id for f in self._registry(tmp_path).get_forms_for_airport("ZZBB")]
        assert forms == ["handling", "customs", "fallback"]
