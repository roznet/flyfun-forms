"""Tests for CLI helper functions."""

import csv
import tempfile
from pathlib import Path

import pytest

from flightforms.cli import _convert_date, _normalize_sex, _load_people, _resolve_person


# ── _convert_date ─────────────────────────────────────────────────────────────

class TestConvertDate:
    def test_iso_passthrough(self):
        assert _convert_date("2099-06-15") == "2099-06-15"

    def test_dd_mm_yyyy(self):
        assert _convert_date("15/06/2099") == "2099-06-15"

    def test_mm_dd_yyyy(self):
        assert _convert_date("06/15/2099") == "2099-06-15"

    def test_dd_dash_mm_dash_yyyy(self):
        assert _convert_date("15-06-2099") == "2099-06-15"

    def test_dd_mon_yyyy(self):
        assert _convert_date("15 Jun 2099") == "2099-06-15"

    def test_dd_month_yyyy(self):
        assert _convert_date("15 June 2099") == "2099-06-15"

    def test_empty(self):
        assert _convert_date("") == ""

    def test_unrecognized_returns_raw(self):
        assert _convert_date("garbage") == "garbage"


# ── _normalize_sex ────────────────────────────────────────────────────────────

class TestNormalizeSex:
    def test_m(self):
        assert _normalize_sex("M") == "Male"

    def test_f(self):
        assert _normalize_sex("F") == "Female"

    def test_male(self):
        assert _normalize_sex("male") == "Male"

    def test_female(self):
        assert _normalize_sex("FEMALE") == "Female"

    def test_other(self):
        assert _normalize_sex("Other") == "Other"

    def test_empty(self):
        assert _normalize_sex("") == ""


# ── _load_people ──────────────────────────────────────────────────────────────

def _write_csv(tmp_path: Path, rows: list[dict]) -> str:
    path = tmp_path / "people.csv"
    if not rows:
        path.write_text("")
        return str(path)
    fieldnames = list(rows[0].keys())
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return str(path)


class TestLoadPeople:
    def test_basic(self, tmp_path):
        csv_path = _write_csv(tmp_path, [
            {
                "First Name": "Zara",
                "Last Name": "Kowalski",
                "DoB": "1985-03-22",
                "Nationality": "XYZ",
                "Doc Number": "PP-999001",
                "Doc Type": "Passport",
                "Doc Issuing State": "XYZ",
                "Doc Expiry": "2030-06-15",
                "Gender": "F",
                "Place of Birth": "Northville",
            },
        ])
        people = _load_people(csv_path)
        assert "Zara Kowalski" in people
        p = people["Zara Kowalski"]
        assert p["first_name"] == "Zara"
        assert p["last_name"] == "Kowalski"
        assert p["dob"] == "1985-03-22"
        assert p["sex"] == "Female"

    def test_skips_empty_names(self, tmp_path):
        csv_path = _write_csv(tmp_path, [
            {"First Name": "", "Last Name": "Ghost", "DoB": ""},
            {"First Name": "Solo", "Last Name": "", "DoB": ""},
        ])
        people = _load_people(csv_path)
        assert len(people) == 0


# ── _resolve_person ───────────────────────────────────────────────────────────

@pytest.fixture
def people_db():
    return {
        "Zara Kowalski": {
            "first_name": "Zara",
            "last_name": "Kowalski",
            "dob": "1985-03-22",
            "nationality": "XYZ",
            "id_number": "PP-999001",
        },
        "Tariq Jens Bergström": {
            "first_name": "Tariq Jens",
            "last_name": "Bergström",
            "dob": "1990-11-07",
            "nationality": "ABC",
            "id_number": "PP-999002",
        },
    }


class TestResolvePerson:
    def test_exact_match(self, people_db):
        p = _resolve_person("Zara Kowalski", people_db)
        assert p["id_number"] == "PP-999001"

    def test_case_insensitive(self, people_db):
        p = _resolve_person("zara kowalski", people_db)
        assert p["id_number"] == "PP-999001"

    def test_fuzzy_first_last(self, people_db):
        """'Tariq Bergström' should match 'Tariq Jens Bergström'."""
        p = _resolve_person("Tariq Bergström", people_db)
        assert p["id_number"] == "PP-999002"

    def test_last_name_only(self, people_db):
        p = _resolve_person("Kowalski", people_db)
        assert p["first_name"] == "Zara"

    def test_not_found_returns_minimal(self, people_db):
        p = _resolve_person("Unknown Person", people_db)
        assert p["first_name"] == "Unknown"
        assert p["last_name"] == "Person"

    def test_role_hint(self, people_db):
        p = _resolve_person("Zara Kowalski", people_db, role_hint="Pilot")
        assert p["function"] == "Pilot"

    def test_single_word_not_found(self, people_db):
        p = _resolve_person("Nemo", people_db)
        assert p["first_name"] == "Nemo"
        assert p["last_name"] == ""
