# Localisation

> Multilingual support for the iOS/macOS app — English (base), French, German, Spanish

## Approach

**Xcode String Catalogs** (`.xcstrings`) — the modern best practice for iOS 17+ apps. A single JSON file manages all languages, with Xcode auto-extracting strings from SwiftUI views on build.

### Why String Catalogs

- Single file (`Localizable.xcstrings`) vs. multiple `.strings` files per language
- Xcode auto-detects new/removed strings on build
- Built-in translation completeness tracking (% per language)
- Native pluralisation and device-specific variant support
- `STRING_CATALOG_GENERATE_SYMBOLS = YES` already enabled in project

## Languages

| Code | Language | Status |
|------|----------|--------|
| `en` | English | Base language (source of truth) |
| `fr` | French | Draft translations provided (needs_review) |
| `de` | German | Draft translations provided (needs_review) |
| `es` | Spanish | Draft translations provided (needs_review) |

## What Was Done

### 1. String Catalog Created

`app/flyfun-forms/flyfun-forms/Localizable.xcstrings` — contains ~95 string entries with draft translations in all 4 languages. All translations are marked `needs_review`.

### 2. Project Configuration

- Added `fr`, `de`, `es` to `knownRegions` in `project.pbxproj`
- Project already had `LOCALIZATION_PREFERS_STRING_CATALOGS = YES`, `SWIFT_EMIT_LOC_STRINGS = YES`, and `STRING_CATALOG_GENERATE_SYMBOLS = YES`

### 3. Code Changes for Localisable Extraction

Most SwiftUI `Text("string")` literals are automatically `LocalizedStringKey` and will be extracted by Xcode on build. The following patterns required manual fixes:

#### Enum computed properties → `LocalizedStringResource`

`ContentView.swift` — `AppSection.title` changed from `String` to `LocalizedStringResource` so Xcode extracts the tab/sidebar labels.

#### Model `displayName` fallbacks → `String(localized:)`

- `Person.displayName`: `"New Person"` → `String(localized: "New Person")`
- `Aircraft.displayName`: `"New Aircraft"` → `String(localized: "New Aircraft")`

#### Localized display for persisted data values

Data values stored in SwiftData (`"Passport"`, `"Male"`, `"private"`) must stay English in the database but display localised to the user. Pattern used:

```swift
// Picker: display is localised, .tag() stays English
Text("Passport", comment: "Document type").tag("Passport")
Text("Male", comment: "Sex/gender option").tag("Male")
Text("Private", comment: "Flight nature").tag("private")
```

`TravelDocument.localizedDocType` — new computed property that maps stored English value to `String(localized:)` for display in lists.

#### Reason for visit options → `LocalizedStringKey`

`FlightEditView.swift` — the `reasonOptions` array contains English data values (`"Business"`, `"Pleasure"`, etc.) displayed via `Text(LocalizedStringKey(reason))` so they're localised for display but stored as English.

#### Service error messages → `String(localized:)`

`FormService.swift` — `FormError.errorDescription` now uses `String(localized:)` for all user-facing error messages.

#### Auth error messages → `String(localized:)`

`LoginView.swift` — programmatic error strings like `"Unexpected credential type."` and `"Failed to create authentication URL."` now use `String(localized:)`.

#### Import result messages → `String(localized:)`

`PeopleListView.swift` — import status messages (`"Import Complete"`, `"Error"`, `"\(count) imported"`) now use `String(localized:)`.

#### People group names → `String(localized:)`

`PeoplePickerView.swift` — `"Usual Crew"` and `"Frequent with \(name)"` group labels now use `String(localized:)`.

### 4. Files Changed

