# Stay Report: days in region the app sees

> **Status: proposed.** iOS first. Android gets the region table fix now (parity of
> `DocumentResolver`) and the report later through `android-parity.md`.

## Intent

A per-person report that answers one question: **on the flights this app knows about,
how many days was this person in each region over the last 180 days?**

It is a counting tool, not a compliance tool. It does not decide whether someone is
within the Schengen 90/180 limit, and it does not claim to know about travel the app
never saw (an airline flight home, a ferry, a drive). It shows the count, shows where
the record has holes, and leaves the decision to the user. If the user wants a more
complete count, they add the missing legs as ordinary flights.

The core of the work is a small state machine over the person's flights, and a test
suite that covers the edge cases. The UI is deliberately thin.

## Why it fits the app

The data is already there: every `Flight` has origin and destination ICAO codes, a
UTC schedule, and its crew and passengers. A person's `crewFlights` and
`passengerFlights` give their history. Nothing new is stored, nothing goes to the
server, and `PRIVACY.md` does not change.

## Regions

One shared table, `Services/AirportRegion.swift`, mapping an ICAO code to a region.
It replaces the private `prefixRegions` table in `DocumentResolver`.

| Region | Meaning |
|---|---|
| `schengen` | Schengen area, the region the 90/180 rule applies to |
| `uk` | United Kingdom (`EG`) |
| `euNonSchengen` | EU but outside Schengen: Ireland (`EI`), Cyprus (`LC`) |
| `other` | Everything else, including unknown prefixes |

Lookup order: exact ICAO override, then two-letter prefix, then `other`.

### Fixes to the current table

The current table was written to choose a passport, where a small error is harmless.
For counting days it is not.

- **Add `LZ` (Slovakia) → `schengen`.** Missing today, so a Slovak airport also gets
  the wrong passport choice.
- **Move `LC` (Cyprus) → `euNonSchengen`.** Cyprus is EU, not Schengen.
- **Add `EI` (Ireland) → `euNonSchengen`.**
- **Add `GC` (Canary Islands) → `schengen`.** Spanish, Schengen, but not under `LE`.
- **Fix the `EL` comment**: `EL` is Luxembourg, not Greece. Mapping unchanged.
- **Exact overrides for territories outside Schengen under a Schengen prefix:**
  `ENSB` (Svalbard), `EKVG` (Faroe Islands) → `other`.

`DocumentResolver` treats `euNonSchengen` like `schengen` when preferring a document
(it already uses one EU+Schengen country list). So Cyprus keeps its current behaviour
and Ireland now prefers an EU-issued document, which is the intended outcome.

The same table fix lands in Android's `core-logic/.../DocumentResolver.kt` so both
platforms pick the same passport.

Longer term the table belongs in rzflight (per the CLAUDE.md library principle). Not
part of this change.

## The state machine

Pure function, no SwiftData or UI dependency:

```swift
struct StayReport {
    static func compute(
        legs: [StayLeg],                    // the person's flights, any order
        asOf: Date,                         // normally now
        region: (String) -> AirportRegion,  // AirportRegion.region(for:)
        zone: (String) -> TimeZone?         // AirportTimezoneCache lookup
    ) -> StayReport
}

struct StayLeg {
    let flightID: UUID?
    let origin: String, destination: String
    let departure: Date, arrival: Date      // Flight.departureDateTime / arrivalDateTime
}
```

`StayLeg` keeps the calculator independent of `Flight`, so tests build legs directly.

### Steps

1. **Collect.** All flights where the person is crew or passenger, deduplicated by
   flight (someone can be in both lists). Drop flights with an empty origin or
   destination, and list them as ignored. Drop flights that depart after `asOf`.
2. **Sort** by departure instant.
3. **Walk.** The state is the region the person was last seen in, or `unknown` before
   the first flight. For each leg:
   - The **departure day** (local date at the origin) is a seen day in the origin region.
   - The **arrival day** (local date at the destination) is a seen day in the
     destination region.
   - Between the previous leg's arrival and this leg's departure:
     - if the previous arrival region equals this departure region, every day in
       between is a seen day in that region (the person stayed put);
     - otherwise it is a **gap**: the person changed region by some means the app did
       not see. The days strictly between the two flight days are **unknown days**,
       and the gap is listed with both flights.
4. **Before the first flight**: unknown. Not counted.
5. **After the last flight**: the person is assumed to have stayed in the last arrival
   region up to `asOf`. These days are counted but flagged as open-ended.
6. **Window.** Count, for each region, the distinct days in
   `[asOf - 179 days, asOf]` (180 calendar days, inclusive) on which the person was
   seen in that region. The whole history is walked, so the state on the first day of
   the window comes from flights before it.

A single day can count for more than one region (fly out and back the same day), and
a gap is flagged even when it covers no unknown days (arrive Monday evening in France,
depart Tuesday morning from the UK).

### Output

