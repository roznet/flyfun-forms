# Security Audit Report — FlightForms

**Date:** 2026-03-11
**Scope:** iOS app (Swift/SwiftData/CloudKit) + Python backend (FastAPI/SQLAlchemy)
**Focus:** Protection of sensitive passport/document data

---

## Executive Summary

The application's architecture is **fundamentally sound** for its purpose: sensitive passport data (document numbers, PII) lives in SwiftData with CloudKit sync and is **never persisted** on the server. The backend is stateless with respect to PII — it receives data, fills a PDF/DOCX/XLSX template, returns the file, and discards everything.

However, there are **several concrete vulnerabilities** that could expose sensitive data in transit or through side-channels. The most critical is that the iOS app **logs the entire POST /generate request body** — including passport numbers — to the system log.

---

## CRITICAL Issues

### 1. Passport Data Logged in Plaintext on iOS Device (CRITICAL)

**File:** `app/flyfun-forms/flyfun-forms/Services/FormService.swift:52-54`

```swift
if let bodyStr = String(data: body, encoding: .utf8) {
    Self.logger.debug("POST /generate body: \(bodyStr)")
}
```

This logs the **entire JSON request body** — including every crew and passenger's `id_number` (passport number), `dob`, `nationality`, `address`, `place_of_birth` — to the unified system log via `os.Logger`.

**Impact:**
- On-device logs can be captured via `Console.app`, `log stream`, or MDM solutions
- Logs may persist in crash reports sent to Apple
- Third-party analytics SDKs with log access could capture this data
- Sysdiagnose files (shareable for bug reports) include unified logs

**Recommendation:** Remove this debug log entirely, or at minimum redact sensitive fields before logging.

---

### 2. Sensitive Data Transmitted to Server in Every Generate Request (DESIGN CONSIDERATION)

**Files:**
- `app/flyfun-forms/flyfun-forms/Services/APITypes.swift:165-192` (`PersonPayload`)
- `app/flyfun-forms/flyfun-forms/Views/FlightEditView.swift:350-366` (`personPayload()`)

Every form generation sends passport numbers, DOB, nationality, address, place of birth, and sex to the backend. This is **inherent to the application's purpose** (filling customs/immigration forms), but it means:

- The data transits the network on every generate call
- The server processes it in memory temporarily
- **This is an accepted architectural trade-off**, not a bug — the server needs this data to fill the PDF fields

The mitigating factors are:
- HTTPS in production (`https://forms.flyfun.aero`)
- The server does not persist this data (only logs `Usage` with airport/form, no PII)
- Data exists in server memory only for the duration of the request

**Recommendation:** This is acceptable given the use case. See recommendation #6 for additional protection.

---

## HIGH Severity Issues

### 3. JWT Token Passed in OAuth Callback URL (HIGH)

**File:** `app/flyfun-forms/flyfun-forms/Services/AuthService.swift:55-61`

```swift
let token = components.queryItems?.first(where: { $0.name == "token" })?.value
```

The JWT is returned as a query parameter in the custom URL scheme callback (`flyfunforms://auth?token=...`). This means:
- The JWT may appear in server access logs on the OAuth redirect
- On older iOS versions, URL scheme handlers could be hijacked by malicious apps
- The URL (including token) might appear in `ASWebAuthenticationSession` browser history

**File:** `app/flyfun-forms/flyfun-forms/Services/AuthService.swift:50`
```swift
session.prefersEphemeralWebBrowserSession = false
```

Setting this to `false` means the browser session persists cookies/state, which is a convenience trade-off but means the OAuth flow state persists.

**Recommendation:**
- Consider switching to `prefersEphemeralWebBrowserSession = true` for security-sensitive deployments
- The JWT-in-URL pattern is standard for mobile OAuth but be aware of the logging implications

### 4. No Certificate Pinning / TLS Validation (HIGH)

**File:** `app/flyfun-forms/flyfun-forms/Services/FormService.swift:56`

```swift
let (data, _) = try await URLSession.shared.data(for: request)
```

