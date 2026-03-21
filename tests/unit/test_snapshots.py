"""Snapshot regression tests for form field mappings.

Each test generates a form with self-describing dummy data, extracts the
field values from the output document, and compares them against a checked-in
golden snapshot.  Any change to a mapping, template, or filler that moves a
value to a different field will cause the snapshot to fail.

Run with ``--snapshot-update`` to regenerate the golden files after a
deliberate change (visual verification recommended first).
"""

import json
from pathlib import Path

import pytest

from flightforms.preview import (
    DIRECTION_AWARE_FORMS,
    FORM_AIRPORTS,
    PreviewAirportResolver,
    _find_mapping_by_id,
    extract_docx_paragraphs,
    extract_docx_tables,
    extract_pdf_fields,
    extract_xlsx_fields,
    generate_preview,
)
from flightforms.registry import MappingRegistry
from tests.conftest import MAPPINGS_DIR, TEMPLATES_DIR

SNAPSHOTS_DIR = Path(__file__).parent.parent / "snapshots"


@pytest.fixture
def snapshot_update(request):
    return request.config.getoption("--snapshot-update", default=False)


# ── Helpers ──────────────────────────────────────────────────────────────────

def _snapshot_path(form_id: str, direction: str) -> Path:
    if direction == "arrival":
        return SNAPSHOTS_DIR / f"{form_id}.json"
    return SNAPSHOTS_DIR / f"{form_id}_{direction}.json"


def _extract_fields(form_id: str, doc_bytes: bytes, registry: MappingRegistry) -> dict:
    """Extract field values from a generated document, keyed by field address."""
    airport = FORM_AIRPORTS.get(form_id, "ZZZZ")
    mapping = registry.get_form(airport, form_id)
    if mapping is None:
        mapping = _find_mapping_by_id(registry, form_id)

    ftype = mapping.filler_type

    if ftype in ("pdf_acroform", "pdf_acroform_french"):
        return extract_pdf_fields(doc_bytes)

    if ftype == "xlsx":
        return extract_xlsx_fields(doc_bytes)

    if ftype == "docx":
        tables = extract_docx_tables(doc_bytes)
        paragraphs = extract_docx_paragraphs(doc_bytes)
        return {
            "tables": tables,
            "paragraphs": paragraphs,
        }

    raise ValueError(f"Unsupported filler type: {ftype}")


def _assert_snapshot(fields, snapshot_file, form_id, direction, snapshot_update):
    """Compare extracted fields against a golden snapshot, or update it."""
    if snapshot_update:
        SNAPSHOTS_DIR.mkdir(parents=True, exist_ok=True)
        with open(snapshot_file, "w") as f:
            json.dump(fields, f, indent=2, sort_keys=True, default=str)
            f.write("\n")
        pytest.skip(f"Snapshot updated: {snapshot_file.name}")
        return

    if not snapshot_file.exists():
        pytest.fail(
            f"Snapshot {snapshot_file.name} does not exist. "
            f"Run with --snapshot-update to generate it."
        )

    with open(snapshot_file) as f:
        expected = json.load(f)

    if fields != expected:
        diff_lines = []
        if isinstance(fields, dict) and isinstance(expected, dict):
            all_keys = sorted(set(list(fields.keys()) + list(expected.keys())))
            for key in all_keys:
                actual_val = fields.get(key)
                expected_val = expected.get(key)
                if actual_val != expected_val:
                    diff_lines.append(
                        f"  {key}:\n"
                        f"    expected: {expected_val!r}\n"
                        f"    actual:   {actual_val!r}"
                    )
        diff_msg = "\n".join(diff_lines) if diff_lines else "(complex diff — compare JSON files)"
        pytest.fail(f"Snapshot mismatch for {form_id} ({direction}):\n{diff_msg}")


# ── Parametrized snapshot tests ──────────────────────────────────────────────

# Build test cases: each form gets arrival, direction-aware forms also get departure
_TEST_CASES = []
for _fid in FORM_AIRPORTS:
    _TEST_CASES.append((_fid, "arrival"))
    if _fid in DIRECTION_AWARE_FORMS:
        _TEST_CASES.append((_fid, "departure"))


@pytest.mark.parametrize("form_id,direction", _TEST_CASES, ids=[f"{f}-{d}" for f, d in _TEST_CASES])
def test_form_snapshot(form_id, direction, snapshot_update):
    registry = MappingRegistry(str(MAPPINGS_DIR), str(TEMPLATES_DIR))
    resolver = PreviewAirportResolver()

    doc_bytes = generate_preview(registry, form_id, resolver, direction=direction)
    fields = _extract_fields(form_id, doc_bytes, registry)
    snapshot_file = _snapshot_path(form_id, direction)

    _assert_snapshot(fields, snapshot_file, form_id, direction, snapshot_update)
