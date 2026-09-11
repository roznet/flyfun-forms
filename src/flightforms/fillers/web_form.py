"""Web form fill plans: prefill an official airport web page instead of a file.

Some airports take movements through their own web forms (book-out, PPR,
out-of-hours).  Rather than posting to those forms ourselves, the client opens
the official page and fills it from a *fill plan*: the page URL plus a value
for each input, keyed by the input's ``name``.  Keying by name keeps the same
plan usable for a direct form submission later.
"""

import re

from ..api.models import FillField, FillPlan, GenerateRequest
from ..registry import FormMapping
from .pdf_filler import build_values

_PLACEHOLDER_RE = re.compile(r"\{([\w.\[\]]+)\}")

_TRANSFORMS = {
    "upper": str.upper,
    # For inputs whose pattern rejects spaces (e.g. Elementor's phone field)
    "no_spaces": lambda s: "".join(s.split()),
}


def _web_values(request: GenerateRequest) -> dict[str, str]:
    """Values web forms ask for that the paper forms don't."""
    pilot = request.crew[0] if request.crew else None
    return {
        "people.count": str(len(request.crew) + len(request.passengers)),
        "pilot.name": f"{pilot.first_name} {pilot.last_name}".strip() if pilot else "",
        # Private GA flies under its registration; forms that insist on a
        # call sign get that.
        "aircraft.callsign": request.aircraft.registration,
    }


def _field_value(spec: dict, values: dict[str, str]) -> str:
    """Resolve one field spec to its value, or "" when the data isn't there."""
    if "static" in spec:
        return str(spec["static"])
    if "format" in spec:
        keys = _PLACEHOLDER_RE.findall(spec["format"])
        if not all(values.get(k) for k in keys):
            return ""
        return _PLACEHOLDER_RE.sub(lambda m: values[m.group(1)], spec["format"])
    return values.get(spec["value"], "")


def build_fill_plan(mapping: FormMapping, request: GenerateRequest, airport_resolver) -> FillPlan:
    """Build the fill plan for a ``web_form`` mapping.

    ``fields`` apply at every airport the mapping covers; ``airport_fields``
    adds per-airport ones (a RedAtlas site's own extra questions differ from
    one airport to the next).
    """
    # A direction-bound form takes its own side even on a local flight, where
    # origin == destination and the airport alone can't say which it is.
    is_arrival = (mapping.direction == "arrival") if mapping.direction else None
    values = build_values(mapping, request, airport_resolver, is_arrival)
    values.update(_web_values(request))

    specs = mapping.raw.get("fields", []) + mapping.raw.get("airport_fields", {}).get(request.airport, [])
    fields = []
    for spec in specs:
        value = _field_value(spec, values)
        if not value:
            continue  # leave the page's own input alone rather than blank it
        if "transform" in spec:
            value = _TRANSFORMS[spec["transform"]](value)
        fields.append(FillField(name=spec["name"], value=value, type=spec.get("type", "text")))

    return FillPlan(
        form=mapping.id,
        label=mapping.label,
        url=mapping.web_url(request.airport),
        scope=mapping.raw.get("scope"),
        note=mapping.raw.get("note"),
        fields=fields,
    )
