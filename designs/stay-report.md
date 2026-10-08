# Stay Report: days in region the app sees

> **Status: implemented on iOS/macOS (#49).** Android has the region table fix
> (parity of `DocumentResolver`); the Android report is a gap tracked in
> `future/android-parity.md` §7.

## Intent

A per-person report that answers one question: **on the flights this app knows about,
how many days was this person in each region over the last 180 days?**

It is a counting tool, not a compliance tool. It does not decide whether someone is
within the Schengen 90/180 limit, and it does not claim to know about travel the app
never saw (an airline flight home, a ferry, a drive). It shows the count, shows where
the record has holes, and leaves the decision to the user. If the user wants a more
complete count, they add the missing legs as ordinary flights.

The core is a small state machine over the person's flights and a test suite that
covers the edge cases. The UI is deliberately thin.

Nothing new is stored, nothing goes to the server, and `PRIVACY.md` does not change:
the report is computed on device from the existing SwiftData flights each time the
view renders.

## Files

| File | Role |
|---|---|
| `Services/AirportRegion.swift` | Region table (ICAO → region) + EU/Schengen issuing countries |
| `Services/StayReport.swift` | `StayDay`, `StayLeg`, `StayReport.compute`, `ruleStatus`, `StayLeg.legs(for:)` |
| `Views/StayReportView.swift` | The report screen, opened from **Travel → Travel Days** in `PersonEditView` |
| `flyfun-formsTests/StayReportTests.swift` | One named test per assumption |
| `flyfun-formsTests/AirportRegionTests.swift` | Region table |
| Android `core-logic/.../DocumentResolver.kt` | Same table, private, for passport choice only |

## Regions

`AirportRegion.region(for:)`: exact ICAO override, then two-letter prefix, then
`.other`. Input is trimmed and uppercased.

| Region | Meaning |
|---|---|
| `schengen` | Schengen area, the region the 90/180 rule applies to |
| `uk` | United Kingdom (`EG`), incl. Channel Islands and Isle of Man |
| `euNonSchengen` | EU but outside Schengen: Ireland (`EI`), Cyprus (`LC`) |
| `other` | Everything else, incl. Gibraltar (`LX`) and unknown prefixes |

Fixes made when the table moved out of `DocumentResolver` (it was written to choose a
passport, where a small error is harmless; for counting days it is not):

- `LZ` Slovakia → `schengen` (was missing, so Slovak airports also got the wrong passport).
- `LC` Cyprus → `euNonSchengen` (was `schengen`).
- `EI` Ireland → `euNonSchengen`; `GC` Canary Islands → `schengen`.
- `EL` comment fixed: Luxembourg, not Greece.
- `ET` German military airfields → `schengen`; `LIE` Liechtenstein added to the EU/Schengen
  issuing countries (it has no ICAO prefix of its own: its airfields are under Swiss `LS`).
- Exact overrides `ENSB` Svalbard, `EKVG` Faroe → `other`.

`DocumentResolver` treats `euNonSchengen` like `schengen` (prefers an EU/Schengen-issued
document), so Cyprus is unchanged and Ireland now prefers an EU document. Side effect:
Svalbard and Faroe now fall back to latest expiry instead of preferring an EU document.

Android keeps its own private copy of the table in `DocumentResolver.kt`; **change both
together**. Longer term the table belongs in rzflight (CLAUDE.md library principle).

## The state machine

Pure, no SwiftData or UI dependency (`nonisolated`, so tests call it off the main actor):

```swift
StayReport.compute(
    legs: [StayLeg],                       // any order, duplicates by flightID counted once
    asOf: Date,                            // now; its day in deviceZone is "today"
    region: (String) -> AirportRegion = AirportRegion.region(for:),
    zone: (String) -> TimeZone?,           // airport timezone, nil → UTC
    deviceZone: TimeZone = .current
) -> StayReport

struct StayLeg { flightID: UUID; origin, destination: String; departure, arrival: Moment }
enum Moment { case instant(Date); case day(StayDay) }  // .day = flight stored with no time
```

`StayDay` is a timezone-free calendar day (days since 1970-01-01), so day arithmetic is
integer arithmetic: DST changes and leap days cannot shift a count.

### Steps

1. **Collect.** Dedupe by `flightID`. Drop legs with an empty origin or destination
   (`flightsIgnored`). Drop legs departing after `asOf` (`flightsFuture`).
2. **Sort** by departure instant, then arrival, then id (order-independent result).
   A `.day` moment sorts at midnight of that day in `deviceZone`.
3. **Walk.** For each leg the departure day (local at origin) is seen in the origin
   region and the arrival day (local at destination) in the destination region.
   Between the previous arrival and this departure:
   - same region → every day from arrival day to departure day is seen there (stayed put);
   - different region → a **gap**: the days strictly between are **unknown days**. A gap
     is listed even when it covers no unknown day (adjacent days).
   - next departs before previous arrives → **overlap**, flagged; the walk continues in
     departure order.
4. **Before the first flight**: nothing is counted.
5. **After the last flight**: if its arrival day is before today, the person is assumed
   to stay in that region up to today; `openEnded` is set.
6. **Window**: distinct days in `[today - 179, today]` per region. Only days inside the
   window are recorded, but the whole history is walked, so the state on the window's
   first day comes from earlier flights.

### Output

`seenDays[region]`, `unknownDays`, `schengenUpperBound` (= |Schengen seen ∪ unknown|,
so a day already seen in Schengen is never counted twice), `gaps` (only those whose next
flight departs inside the window), `openEnded` (airport, region, since), `flightsUsed`
(whole history walked), `flightsInWindow` (flights arriving in the window plus the last one
before it, which sets where the window starts; the count shown in the footer),
`flightsIgnored`, `flightsFuture`, `overlaps`.

### Who the rule applies to

`StayReport.ruleStatus(issuingCountries:)`, fed **all** documents, active or not:
any EU/Schengen issuer → `.notSubject` (an expired passport doesn't end citizenship);
otherwise any named issuer → `.subject`; none → `.unknown`. A label, never a filter.

## Assumptions (each has a named test in `StayReportTests`)

1. Entry and exit days count as full days. A day trip is one day.
2. A day can count for several regions (out and back the same day).
3. Days are local calendar days at the airport (`AirportTimezoneCache`), UTC when unknown.
4. A flight with no time uses its stored day (`Flight.departureDate`, device-zone midnight).
5. Staying put is assumed between flights in the same region, however far apart.
6. A region change between flights is unknown, not guessed: a gap.
7. After the last flight the person is assumed to stay, flagged open-ended.
8. Nothing is counted before the first flight.
9. Every flight in the app happened. A cancelled flight left in the app counts.
10. Future flights are excluded; a flight counts once it has departed (in progress counts).
11. Window = 180 calendar days ending today (device zone), inclusive.
12. Channel Islands and Isle of Man count as UK; Gibraltar as other.
13. Overlapping flights are processed in departure order and flagged.
14. Flights missing an origin or destination are ignored and listed.
15. Residence permits and long-stay visas are unknown to the app, so the label can be wrong.

## Implementation choices

- **Adapter** `StayLeg.legs(for: Person)` merges `crewFlights` + `passengerFlights`,
  deduped by `persistentModelID`, and returns a `[UUID: Flight]` lookup so the view can
  link a gap back to its flights. A flight without a `uuid` (not yet backfilled by `StableRecords`) gets an id hashed from
  its `persistentModelID`, stable across renders within a run.
- **Timed vs day-only**: a leg is `.instant(departureDateTime)` when it has a time
  (`hasDepartureTime`) or a backfilled `departureInstant`; otherwise `.day`.
- **Timezones**: the view reads the cache into a plain dictionary on the main actor before
  calling `compute`, and asks the cache to resolve each airport in `.task`. The cache is
  `@Observable`, so the report recomputes as zones land. First open with uncached zones
  may briefly show UTC days.
- **UI**: four region rows always shown (Schengen first), "Up to N days with gaps" under
  Schengen only when the upper bound is higher, the rule label under Schengen, a Gaps
  section with Previous / Next flight links (push `FlightEditView`), and a Notes section
  for open-ended, overlaps, ignored and planned flights. No colours or thresholds.
- **Strings**: EN/FR/DE/ES in `Localizable.xcstrings`, machine-drafted, `needs_review`;
  `%lld days`, `Up to %lld days…` and `Based on %lld flights…` have plural variants.

## Out of scope (possible later)

- "Ignore flight" without deleting it.
- A lightweight non-GA leg (airline, ferry) distinct from a GA flight.
- Projection with planned future flights ("84 days on 12 November").
- Warnings and thresholds. UK-specific rules.
- Moving the region table to rzflight.
- Android report.
