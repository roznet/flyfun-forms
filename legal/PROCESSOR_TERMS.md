# FlightForms — Data Processing Terms

**Version 1.0 — DRAFT, not yet in force.** *Last updated: 2026-09-17*

> *Before publication:* choose the notice address used in §13 (a `privacy@flyfun.aero`
> alias is the tidy option), decide how these Terms are incorporated (§2), and remove
> this banner together with the "DRAFT" marker above.

These Terms set out the agreement required by **Article 28(3) UK GDPR / EU GDPR** for the
situations where FlightForms processes personal data *on your behalf*.

They are written to be read, not to be impressive. Where a clause is easy for us to meet,
it says so and explains why — usually because **FlightForms stores no manifest data at
all**. That single architectural fact does most of the work in this document.

Related: [`PRIVACY.md`](../PRIVACY.md) (what the service does with data, for everyone) ·
[`GDPR.md`](./GDPR.md) (our full compliance record, §5 in particular) ·
[`SECURITY_AUDIT.md`](../SECURITY_AUDIT.md) (the standing security review).

---

## 1. Who these Terms are for

FlightForms fills customs and immigration forms from data you enter about the people on
your flight. Two different relationships exist, and only one of them needs a contract:

| Data | Our role | Governed by |
|------|----------|-------------|
| **Account Data** — your email, display name, sign-in provider identifier, usage and cost records | We are the **controller** | [`PRIVACY.md`](../PRIVACY.md) — not these Terms |
| **Manifest Data** — the crew and passenger details you enter, and the documents generated from them | We are the **processor**, acting on your instructions | **These Terms** |

**These Terms engage only where you are a controller subject to GDPR.** If you are a
private individual entering details of family or friends for a private flight, your
processing may fall outside GDPR entirely under the household exemption (Art. 2(2)(c)); in
that case there is no controller, no processor, and nothing here applies to you. You are a
controller — and these Terms apply — if you use FlightForms in the course of an
organisation's activity: a flight school, club, air-taxi, corporate flight department, or
any operation carrying people other than as a purely personal matter.

If you are unsure which you are, these Terms applying costs you nothing. They give you
rights; they impose no obligation on you that GDPR does not already impose.

## 2. How these Terms are entered into

These Terms are **pre-accepted on account creation and on continued use of the service**,
and form a contract in writing in electronic form as permitted by Art. 28(9). No signature
or countersignature is required, and we do not operate a separate DPA signing process.
This is the same mechanism our own suppliers use with us (see §7).

If your organisation requires a counter-signed paper document instead, contact us (§13).
We would rather discuss it than have you use a service without the agreement you are
entitled to.

**Parties.** "**We**", "**us**", "**FlightForms**" means Brice Rosenzweig, the individual
developer who operates the FlightForms service (`forms.flyfun.aero`), established in the
**United Kingdom**. "**You**" means the controller accepting these Terms. "**GDPR**" means
the UK GDPR and the Data Protection Act 2018, and the EU GDPR where it applies to you.

## 3. Description of the processing (Art. 28(3), opening paragraph)

| | |
|---|---|
| **Subject matter** | Filling airport, customs and immigration forms from flight and passenger data you supply |
| **Duration** | The lifetime of your account. Each individual processing operation lasts for the duration of one API request |
| **Nature and purpose** | Receiving Manifest Data over HTTPS; mapping it onto a form template; generating a completed PDF, DOCX or XLSX document; or generating a *fill plan* for an airport's own web form. Returning the result to you. Nothing else |
| **Types of personal data** | Names; dates of birth; nationality; sex; place of birth; address; phone; email; travel-document type, number, issuing country and expiry date |
| **Categories of data subject** | Crew and passengers on flights you operate; where you also enter your own details, yourself |
| **Storage** | **None.** Manifest Data exists only in server memory for the duration of the request. It is never written to our database, never written to disk, and never written to a log |