| File | Changes |
|------|---------|
| `ContentView.swift` | `AppSection.title` → `LocalizedStringResource` |
| `PersonEditView.swift` | Sex/docType pickers: added `comment:` for context |
| `FlightEditView.swift` | Nature picker + reason options localisation |
| `Person.swift` | `displayName` fallback |
| `Aircraft.swift` | `displayName` fallback |
| `TravelDocument.swift` | Added `localizedDocType` computed property |
| `FormService.swift` | Error descriptions |
| `LoginView.swift` | Error message strings |
| `PeopleListView.swift` | Import result messages |
| `PeoplePickerView.swift` | Group name strings |
| `MRZResultActionView.swift` | `"ID Card"` display string |
| `project.pbxproj` | Added `fr`, `de`, `es` to `knownRegions` |
| `Localizable.xcstrings` | **New** — String Catalog with ~95 entries |

## What's NOT Localised (By Design)

- **Persisted data values** — `"Passport"`, `"Identity card"`, `"Male"`, `"Female"`, `"private"`, `"commercial"`, `"Business"`, `"Pleasure"`, `"Transit"`, `"Other"` stay English in SwiftData/CloudKit
- **ICAO codes** — airport identifiers are international standards
- **ISO country codes** — `"FRA"`, `"GBR"`, etc.
- **API payloads** — all server communication uses English values
- **System image names** — SF Symbols identifiers
- **OAuth URLs** — authentication endpoints
- **Person names** — user-entered data shown verbatim

## Still To Do on Mac

### 1. Build the project in Xcode

**Critical first step.** Building triggers Xcode's string extraction:
- Xcode will scan all SwiftUI views and merge any strings it finds into `Localizable.xcstrings`
- It may discover strings we missed (Xcode is the source of truth for SwiftUI auto-extraction)
- Check the String Catalog editor for any strings marked "New" or "Stale"

### 2. Review and fix extracted strings

Open `Localizable.xcstrings` in Xcode's String Catalog editor:
- Verify all ~95 strings appear
- Look for any auto-extracted strings that don't have translations yet
- Mark strings that shouldn't be translated as "Don't Translate" (e.g., if Xcode extracts data values)

### 3. Review draft translations

All translations are marked `needs_review`. For each language:
- Review translations for accuracy (they are AI-generated drafts)
- Particularly check aviation-specific terms (these may need domain expertise)
- Update state from `needs_review` to `translated` when verified
- Consider having a native speaker review each language

### 4. Test each language

In Xcode: Edit Scheme → Run → Options → App Language:
- Test English, French, German, Spanish
- Check for layout issues (German strings are 30-40% longer than English)
- Verify tab bar labels don't truncate
- Check picker labels in compact views
- Verify MRZ scanner overlay text fits
- Test on both iPhone (compact) and iPad (regular) size classes

### 5. Handle pluralisation (optional)

Some strings may need plural forms (e.g., `"%lld imported"` → `"1 imported"` vs `"5 imported"`). The String Catalog supports this via the "Vary by Plural" option in Xcode's editor. Particularly relevant for:
- `"%lld imported"` / `"%lld already existed"` — import result messages
- French and Spanish have different plural rules than English/German

### 6. Info.plist localisation (optional)

To localise the app name shown on the home screen:
- Create `InfoPlist.xcstrings` in the project
- Add `CFBundleDisplayName` key with translations

### 7. Export for professional translation (optional)

If you want professional translations instead of AI drafts:
- Xcode → Product → Export Localizations → select languages
- This generates `.xliff` files that translators can work with
- Re-import with Product → Import Localizations

## Key Decisions

- **String Catalogs over `.strings` files**: Modern approach, better tooling, single file to manage
- **Data values stay English**: SwiftData stores English strings; display layer maps to localised strings. This ensures CloudKit sync works across devices regardless of language, and API payloads are always English.
- **`needs_review` state**: All draft translations are marked for review — they should be verified by a native speaker before shipping
- **No runtime language switching**: App follows system language setting (standard iOS behaviour). No in-app language picker needed.

## References

- [Apple: Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)
- [iOS App Design](./ios-app.md) — app architecture context
