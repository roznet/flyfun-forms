# Submission Server

> Server-mediated flight submission: pilots file once, airports see a live queue, identity data stays end-to-end encrypted

**Status: proposal.** Nothing here is implemented. This is a design to argue
with, not a build plan.

## Intent

Today the app fills an airport-specific form and the pilot emails it. The
airport receives a PDF in a shared mailbox and does whatever it does. Nobody
gets confirmation, nothing is queryable, and every airport invented its own
process.

Replace the *transport*, keep the *artifact*: the pilot submits to
`forms.flyfun.aero`, the airport sees it in a console, and can acknowledge,
approve, reject or request changes. The pilot gets a signed receipt proving
they filed on time. The airport gets an arrivals queue, aircraft and visitor
history, and eventually ADS-B-driven "this flight just departed" updates.

Crucially, the server **cannot read passenger identity data**. That property is
designed in from the first line — see
[flyfun-common/designs/e2ee.md](../../flyfun-common/designs/e2ee.md).

## The problem, quantified

The current `email_overrides` map is the evidence. In
`src/flightforms/mappings/french_customs.json`:

- **51 French airports**, **48 distinct recipient addresses**, nearly all
  `bse-<city>@douane.finances.gouv.fr` — one regional customs brigade per field.
- `src/flightforms/mappings/lsgs.json` → a single `aeroport@sion.ch` mailbox.
- `src/flightforms/mappings/lfqa.json` → yet another office (CODT Metz),
  covering three airports.
- `myhandling.json` → 117 airports through a commercial handling agent, an
  entirely different channel again.

Notification requirements have been delegated to individual fields and regional
offices, and each arrived at its own answer: a PDF by email, a spreadsheet, a
bespoke web form. That fragmentation is the product opportunity — and the reason
this must be additive rather than a replacement.

## Design partners

Two fields, deliberately chosen to differ:

| | **Swiss GA field** (LSGS-shaped) | **French GA field** (LF*-shaped) |
|---|---|---|
| Current channel | single airport mailbox | regional customs brigade mailbox |
| Recipient | aerodrome operator | state customs office |
| Driver | Schengen member, **outside the EU customs union** — goods declaration applies even on intra-Schengen flights | EU + Schengen — border/immigration interest concentrated on non-Schengen arrivals |
| Fields required today | first/last name, DOB, nationality, ID number | first/last name, nationality, ID number |
| Adoption difficulty | lower — the aerodrome owns its own inbox | higher — a state office with existing procedure |

The asymmetry is the point. If the field-group model survives two authorities
with different legal drivers and different required fields, it will survive the
third. Start with the aerodrome operator: it has no state-mandated channel to
displace and directly benefits from an arrivals queue. Approach the customs
brigade second, with a working system to demonstrate.

*(Legal drivers above are design assumptions, not advice — confirm with each
authority during onboarding. They shape which field groups exist, so getting
them wrong is expensive.)*

## Data tiers

The decision that precedes everything. Every feature request resolves to "which
tier does this field live in," and getting it wrong is a migration, not a patch.

| Tier | Fields | Server sees | Why |
|---|---|---|---|
| **0 — Routing** | submission id, status, origin/destination ICAO, ETD/ETA, registration, aircraft type, crew/pax **counts**, direction | **plaintext** | Required for the arrivals queue, notifications, ADS-B matching, "when did this aircraft last visit" |
| **1 — Identity** | ID/passport number, document type, issuing country, expiry, DOB, place of birth, nationality, address, phone, email | **ciphertext** | Never needed server-side. This is the whole risk surface. |
| **2 — Linkage** | "is this the same person as last time" | **opaque 16-byte tag** | Visitor history without identities — client-computed blind index |

Names are the genuinely contested case. They are Tier 1 here. An airport that
wants a name on the arrivals board gets it after decryption, in its own client —
not from the server. That costs a server-rendered board and is worth it; names
plus route plus date is effectively identifying.

### Field groups

Tier 1 is not one blob. It splits into groups, each with its own DEK, so
different recipients see different subsets of the same submission:

| Group | Contents | Customs | Aerodrome ops | Handling agent |
|---|---|---|---|---|
| `identity_docs` | doc number, type, issuing country, expiry, nationality | ✅ | ⚪ configurable | ❌ |
| `personal_details` | full name, DOB, place of birth, sex | ✅ | ⚪ | ❌ |
| `contact` | responsible person, phone, email | ✅ | ✅ | ✅ |
| `aircraft_owner` | owner name and address | ✅ | ✅ | ⚪ |