This description is also the basis of the processor-side record we maintain under
Art. 30(2) — see [`GDPR.md`](./GDPR.md) §16.

## 4. Our obligations

### 4.1 We process only on your instructions — Art. 28(3)(a)

We process Manifest Data only on your documented instructions. **Your use of the service's
documented functionality constitutes those instructions**: each API request you or your
authorised users make (`/generate`, `/prefill`, `/validate`, `/email-text`) instructs us to
carry out the processing described in §3 for that request, and nothing more.

We will not process Manifest Data for any other purpose. In particular we will not use it
to produce statistics or analytics, to improve or train any model, or to enrich any other
dataset. If we are ever required by law to process it otherwise, we will tell you before
doing so unless that law forbids us from telling you.

We do not transfer Manifest Data to a third country (§6).

**We will tell you immediately if an instruction appears to us to infringe GDPR** (Art.
28(3), final paragraph).

### 4.2 Confidentiality — Art. 28(3)(b)

FlightForms is operated by one person. That person is the only individual with access to
the production system, and is bound to keep Manifest Data confidential. No other person is
authorised to process Manifest Data. If that ever changes, anyone granted access will be
under an equivalent written confidentiality undertaking before access is given.

### 4.3 Security — Art. 28(3)(c) and Art. 32

We implement and maintain the technical and organisational measures listed in **Annex B**.
The most significant of them is structural rather than procedural: because Manifest Data is
never stored, there is no dataset of passport numbers for anyone to exfiltrate, and the
exposure window for any individual record is the duration of one HTTPS request.

### 4.4 Sub-processors — Art. 28(2) and 28(3)(d)

You give us **general authorisation** to engage the sub-processors listed in **Annex A**.
Today that list has **one entry**: our hosting provider.

Before adding or replacing a sub-processor we will **give you at least 30 days' notice**,
published in the repository and in the service's release notes. You may object on
reasonable data-protection grounds within that period; if we cannot address your objection,
you may stop using the service and close your account, and we will not charge you for the
notice period. We cannot offer a parallel deployment that excludes a sub-processor.

Every sub-processor is bound by data-protection obligations equivalent to these Terms, and
**we remain fully liable to you for their performance**.

*Not sub-processors:* your iCloud account and Apple's CloudKit hold Manifest Data under
**your own** relationship with Apple, which we neither instruct nor can read; and the
sign-in providers (Google, Apple) process **Account Data**, for which we are the controller,
not your processor. Neither is engaged by us to process your Manifest Data. See
[`GDPR.md`](./GDPR.md) §6 and §13.

### 4.5 Helping you answer data-subject requests — Art. 28(3)(e)

If a passenger or crew member exercises a right against you — access, rectification,
erasure, portability, objection — we will assist you, taking into account the nature of the
processing.

In practice that assistance is unusual in shape, and it is fair to be blunt about why: **we
hold none of their data**, so there is nothing for us to search, correct, export or delete.
The records live on your device and in your iCloud account, under your control. What we
will do is confirm that in writing for your records, explain where the data actually sits,
and point you at the app's own CSV export, which produces a machine-readable copy of the
people you hold and is normally a complete answer to an access or portability request.

We will not respond directly to a data subject about your Manifest Data; we will refer them
to you, and tell you promptly that we have done so.

### 4.6 Helping you with security, breaches and DPIAs — Art. 28(3)(f) and Arts. 32–36

**Personal data breaches.** We will notify you **without undue delay** after becoming aware
of a breach affecting Manifest Data processed for you, with the information available to us
at the time — the nature of the breach, categories and approximate number of records
concerned, likely consequences, and measures taken (Art. 33(3)). We will supply further
detail as we establish it. It is then for you, as controller, to decide on notification to
your supervisory authority and to the affected individuals.

**What a breach would realistically look like here** is worth stating, because it shapes
what we can promise: our database cannot leak Manifest Data, because it contains none. The
credible scenario is a compromise of the running server able to observe request bodies in
flight. We would treat that as a reportable breach affecting every controller whose
requests fell within the exposure window, and notify accordingly.