```swift
struct StayReport {
    let windowStart: Date, asOf: Date       // calendar days
    let seenDays: [AirportRegion: Int]      // in window
    let unknownDays: Int                    // in window, from gaps
    let gaps: [Gap]                         // previous leg, next leg, from/to region, unknown day range
    let openEndedSince: Date?               // last arrival, if counting assumed days after it
    let flightsUsed: [UUID]
    let flightsIgnored: [UUID]              // missing airports
    let overlaps: [(UUID, UUID)]            // next departs before previous arrives
}
```

Schengen is shown as a range: `seenDays[.schengen]` up to `seenDays[.schengen] +
unknownDays` (the upper end assumes every unknown day was spent in Schengen).

### Who the rule applies to

The report also says whether the person looks subject to the 90/180 rule: **not
subject** if they hold any document, active or not, issued by an EU or Schengen
country (an expired passport doesn't end citizenship). No documents → "unknown". It
still shows the count either way; this is a label, not a filter.

## Assumptions (all revisable later)

1. **Entry and exit days count as full days**, as the Schengen rule does. A day trip
   is one day.
2. **Days are local calendar days at the airport**, from `AirportTimezoneCache`.
   Falls back to UTC when the timezone isn't known yet.
3. **A flight with no time** uses its stored day.
4. **Staying put is assumed** between two flights that start and end in the same
   region, even weeks apart.
5. **Region changes between flights are unknown**, not guessed. They become gaps.
6. **After the last flight the person is assumed to stay** in the last arrival region
   until today, flagged open-ended.
7. **Before the first flight nothing is known**, and nothing is counted.
8. **Every flight in the app happened.** Cancelled flights left in the app are counted.
   The user deletes them to correct the count (a future "ignore flight" can replace this).
9. **Future flights are excluded.** A flight counts once it has departed.
10. **Window is 180 calendar days ending today, inclusive.**
11. **Channel Islands and Isle of Man (`EG`) count as UK**; Gibraltar (`LX`) is `other`.
12. **Residence permits and long-stay visas are not known** to the app, so the
    "subject to the rule" label can be wrong for those holders.
13. **Overlapping flights** (next departs before previous arrives) are processed in
    departure order and flagged as a data problem.

## UI (thin)

- `PersonEditView`: a **Travel Days** row opening `StayReportView`.
- `StayReportView`:
  - Header: window dates, "Based on N flights in this app".
  - One row per region with seen days. Schengen shows the range when there are
    unknown days, e.g. "62 days (up to 74 with gaps)", and the subject label.
  - **Gaps** section: each gap as "Arrived LFAC 3 Mar, next departs EGTF 14 Mar,
    no flight between", tapping a flight opens it so the user can fix or add a leg.
  - Open-ended note when assumption 6 applies.
  - Footer: "Counts only flights recorded in this app. It is not a legal calculation."
- No warning colours or thresholds. The user decides.
- Strings in EN/FR/DE/ES per `designs/localisation.md`.

## Tests

`flyfun-formsTests/StayReportTests.swift` and `AirportRegionTests.swift`, unit target
(runs in CI). Every assumption above has at least one test, so changing an
assumption later means changing a named test.

**Counting**
- Same-day out and back: 1 Schengen day and 1 UK day.
- Out day 1, back day 3: 3 Schengen days.
- Schengen internal hop (LFAC → LFPN) with days between: continuous, no gap.
- Two trips in the window: counts add, shared days not double counted.
- Person on the same flight as crew and passenger: counted once.
- Crew on one leg, passenger on the next: both used.

**Window**
- Trip ending on `asOf - 180`: excluded. Ending on `asOf - 179`: one day included.
- Trip straddling the window start: only the days inside count.
- Stay that began before the window (state from an earlier flight).
- Leap day (29 Feb) inside the window: still 180 calendar days.
- DST change inside a stay: day arithmetic by calendar, not 86 400 seconds.

**Time**
- Departure 23:30 local, arrival 00:30 local next day: departure day in origin,
  arrival day in destination.
- Arrival 23:30Z in Greece in summer is the next local day.
- Unknown timezone: UTC fallback.
- Flight with no times.

**Gaps**
- Arrive LF, next departs EG with days between: gap, unknown days counted, range shown.
- Same, adjacent days: gap flagged, zero unknown days.
- First flight departs from Schengen: nothing counted before it.
- Last flight arrives in Schengen: days to `asOf` counted, open-ended set.
- Overlapping flights: flagged.
- Missing origin or destination: ignored and listed.
- Future flight: excluded.

**Regions**
- `LZ` Schengen; `LC`, `EI` EU non-Schengen; `GC` Schengen; `ENSB`, `EKVG` other;
  `EGJJ` UK; `LXGB` other; unknown prefix other.
- `DocumentResolver`: existing tests still pass; Ireland prefers an EU document;
  Slovakia prefers an EU document.

**Subject label**
- GBR only: subject. GBR + FRA: not subject. Expired FRA only: not subject.
  No documents: unknown.

## Out of scope (possible later)

- "Ignore flight" without deleting it.
- A lightweight non-GA leg (airline, ferry) distinct from a GA flight.
- Projection with planned future flights ("84 days on 12 November").
- Warnings and thresholds.
- UK-specific rules (no rolling count for visitors today).
- Moving the region table to rzflight.
- Android report.