A handling agent needs to know who to meet, not their passport number. One
submission, three recipient views, no duplicate filing. This is the concrete
answer to "visible to one party but not another."

Group membership is derived from the existing `required_fields` in each mapping,
so an airport's entitlements stay consistent with the form it already receives.

## Architecture

```
┌─────────────┐   submit (tier0 + sealed groups + Ed25519 sig)
│  iOS/macOS  │ ──────────────────────────────────────┐
│  flyfun-    │                                       ▼
│  forms app  │ ◄──── receipt / status ────┐   ┌──────────────────────┐
└─────────────┘                            └───│ forms.flyfun.aero    │
      │ seals with airport bundle              │  submissions API     │
      │ (root-verified, pinned)                │  ── cannot decrypt ──│
      ▼                                        │  tier0 + blobs + tags│
┌─────────────┐                                └──────────────────────┘
│ key bundle  │ ◄── root-signed ───┐              ▲          │
└─────────────┘                    │              │          │ notify
                                   │              │          ▼
      FlyFun Root (air-gapped) ────┘        ┌──────────────────────┐
                                            │ airports.flyfun.aero │
   ┌────────────────┐   no console yet      │  airport console     │
   │ email fallback │ ◄─────────────────────│  decrypts in-client  │
   │ (unchanged)    │                       └──────────────────────┘
   └────────────────┘                                 ▲
                                            ADS-B ────┘ (tier 0 only)
```

New surface, following the existing subdomain-SSO pattern from `auth.md`:

```
src/flightforms/
├── api/
│   ├── submissions.py    # POST /submissions, GET /submissions/{id}, amend, withdraw
│   ├── inbox.py          # airport-side: queue, decisions, history
│   └── keys.py           # key bundle publication + verification (thin over flyfun-common)
├── db/models.py          # SubmissionRow, DecisionRow, VisitTagRow  (tier 0 + opaque only)
└── console/              # airports.flyfun.aero — decrypts client-side
```

Airport staff will not have Google/Apple accounts. **Passkeys (WebAuthn) are the
console's auth mechanism**, with the existing `magic_link_tokens` path used only
for first-time enrolment and device recovery.

This is deliberate and worth the extra build. The realistic attack on this
system is not broken cryptography — it is a convincing spear-phish against an
airport mailbox, and phishing quality is exactly what has improved most in the
last two years. An email-delivered credential is phishable by construction;
a passkey is origin-bound and cannot be replayed against a lookalike domain.
Since an officer's session decrypts real passport data, phishing-resistant auth
is load-bearing, not a nicety — a stolen console session yields everything that
officer can see, whatever the encryption does.

Magic links remain acceptable for enrolment because that step is chaperoned
during onboarding, and because a device added to an org is visible to every
other member.

## Submission lifecycle

```
draft ──submit──► filed ──ack──► received ──┬──► approved
                    │                       ├──► rejected  (reason, signed)
                    │                       └──► changes_requested
                    │                              │
                    ├──amend──► filed (v+1, prev_hash chain)
                    └──withdraw──► withdrawn  (crypto-shred: envelopes deleted)
```

- Every transition is **Ed25519-signed** by the acting party and appended to a
  hash chain. The pilot can prove "filed 48h ahead" and show a verifiable
  approval **offline** — arguably more valuable than the encryption, and
  routinely forgotten in designs like this.
- Amendments are new versions with fresh DEKs, never in-place edits. Flights
  change constantly; the audit trail is the product.
- Withdrawal deletes envelopes. The ciphertext stays inert in backups forever.

### Retention

Tier 1 lives on the server only until the airport acknowledges, then **N days**
(default 30, per-airport configurable), then envelopes are shredded. Tier 0
persists for history and dashboards.

This matters philosophically. `PRIVACY.md` currently claims *"never retained by
the server"* — a claim this project cannot keep once it becomes a mailbox. The
defensible evolution is **"stored briefly, in a form we cannot read"**; the
indefensible one is quietly becoming a passport-number database. Retention
policy is what keeps the first sentence true, and `PRIVACY.md` must be rewritten
alongside phase 1, not after it.

## Email stays first-class, forever

Adoption will be partial for years, and the non-adopting majority must not
notice this project exists.

