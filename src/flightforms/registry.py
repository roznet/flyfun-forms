"""Mapping registry: discovers and loads form mappings from JSON files."""

import json
import os
from pathlib import Path
from typing import Optional


class FormMapping:
    """A single form mapping configuration loaded from JSON."""

    def __init__(self, data: dict, mapping_id: str):
        self.id = mapping_id
        self.raw = data
        self.icao: Optional[str] = data.get("icao")
        self.icao_list: list[str] = data.get("icao_list", [])
        self.icao_prefix: Optional[str] = data.get("icao_prefix")
        self.is_default: bool = data.get("default", False)
        self.template = data["template"]
        self.filler_type = data["type"]  # pdf_acroform, docx, xlsx
        self.version = data.get("version", "1.0")
        self.label = data.get("label", mapping_id)
        self.time_reference = data.get("time_reference", "utc")
        self.time_zone = data.get("time_zone")
        self.date_format = data.get("date_format", "%d/%m/%Y")
        self.time_format = data.get("time_format", "HH:MM")
        self.default_observations = data.get("default_observations")
        self.extra_fields = data.get("extra_fields", [])
        self.has_connecting_flight = data.get("has_connecting_flight", False)
        self.max_crew = data.get("max_crew", 4)
        self.max_passengers = data.get("max_passengers", 8)
        self.send_to = data.get("send_to")
        self.checkbox_on = data.get("checkbox_on", "/Yes")
        self.checkbox_off = data.get("checkbox_off", "/Off")
        self.email_overrides: dict = data.get("email_overrides", {})
        self.email_templates: dict = data.get("email_templates", {})

    @property
    def required_fields(self) -> dict:
        return self.raw.get("required_fields", {})


DEFAULT_EMAIL_TEMPLATES = {
    "en": {
        "subject": "{form_label} - {airport} - {date} - {registration}",
        "body": (
            "Dear Sir or Madam,\n\n"
            "Please find attached the {form_label} for the following flight:\n\n"
            "  Route: {origin} \u2192 {destination}\n"
            "  Date: {date}\n"
            "  Aircraft: {registration}\n\n"
            "Kind regards"
        ),
    },
    "fr": {
        "subject": "{form_label} - {airport} - {date} - {registration}",
        "body": (
            "Bonjour,\n\n"
            "Veuillez trouver ci-joint le {form_label} pour le vol suivant :\n\n"
            "  Trajet : {origin} \u2192 {destination}\n"
            "  Date : {date}\n"
            "  A\u00e9ronef : {registration}\n\n"
            "Cordialement"
        ),
    },
    "de": {
        "subject": "{form_label} - {airport} - {date} - {registration}",
        "body": (
            "Sehr geehrte Damen und Herren,\n\n"
            "anbei finden Sie das {form_label} f\u00fcr folgenden Flug:\n\n"
            "  Strecke: {origin} \u2192 {destination}\n"
            "  Datum: {date}\n"
            "  Luftfahrzeug: {registration}\n\n"
            "Mit freundlichen Gr\u00fc\u00dfen"
        ),
    },
    "es": {
        "subject": "{form_label} - {airport} - {date} - {registration}",
        "body": (
            "Estimado/a,\n\n"
            "Adjunto el {form_label} para el siguiente vuelo:\n\n"
            "  Ruta: {origin} \u2192 {destination}\n"
            "  Fecha: {date}\n"
            "  Aeronave: {registration}\n\n"
            "Un cordial saludo"
        ),
    },
    "it": {
        "subject": "{form_label} - {airport} - {date} - {registration}",
        "body": (
            "Gentilissimi,\n\n"
            "in allegato il {form_label} per il seguente volo:\n\n"
            "  Rotta: {origin} \u2192 {destination}\n"
            "  Data: {date}\n"
            "  Aeromobile: {registration}\n\n"
            "Cordiali saluti"
        ),
    },
}


class MappingRegistry:
    """Discovers and indexes form mappings from a directory of JSON files."""

    def __init__(self, mappings_dir: str, templates_dir: str):
        self.mappings_dir = Path(mappings_dir)
        self.templates_dir = Path(templates_dir)
        # icao -> list of FormMapping (exact match)
        self._by_icao: dict[str, list[FormMapping]] = {}
        # prefix -> list of FormMapping (fallback)
        self._by_prefix: dict[str, list[FormMapping]] = {}
        # default mappings (catch-all when no icao or prefix match)
        self._defaults: list[FormMapping] = []
        self._load_all()

    def _load_all(self):
        if not self.mappings_dir.exists():
            return
        for path in sorted(self.mappings_dir.glob("*.json")):
            if ".lookup." in path.name:
                continue  # Skip lookup data files (e.g. myhandling_fbos.lookup.json)
            with open(path) as f:
                data = json.load(f)
            mapping_id = path.stem
            mapping = FormMapping(data, mapping_id)
            if mapping.icao:
                self._by_icao.setdefault(mapping.icao, []).append(mapping)
            elif mapping.icao_list:
                for icao in mapping.icao_list:
                    self._by_icao.setdefault(icao, []).append(mapping)
            elif mapping.icao_prefix:
                self._by_prefix.setdefault(mapping.icao_prefix, []).append(mapping)
            elif mapping.is_default:
                self._defaults.append(mapping)

    def get_forms_for_airport(self, icao: str) -> list[FormMapping]:
        """Get all form mappings for an airport.

        Combines exact ICAO matches with prefix matches.  Falls back to
        defaults only when neither exact nor prefix matches exist.
        """
        result = list(self._by_icao.get(icao, []))
        for prefix, mappings in self._by_prefix.items():
            if icao.startswith(prefix):
                result.extend(mappings)
        return result if result else self._defaults

    def get_form(self, icao: str, form_id: str) -> Optional[FormMapping]:
        """Get a specific form mapping by airport and form ID."""
        for mapping in self.get_forms_for_airport(icao):
            if mapping.id == form_id:
                return mapping
        return None

    def get_template_path(self, mapping: FormMapping) -> Path:
        path = (self.templates_dir / mapping.template).resolve()
        if not path.is_relative_to(self.templates_dir.resolve()):
            raise ValueError("Invalid template path")
        return path

    def all_airports(self) -> dict[str, list[FormMapping]]:
        """Return all airports with specific mappings."""
        return dict(self._by_icao)

    def all_prefixes(self) -> dict[str, list[FormMapping]]:
        """Return all prefix-level mappings."""
        return dict(self._by_prefix)

    def all_defaults(self) -> list[FormMapping]:
        """Return all default (catch-all) mappings."""
        return list(self._defaults)

    def get_email_template(self, mapping: FormMapping, lang: str) -> dict[str, str]:
        """Return {"subject": ..., "body": ...} for the given language.

        Priority: mapping-specific -> global default -> English fallback.
        """
        if lang in mapping.email_templates:
            return mapping.email_templates[lang]
        if lang in DEFAULT_EMAIL_TEMPLATES:
            return DEFAULT_EMAIL_TEMPLATES[lang]
        return mapping.email_templates.get("en", DEFAULT_EMAIL_TEMPLATES["en"])