The app uses `URLSession.shared` with default TLS validation. This means:
- A compromised CA could issue a rogue certificate for `forms.flyfun.aero`
- On managed devices (corporate MDM), installed profiles can add trusted CAs, enabling MITM
- No certificate pinning means network interception proxies (Charles, mitmproxy) can capture all traffic including passport data

**Recommendation:** Implement certificate pinning via `URLSessionDelegate` or an `NSAppTransportSecurity` pinned domain configuration, at least for the production domain.

### 5. Person Legacy Fields Still on Model (HIGH — Data Hygiene)

**File:** `app/flyfun-forms/flyfun-forms/Models/Person.swift:10-13`

```swift
var idNumber: String?
var idType: String?
var idIssuingCountry: String?
var idExpiry: Date?
```

These legacy fields on `Person` duplicate the data now stored in `TravelDocument`. The migration code (`flyfun_formsApp.swift:54-77`) copies data to `TravelDocument` but **never clears** the legacy fields. This means passport numbers exist in two places in the SwiftData store (and consequently in two places in CloudKit).

**Recommendation:** After migration, nil out the legacy fields:
```swift
person.idNumber = nil
person.idType = nil
person.idIssuingCountry = nil
person.idExpiry = nil
```

---

## MEDIUM Severity Issues

### 6. No Request Body Encryption (MEDIUM)

While HTTPS provides transport encryption, the passport data in the POST body is plaintext JSON that the server processes. If you want defense-in-depth against server-side compromise:

**Recommendation:** Consider encrypting the `PersonPayload` fields with a per-request key that the server holds only in memory. This is likely over-engineering for this use case but noted for completeness.

### 7. CLI Tool Uses HTTP by Default (MEDIUM)

**File:** `src/flightforms/cli.py:13`

```python
DEFAULT_URL = "http://127.0.0.1:8030"
```

The CLI defaults to `http://` (not HTTPS). While this is meant for local development, if users point it at a remote server and forget to specify `https://`, passport data would travel in plaintext.

**Recommendation:** Add a warning when using HTTP with a non-localhost URL, or default to HTTPS for non-local URLs.

### 8. CLI People CSV Contains Passport Data on Disk (MEDIUM)

**File:** `src/flightforms/cli.py:16-39`

The `--people-file` CSV contains passport numbers, DOB, nationality in plaintext on disk. This is user-managed, but the CLI doesn't warn about file permissions.

**Recommendation:** Document that the CSV should be stored with restricted permissions. Consider adding a check that warns if the file is world-readable.

### 9. CORS Allows All Origins in Dev Mode (MEDIUM)

**File:** `src/flightforms/api/app.py:57-58`

```python
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])
```

In dev mode, CORS is completely open. If dev mode is accidentally enabled in production, any website could make authenticated requests to the API.

**Recommendation:** Even in dev mode, restrict CORS to known origins (e.g., `http://localhost:*`). The `is_dev_mode()` guard is good, but defense-in-depth is warranted.

### 10. SessionMiddleware Uses JWT Secret (MEDIUM)

**File:** `src/flightforms/api/app.py:51-54`

```python
app.add_middleware(
    SessionMiddleware,
    secret_key=get_jwt_secret(),
)
```

The session middleware and JWT signing share the same secret. If the session secret is leaked (e.g., via a session cookie vulnerability), the JWT signing key is also compromised.

**Recommendation:** Use a separate secret for session middleware.

### 11. `.env.sample` Contains Placeholder Credentials (MEDIUM)

**File:** `.env.sample:3`

```
DATABASE_URL=mysql+pymysql://user:pass@shared-mysql:3306/flyfun
JWT_SECRET=change-me-in-production
```

While this is a sample file, `change-me-in-production` as a JWT secret is dangerous if someone forgets to change it. The `.env` itself is properly gitignored.

**Recommendation:** Add a startup check that refuses to start if `JWT_SECRET` equals the placeholder value.

---

## LOW Severity Issues

### 12. Generated PDFs Written to Temp Directory (LOW)

**File:** `app/flyfun-forms/flyfun-forms/Views/FlightEditView.swift:294-297`

```swift
let tempDir = FileManager.default.temporaryDirectory
let fileURL = tempDir.appendingPathComponent(filename)
try data.write(to: fileURL)
```

