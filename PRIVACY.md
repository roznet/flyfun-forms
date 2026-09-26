# Privacy

FlightForms handles sensitive personal data — passport numbers, dates of birth, nationalities — because that is what customs and immigration forms require. This document explains how that data is protected at every layer.

## Core Principle

**Your personal data is yours.** It is stored on your devices, encrypted by the operating system, and never retained by the server.

## On-Device Storage (iOS/macOS App)

All personal data (crew, passengers, travel documents, flights) is stored locally using Apple's SwiftData framework and synced via **CloudKit private database**.

- **Encrypted at rest** — on iPhone and iPad, iOS Data Protection encrypts the on-device database when the device has a passcode. The app uses the iOS default protection level: data is locked from boot until you first unlock the device, and after that first unlock it remains available to the system even while the screen is locked. On a Mac, at-rest encryption comes from FileVault, if enabled
- **Encrypted in iCloud** — CloudKit private databases are encrypted and tied to your own iCloud account; no other app user or developer can open them
- **Synced across your devices** — data follows Apple's standard CloudKit sync, meaning it is available on your iPhone, iPad, and Mac under the same Apple ID
- **No access by FlightForms** — we have no copy of, and no way to read, your CloudKit private data. It is held by Apple under your own iCloud account and Apple's terms. By default Apple manages the iCloud encryption keys; if you turn on [Advanced Data Protection](https://support.apple.com/en-gb/102651), the keys are held only on your devices and Apple cannot read the data either
- **Authentication tokens in Keychain** — JWT credentials are stored in the iOS/macOS Keychain, the most secure storage available on Apple platforms

## On-Device Storage (Android App)

All personal data (crew, passengers, travel documents, aircraft, flights) is stored locally in the app's own database on the phone.

- **Encrypted at rest** — Android's file-based encryption protects the app's storage whenever the phone has a screen lock
- **Stays on the phone** — there is no cloud sync, and the app opts out of Android backup and device-to-device transfer, so the data is not copied to your Google account or to a new phone
- **Moving to another device is your choice** — *Settings → Move my data* writes one file, encrypted with a passphrase the app generates and shows you; the file only goes where you send it. A plain, unencrypted export is also available for your own records
- **No access by FlightForms** — we have no copy of, and no way to read, the data on your phone
- **Authentication tokens in the Android Keystore** — sign-in credentials are stored in encrypted preferences backed by the Keystore

## Passport Scanning

Scanning a passport reads the machine-readable zone (the two lines of `<<<` characters) with on-device text recognition — Apple's Vision framework on iPhone, iPad and Mac, Google's ML Kit on Android. The image is processed on the device, is not kept, and is never sent to the FlightForms server or to anyone else; only the text you accept is saved to the person's record.

