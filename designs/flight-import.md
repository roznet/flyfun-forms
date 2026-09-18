# Flight Import

> How a new flight in the iOS/macOS app gets its route, schedule, aircraft and people
> from somewhere other than typing: clipboard flight plan, FlyFun Weather, Autorouter,
> or a previous flight.

## Intent

Creating a flight by hand is four route fields plus a people picker, and almost every
flight a pilot files resembles one that already exists somewhere: on the clipboard as an
ICAO FPL, in FlyFun Weather where the briefing was planned, in their Autorouter history,
or in this app as last month's trip down the same route with the same crew.

Import exists to make the common case a tap, not a form. The design goal is that the
method the pilot wants is the one already showing, and that an import fills the *people*
step as well as the route step, because that is where the typing actually is.

## Architecture

```
NewFlightFlow (route + people steps)
      ▲
      │ apply(draft:)                    ← the single writer of form state
      │
  FlightDraft ───────────────────────────────────────────┐
      ▲            ▲              ▲              ▲        │
      │            │              │              │        │
 ICAOFlightPlan  FlightExchange  FlightExchange  Flight   │  + PeopleSuggestion
 (clipboard)     (weather)       (autorouter)  (previous) │
      │            │              │              │        │
 RZFlight        WeatherImport   Autorouter    SwiftData  │
 parser          Service         ImportService  @Query    │
```

### An import replaces what an earlier import wrote

`apply(_:)` replaces the people and form-level fields rather than merging into them.
Merging meant that importing a previous flight (crew, nature, observations) and then
changing your mind and importing an unrelated route from the clipboard left the first
flight's crew in place — on a customs form, the wrong people on the document.

