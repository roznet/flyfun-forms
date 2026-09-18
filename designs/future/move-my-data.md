# Move My Data: Encrypted Device Transfer + GDPR Export

> **Status: proposed. Nothing built. Written 2026-09-18.**
>
> Two user-facing features that share **one serializer**:
>
> 1. **Move my data** — an encrypted, password-protected file that carries a
>    pilot's people, aircraft, flights and travel documents to another device.
> 2. **Export my data** — the GDPR Art. 20 portability export, which we do not
>    currently have.
>
> They differ only in encryption and framing. Building them as one payload with
> two wrappers is the whole design.

## Related docs

- [Android app](./android-app.md) — this document is a **prerequisite** for that plan (§7)
- [iOS app](../ios-app.md) — the SwiftData models being serialized
- [API](../api.md) — where the server-side half of the GDPR export lands
- [people_import](../people_import.md) — the existing CSV format, and why it is not this

---

## 1. Why this exists

### It is the only iOS↔Android bridge

CloudKit is Apple-side. Google Drive `appDataFolder` is Google-side. Nothing
bridges them except a server we operate — which
[android-app.md §3](./android-app.md#3-gate-the-sync-model) refuses, because
holding passport numbers server-side would make us the controller and force a
rewrite of `PRIVACY.md`, the GDPR Art. 30 record and
`legal/PROCESSOR_TERMS.md`.

A file costs roughly 1% of that and breaks nothing.

### It solves three problems we have today, with no Android app in sight

- **Disaster recovery.** CloudKit is currently the *only* copy. No Apple ID, no data.
- **GDPR Art. 20.** We have `DELETE /auth/account` (Art. 17) but no portability export. See §3.
- **Android test fixtures.** Real exported files become the Android importer's test corpus on day one.

### It forces the UUID migration at the cheapest possible moment

See §7. This is the sleeper argument and the main reason to build it **before**
any Android work.

---

## 2. What we have today, and why it is not this

`Views/PeopleListView.swift:117-120` already offers "Export to CSV", paired with
`Services/PeopleCSVImporter.swift`. `CSVExportDocument` (same file, line 257)
writes one row per travel document:

```
First Name, Last Name, Gender, DoB, Nationality,
Doc Type, Doc Number, Doc Expiry, Doc Issuing State, Type
```

That is a good **seeding** format — bulk entry from a spreadsheet — but it
cannot round-trip:

| Problem | Consequence |
|---|---|
| No stable IDs | Re-importing duplicates, or falls back to name matching |
| Lossy | Drops `phone`, `email`, `address`, `placeOfBirth` |
| People only | No aircraft, flights, trips, or crew/passenger assignments |

**Keep the CSV for what it is good at.** The transfer format is a separate
thing, and the two should not be merged.

---

## 3. The GDPR gap

Art. 20 requires a copy of the user's personal data in a *structured, commonly
used, machine-readable* format. We do not have one. The data lives in two
places, so the export has two halves.

### Server half — does not exist, should

`flyfun-weather` already has the pattern: `src/weatherbrief/api/account_export.py`
serves `GET /account/export` as JSON with a `Content-Disposition` attachment
header, mirrors the table coverage of `_on_delete_user`, and carries an
`_EXCLUDE` list so secrets and server-internal fields never leave.

For forms the payload is small, because the server deliberately holds almost
nothing:

| Table | Source | Notes |
|---|---|---|
| `users` | `flyfun_common.db.UserRow` | Account record |
| `usage` | `db/models.py::Usage` | endpoint, airport ICAO, form id, timestamp |
| `api_tokens` | `flyfun_common.db.ApiTokenRow` | **Metadata only** — never the SHA256 hash |

Mirror `_on_delete_user` (`api/app.py:93-95`) exactly: **whatever deletion
covers, export must cover.** The two drifting apart is the classic GDPR bug.

### Device half — the same payload as "move my data"

The people, documents, aircraft, flights and trips are on the device and have
never been on the server. The app's own export *is* the device half.

**Art. 20 wants machine-readable.** An encrypted blob the user holds the
password to is arguably compliant, but a plaintext option is cleaner and avoids
the argument entirely. Hence:

| Feature | Encryption | Framing |
|---|---|---|
| Move my data | **Encrypted, password required** | "Move to another device" |
| Export my data | Plaintext JSON, clearly labelled, with a warning | "Download a copy of my data (GDPR)" |

Same serializer. Two buttons. Different wrappers.

---

## 4. Format

Flat arrays with an explicit join table — **not** a nested object graph.
Nesting forces ownership decisions and makes per-record merge awkward; flat
arrays map 1:1 onto both SwiftData objects and Room entities and merge
independently.

```json
{
  "format": "flyfun-forms/data",
  "version": 1,
  "exportedAt": "2026-09-18T14:22:03Z",
  "exportedBy": { "platform": "ios", "appVersion": "1.7" },

  "people": [
    { "id": "8f14e45f-...", "firstName": "...", "lastName": "...",
      "dateOfBirth": "1975-04-12", "sex": "Male", "placeOfBirth": "...",
      "phone": "...", "email": "...", "address": "...",
      "isUsualCrew": true,
      "updatedAt": "2026-09-12T09:01:44Z", "deletedAt": null }
  ],
  "travelDocuments": [
    { "id": "c9f0f895-...", "personId": "8f14e45f-...",
      "docType": "Passport", "docNumber": "...", "issuingCountry": "FRA",
      "expiryDate": "2031-06-30", "isActive": true,
      "updatedAt": "...", "deletedAt": null }
  ],
  "aircraft": [ /* registration, type, owner, ownerAddress, isAirplane, usualBase */ ],
  "trips":    [ /* name, createdAt, extraFields */ ],
  "flights": [
    { "id": "...", "originICAO": "EGTF", "destinationICAO": "LFRM",
      "departureInstant": "2026-09-20T08:15:00Z",
      "arrivalInstant":   "2026-09-20T10:05:00Z",
      "nature": "private", "observations": null, "contact": null,
      "legOrder": 0, "tripId": null,
      "aircraftId": "...", "responsiblePersonId": "...",
      "updatedAt": "...", "deletedAt": null }
  ],
  "flightPeople": [
    { "flightId": "...", "personId": "...", "role": "crew" }
  ]
}
```

### Two deliberate choices

**Export instants, never the legacy date+time pair.** `Models/Flight.swift:7-27`
documents the in-flight migration from `departureDate` (local midnight) +
`departureTimeUTC` to `departureInstant`. An interchange format is exactly the
wrong place to encode a representation we are actively migrating away from — and
an offset-less datetime crossing between devices in different zones is the bug
that comment block describes having already been fixed once. Export the absolute
instant with an explicit `Z`; let each platform derive its local view. This also
pushes the iOS instant migration forward rather than cementing the pair.

**Calendar days stay calendar days.** `dateOfBirth` and `expiryDate` are
`YYYY-MM-DD` with no time component. They are facts printed in a passport, not
instants; giving them a timezone is how someone ends up born a day earlier in
Sydney.

### No binary payloads

Verified 2026-09-18: nothing binary is persisted. The only `Data` field in the
models is `Trip.extraFieldsData`, which is a JSON-encoded `[String: String]`.
Scanned passport images are parsed and discarded, never stored. **A single JSON
file is sufficient** — no zip container needed.

---

## 5. Encryption

The file contains passport numbers and leaves the app sandbox — into Downloads,
a share sheet, WhatsApp, email — where it persists, gets backed up and gets
indexed. Plaintext passport data sitting in a Downloads folder is precisely the
artifact to avoid.

**Encrypted by default, password required to reopen.**

| Concern | Choice |
|---|---|
| Cipher | AES-256-GCM |
| Key derivation | Argon2id (preferred) or PBKDF2-HMAC-SHA256 at high iteration count |
| iOS | CryptoKit |
| Android | Tink (cross-platform consistency) |
| Salt / nonce | Random per export, stored in the file header |

**Passphrase UX:** generate a 6-word passphrase on export, display it, the user
types it on the receiving device. This beats user-chosen passwords — which will
be weak and reused — and reads naturally as a one-time transfer code.

The plaintext GDPR variant (§3) is an explicit, separately-labelled action with
a clear warning, never the default.

**Wrong password must fail cleanly.** GCM authentication failure → "that
password doesn't match this file", not a parse error or a partial import.

---

## 6. Merge semantics

Import **merges**; it never replaces. Match on `id`, then:

| Case | Action |
|---|---|
| In file, not local | Insert |
| In both | Newer `updatedAt` wins — whole record (field-level merge is overkill here) |
| Local only, not in file | **Keep.** Never delete on import |
| `deletedAt` in file, newer than local `updatedAt` | Delete locally |

That last row is why tombstones matter: without them, importing a file from a
device where an expired passport was deleted silently resurrects it.

**Show a preview before applying:**

> 12 new people · 3 updated · 1 removed · 45 unchanged

with a confirm. A blind merge over passport records destroys trust, and the
preview is nearly free once the merge is a pure function returning a diff.

### This is sync's reusable first half

Export/import with per-record merge is not a lesser cousin of sync — it is
sync's first half, and specifically the half that is pure, testable,
platform-independent logic. If Drive `appDataFolder` sync is ever added
([android-app.md §3](./android-app.md#3-gate-the-sync-model), Option B), it
becomes *"automate the file transfer"* with the merge already written and
tested.

A destructive "replace everything" import would be trivial to build and a dead
end. Do not build it.

**Write the merge as a pure function with a golden-file test corpus.** The
Kotlin port is then mechanical and verifiable — the same pattern that makes the
existing 1,631 lines of Swift tests so valuable.

---

## 7. The UUID prerequisite

The SwiftData models have **no stable external IDs** — `Person` and friends rely
on `PersistentIdentifier`, and `designs/ios-app.md` already records that
*"SwiftData + CloudKit doesn't support unique constraints."*

Export forces the issue: a file without stable IDs cannot round-trip (§2).

**Do this on iOS now, while CloudKit is the only consumer.** Adding a UUID
column to `Person`, `TravelDocument`, `Aircraft`, `Flight` and `Trip` is a
CloudKit-synced schema change — which, per the `departureInstant` experience, is
a multi-release exercise paced by how quickly users update. Far better to start
it for a feature that pays for itself immediately than to discover it is needed
in Android Phase 1, with rows already sitting on two platforms' devices.

Add `updatedAt` and `deletedAt` in the same migration. They cost nothing and
§6 depends on both.

---

## 8. Privacy, legal and framing

**`PRIVACY.md` needs a paragraph.** It currently says data never leaves the
device except transiently for form generation. An export file deliberately
leaves. Document what the file contains, that it is encrypted by default, and
that the user controls where it goes.

**`legal/GDPR.md` gains a portability entry** — §3 makes Art. 20 airtight rather
than merely arguable.

**Framing matters.** An export of "people" is an export of *other people's*
passport data. Someone will eventually use it to send crew details to another
pilot.

Frame the feature as **"move my data to my other device"** and **"backup"**.
Do not build a per-person share flow, and do not place it near anything that
reads as sharing. If a pilot chooses to forward the file onward that is their
call as controller of their own records — but the app must not suggest it.

---

## 9. Phasing

| Step | Where | Effort |
|---|---|---|
| **1.** UUID + `updatedAt` + `deletedAt` migration | iOS | Small in code; paced by release cadence (§7) |
| **2.** Serializer + merge as a pure function, with golden-file tests | iOS | ~½ session |
| **3.** Encryption, passphrase generation + entry UI | iOS | ~½ session |
| **4.** `fileExporter` / `fileImporter` + preview sheet | iOS | ~½ session |
| **5.** `GET /account/export` (server half) | forms server | ~½ session, follows the weather precedent |
| **6.** Plaintext GDPR variant + `PRIVACY.md` / `legal/GDPR.md` updates | iOS + docs | small |
| **7.** Kotlin importer against real fixtures | Android | falls out of [android-app.md](./android-app.md) Phase 1 |

Roughly **one to two sessions on iOS** plus the migration, which is small in
code and gated by release pace.

---

## 10. References

- [Android app](./android-app.md) — the plan this unblocks
- [iOS app](../ios-app.md) — models at `Models/`, existing CSV at `Views/PeopleListView.swift:257`
- [people_import](../people_import.md) — the CSV seeding format this does not replace
- `flyfun-weather/main/src/weatherbrief/api/account_export.py` — GDPR export precedent to follow
- `src/flightforms/api/app.py:93-95` — `_on_delete_user`, the coverage the server export must mirror
- `PRIVACY.md`, `legal/GDPR.md` — documents this feature changes
