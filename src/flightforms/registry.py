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
        self.filler_type = data["type"]  # pdf_acroform, docx, xlsx, web_form
        # Web forms have no template: they describe an official web page
        # instead, which the client opens and prefills from a fill plan.
        self.template = data.get("template") if self.is_web_form else data["template"]
        # "departure" / "arrival" pins a form to one side of the flight (a
        # book-out only makes sense when leaving); None means either.
        self.direction: Optional[str] = data.get("direction")
        self.version = data.get("version", "1.0")
        self.label = data.get("label", mapping_id)
        self.time_reference = data.get("time_reference", "utc")
        self.time_zone = data.get("time_zone")
        self.date_format = data.get("date_format", "%d/%m/%Y")
        self.time_format = data.get("time_format", "HH:MM")
        self.default_observations = data.get("default_observations")
        self.extra_fields = data.get("extra_fields", [])
        self.has_connecting_flight = data.get("has_connecting_flight", False)
        self.has_return_flight = data.get("has_return_flight", False)
        self.max_crew = data.get("max_crew", 4)
        self.max_passengers = data.get("max_passengers", 8)
        self.send_to = data.get("send_to")
        self.checkbox_on = data.get("checkbox_on", "/Yes")
        self.checkbox_off = data.get("checkbox_off", "/Off")
        self.preferred_prefix: Optional[str] = data.get("preferred_prefix")
        self.email_overrides: dict = data.get("email_overrides", {})
        self.email_templates: dict = data.get("email_templates", {})
        # Per-airport e-mails generated from the AIP (scripts/sync_aip_emails.py);
        # the registry fills them in from the "email_lookup" file.
        self.email_lookup: Optional[str] = data.get("email_lookup")
        self.lookup_emails: dict = {}

    def email_for(self, icao: str) -> Optional[dict]:
        """Where to send this form for *icao*: ``{"to", "cc", "subject"}``, or None.

        Layers, each replacing only the keys it sets: the form-level
        ``send_to``, then the AIP-generated lookup, then the hand-written
        ``email_overrides`` (for airports whose AIP names no address).
        """
        email: dict = {"to": [self.send_to] if self.send_to else [], "cc": [], "subject": None}
        for layer in (self.lookup_emails.get(icao, {}), self.email_overrides.get(icao, {})):
            for key in ("to", "cc"):
                if key in layer:
                    email[key] = layer[key] if isinstance(layer[key], list) else [layer[key]]
            if "subject" in layer:
                email["subject"] = layer["subject"]
        if not email["to"] and not email["cc"]:
            return None
        return email

    @property
    def required_fields(self) -> dict:
        return self.raw.get("required_fields", {})

    @property
    def is_web_form(self) -> bool:
        return self.filler_type == "web_form"

    def web_url(self, icao: str) -> str:
        """The web form's page URL for *icao*.

        ``url`` may hold ``{icao}`` and ``{site}`` placeholders so one mapping
        serves every airport running the same system (e.g. RedAtlas at
        ``https://{site}.redatlas.co.uk/...``).  ``site`` defaults to the
        lower-cased ICAO; ``sites`` overrides it per airport.
        """
        site = self.raw.get("sites", {}).get(icao, icao.lower())
        return self.raw["url"].format(icao=icao, site=site)


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
            "Veuillez trouver ci-joint le formulaire de pr\u00e9avis de vol pour :\n\n"
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
            if mapping.email_lookup:
                mapping.lookup_emails = self._load_email_lookup(mapping.email_lookup)
            if mapping.icao:
                self._by_icao.setdefault(mapping.icao, []).append(mapping)
            elif mapping.icao_list:
                for icao in mapping.icao_list:
                    self._by_icao.setdefault(icao, []).append(mapping)
            elif mapping.icao_prefix:
                self._by_prefix.setdefault(mapping.icao_prefix, []).append(mapping)
            elif mapping.is_default:
                self._defaults.append(mapping)

    def _load_email_lookup(self, filename: str) -> dict:
        path = (self.mappings_dir / filename).resolve()
        if not path.is_relative_to(self.mappings_dir.resolve()):
            raise ValueError("Invalid email_lookup path")
        with open(path) as f:
            return json.load(f)["airports"]

    def get_forms_for_airport(self, icao: str) -> list[FormMapping]:
        """Get all form mappings for an airport.

        Order: forms written for this one airport (``icao``); then, among
        ``icao_list`` and prefix matches, those holding an e-mail for the
        airport — the AIP says that is how to notify customs there, so the
        form to send outranks one that merely lists the airport (LFOH's
        customs notice before myhandling; LFMD, with no address, keeps
        myhandling first); then the remaining ``icao_list`` matches, then
        prefix matches, then defaults.  Among defaults, forms whose
        preferred_prefix matches the airport are sorted first.
        """
        seen_ids: set[str] = set()
        result: list[FormMapping] = []

        exact: list[FormMapping] = []
        listed: list[FormMapping] = []
        for m in self._by_icao.get(icao, []):
            (exact if m.icao == icao else listed).append(m)
        prefixed = [
            m for prefix, mappings in self._by_prefix.items()
            if icao.startswith(prefix) for m in mappings
        ]
        with_email = [m for m in listed + prefixed if m.email_for(icao)]
        without_email = [m for m in listed + prefixed if not m.email_for(icao)]

        for m in exact + with_email + without_email:
            if m.id not in seen_ids:
                result.append(m)
                seen_ids.add(m.id)

        # Defaults: preferred match first, then no-preference, then non-matching
        preferred = []
        no_pref = []
        non_matching = []
        for m in self._defaults:
            if m.id in seen_ids:
                continue
            if m.preferred_prefix and icao.startswith(m.preferred_prefix):
                preferred.append(m)
            elif not m.preferred_prefix:
                no_pref.append(m)
            else:
                non_matching.append(m)
        result.extend(preferred)
        result.extend(no_pref)
        result.extend(non_matching)

        return result

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