**One disclosure for Android:** ML Kit, which is part of the app, sends Google usage and diagnostic metrics about the text-recognition API — device model and OS version, app version, a per-installation identifier, how long recognition took, image size and format, and error codes. It does **not** send the image or the recognised text ([Google's ML Kit terms](https://developers.google.com/ml-kit/terms), [data disclosure](https://developers.google.com/ml-kit/android-data-disclosure)). The app only starts ML Kit when you open the passport scanner, so if you never scan, none of this is sent; once you have scanned, Google may send the metrics later in the background. Google offers no switch to turn the metrics off. The iPhone, iPad and Mac apps send nothing comparable.

## Server-Side Processing

The FlightForms API server (`forms.flyfun.aero`) is **stateless with respect to personal data**.

- **Data in transit only** — when you generate a form, the server receives your flight and passenger data, fills the template, returns the file, and discards everything. No personal data is written to disk or database.
- **No PII in logs** — server logs record only usage metrics (which airport, which form, timestamp). Names, passport numbers, and other personal data are never logged.
- **No PII in error messages** — error responses contain generic messages, never personal data or internal details.
- **HTTPS enforced** — all communication uses TLS encryption. HSTS headers ensure browsers and clients never downgrade to plain HTTP.
- **Authenticated access** — form generation requires authentication (OAuth or API token). Unauthenticated requests are rejected.
- **Rate limited** — each account can fill a bounded number of forms per hour, which limits what a stolen token could be used for.

## Why Form Generation Uses a Server

A natural question is: why not generate forms entirely on-device, avoiding the server altogether?

The short answer is that Apple's built-in PDF framework (PDFKit) cannot reliably do what form filling requires, and the alternatives are commercial SDKs with enterprise pricing that would be disproportionate for this use case.

Specifically, the server-side Python library (pypdf) handles several operations that PDFKit does not support or supports unreliably:

- **Auto-sizing text** — official forms have fields of varying sizes. The server calculates font sizes to fit each field; PDFKit has no equivalent.
- **Appearance stream generation** — filled fields need valid PDF appearance streams to display correctly across viewers. PDFKit's generated streams are unreliable, sometimes producing blank fields.
- **Flattening** — baking field values into the page content so the form looks correct in any viewer. PDFKit has no flattening API.
- **Non-PDF formats** — several airports require DOCX or XLSX forms. No Swift equivalent exists for the Python libraries used (python-docx, openpyxl).

Building a custom PDF engine to replace these capabilities would be a large undertaking with ongoing maintenance burden. Commercial SDKs (PSPDFKit, Foxit, Apryse) cover all these gaps but cost thousands per year — not justified for a niche general aviation tool.

The server-side approach lets us use mature, well-tested open-source libraries while keeping the privacy tradeoff minimal: personal data is transmitted over TLS, held in memory only for the duration of form generation, and never stored or logged.

## What the Server Does Store

The server stores only:

- **User accounts** — email address, display name and sign-in provider identifier, used for authentication. The account is shared with [FlyFun Weather](https://weather.flyfun.aero).
- **Usage records** — which airport, which form, and when. No crew or passenger data.

## Passengers

If you are a passenger or crew member and a pilot has entered your details into FlightForms, this section is for you.

- **Where your details are** — in the FlightForms app on the pilot's own devices. On iPhone, iPad and Mac they sync through the pilot's private iCloud account; on Android they stay on the pilot's phone. FlightForms (the developer) has no copy and cannot see them.
- **What they are used for** — filling in the customs, immigration and airport forms the flight requires. The pilot sends those forms to the authorities that ask for them, from their own email or the airport's own website; FlightForms never sends anything on their behalf.
- **The server keeps nothing** — to fill a form, the details pass through our server for the moment it takes, over an encrypted connection, and are then discarded.
- **Your rights** — the pilot (or the organisation they fly for) decides what is kept, so ask them to show, correct or delete your details. The app lets them delete a person, or everything, in one step.

Pilots can share a short version of this with their passengers from the app's *Settings → Privacy note for passengers*.

## Deleting Your Data

- **Delete Account** (Settings) permanently deletes your FlightForms account and your usage records from our server. It does **not** delete the people, aircraft, flights and trips in the app, because those were never on our server.
- **Delete All Data** (Settings) deletes every person, travel document, aircraft, flight and trip from the app. On iPhone, iPad and Mac this also removes them from your iCloud, and so from all your devices signed in to the same Apple ID. It does not affect your account.
- A small record of form costs is kept for accounting after an account is deleted. It is keyed by a random identifier that no longer maps to anyone once the account is gone.

## Network Security

- **TLS encryption** — all API traffic is encrypted in transit via HTTPS
- **HSTS** — Strict-Transport-Security header prevents protocol downgrade attacks
- **Security headers** — X-Content-Type-Options, X-Frame-Options, and Referrer-Policy headers are set on all responses
- **Non-root container** — the server runs as an unprivileged user inside the Docker container
- **Input validation** — all inputs (ICAO codes, field values) are validated before processing

## Temporary Files

When you generate a form, the filled file is written to the app's temporary storage on your device so it can be saved, shared or emailed. On iPhone, iPad and Android the app deletes it as soon as the share sheet or mail composer closes. On a Mac, if you open the form in another app, reveal it in Finder, or send it with Mail or a sharing service, the file is kept briefly because that app is still reading it; it is deleted when you next generate a form (once it is more than 15 minutes old) or the next time the app starts. The file never leaves your device unless you send it, and it is covered by the same at-rest encryption as the rest of the app's data.

## CLI Tool

The command-line tool sends the same data to the server for form generation. If you use CSV files for crew/passenger data, those files are on your local machine — manage their permissions accordingly. The CLI defaults to `http://localhost` for local development; when pointing at a remote server, always use HTTPS.

## Summary

| Layer | Protection |
|-------|------------|
| On-device storage (Apple) | Apple Data Protection encryption + SwiftData |
| On-device storage (Android) | Android file-based encryption; no cloud backup |
| Cross-device sync | CloudKit private database on Apple (encrypted, single-account access); none on Android |
| Auth credentials | iOS/macOS Keychain; Android Keystore |
| Network transport | TLS / HTTPS with HSTS |
| Server processing | In-memory only, no persistence of personal data |
| Server logs | Usage metrics only, no PII |
| Temporary files | Deleted when sharing ends (briefly kept on Mac for the receiving app), swept at launch, encrypted at rest |

## Security Issues

To report a security problem, or if you think your data may have been exposed, see [SECURITY.md](SECURITY.md).
