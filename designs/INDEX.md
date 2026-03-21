# flyfun-forms

> GA customs/immigration form generator — FastAPI backend + iOS app + CLI for filling airport-specific PDF/DOCX/XLSX forms with flight and passenger data

Install: `pip install -e .` (Python backend/CLI) or open `app/flyfun-forms/flyfun-forms.xcodeproj` (iOS/macOS)

Related: flyfun-common, rzflight

## Modules

### api
FastAPI backend: form generation, airport discovery, validation. Stateless — receives flight/people data, returns filled forms, never stores PII.
Key exports: `/generate`, `/validate`, `/airports`, `/airports/{icao}`
→ Full doc: api.md

### form-system
Template + mapping + filler architecture. How forms are discovered, configured via JSON mappings, and filled by pluggable fillers (PDF, DOCX, XLSX). Supports exact ICAO, prefix, and default fallback matching.
Key exports: `MappingRegistry`, `fill_pdf`, `fill_french_customs`, `fill_docx`, `fill_xlsx`
→ Full doc: form-system.md

### ios-app
SwiftUI app (iOS/macOS) with SwiftData + CloudKit cross-device sync. Manages people, aircraft, flights/trips locally with encrypted sync. Calls backend for form generation. Multi-document per person with automatic region-based selection.
Key exports: `AppState`, `FormService`, `DocumentResolver`, Person/TravelDocument/Aircraft/Flight/Trip models
→ Full doc: ios-app.md

### cli
Command-line client for batch form generation from CSV files. Uses API tokens for auth. Includes `preview` command for generating forms with self-describing dummy data for visual verification.
Key exports: `cli.py` (generate, trip, preview, airports commands)
→ Full doc: cli.md

### localisation
Multilingual support for the iOS/macOS app — English (base), French, German, Spanish. Uses Xcode String Catalogs (`.xcstrings`). Documents code changes, what's localised vs not, and remaining steps for Mac.
→ Full doc: localisation.md

### people-import
CSV format documentation for bulk importing crew and passengers. Covers required/optional columns, data formats, deduplication, and behaviour.
→ Full doc: people_import.md

