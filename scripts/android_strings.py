#!/usr/bin/env python3
"""Write the Android app's translations from the iOS app's string catalogue.

The iOS app is translated (``Localizable.xcstrings``, fr/de/es); Android's
strings are English in ``res/values/strings*.xml``. A string whose English is
the same as an iOS key, placeholders aside, takes that key's translations;
failing that, one that differs only in case or a trailing full stop or
ellipsis ("First name" and iOS's "First Name"). The
rest stay English: Android falls back to ``values/`` for anything a language
folder lacks, so a partly translated language shows English for the gaps
rather than failing.

Writes ``res/values-{fr,de,es}/strings.xml``; never edit those by hand, they are
overwritten. Run it after adding or rewording strings, and commit the result:

    python scripts/android_strings.py

Placeholders are compared by position: iOS ``%@``/``%lld`` and Android
``%1$s``/``%1$d`` are the same slot. A translation that reorders them
(``%2$@ … %1$@``) keeps its order, rewritten to Android's types.
"""

import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from xml.sax.saxutils import escape

ROOT = Path(__file__).resolve().parent.parent
CATALOGUE = ROOT / "app" / "flyfun-forms" / "flyfun-forms" / "Localizable.xcstrings"
RES = ROOT / "app" / "android" / "app" / "src" / "main" / "res"
LANGUAGES = ["fr", "de", "es"]

# %@, %lld, %d, %1$@, %2$s ... (not %%).
PLACEHOLDER = re.compile(r"%(?:(\d+)\$)?(@|lld|ld|lu|d|s|f|\.\d+f)")


def android_text(raw: str) -> str:
    """The text of a string resource as the app shows it (Android escapes undone)."""
    text = raw.strip()
    if len(text) >= 2 and text[0] == '"' and text[-1] == '"':
        text = text[1:-1]
    return re.sub(r"\\(['\"@?n])", lambda m: "\n" if m.group(1) == "n" else m.group(1), text)


def android_escape(text: str) -> str:
    """Text for a string resource: XML-escaped, with Android's own escapes."""
    text = escape(text).replace("\\", "\\\\").replace("'", "\\'").replace('"', '\\"').replace("\n", "\\n")
    if text.startswith("@") or text.startswith("?"):
        text = "\\" + text
    return text


def shape(text: str) -> str:
    """The text with every placeholder replaced by one marker, for matching."""
    return PLACEHOLDER.sub("\u0000", text)


def loose(text: str) -> str:
    """[shape] ignoring case and a trailing full stop or ellipsis: "First name" is iOS's "First Name"."""
    return re.sub(r"(\.\.\.|…|\.)$", "", shape(text).strip()).casefold()


def android_types(text: str) -> list[str]:
    """Android conversion of each placeholder, in order: s or d."""
    return ["d" if kind in ("d", "lld", "ld", "lu") else "s" for _, kind in PLACEHOLDER.findall(text)]


def to_android(translation: str, types: list[str]) -> str | None:
    """An iOS translation with its placeholders rewritten as Android positional ones."""
    count = 0

    def replace(match: re.Match) -> str:
        nonlocal count
        count += 1
        position = int(match.group(1)) if match.group(1) else count
        if position > len(types):
            raise ValueError
        return f"%{position}${types[position - 1]}"

    try:
        # Escape bare % before rewriting, then restore our placeholders.
        converted = PLACEHOLDER.sub(replace, translation)
    except ValueError:
        return None
    return converted if count == len(types) else None


def unit(entry: dict) -> str | None:
    return entry.get("stringUnit", {}).get("value")


def load_android() -> tuple[dict[str, str], dict[str, dict[str, str]]]:
    """English strings and plurals by name, from every values/strings*.xml."""
    strings: dict[str, str] = {}
    plurals: dict[str, dict[str, str]] = {}
    for path in sorted((RES / "values").glob("strings*.xml")):
        for element in ET.parse(path).getroot():
            name = element.get("name")
            if element.get("translatable") == "false":
                continue
            if element.tag == "string":
                strings[name] = android_text("".join(element.itertext()))
            elif element.tag == "plurals":
                plurals[name] = {item.get("quantity"): android_text("".join(item.itertext())) for item in element}
    return strings, plurals


def main() -> None:
    catalogue = json.loads(CATALOGUE.read_text(encoding="utf-8"))["strings"]
    by_shape: dict[str, dict] = {}
    by_loose: dict[str, dict] = {}
    for key, entry in catalogue.items():
        if entry.get("localizations"):
            by_shape.setdefault(shape(key), entry)
            by_loose.setdefault(loose(key), entry)

    def lookup(english: str) -> dict | None:
        return by_shape.get(shape(english)) or by_loose.get(loose(english))

    strings, plurals = load_android()
    for language in LANGUAGES:
        lines = [
            '<?xml version="1.0" encoding="utf-8"?>',
            "<!-- Written by scripts/android_strings.py from the iOS Localizable.xcstrings. Do not edit. -->",
            "<resources>",
        ]
        found = 0
        for name, english in strings.items():
            entry = lookup(english)
            local = entry and entry["localizations"].get(language)
            value = local and unit(local)
            if value is None and local and "variations" in local:
                # A plural key used for a plain string: take its "other".
                value = unit(local["variations"].get("plural", {}).get("other", {}))
            converted = value and to_android(value, android_types(english))
            if converted:
                lines.append(f'    <string name="{name}">{android_escape(converted)}</string>')
                found += 1
        for name, forms in plurals.items():
            english = forms.get("other", "")
            entry = lookup(english)
            local = entry and entry["localizations"].get(language)
            if not local:
                continue
            variations = local.get("variations", {}).get("plural", {})
            items = {q: unit(v) for q, v in variations.items()} if variations else {"other": unit(local)}
            types = android_types(english)
            converted = {q: to_android(v, types) for q, v in items.items() if v}
            if converted.get("other"):
                lines.append(f'    <plurals name="{name}">')
                for quantity, text in converted.items():
                    if text:
                        lines.append(f'        <item quantity="{quantity}">{android_escape(text)}</item>')
                lines.append("    </plurals>")
                found += 1
        lines.append("</resources>")
        out = RES / f"values-{language}"
        out.mkdir(parents=True, exist_ok=True)
        (out / "strings.xml").write_text("\n".join(lines) + "\n", encoding="utf-8")
        total = len(strings) + len(plurals)
        print(f"{language}: {found} of {total} translated from iOS", file=sys.stderr)


if __name__ == "__main__":
    main()
