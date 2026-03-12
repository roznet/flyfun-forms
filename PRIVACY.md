# Privacy

FlightForms handles sensitive personal data — passport numbers, dates of birth, nationalities — because that is what customs and immigration forms require. This document explains how that data is protected at every layer.

## Core Principle

**Your personal data is yours.** It is stored on your devices, encrypted by Apple, and never retained by the server.

## On-Device Storage (iOS/macOS App)

All personal data (crew, passengers, travel documents, flights) is stored locally using Apple's SwiftData framework and synced via **CloudKit private database**.

- **Encrypted at rest** — iOS Data Protection encrypts the on-device database when the device is locked
- **Encrypted in iCloud** — CloudKit private databases are encrypted and accessible only to the signed-in iCloud account
- **Synced across your devices** — data follows Apple's standard CloudKit sync, meaning it is available on your iPhone, iPad, and Mac under the same Apple ID
- **No third-party access** — neither FlightForms nor anyone else can read your CloudKit private data; only your iCloud account has the keys
- **Authentication tokens in Keychain** — JWT credentials are stored in the iOS/macOS Keychain, the most secure storage available on Apple platforms

## Server-Side Processing

The FlightForms API server (`forms.flyfun.aero`) is **stateless with respect to personal data**.

- **Data in transit only** — when you generate a form, the server receives your flight and passenger data, fills the template, returns the file, and discards everything. No personal data is written to disk or database.
- **No PII in logs** — server logs record only usage metrics (which airport, which form, timestamp). Names, passport numbers, and other personal data are never logged.
- **No PII in error messages** — error responses contain generic messages, never personal data or internal details.
- **HTTPS enforced** — all communication uses TLS encryption. HSTS headers ensure browsers and clients never downgrade to plain HTTP.
- **Authenticated access** — form generation requires authentication (OAuth or API token). Unauthenticated requests are rejected.

## What the Server Does Store

The server stores only:

- **User accounts** — email address and OAuth provider identifier, used for authentication
- **Usage records** — which airport, which form, and when (no personal data)

## Network Security

- **TLS encryption** — all API traffic is encrypted in transit via HTTPS
- **HSTS** — Strict-Transport-Security header prevents protocol downgrade attacks
- **Security headers** — X-Content-Type-Options, X-Frame-Options, and Referrer-Policy headers are set on all responses
- **Non-root container** — the server runs as an unprivileged user inside the Docker container
- **Input validation** — all inputs (ICAO codes, field values) are validated before processing

## Temporary Files

When you preview a generated form on your device, the PDF is written to a temporary file. This file is deleted as soon as you dismiss the preview. Even before deletion, it is protected by iOS Data Protection encryption.

## CLI Tool

The command-line tool sends the same data to the server for form generation. If you use CSV files for crew/passenger data, those files are on your local machine — manage their permissions accordingly. The CLI defaults to `http://localhost` for local development; when pointing at a remote server, always use HTTPS.

## Summary

| Layer | Protection |
|-------|------------|
| On-device storage | Apple Data Protection encryption + SwiftData |
| Cross-device sync | CloudKit private database (encrypted, single-account access) |
| Auth credentials | iOS/macOS Keychain |
| Network transport | TLS / HTTPS with HSTS |
| Server processing | In-memory only, no persistence of personal data |
| Server logs | Usage metrics only, no PII |
| Temporary files | Deleted after use, encrypted at rest by iOS |