- The pilot flow is unchanged: pick airport → fill → send. The app resolves
  transport from the airport's onboarding status, and says "submitted to Sion"
  or falls back to the mail composer.
- **The server path produces the same filled artifacts.** The
  `form-system.md` registry, mappings, fillers and snapshot tests are untouched;
  an onboarded airport downloads the identical PDF/XLSX it used to receive by
  email, now alongside structured data. Onboarding an airport is a config flag,
  not a data-model migration — and de-onboarding is the same flag.
- A partially-onboarded trip (Sion server-side, next leg by email) must be
  ordinary, not an error path.

This also hedges the largest risk in the whole idea: if authorities decline to
accept a third-party intermediary, the product degrades to exactly what it is
today rather than to nothing.

## Airport console

What an airport actually gets, in rough value order:

1. **Arrivals/departures queue** — tier 0, no crypto, useful on day one.
2. **Decide** — acknowledge, approve, reject with reason, request changes.
3. **Open a submission** — client-side decrypt, render, print the same PDF.
4. **Aircraft history** — "when did this registration last come" — pure tier 0.
5. **Visitor history** — via blind-index tags, computed in-client after
   decryption. Per-org index keys mean Sion and France cannot correlate.
6. **Export** — the airport's own records, their retention obligation.

Feature 4 is worth shipping before any crypto exists. It is the cheapest
demonstration that a server in the middle beats a shared mailbox, and it
requires nothing from this design beyond tier 0.

## ADS-B

Entirely tier 0, no crypto involvement, independently buildable: match
`registration` against a feed, drive "departed" / "30 min out" / "landed"
transitions, flag no-shows and unannounced arrivals.

Two honest caveats. ADS-B is public data, so nothing here is a privacy
concession — but it *is* another correlation source pointed at the same tail
numbers, so retention should be short and its purpose explicit. And GA aircraft
are unreliably equipped; treat every signal as advisory and never let a missing
one block a decision.

## Phasing

| Phase | Deliverable | Depends on crypto? |
|---|---|---|
| **0** | Field-tier table agreed; `PRIVACY.md` rewritten | No |
| **1** | Tier-0 submissions + console queue + aircraft history, one design partner | No |
| **2** | Envelope encryption, root-signed bundles, native iOS sealing | Yes |
| **3** | Signed decisions + offline receipts | Ed25519 only |
| **4** | Blind-index visitor history | Yes |
| **5** | ADS-B status | No |
| **6** | Second partner, staff management, rotation | Yes |

Phases 0, 1 and 5 need none of the cryptography. Building the key
infrastructure before one real officer has clicked "approve" on one real flight
is the way this dies at 80% complete: the crypto is the tractable part, and
adoption is not.

## Key choices

- **Same artifacts, new transport** — reuse the entire form system rather than
  inventing a parallel structured channel. Airports keep the document they know.
- **Tier the data before designing anything else** — every later decision falls
  out of it, and it is free to change today.
- **Field groups over one encrypted blob** — different recipients legitimately
  need different subsets; one submission should serve all of them.
- **Aerodrome operator first, customs second** — pick the party that owns its
  own inbox and gains immediately.
- **Email path permanent** — partial adoption is the expected steady state, not
  a transition.
- **Signed decisions, not just encrypted payloads** — non-repudiation is
  independently valuable and cheap.

## Open questions

- Do authorities accept a private intermediary at all? Some may require direct
  submission. Determines whether phase 2+ is worth building.
- Is flyfun a data controller or processor here? Affects retention, DPA
  paperwork and breach obligations, and the answer likely differs CH vs FR.
- Console as web (adoption) or native (real integrity against us)? See the
  threat model in `e2ee.md`.
- Does an airport need to forward to a third party without pilot re-encryption?
  Possible, but weakens the "only the addressed airport" claim.
- What happens on diversion? Re-sealing to an unplanned airport in flight, with
  no connectivity, is unsolved — probably falls back to email.

## References

- [flyfun-common e2ee](../../flyfun-common/designs/e2ee.md) — key hierarchy, wire format, trust root
- [form-system](./form-system.md) — mappings and fillers, reused unchanged
- [api](./api.md) — current stateless generation endpoints
- [ios-app](./ios-app.md) — client that would do the sealing
- [flyfun-common auth](../../flyfun-common/designs/auth.md) — magic-link path for airport staff
