# FlightForms — GDPR Considerations

*Last updated: 2026-09-26*

## Statement

**This document has not been through a formal legal review.** FlightForms is a
personal, open-source project run by a single developer, not a company. We are not
lawyers, and nothing here is legal advice or a certification of compliance.

What this document *is*: an honest, good-faith record of everything we understand
GDPR to require, what we have implemented to meet it, where we believe we are fine
and why, and what we know is still outstanding. The entire codebase is
[open source](https://github.com/roznet/flyfun-forms), so every claim below can be
verified against the code. See also [`PRIVACY.md`](../PRIVACY.md) for the user-facing
privacy notice and [`SECURITY_AUDIT.md`](../SECURITY_AUDIT.md) for the security review.

If you spot something we've missed or got wrong, please open a
[GitHub issue](https://github.com/roznet/flyfun-forms/issues).

**Why this document differs from [FlyFun Weather's](https://github.com/roznet/flyfun-weather/blob/main/GDPR.md).**
The two apps share an account system, a host and a developer, so §§11–13 below are
near-identical. Everything else is different, because the data is different:

- **Weather** processes the *user's own* data (their flights, their preferences) on
  our server. We are the controller throughout.
- **Forms** processes **third parties' passport data** — crew and passengers the pilot
  enters — and **never stores it**. It lives on the pilot's device and in *their* iCloud;
  our server only sees it for the fraction of a second it takes to fill a PDF field.

That inverts the two hardest questions. Weather's answer to "does anyone need a DPA
*from us*?" is *no*. Forms' answer is **yes, potentially** — see §5.

---

## Summary

| Area | Status |
|------|--------|
| Privacy notice / transparency (Art. 13–14) | ✅ Served at `forms.flyfun.aero/privacy`, linked from Settings on every platform; passenger note for Art. 14 |
| Data minimization (Art. 5) | ✅ Implemented — server persists no manifest data at all |
| Lawful basis (Art. 6) | ✅ Believe fine |
| Special-category data & ID numbers (Art. 9, Art. 87) | ✅ Believe fine — no Art. 9 data; passport numbers handled as national ID numbers |
| **Our role: processor for manifest data, controller for the account** | 🟡 Position documented here; [`PROCESSOR_TERMS.md`](./PROCESSOR_TERMS.md) drafted, not yet in force |
| On-device & iCloud storage (the real data store) | ✅ Sound, with two hardening items (§6) |
| Android client (on-device only) | ✅ No cloud backup or transfer; 🟡 ML Kit sends Google diagnostics (§6a) |
| Right to erasure (Art. 17) | ✅ Server-side, plus **Delete All Data** on-device (iOS/macOS, Android) |
| Right to data portability (Art. 20) | 🟡 CSV export of people on device ✅; no server-side account export |
| Security of processing (Art. 32) | ✅ Temp-file regression fixed, `/generate` rate-limited; iOS hardening items remain (§6) |
| Retention / storage limitation (Art. 5(1)(e)) | 🟡 Usage rows never pruned; temp files now deleted (§9) |
| Data residency (UK, EU-adequate) | ✅ Implemented |
| International transfers (Art. 44–49) | ✅ No manifest data leaves the server; sign-in, and ML Kit diagnostics on Android (§12) |
| Processor agreements / DPAs (Art. 28) | ✅ DigitalOcean + Google in force; Apple as independent controller; 🟡 Google ML Kit role (§13) |
| Onward transfer to airports & authorities | ✅ User-initiated, from the user's own device |
| Breach notification (Art. 33–34) | ✅ [`SECURITY.md`](../SECURITY.md) runbook; GitHub private vulnerability reporting enabled |
| Records of processing (Art. 30) | 🟡 The small-scale exemption probably does **not** apply here — this doc is the record |
| DPIA (Art. 35) | 🟡 Considered; believe not required, reasoning recorded |
| DPO / EU representative | 🟡 Believe not required (small scale) |

✅ implemented · 🟡 partial / needs confirmation · ❌ outstanding

### Applicable law & supervisory authority

The controller is established in the **United Kingdom**, so the governing regime is the
**UK GDPR + Data Protection Act 2018** and the lead supervisory authority is the
**Information Commissioner's Office (ICO)**. UK GDPR is the retained version of the EU
GDPR — the article numbers and obligations referenced throughout this document are
materially identical. Because the app also serves pilots flying in and out of the EU/EEA,
**EU GDPR applies in parallel** by territorial scope (Art. 3(2)) for those users.

---

## What the system actually holds

Everything below hangs off this inventory, so it comes first.

| Data | Where it lives | Who can read it |
|------|----------------|-----------------|
| Crew/passenger names, DOB, nationality, sex, place of birth, address, phone, email | The pilot's device (SwiftData) + **their** iCloud private database | The pilot only |
| Passport / ID numbers, issuing country, expiry | Same | The pilot only |
| The same data, on Android | The phone only (Room database); excluded from Android backup and device transfer | The pilot only |
| The same data, in flight | HTTPS request body to `forms.flyfun.aero`, in memory, for one request | Nobody — discarded when the response is written |
| The filled PDF/DOCX/XLSX | Returned to the device; held in the app's temp storage until shared, then deleted | The pilot (and whoever they send it to) |
| ML Kit usage metrics (Android) | Google — device model/OS, app version, per-installation id, latency, image size/format, error codes; **no image or text** | Google |
| Account: email, display name, OAuth provider + `sub` | Our MySQL on the droplet (`users`, shared with weather) | Us |
| Usage: `user_id`, endpoint, airport ICAO, form id, timestamp | Our MySQL (`usage`) | Us |
| Cost ledger: `user_id`, service, action, `{airport, form}` | Our MySQL (`cost_ledger`, shared) | Us |
| API tokens (SHA-256 hashes) | Our MySQL (`api_tokens`, shared) | Us |

Verifiable in `src/flightforms/db/models.py` (the *whole* app-specific schema is one
`Usage` table) and `src/flightforms/api/generate.py` (`generate_form` — fill, log the
airport/form, return bytes; nothing else touches the request body).

---

## What we have considered

### 1. Transparency & privacy notice (Art. 13–14) — 🟡

- [`PRIVACY.md`](../PRIVACY.md) is a detailed, plain-language notice: what is stored where,
  why the server exists at all, what it does and doesn't keep.
- **Resolved 2026-09-26:** `PRIVACY.md` is served at `https://forms.flyfun.aero/privacy`
  (`src/flightforms/api/privacy.py` renders the repo file, so there is one source), linked
  from Settings on iOS/macOS and Android. It has a **Passengers** section, and both apps
  have *Settings → Privacy note for passengers*, a share sheet with a short note that links
  `/privacy#passengers` — the Art. 14 point below.
- **Gaps we knew about (kept for the record):**
  1. It was only in the repository. Unlike weather (`web/privacy.html`, linked from the app),
     the forms backend serves **no web pages at all**, and the iOS/macOS app contains **no
     link to a privacy policy** — `Settings` offers Sign Out and Delete Account and nothing
     else (`ContentView.swift`). The App Store listing carries the required privacy-policy
     URL, but that is not reachable from inside the app.
  2. The notice is written for the *pilot*. It says nothing about the **passengers** whose
     passport data the pilot types in — see the Art. 14 point below.
  3. `PRIVACY.md` used to say a previewed form "is deleted as soon as you dismiss the
     preview." That stopped being true (§9); the notice was corrected on 2026-09-21 to say
     the file stays in the temp directory until the OS clears it.
- **Art. 14 (data not obtained from the data subject):** a passenger's passport details
  reach the app from the *pilot*, not from the passenger. The duty to tell that passenger
  what is happening sits with whoever is the controller of the manifest — the pilot or their
  operator (§5), not us. We should nonetheless make that duty visible: a short, quotable
  paragraph the pilot can show a passenger ("your details are stored on my device, synced
  to my iCloud, and sent to the airport/customs authority that requires them") costs us
  nothing and is the single most useful transparency improvement available here.

### 2. Data minimization (Art. 5) — ✅

- **The server stores no manifest data — ever.** `/generate` and `/prefill` take the
  request, fill the template in memory, write one `Usage` row (`user_id`, endpoint,
  airport, form id, timestamp) and return the file. No file, no field value, no name
  reaches disk or database.
- **No PII in logs.** The backend's only log statement is the startup line
  (`src/flightforms/api/app.py`); the shared auth library logs the opaque `user.id`, never
  the email. There is no `mask_email`-equivalent needed because nothing logs an email.
- **No third-party analytics, no tracking, no advertising SDKs.** The app's only package
  dependencies are our own (`flyfun-common`, `rzflight`, `rzutils`).
- **On-device capture is on-device.** Passport MRZ scanning uses Apple's **Vision**
  framework locally (`Services/CameraOCRManager.swift`, `Services/ImageOCRManager.swift`);
  no image and no scanned text is sent anywhere for recognition.
- **Contacts import is selective** — the pilot picks people to import
  (`Views/ContactImportView.swift`, `NSContactsUsageDescription` declared); we never read
  the address book wholesale.
- **Why we think we're fine:** the sensitive data has the shortest possible life on our
  infrastructure — one request, in memory — and the persistent footprint is an email
  address and a count of forms.

### 3. Lawful basis (Art. 6) — ✅ (believe fine)

Two distinct processing activities, two different answers:

- **The account** (email, provider `sub`, usage, cost) — **contract** (Art. 6(1)(b)):
  necessary to provide authenticated access to the service the pilot signed up for.
  Sign-in provider choice (Google/Apple) is the user's own.
- **The manifest** (crew/passenger data during form filling) — we act **on the pilot's
  instructions** (§5), so the basis is *theirs*, not ours to pick. For the pilot it is
  normally **legal obligation** (Art. 6(1)(c)): customs, immigration and GAR-type filings
  are required by the state the flight touches. That is a strong, uncontroversial basis —
  which is precisely why this app exists.
- **Minimal usage/cost logging** — **legitimate interest** (Art. 6(1)(f)): abuse
  protection and cost transparency, no profiling, no marketing, never shared.
- **Why we think we're fine:** each activity maps to a clear basis; none rely on
  bundled or opaque consent, and we never ask a passenger for consent we couldn't rely on.

### 4. Special-category data & national identification numbers (Art. 9, Art. 87) — ✅ (believe fine)

This is the section weather does not need, so the reasoning is written out.

- **Nothing here is Art. 9 special-category data.** Name, date of birth, sex, place of
  birth, address, nationality and passport number are all ordinary personal data. The
  usual argument to the contrary is that *nationality* or *place of birth* can hint at
  racial or ethnic origin — the settled reading (EDPB/ICO) is that data is special-category
  when it *reveals* such an origin, not when a determined inference might be drawn, and a
  customs form asking for the nationality on a passport is not processing data about
  ethnicity. We record no religion, no health data, no biometrics — the passport photo page
  is scanned by **Vision for its MRZ text only** and no image is retained or transmitted.
- **Passport/ID numbers are "national identification numbers" (Art. 87).** Member states may
  impose specific conditions on them; several do. The relevant safeguards are exactly the
  ones already in place: we never store the number, never log it, and it exists on our side
  only in request memory. Nothing else in our stack could meet a state-specific condition
  we didn't know about, and this design means we don't have to.
- **Children.** Passengers include minors, whose DOB the pilot enters. Art. 8 (child consent
  for information-society services) does **not** bite: the basis is legal obligation, not
  consent, and the child is not our user. The account holder must be an adult in practice
  (they are the pilot in command). No separate mechanism is required — recorded here so the
  question is visibly answered rather than missed.
- **Why we think we're fine:** the most sensitive field in the system (passport number) is
  also the field with the shortest lifetime on our infrastructure.

### 5. Our role: **processor** for manifest data, controller for the account — 🟡

This is the structural difference from weather, and the one item on this page that could
require us to publish a document.

- **For the account** (email, display name, provider `sub`, usage, cost ledger) we decide
  the purposes and means. **We are the controller.** Pilots are data subjects; they are owed
  a privacy notice and their rights, never a DPA.
- **For the manifest** (crew and passenger data) we decide nothing. The pilot decides who
  is on the flight, which fields to enter, which airport form to fill and where to send it.
  We provide a template-filling function that runs on their instruction and keeps nothing.
  On the ordinary reading of Art. 4(7)–(8) that makes us a **processor**, and the pilot (or
  their organisation) the controller.
- **Does that mean someone can demand a DPA from us?** It depends who the pilot is:
  1. **A private pilot flying friends and family.** Arguably the **household exemption**
     (Art. 2(2)(c)) puts their manifest outside GDPR's scope entirely, in which case there
     is no controller to contract with and no DPA to give. The exemption is narrow and gets
     shakier the moment money, a club, or a business trip is involved — so we do not lean
     on it as the whole answer.
  2. **A flight school, club, air-taxi or corporate operator** carrying *other people* as
     part of a business. That organisation is plainly the controller of its passengers'
     data, we are plainly its processor, and **Art. 28(3) entitles it to a written contract
     with us.** We do not currently offer one.
- **What we are doing about it.** Not chasing the question, but pre-empting it:
  [`PROCESSOR_TERMS.md`](./PROCESSOR_TERMS.md) covers the Art. 28(3) mandatories — process
  only on instructions, confidentiality, Art. 32 security, sub-processors (DigitalOcean only),
  assist with data-subject requests, delete/return on termination, allow audit — and engages
  only where the user is in fact a controller. For a service that stores nothing, most of
  those clauses are satisfied by the architecture rather than by a promise, and having them
  written down converts an awkward email from a flight school into a link. **Currently
  drafted and marked not in force**; it needs a notice address and a decision on how it is
  incorporated before it is published.
- **Sub-processor position:** if we are a processor, our own supplier (DigitalOcean) is a
  **sub-processor** and must be disclosed. It is, in §12.
- **Why this is 🟡 and not ❌:** no organisational user exists today (accounts are
  individual pilots), so nothing is currently unlawful. The first flight school to sign up
  is the trigger.

### 6. On-device & iCloud storage — the real data store — ✅ (with two hardening items)

- All manifest data lives in **SwiftData**, synced through the **CloudKit private
  database** of the user's own Apple ID (`iCloud.net.ro-z.flyfun-forms`, see
  `flyfun-forms.entitlements`). **We have no access to it** — no server-side copy, no
  CloudKit public/shared zone, no developer read path. This is the single strongest privacy
  property of the app and it is architectural, not procedural.
- **Encrypted at rest on device** by iOS/macOS Data Protection; **encrypted in iCloud**;
  **auth tokens in the Keychain**.
- **Apple's role here is not ours to assign.** The iCloud storage is the *user's* contract
  with Apple, under Apple's own privacy policy — we are not a party to it and could not
  instruct Apple about it. Users with **Advanced Data Protection** enabled additionally hold
  the keys end-to-end.
- **Hardening item 1 — CloudKit field encryption.** SwiftData supports
  `@Attribute(.allowsCloudEncryption)`, which puts a value in the CKRecord's
  `encryptedValues` and out of reach of Apple's own key hierarchy. **No model uses it**
  (`Models/Person.swift`, `Models/TravelDocument.swift`). Applying it to `docNumber`,
  `idNumber`, `dateOfBirth` and `placeOfBirth` would mean passport numbers are unreadable to
  Apple even without ADP. *Caveat before doing it:* encrypted CloudKit fields cannot be
  queried or sorted on, and changing the attribute on an existing model is a schema
  migration — worth scoping properly, not a one-liner.
- **Hardening item 2 — file protection class.** `SECURITY_AUDIT.md` §19 notes the store
  does not explicitly set `NSFileProtectionComplete`, so data may be readable before first
  unlock after a reboot. Still open.

### 6a. The Android client — ✅ (with one disclosure)

The Android app (merged after the first version of this record) keeps the same shape as
iOS — manifest data on the device, the server for filling only — with two differences.

- **No cloud copy at all.** Data lives in a Room database on the phone. The manifest sets
  `allowBackup="false"`, `fullBackupContent="false"` and `data_extraction_rules.xml`, which
  excludes every domain from both `<cloud-backup>` and `<device-transfer>`; with `minSdk` 33
  the rules always apply. So passport data never reaches the user's Google account. Moving
  to another device is the user-initiated **move my data** file, encrypted with a generated
  passphrase; a plain JSON export exists for Art. 20.
- **At rest:** Android file-based encryption (when a screen lock is set). The Room database
  is not additionally encrypted (no SQLCipher). The sign-in token is in
  `EncryptedSharedPreferences` backed by the Keystore.
- **Passport scanning uses Google ML Kit**, bundled model, on-device. Images and recognised
  text are not sent anywhere ([ML Kit terms](https://developers.google.com/ml-kit/terms)).
  **But ML Kit sends Google usage metrics** — device model and OS, app version, a
  per-installation identifier, latency, image format/size, error codes
  ([data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)) — through
  the bundled `datatransport` components, and `MlKitInitProvider` starts it at app launch,
  not only when scanning. Google documents **no opt-out** (open request
  googlesamples/mlkit#593 since 2022). Its terms put disclosure on us: *"You are responsible
  for informing users of your app about Google's processing of ML Kit metrics data."* Done
  in `PRIVACY.md` (Passport Scanning). This is **pilot device data, not passenger data** —
  the passenger note stays accurate. The iOS path (Vision) has no equivalent.
- **Worth revisiting:** if the metrics are unwelcome, the alternatives are a non-Google OCR
  or lazy initialisation so ML Kit only starts when the pilot scans. Neither is needed for
  compliance; both would shrink the disclosure.

### 7. Right to erasure (Art. 17) — ✅ server-side, 🟡 wording

- **Delete Account** in the app (`ContentView.swift`) calls `DELETE /auth/account`. The
  forms-specific hook deletes every `Usage` row for the user
  (`src/flightforms/api/app.py`, `_on_delete_user`); the shared router then deletes
  preferences, API tokens, OAuth grants and the user row itself.
- **Cost-ledger rows are deliberately retained** for accounting, keyed by `user_id`. Because
  that id is a **random UUID** assigned at signup (not derived from the provider `sub`), once
  the `users` row is gone the id maps to nobody and a re-registration gets a fresh one — the
  residue is effectively anonymous, not pseudonymous. That is why we consider erasure complete.
- **On-device and iCloud data is not ours to erase**, and deleting the account does not
  remove it. The app is honest about this ("Permanently deletes your account and all server
  data") but a pilot may still read "delete account" as "delete everything".
- **Resolved 2026-09-26:** the Delete Account confirmation now says the account and usage
  records go, and that people, aircraft, flights and trips stay on the device. A separate
  **Delete All Data** action (iOS/macOS and Android) removes every on-device record and
  generated file in one step, without signing out. On Apple platforms the confirmation says
  plainly that the deletion propagates through iCloud to all the user's devices; on Android
  it also clears the web-form WebView's storage and runs Room's `clearAllTables` (which
  VACUUMs, so rows do not linger in free pages).

### 8. Right to data portability (Art. 20) — 🟡

- **On-device data: ✅.** People can be exported to CSV from the app
  (`Views/PeopleListView.swift`, "Export to CSV"), which is the bulk of what a user holds and
  is a genuine machine-readable export. It is also how a pilot would satisfy a passenger's
  own access request.
- **Server-side data: missing.** There is no forms equivalent of weather's
  `GET /api/account/export`. What we hold is small — email, display name, provider, timestamps
  and a list of `(airport, form, when)` rows — but "small" is not an exemption. A single
  read-only endpoint returning that JSON would close it, and would be a better home in
  `flyfun-common` than in either app, since the shape is shared.

### 9. Security of processing (Art. 32) — 🟡

The standing review is [`SECURITY_AUDIT.md`](../SECURITY_AUDIT.md) (critical and high items
resolved). Points that bear on GDPR specifically:

- **TLS everywhere**, HSTS with `preload` at the Caddy layer plus in the app itself; security
  headers and a `Permissions-Policy` denying geolocation/camera/microphone to the origin
  (`deploy/forms.flyfun.aero.caddy`).
- **Authenticated by default** — `/generate`, `/prefill`, `/validate` and `/email-text` all
  depend on `current_user_id`; there is no anonymous form-filling path.
- **JWT in the Keychain**, rolling sessions, and the OAuth deep-link hardening (audit H8)
  that removed the token from the callback URL.
- **No PII in logs or error messages** — verified above (§2).
- **Resolved 2026-09-26** — kept below for the history. Generated forms now live in
  `tmp/forms/` (`Services/GeneratedFormFiles.swift`): on iOS the file is deleted when the share
  sheet closes, and straight after the mail composer has copied the attachment; on macOS it is
  deleted on Done/close/Save, but kept after Open, Reveal, a sharing service or Mail (those
  keep reading it) until the next form sweeps files over 15 minutes old, or the next launch;
  `SECURITY_AUDIT.md` §16 and `PRIVACY.md` describe the new behaviour. Android already
  purged its `cacheDir/forms` folder.
- **Regression (as found): generated forms are left in the temp directory.** `generateForm(...)` writes
  the filled file to `FileManager.default.temporaryDirectory`
  (`Views/FlightEditView.swift`) and **nothing ever deletes it**. The cleanup that
  `SECURITY_AUDIT.md` §16 records as FIXED was removed on 2026-03-14 in commit `6d5d0cc`,
  when QuickLook was replaced by `fileExporter`/share-sheet; the `.onChange(of: previewURL)`
  that called `removeItem` went with it. So a filled PDF containing passport numbers persists
  in the app's tmp directory until iOS decides to purge it. Impact is genuinely low — it is
  the owner's own device and the file is covered by Data Protection — but it is **still claimed
  as fixed in `SECURITY_AUDIT.md` §16** (`PRIVACY.md` was corrected 2026-09-21). Fix: delete
  the file when the share sheet or mail composer dismisses (`shareFileURL` is already the
  single lifetime anchor), then correct the audit and restore the stronger `PRIVACY.md` wording.
- **Rate limiting on `/generate` and `/prefill`** (audit §17, resolved 2026-09-26) — 100 fills
  per user per rolling hour, counted over the `usage` log (`src/flightforms/api/rate_limit.py`),
  bounding what a stolen token can be used for.

### 10. Retention / storage limitation (Art. 5(1)(e)) — 🟡

- **Manifest data: zero retention on our side.** Nothing to schedule.
- **`usage` and `cost_ledger` rows grow without bound.** They are low-sensitivity
  (`user_id` + airport + form id), but "we keep them forever because they're small" is not a
  retention policy. A stated period (e.g. usage rows pruned after 24 months, cost ledger kept
  in anonymous form) would close this properly, and is shared work with weather.
- **Reverse-proxy access logs record IP addresses** (`header_up X-Real-IP`, Caddy's own access
  log), which are personal data. Basis: legitimate interest in security and diagnostics.
  Retention is currently whatever journald/Docker rotation gives us, which should be stated
  rather than inherited silently.
- **Temp files on device** — deleted after sharing since 2026-09-26, see §9.

### 11. Data residency — ✅

- The server runs on a **DigitalOcean droplet in the UK (London) region**, behind Caddy,
  alongside weather (`docker-compose.yml`, `deploy/forms.flyfun.aero.caddy`). The UK holds an
  EU data-protection **adequacy decision**, so storage there is recognised as adequately
  protected for EU/EEA users.
- The only database content is the account/usage data listed above. Manifest data is never
  written there, so "residency" for the sensitive data is really "the pilot's device and the
  pilot's iCloud".

### 12. International transfers (Art. 44–49) — ✅

- **No manifest data crosses a border because of us.** It goes device → UK server → back to
  the device, over TLS, and is never stored. There are **no LLM providers, no analytics
  vendors and no email provider** anywhere in the forms stack — the backend sends no email at
  all (the shared magic-link router is not mounted, as no send callback is wired).
- **OAuth sign-in (Google / Apple)** involves US-based providers and transfers an email
  address. **Google** transfers are covered by the SCCs incorporated into its API/Cloud DPA
  (§13). **Apple** acts as an **independent controller** for the authentication it performs
  and handles its own transfer mechanisms; the native Sign in with Apple path verifies the
  identity token locally against Apple's public keys and sends Apple no user data.
- **ML Kit metrics (Android only)** go to Google, a US provider, over HTTPS (§6a). They are
  device and usage diagnostics about the pilot's phone, never manifest data. Google's transfer
  mechanism is its own terms (see §13 on its role).
- **iCloud/CloudKit** may store the user's data outside the UK/EEA, but that transfer arises
  from the **user's own relationship with Apple**, not from any instruction of ours — we have
  no access to the data and no contract governing it (§6).
- **Why we think we're fine:** the only PII we cause to leave the country is an email address
  in a sign-in exchange, to processors with SCC-backed terms already in force — plus, on
  Android, ML Kit's device diagnostics, disclosed in `PRIVACY.md`.

### 13. Processor agreements / DPAs (Art. 28) — ✅

Same suppliers as weather, minus everything weather needs for email and LLMs.

- **DigitalOcean (hosting, and our *sub*-processor per §5):** DigitalOcean's DPA is
  **automatically accepted by agreeing to their Terms of Service** — no separate signature —
  so it is in force. A copy can be downloaded from
  [DigitalOcean's DPA page](https://www.digitalocean.com/legal/data-processing-agreement).
  Hosting is UK (London). ✅
- **Google Sign-In (processor):** the DPA is **automatically incorporated into the terms we
  already accepted** — the [Google API Services / OAuth terms](https://developers.google.com/terms)
  for the sign-in APIs we use, and the
  [Google Cloud DPA](https://cloud.google.com/terms/data-processing-addendum) where Cloud
  services apply. We use standard OIDC sign-in, not Firebase. Nothing further to sign. ✅
- **Sign in with Apple (independent controller):** Apple's position is that it is an
  independent controller for its part of the authentication, so **no developer DPA exists**.
  The relationship is governed by the Apple Developer Program License Agreement and is
  documented rather than contracted: we receive a stable `sub`, an email (often a private-relay
  address) and a display name on first login. ✅
- **Apple / iCloud (neither our processor nor our controller):** the CloudKit private database
  belongs to the user's Apple ID. We do not instruct Apple, cannot read the data, and there is
  no DPA to obtain — recorded in §6 and in `PRIVACY.md`. ✅
- **Google ML Kit (Android) — 🟡 role to confirm:** governed by the
  [ML Kit terms](https://developers.google.com/ml-kit/terms) under the Google APIs Terms of
  Service we already accept. Google uses the metrics "to measure performance, debug, maintain
  and improve the APIs, and detect misuse or abuse" — purposes of its own, which reads as an
  **independent controller** for that data rather than our processor. Nothing to sign either
  way; what the terms require of us is disclosure, which is done (§6a).
- **No email processor, no LLM processor, no analytics processor** — ML Kit's metrics are
  the one SDK telemetry in any client, and are about API performance, not user behaviour. ✅

### 14. Onward transfer to airports and authorities — ✅

The whole purpose of the app is to get a manifest to a customs or airport authority, so it
is worth being explicit about who does the sending:

- **Documents (PDF/DOCX/XLSX):** the filled file is returned to the device, and the pilot sends
  it from **their own mail client** (`MFMailComposeViewController` on iOS, `NSSharingService` on
  macOS, or the share sheet) — pre-addressed and pre-worded from the form's mapping, but
  reviewed and sent by them. **Our server never emails anything and never contacts an airport.**
- **Airport web forms:** `/prefill` returns a *fill plan* (field name → value) to the client; the
  app opens the airport's own page in a `WKWebView`, fills it, and the pilot presses Submit on
  the airport's site (`Views/WebFormView.swift`, `src/flightforms/fillers/web_form.py`). **We
  never post to a third party's form.** The banner says so in the UI.
- **The recipient authority is its own controller**, processing under its own legal mandate;
  our part ends when the file is on the pilot's device.
- **Honest caveat:** ordinary email is not encrypted end-to-end, so a manifest sent to an
  airport travels as far as TLS between mail servers takes it. That is inherent to how these
  authorities accept filings — most publish an address and nothing else — and it is the pilot's
  transfer, not ours. It deserves a line in `PRIVACY.md` rather than silence.
- *Flagged for future review:* a planned feature would notify the pilot when a form is
  **accepted**. Our server cannot know that today, because it plays no part in submission.
  Any status tracking means the server becomes involved in the submission path, which would
  weaken the stateless premise §3, §5 and this section all rest on, and would require updating
  the description of processing in [`PROCESSOR_TERMS.md`](./PROCESSOR_TERMS.md) §3 — on 30
  days' notice if those terms are in force by then. To be designed deliberately, not drifted
  into: notifying on a status the pilot reports is very different from us transmitting the form.

### 15. Breach notification (Art. 33–34) — ✅

- **Resolved 2026-09-26:** [`SECURITY.md`](../SECURITY.md) carries the runbook (record →
  contain & assess → notify the **ICO within 72 hours** → notify affected users if high risk),
  adds the processor duty to tell pilot-controllers when manifest data is involved (§5), and
  GitHub's private "Report a vulnerability" channel is enabled on the repository — so a finder
  can reach us privately, and time-to-awareness (when the 72-hour clock starts) is short.
- Worth noting *what* a breach would look like here, because it shapes the runbook: our
  database cannot leak passport data (it has none). The realistic scenarios are (a) account
  data exposure — emails and usage rows, and (b) a compromise of the running server able to
  observe request bodies in flight. (b) is the severe one and would be reportable and
  user-notifiable; it argues for keeping the deployment surface as boring as it currently is.

### 16. Records of processing (Art. 30) — 🟡

- Weather leans on the Art. 30(5) small-organisation exemption. **That exemption is harder to
  claim here.** It falls away where processing is *not occasional*, is likely to result in a
  risk to rights and freedoms, **or** involves certain sensitive data — and form filling is
  routine, continuous, and involves passport and ID-document data.
- We therefore treat a record as **required in substance**, and this document (particularly
  *What the system actually holds*, §3, §5, §10 and §13) is that record: purposes, categories of
  data subject and data, recipients, transfers, retention, and security measures.
- **To make it formal**, the one thing it lacks is the processor-side record (Art. 30(2)) that
  §5 implies: the categories of processing we carry out on behalf of each controller. That is
  a paragraph, not a project, and it should land alongside the standard processor terms.

### 17. Data Protection Impact Assessment (Art. 35) — 🟡

- A DPIA is mandatory where processing is "likely to result in a high risk", typically via the
  ICO's trigger list: large-scale use of sensitive data, systematic monitoring, innovative
  technology, biometrics, matching or combining datasets.
- **We believe none is triggered:** the scale is a handful of private pilots; there is no
  monitoring, profiling or automated decision-making; the MRZ scan is OCR, **not biometric
  identification**; and the sensitive-ish data is never retained by us. The processing is also
  precisely what the data subject would expect — a passenger on an international GA flight
  knows their passport details go to customs.
- **But** "passport data + a mobile app" is close enough to the trigger list that the answer
  should be written down rather than assumed, and revisited if we ever (a) store manifest data
  server-side, (b) take on organisational users at scale, or (c) add anything that matches or
  enriches passenger records.

### 18. DPO / UK & EU representative — 🟡

- A Data Protection Officer is **not required**: processing is small-scale, there is no
  large-scale systematic monitoring, and no Art. 9 data (§4).
- As a UK-established controller the **ICO** is the supervisory authority. An Art. 27 EU
  representative could in principle be needed for offering services to EU residents; the
  exemption for occasional, low-risk processing is likely to apply at this scale — though note
  that the same "not occasional" argument that weakens our Art. 30 exemption (§16) would weaken
  this one too if the user base grew. **To revisit** if it does.

---

## Outstanding items (action list)

Ordered by ratio of obligation to effort.

1. ✅ ~~Add `SECURITY.md` and enable private vulnerability reporting~~ — done 2026-09-26. *(§15)*
2. ✅ ~~Delete the generated file when the share/mail sheet dismisses~~ — done 2026-09-26,
   `SECURITY_AUDIT.md` §16 and `PRIVACY.md` corrected. *(§9)*
3. ✅ ~~Make the privacy notice reachable from the app~~ — `/privacy`, linked from Settings. *(§1)*
4. 🟡 **Passenger-facing paragraph** — done (`PRIVACY.md` Passengers, in-app share). Still to
   add: the plain-email caveat from §14. *(§1, §14)*
5. 🟡 **Put the processor terms in force** (Art. 28(3)) — [`PROCESSOR_TERMS.md`](./PROCESSOR_TERMS.md)
   is drafted; it needs a notice address, an incorporation decision, and the DRAFT banner
   removed. Then add the Art. 30(2) processor-side record. *(§5, §16)*
6. 🟡 **Server-side account export** (Art. 20) — account + usage JSON; best built in
   `flyfun-common` and shared with weather. *(§8)*
7. ✅ ~~Clarify Delete Account, and add "Delete all local data"~~ — done 2026-09-26. *(§7)*
8. 🟡 **State a retention period** for `usage` and `cost_ledger` rows and for proxy access logs,
   and implement the prune. Shared with weather. *(§10)*
9. 🟡 **Evaluate `@Attribute(.allowsCloudEncryption)`** for document number, ID number, DOB and
   place of birth — scoped as a schema migration, not a one-liner. *(§6)*
10. 🟡 **Set `NSFileProtectionComplete`** on the SwiftData store (`SECURITY_AUDIT.md` §19). *(§6)*
11. 🟡 **Confirm the App Store privacy "nutrition labels"** match this document — in particular
    that passport/manifest data is declared as **not collected**, which is what the code does.
    **And the Play Console Data safety form** for Android: manifest data not collected, but
    **ML Kit's diagnostics and device identifier are collected (by Google, via an SDK)** and
    must be declared. *(§1, §6a)*
12. 🟡 **Document the push capability, and prepare for it.** The `aps-environment` entitlement
    is declared, but the app registers for no notifications and **collects no device token
    today** — recorded so the capability is explained rather than dangling. Push *is* planned
    (form-status notifications), and when it lands the device token is personal data: add it
    to the deletion inventory and the account export with the token value redacted, name it in
    `PRIVACY.md` and in the Art. 30 records, and keep passenger data out of the payload — an
    APNs payload passes through Apple, so "accepted for LFMD" is fine and "accepted for
    John Smith" is not. Weather's `device_tokens` handling is the pattern to copy. Separately,
    `flyfun_forms.entitlements` (underscore) is referenced by no build configuration and can go.
13. 🟡 **Confirm Google's role for ML Kit metrics** (independent controller is our reading),
    and decide whether to shrink the disclosure by initialising ML Kit lazily. *(§6a, §13)*

---

## Our current public answer

> FlightForms handles passport data the only way we think it should be handled: it never
> touches our database. Crew and passenger details live on your device and in your own
> iCloud (on Android, on the phone alone), and reach our UK-hosted server only in memory, for the fraction of a second it
> takes to fill a form field. Nothing is stored, nothing is logged, no analytics or AI
> provider is anywhere in the path (the one caveat: on Android, Google's ML Kit, which reads
> the passport's machine-readable zone on the phone, sends Google performance metrics about
> itself — never the image or the text), and you send the finished form to the airport yourself,
> from your own mail app. We have not undergone a formal legal review, but we have written
> down everything we understand GDPR to require — including the awkward question of whether
> a flight school using FlightForms is entitled to a processor agreement from us — and we
> track what is still outstanding in this document. The codebase is open source so anyone
> can check the claims.