The replacement is scoped by ownership, tracked in `peopleCameFromImport`: a selection an
import wrote is replaced or cleared by the next import, and a selection the pilot made by
hand (through the people picker, the suggestion chip, or copying a flight's crew) survives, so
re-importing a route to fix a typo does not wipe the crew they just chose. The
form-level fields (`responsiblePerson`, `nature`, `contact`, `observations`) have no
editor in this flow, so an import is their only source and they are replaced
unconditionally.

Route fields keep their `if !isEmpty` guards: an empty departure in a draft is a parse
defect, not an instruction to clear a good value.

### `FlightDraft` — the in-app import result

`Models/FlightDraft.swift`. Every import method produces one, and `NewFlightFlow`
consumes only this. Adding a method never touches the form.

```swift
struct FlightDraft {
    var route: Route                     // RZFlight.Route — the route truth
    var registration: String?
    var aircraftType: String?
    // local-only, never crosses an app boundary
    var crew: [Person] = []
    var passengers: [Person] = []
    var responsiblePerson: Person?
    var nature: String?
    var observations: String?
    var provenance: Provenance
}
```

**Why not use `FlightExchange` as the internal type.** `FlightExchange` is deliberately
PII-free (see rzflight `designs/flight_exchange_design.md`, "Deliberately excluded"), and
the "previous flight" method must carry crew, passengers and the responsible person.
`FlightExchange` stays the *wire* type for anything that crosses an app boundary;
`FlightDraft` is the *in-app* type. Weather and Autorouter both arrive as a
`FlightExchange` or an `ICAOFlightPlan` and are widened into a draft at the boundary.

### `FlightImportMethod` — methods as data

`Services/FlightImportMethod.swift`. A `CaseIterable` enum plus a `FlightImportContext`
snapshot (`hasPastFlights`, `clipboardHasText`, `isSignedIn`, `autorouterLinked`). Each
method reports an `Availability` and the UI renders an unavailable method greyed with its
reason rather than hiding it, so "Import from Autorouter" is discoverable before the
account is linked.

`autorouterLinked` is `Bool?`, filled by `GET /api/autorouter/status` when the form opens.
**Unknown counts as available**: a check still in flight must never hide a method that
works, and the picker's own 409 still explains it if the answer turns out to be no. Being
signed in is deliberately not enough to offer Autorouter — without the linked check the
pilot taps, waits on a spinner, and learns the same thing from a 409.

### Context ranking, not last-used

One **Import…** button opens the list of all four methods, ordered by what the current
context makes likeliest, with the unusable ones last (`rankedOrder(for:)`). Ranking:

1. Clipboard holds text that parses as an ICAO FPL
2. Any past flights exist → "Previous flight"
3. Signed in → "FlyFun Weather"
4. Autorouter, when the account is linked

A last-used sticky order was considered and rejected: two of the four methods are
contextual rather than habitual (a clipboard FPL is only useful when there is one on the
clipboard; "previous flight" is the overwhelming choice for a repeat trip), rows that move
under the pilot cost muscle memory, and a fresh install has no last-used value to show.

The row led with the top-ranked method as a labelled button ("Repeat EGTF → LFRM") and put
the list behind a chevron. That was dropped: the same choice appeared twice, and the
button's meaning changed under the pilot as the clipboard or the flight history changed.
Ranking now only decides the order inside the list, where being wrong costs a glance
rather than a wrong flight.

### Import reaches people, not just the route

`applyRoute` historically filled origin/destination/times/aircraft and stopped. The route
step is four fields; the people step is the slow one. So:

- **Previous flight** copies crew, passengers, responsible person, nature and contact
  outright (`Flight.copyCommon(to:)` semantics).
- **Every other method** offers a one-tap `PeopleSuggestion` on the people step: the crew
  and passengers of the most recent flight flown with the same aircraft, falling back to
  the most recent flight overall, falling back to `isUsualCrew`.
- **"Choose another flight…"** sits beside the chip and opens `CrewSourcePickerView`:
  the same copy with the choice handed back, for a pilot who flies with different people
  on different trips. Rows are deduplicated by *the people*, not the route, so a weekly
  trip with the same four aboard is one row rather than eight that differ by date.

### The aircraft starts filled in

`Aircraft.defaultForNewFlight(flights:available:)` opens the form on the aircraft the
pilot last flew, falling back to the only one on file, and to nil when there is neither.
Most pilots fly one aircraft, or the same one for a stretch, so "None" asked every new
flight for an answer already on record. A wrong guess costs one tap in a picker the pilot
can see; no guess costs one every time.

Last-flown outranks the single-aircraft rule, so adding a second aircraft mid-season stops
offering the one it replaced as soon as the new one is flown. Applied once per sheet
(`hasDefaultedAircraft`) — `onAppear` fires again coming back from a picker, and a pilot
who sets the aircraft to None means it. An import carrying a registration still wins, via
`resolveOrCreateAircraft`.

It also sharpens the people step: `PeopleSuggestion` prefers the most recent flight in the
*same aircraft*, which is only reachable when an aircraft is set before that step.

`PeopleSuggestion` is deliberately *not* built on `Person.coTravelers(minimumFlights:)`,
which `PeoplePickerView` uses for its Groups section. The two answer different questions
and are both wanted: `coTravelers` answers "who usually flies with this person" and needs
a person already selected to anchor it, so it widens a selection that exists;
`PeopleSuggestion` answers "who was on board last time", which is the only one of the two
that can fill an *empty* people step in one tap.

### Re-dating a previous flight

`Flight.nextOccurrence(of:duration:now:zone:)` is a pure static on the model, unit-tested,
and is the only place the rule lives:

- Keep the original **time of day**, read in the **origin airport's timezone** when
  `AirportTimezoneCache` has resolved it, UTC otherwise. Pilots think "the 09:00 out of
  EGTF", not "the 08:00Z".
- If that time of day is still ahead of `now`, use today; otherwise tomorrow.
- Set the arrival as `departure + (oldArrival - oldDeparture)` so an overnight leg keeps
  its duration instead of being flattened onto the departure day.

## Autorouter: one client, two apps

flyfun-weather already shipped Autorouter import (`api/flights.py`, the
`/autorouter-routes` endpoint, ~180 lines of `router/logs` fetch + normalise + clear-token-
on-401). Forms needs the same thing, so the client moves down into **flyfun-common**,
which already owns the OAuth link flow and `get_autorouter_token`:

```
flyfun_common.autorouter
    get_autorouter_token(db, user_id)             (existing)
    list_recent_routes(token, limit)              (new — pure HTTP + normalise)
    fetch_recent_routes(db, user_id, limit)       (new — token glue + 401 clears token)
    create_autorouter_routes_router(...)          (new — GET {prefix}/routes + /status)
```

Weather's endpoint becomes a thin wrapper over the same function; forms mounts the
router. Neither app owns a second copy of the payload quirks.

**No second OAuth registration.** Forms and weather share one MySQL database and one
Fernet key, so the token the pilot linked on weather is readable from forms via
`get_autorouter_token`. Forms does not mount the link flow and does not need its own
redirect URI registered with Autorouter. When no token is stored the endpoint answers
`409 autorouter_not_linked` and the app points the pilot at the weather web app to link.

**Forms parses the FPL locally.** Weather returns the raw `fplan` and posts it back to
`/flights/parse-fpl`. Forms has `RZFlight.ICAOFlightPlanParser` in-process, so it parses
the `fplan` client-side and lands on the same `FlightDraft` as the clipboard path: one
round trip instead of two, and one parser for both methods.

## Key Choices

- **One draft type, one writer.** `NewFlightFlow.apply(draft:)` is the only code that
  writes form state. Two import paths already converged on `applyRoute`; the refactor
  generalises that rather than replacing it.
- **`FlightExchange` on the wire, `FlightDraft` in the app.** Keeps the cross-app contract
  PII-free while letting a local import carry people.
- **Context ranking over last-used.** See above.
- **Autorouter client in flyfun-common, not euro_aip.** `euro_aip`'s `AutorouterSource` is
  AIP-document oriented with a cache-dir constructor, and the token lives in the shared
  DB that flyfun-common owns. Putting the client there keeps it to one repo.
- **The `+` opens the form directly.** It was a menu (New Flight / Repeat … / Import…),
  on the reasoning that repeating last week's trip should not need the form first. In use
  the menu was a tap spent choosing where to choose: the form's first row is the import
  control, and repeating a flight is one of the methods there.

## Gotchas

- **`UIPasteboard.general.string` prompts.** Reading the pasteboard raises the system
  "Allow Paste?" alert on modern iOS. Gate the *suggestion* on the non-prompting
  `hasStrings`, and read the string only when the pilot commits to the method.
- **A failed paste must say so.** The original `pasteFlightPlan()` did
  `guard let plan = … else { return }`, so an unparseable clipboard looked like a dead
  button.
- **Use the schedule setters.** `departureDateTime` / `arrivalDateTime` dual-write the
  legacy `departureDate` + `departureTimeUTC` pair *and* the instant. Writing
  `departureDate` alone (as `createReturnFlight` and `createNextLeg` did) leaves
  `hasDepartureTime` false and `departureInstant` nil, so the flight reads as having no
  time entered. See the CloudKit migration note in `Models/Flight.swift`.
- **Autorouter deployment assumption.** The shared-token design depends on forms and
  weather pointing at the same `DATABASE_URL` and sharing the Fernet key. If those ever
  diverge, forms loses Autorouter import with a 409 rather than failing loudly.
- **New UI strings need a build.** `Localizable.xcstrings` is populated by Xcode's
  extraction; the new strings land untranslated until fr/de/es are filled in.

## Status

- `FlightDraft` + `FlightImportMethod` + context-ranked list: **complete**
- Previous-flight import with re-dating: **complete**
- People suggestion on the people step, and copy-crew-from-a-flight: **complete**
- Import entry point on the flight list: **complete** — the `+` opens the form, which
  leads with the import control
- Autorouter import (shared client in flyfun-common): **complete**
- Share / deep-link import from weather (`flyfunforms://import`): **planned** — the real
  frictionless path, since it starts in the app the pilot is already in

## References

- [ios-app.md](./ios-app.md) — the app this lives in
- rzflight `designs/flight_exchange_design.md` — the cross-app wire format
- flyfun-common `designs/autorouter.md` — the OAuth link flow and token storage
- flyfun-weather `app/.../Views/Flights/AddFlightView.swift` — the sibling import menu