Generated PDFs (which contain passport data) are written to the iOS temp directory. These files persist until the system reclaims them.

**Recommendation:** Clean up temp files after QuickLook preview is dismissed, or use a more ephemeral storage mechanism.

### 13. No Rate Limiting on /generate Endpoint (LOW)

The `/generate` endpoint has no rate limiting. A compromised JWT could be used to make unlimited requests. The `Usage` table tracks calls but doesn't enforce limits.

**Recommendation:** Add per-user rate limiting (e.g., via `slowapi` or middleware).

### 14. Server Error Messages May Leak Internal Paths (LOW)

**File:** `src/flightforms/api/generate.py:49`

```python
raise HTTPException(status_code=500, detail=f"Template file not found: {mapping.template}")
```

This leaks the template filename to the client. Not a direct data exposure, but reveals internal structure.

**Recommendation:** Use generic error messages in production.

### 15. No SwiftData Encryption at Rest (LOW — Mitigated by iOS)

SwiftData/Core Data stores are encrypted at rest by iOS Data Protection (when the device has a passcode). CloudKit private database is also encrypted. However, the app does not use the `NSFileProtectionComplete` attribute explicitly, which means data may be accessible before first unlock after boot.

**Recommendation:** Set `NSFileProtection` to `.complete` on the SwiftData store file for maximum protection.

---

## Positive Security Findings

These aspects of the architecture are well-designed:

1. **JWT stored in Keychain** (`AppState.swift:14-16`) — The JWT is stored using `CodableSecureStorage` backed by the iOS Keychain, not UserDefaults or files.

2. **Server stores no PII** — The `Usage` database table (`db/models.py:17-27`) only stores `user_id`, `endpoint`, `airport_icao`, `form_id`, and `timestamp`. No passport data, names, or PII are persisted server-side.

3. **CloudKit private database** (`flyfun_formsApp.swift:20-21`) — Data syncs via `iCloud.aero.flyfun.flightforms` private database, which is encrypted and only accessible to the user's iCloud account.

4. **Non-root Docker container** (`Dockerfile:6-7`) — The container runs as user `app` (UID 2000), not root.

5. **Production Swagger docs disabled** (`app.py:45`) — `/docs` endpoint is only enabled in dev mode.

6. **Proper .gitignore** — `.env` is gitignored, preventing secret leakage.

7. **Auth-protected endpoints** — The `/generate` endpoint requires authentication via `current_user_id` dependency.

8. **Test data uses fake values** — Tests use synthetic IDs like `PP-999001`, not real passport numbers.

9. **Memory-limited container** (`docker-compose.yml:19-20`) — 512M memory limit helps prevent resource exhaustion attacks.

---

## Priority Action Items

| Priority | Issue | Effort |
|----------|-------|--------|
| **P0** | Remove/redact passport data from iOS debug log (Issue #1) | 5 min |
| **P1** | Clear legacy Person ID fields after migration (Issue #5) | 15 min |
| **P1** | Implement certificate pinning for production domain (Issue #4) | 2-4 hrs |
| **P2** | Use separate secret for SessionMiddleware (Issue #10) | 15 min |
| **P2** | Clean up temp PDF files after preview (Issue #12) | 30 min |
| **P2** | Add startup check for placeholder JWT_SECRET (Issue #11) | 15 min |
| **P3** | Add HTTP warning in CLI for non-localhost URLs (Issue #7) | 15 min |
| **P3** | Add rate limiting to /generate endpoint (Issue #13) | 1 hr |
| **P3** | Sanitize error messages in production (Issue #14) | 30 min |

---

## Conclusion

**Your core security goal — keeping passport data out of the server — is achieved.** The server never persists PII; it only holds it in memory during form generation. The SwiftData + CloudKit private database architecture ensures sensitive data stays encrypted on-device and in iCloud.

The most urgent fix is **removing the debug log that dumps the entire request body** (including all passport numbers) to the iOS system log. This is the single point where your security model breaks down — passport data that should stay in the encrypted SwiftData layer is being written to the unencrypted unified log system.