**DPIAs and prior consultation.** If you carry out a data protection impact assessment
covering your use of FlightForms, we will provide the information you reasonably need about
our side of the processing. Most of it is already public: see [`GDPR.md`](./GDPR.md) §17 and
Annex B below.

### 4.7 Deletion and return — Art. 28(3)(g)

On termination, you may choose deletion or return of Manifest Data. Both are satisfied
immediately and continuously by the design of the service:

- **Return** happens at the moment of creation — the completed document is delivered to you
  in the response to your request, and we keep no copy.
- **Deletion** requires nothing, because nothing is retained. There is no archive, backup,
  cache or queue containing Manifest Data.

Account Data is separate and is deleted by you at any time using **Delete Account** in the
app, which removes your account, your usage records and your API tokens. Cost-ledger entries
are retained for accounting, keyed to a random account identifier that no longer maps to any
person once the account is gone — see [`GDPR.md`](./GDPR.md) §7.

### 4.8 Information and audits — Art. 28(3)(h)

We will make available the information necessary to demonstrate compliance with Art. 28.
Most of it is already published and continuously current:

- the **complete source code** of the service and the app, at
  <https://github.com/roznet/flyfun-forms> — you can verify the claims in §3 yourself rather
  than take them on trust;
- [`GDPR.md`](./GDPR.md), our full compliance record, including known open items;
- [`SECURITY_AUDIT.md`](../SECURITY_AUDIT.md), the standing security review.

Beyond that, we will answer a reasonable written security or data-protection questionnaire
**once per twelve months**, and will allow and contribute to an audit or inspection
conducted by you or a mandated auditor on the following basis: at most once per twelve
months (unless a breach has occurred or a supervisory authority requires otherwise), on at
least 30 days' written notice, conducted remotely where remote access is sufficient, subject
to confidentiality, and at your cost. We will not grant access to other controllers' data or
to systems in a way that would compromise the security of the service.

## 5. Your obligations as controller

These Terms give you rights; GDPR also gives you duties, which remain yours:

- **Lawful basis.** You determine and can demonstrate the basis on which you process crew
  and passenger data. For customs and immigration filing this is normally legal obligation
  (Art. 6(1)(c)).
- **Telling people (Arts. 13–14).** The passengers whose passport details you enter did not
  give them to us — they gave them to you, or you hold them for another reason. Informing
  them how their data is handled, including that it is transmitted for form filling and sent
  onward to an airport or authority, is your responsibility. `PRIVACY.md` contains wording
  you are welcome to reuse.
- **Accuracy and minimisation.** You decide which people and which fields to enter. Only
  enter what the form you are filing requires.
- **Lawful instructions.** Your instructions to us must comply with GDPR.
- **Your devices and accounts.** Manifest Data lives on your devices and in your iCloud
  account. Device passcodes, account security, and who can unlock those devices are matters
  within your control, not ours.
- **Onward transmission.** You send the completed form to the airport or authority yourself,
  from your own mail client, or submit it on the authority's own website. That transfer is
  yours, including the fact that ordinary email is not encrypted end-to-end. See
  [`GDPR.md`](./GDPR.md) §14.

## 6. International transfers

**We do not transfer Manifest Data outside the United Kingdom.** It travels from your device
to our UK-hosted server over TLS, is processed in memory, and returns to your device. Our
sole sub-processor hosts in the UK (London), which holds an EU adequacy decision.

We will not transfer Manifest Data to a third country without either your instruction or a
valid transfer mechanism, and we will tell you in advance under §4.4 if a change would
introduce one.

Note separately that your own use of iCloud may store Manifest Data outside the UK/EEA. That
transfer arises from your relationship with Apple, not from any instruction of ours.

## 7. Our own suppliers, for symmetry

We are a controller too, and our suppliers cover us the same way we cover you: DigitalOcean's
data processing agreement is automatically accepted with its terms of service, and Google's
is incorporated into the API terms we accepted. Neither asked us to sign anything, and both
are in force. These Terms follow that pattern deliberately. Full detail in
[`GDPR.md`](./GDPR.md) §13.

## 8. Duration

These Terms apply for as long as you hold a FlightForms account, and the obligations that by
their nature should survive — confidentiality, and §4.7 — survive its closure.

## 9. Liability

These Terms allocate responsibility **between us and you**. They do not and cannot limit any
liability either of us has directly to a data subject under Art. 82, or to a supervisory
authority. Each party is responsible for its own compliance with GDPR.

FlightForms is a personal open-source project offered under the
[MIT Licence](../LICENSE), and the warranty position in that licence applies to the software.
Nothing in these Terms is a warranty that your use of FlightForms makes *you* compliant —
that depends on choices only you control (§5).

## 10. Changes to these Terms

We may update these Terms to reflect changes in the service or in law. Material changes will
be published in the repository and in the service's release notes at least 30 days before
they take effect, with the version number and date at the top of this document updated. The
change history is the repository's own commit history for this file — every revision is
public and attributable.

## 11. Order of precedence

If these Terms conflict with any other agreement between us about the same processing, these
Terms prevail in respect of the processing of Manifest Data.

## 12. Governing law

These Terms are governed by the law of England and Wales, and the courts of England and
Wales have jurisdiction, without prejudice to any mandatory right you have to bring
proceedings, or a data subject has, in another jurisdiction under GDPR.

## 13. Contact

Notices under these Terms — including a request for a counter-signed document, a
sub-processor objection, an audit request or a breach-related enquiry — should be sent to
the address published for data-protection matters in [`PRIVACY.md`](../PRIVACY.md).

Suspected security vulnerabilities should be reported privately through GitHub's
"Report a vulnerability" on <https://github.com/roznet/flyfun-forms>, which reaches the
maintainer without public disclosure.

---

## Annex A — Sub-processors

| Sub-processor | Purpose | Location | Transfer basis |
|---|---|---|---|
| DigitalOcean, LLC | Hosting of the FlightForms API server | **United Kingdom (London)** | No transfer outside the UK; DigitalOcean's DPA in force via its terms of service |

There is no email provider, no analytics provider, no AI or LLM provider, and no OCR
provider in this list, because the service uses none. Passport scanning runs on your own
device using Apple's on-device Vision framework; no image or scanned text is transmitted for
recognition.

## Annex B — Technical and organisational measures (Art. 32)

**Architectural**

- Manifest Data is **never persisted** — not to database, disk, cache, queue or backup. The
  entire app-specific database schema is a single usage table recording account identifier,
  endpoint, airport code, form identifier and timestamp.
- **No personal data in logs or error messages.** The backend emits one log line, at startup.
  Errors return generic messages.
- The completed document is returned in the HTTP response and no copy is kept.

**Transport and access**

- TLS for all traffic; HSTS with a two-year max-age and `includeSubDomains`, enforced both at
  the reverse proxy and by the application.
- Security headers on every response: `X-Content-Type-Options`, `X-Frame-Options`,
  `Referrer-Policy`, and a `Permissions-Policy` denying geolocation, camera and microphone.
- **Every endpoint requires authentication** — there is no anonymous form-filling path.
- Authentication by OAuth (Google, Apple) or hashed API token; no passwords are stored. JWTs
  are held in the platform Keychain on Apple devices, with rolling session renewal.
- Input validation on ICAO codes and field values; template paths are constrained against
  traversal.

**Operational**

- The service runs as an unprivileged user in a container, with a memory limit, on a UK host.
- A standing security review is maintained in public at
  [`SECURITY_AUDIT.md`](../SECURITY_AUDIT.md), including items still open.
- The full source is public, so these measures are verifiable rather than asserted.

**Known open items** are listed in [`GDPR.md`](./GDPR.md) — we publish them rather than wait
to be asked.
