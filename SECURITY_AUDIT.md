# Security Audit Report: FlightForms

**Latest audit:** 2026-10-02 (previous: 2026-03-11)
**Scope:** Python backend (FastAPI), deploy and CI config, iOS/macOS app, Android app, and the shared `flyfun-common` library that the backend and apps use for auth.
**Focus:** protection of passport and travel-document data, and of the shared FlyFun account.

The 2026-10-02 audit was run independently of the March report, by four separate reviews (backend, iOS/macOS, Android, flyfun-common), and then compared with it. Findings were checked against the code; the server and library ones were also reproduced with small tests against the real code.

**Status legend:**
- **Fixed:** merged and deployed.
- **Fixed, pending release:** merged or in an open PR; not yet in production until the release and deploy listed with it.
- **Open:** not fixed yet.
- **Accepted:** deliberately not fixed, with the reason.

---

## Summary

The core design still holds: the server keeps no passport or passenger data, and the apps store it on the device and in the user's private iCloud (iOS) or app-private storage with no backup (Android).

The serious problems found in October were in the shared auth library rather than in forms itself, plus two privacy gaps in how the apps delete people:

| ID | Severity | Area | Finding | Status |
|----|----------|------|---------|--------|
| N1 | High | flyfun-common | Magic-link sign-in could resolve to a different account (unescaped `LIKE`, then accent-insensitive collation) | Fixed, pending release (0.6.8) |
| N2 | High | flyfun-common, forms | API-token scopes not registered by an app were given full access there | Fixed, pending release (0.6.9) |
| N3 | High | flyfun-common | Script injection on the OAuth server's redirect pages | Fixed, pending release (0.6.8) |
| N4 | High | Android | Deleting a person kept all their data in the database and in exports | Open |
| N5 | High | iOS, Android | Suggested "Move my data" passphrase is low-entropy (3 words, about 15.5 bits) | Accepted |
| N6 | Medium | flyfun-common | Sliding-session renewal can revive a token revoked by "log out everywhere" | Fixed, pending release (0.6.9) |
| N7 | Medium | Android, flyfun-common | Native sign-in callback can be intercepted by another installed app | Fixed, pending release (0.6.9 + Android build) |
| N8 | Medium | Backend | Dates of birth could reach the server log through error tracebacks | Fixed, pending deploy |
| N9 | Medium | Backend, deploy | No request body size limit | Fixed, pending deploy |
| N10 | Medium | iOS | Deleted documents' numbers kept on flights | Open |
| N11 | Low-Med | flyfun-common | Legacy native login still returns the session token in a URL | Fixed, pending release (0.6.9) |
| N12 | Low | Deploy | Container port published on all interfaces | Fixed, pending deploy |
| N13 | Low | iOS, Android | Web-form prefill does not check the page's origin | Open |
| N14 | Low | Backend, macOS | Spreadsheet formula injection in XLSX forms and the people CSV export | Open |
| N15 | Low | iOS, Android | Passport screens visible in app-switcher snapshots and screenshots | Open |
| N16 | Low | Android | Keyboard may learn document numbers; passphrase shown in clear | Open |
| N17 | Low | CI | `claude.yml` grants broad tools and write access | Open |
| N18 | Low | flyfun-common | OAuth server hardening (refresh-token reuse, code redemption race, registration cap) | Open |
| N19 | Low | iOS, Android | Oversized PDFs or import files can crash the app | Open |

**Release steps for the fixes above:**
1. Publish flyfun-common 0.6.9 (0.6.8 is tagged).
2. Deploy forms (it now requires `flyfun-common>=0.6.9`) and weather.

Until then the "pending" items are fixed in code only.

---

## October 2026 findings

### N1. Magic-link sign-in could resolve to a different account (High)
**Where:** `flyfun-common/python/src/flyfun_common/auth/magic_link.py`

- **Original flaw:** the case-insensitive fallback lookup used `ILIKE` with the requested address unescaped, so `_` and `%` acted as wildcards.
- **Second route:** production MySQL's `utf8mb4_unicode_ci` collation also treats accented look-alikes as equal.
- **Impact:** either way, a sign-in link sent to one mailbox could log into a different existing account.
- **Exposure:** only apps that enable magic-link sign-in (weather). Forms does not mount it.

**Fix (0.6.8):**
- Magic-link addresses must be ASCII.
- SQL only narrows the candidates; Python accepts a row only if its email equals the request ignoring case, so the database collation can't change the result.
- Code redemption only considers tokens for exactly that address.
- Regression tests cover wildcards, look-alikes and a simulated accent-folding collation.

### N2. Unregistered token scopes had full access (High)
**Where:** `flyfun-common/python/src/flyfun_common/db/deps.py`

- **Flaw:** each app keeps its own scope registry, but the `api_tokens` table is shared. A scope missing from the local registry was treated as broad.
- **Impact:** a limited token issued by weather (`flights:read`) had full access on forms, including account deletion and the account export.

**Fix (0.6.9):**
- Scopes are default-deny: a scoped token reaches only paths the current app registered for it. Forms registers none.
- `mcp` stays broad by default, and `register_broad_scope()` declares any other broad scope.

### N3. Script injection on the OAuth redirect pages (High)
**Where:** `flyfun-common/python/src/flyfun_common/oauth/router.py`

- **Flaw:** the error and approve redirect pages embedded the client's registered `redirect_uri` in an inline script without escaping `<`. Client registration is open.
- **Impact:** a crafted client could run script on the host app's domain when a signed-in user followed a link.
- **Exposure:** weather (MCP), not forms.

**Fix (0.6.8):**
- One redirect-page helper now escapes the URL for both the script and the meta-refresh contexts.
- Registration rejects redirect URIs containing characters RFC 3986 does not allow.

### N4. Android: deleting a person kept their data (High)
**Where:** `app/android/.../data/Daos.kt` (soft delete), `data/DataTransfer.kt` (export of all rows including deleted ones)

- **Flaw:** deletion only set `deletedAt`. The full row (name, date of birth, address, document numbers) stayed in Room.
- **Impact:** every later "Move my data" or GDPR export carried the deleted data. This contradicts `PRIVACY.md`. iOS tombstones correctly hold only an id, kind and date.

**Fix to do:**
- Clear every personal field of a tombstoned row once the undo window closes.
- Export tombstones as id, kind and date only.
- Add a migration that scrubs existing tombstones.

### N5. Weak suggested "Move my data" passphrase (High)
**Where:** `app/flyfun-forms/.../Services/DataFileCrypto.swift`, Android `core-logic/.../DataFileCrypto.kt`

- **Flaw:** the suggested passphrase is three words from a 36-word list, about 15.5 bits (reduced from six words, about 31 bits, on 2026-10-03). Under PBKDF2 at 210k iterations it can be brute-forced quickly.
- **Impact:** the file is meant to be moved through chat, mail or AirDrop, and contains every stored passport number.

**Accepted (2026-10-03):** six words wrapped on screen and were too hard to remember. The file is a one-off transfer that the user creates, imports and deletes, and the user controls where it goes; anyone wanting more strength can type their own passphrase. If this is revisited, a larger word list (e.g. the EFF long list) raises strength without making the passphrase longer; it only affects generation, not the file format.

### N6. Sliding renewal can revive revoked sessions (Medium)
**Where:** `flyfun-common/python/src/flyfun_common/auth/middleware.py`

- **Flaw:** the renewal middleware issues a fresh token for any validly signed token near expiry, even on public endpoints. It does not check the account's revocation time.
- **Impact:** a token revoked by "log out everywhere" can be renewed into a valid one.

**Fix (0.6.9):**
- The auth dependencies record the user they authenticated once every check has passed (user exists, not suspended, not revoked).
- The middleware renews only when that user is the token's `sub`, so public routes never renew.
- Sessions are shared across FlyFun apps, so this also closes the route through forms into weather.

### N7. Android sign-in callback interception (Medium)
**Where:** `app/android/.../AndroidManifest.xml`, `auth/AuthService.kt`; server `flyfun_common/auth/router.py`

- **Flaw:** the callback uses a custom URL scheme opened from a Custom Tab, and the exchange step has no PKCE.
- **Impact:** a malicious app on the same device could register the scheme and redeem the code.
- **Not affected:** iOS, because `ASWebAuthenticationSession` delivers the callback privately.

**Fix:**
- **Server (0.6.9):** `/auth/login` accepts an S256 `code_challenge`, bound into the exchange code; `/auth/exchange` then requires the matching `code_verifier`. An intercepted `code`+`state` can no longer be redeemed.
- **Android:** the app sends a challenge and keeps the verifier with the pending `state`. This ships with the next Android build.
- **Optional:** Android's Auth Tab would also keep the redirect private, but with PKCE it is no longer needed for safety.
- **Not done:** the Swift client does not send a challenge yet. It isn't exposed, because `ASWebAuthenticationSession` already delivers the callback privately.

### N8. Dates of birth in server logs (Medium)
**Where:** `src/flightforms/api/models.py`, `src/flightforms/fillers/*.py`

- **Flaw:** a date of birth or expiry not in `YYYY-MM-DD` reached the fillers' `strptime`. Its error message, which quotes the value, was logged with the traceback. The CLI passes unrecognised date formats through unchanged.

**Fix (pending deploy):**
- `PersonData` validates `dob` and `id_expiry` (blank allowed), so a malformed date is a 422 to the caller.
- A new `RedactedErrorMiddleware` logs unhandled exceptions by type, route and stack frames only, never the message.

### N9. No request body size limit (Medium)
**Where:** `deploy/forms.flyfun.aero.caddy`, `src/flightforms/api/middleware.py`

- **Flaw:** FastAPI parses the JSON body before authentication, and nothing capped its size.
- **Impact:** one unauthenticated oversized request could exhaust the container's 512 MB.

**Fix (pending deploy):**
- 1 MB cap in Caddy and in the app, which also counts chunked bodies.
- Form requests are a few KB.

### N10. iOS: deleted documents' numbers kept on flights (Medium)
**Where:** `app/flyfun-forms/.../Models/Flight.swift` (`chosenDocNumbers`), `Services/StableRecords.swift`

- **Flaw:** the per-flight document choice stores raw document numbers, and deleting the document or person does not remove them.
- **Impact:** they keep syncing through iCloud, are copied to duplicated flights and appear in exports.

**Fix to do:**
- Strip the numbers on delete, plus a launch-time sweep.
- Longer term, store document ids instead of numbers.

### N11. Legacy token-in-URL login branch (Low-Medium)
**Where:** `flyfun_common/auth/router.py`

- **Flaw:** a native login without `state` still returns the session token in the custom-scheme callback URL. When no scheme is given it defaults to one that isn't on the allowlist. Current apps always send `state`.

**Fix (0.6.9):** the branch is removed. A native login without an allowlisted scheme and a `state` is refused at `/auth/login`, and the callback has no default scheme. App builds older than the `state` flow (2026-07) can no longer sign in.

### N12. Container port on all interfaces (Low)
**Where:** `docker-compose.yml`

- **Flaw:** `8030:8030` published plain HTTP on the public interface. Docker's published ports bypass the host firewall, so this route skipped Caddy's TLS and limits.

**Fix (pending deploy):** publish on `127.0.0.1` only. Caddy runs on the host and proxies `localhost:8030`.

### N13. Web-form prefill without origin check (Low)
**Where:** `app/flyfun-forms/.../Views/WebFormView.swift`, Android `ui/webform/WebFormScreen.kt`

- **Flaw:** both the automatic fill and "Fill again" write passenger data into whatever page is loaded, even after a redirect or a link to another site.

**Fix to do:** fill only when the page's host matches the plan's URL and the page uses https.

### N14. Spreadsheet formula injection (Low)
**Where:** `src/flightforms/fillers/xlsx_filler.py`, macOS `Views/PeopleListView.swift`

- **Flaw:** a value starting with `=`, `+`, `-` or `@` is treated as a formula when the airport opens the XLSX form, or when someone opens the exported CSV.

**Fix to do:** prefix such values with `'` in user-supplied cells.

### N15. Screen exposure of passport data (Low)
- **Flaw:** there is no app-switcher privacy cover on iOS and no `FLAG_SECURE` on Android.

**Fix to do:** apply these to the person, document, scanner and passphrase screens only, so legitimate screenshots of flight details still work.

### N16. Android keyboard learning (Low)
- **Flaw:** document-number fields allow the keyboard to learn and suggest their contents, and the import passphrase is shown in clear.

**Fix to do:** turn off autocorrect and personalised learning on those fields, and mask the passphrase.

### N17. CI agent permissions (Low)
**Where:** `.github/workflows/claude.yml`

- **Flaw:** the workflow allows arbitrary code tools with a write token, prints full output to public logs, and pins actions to tags rather than commit SHAs.
- **Trigger:** only maintainers can start it, but the content it processes may come from outsiders.

**Fix to do:**
- Drop `python`, `pip`, `npm` and `npx` from the allowed tools.
- Set `show_full_output: false`.
- Pin actions to commit SHAs.

### N18. OAuth server hardening (Low)
**Fix to do:**
- Revoke the token family when a rotated refresh token is reused.
- Lock the authorization code row while it is redeemed.
- Add a per-IP limit on client registration as well as the global one.
- Show the redirect host on the consent page.

### N19. Local crashes from oversized files (Low)
**Fix to do:**
- iOS: cap the size and page count when rendering PDFs for scanning.
- Android: cap the size when reading a data file for import.

---

## March 2026 findings: current status

| # | Finding | Status (2026-10-02) |
|---|---------|----------------------|
| 1 | Passport data in iOS debug log | **Fixed.** Verified again: all Swift logging uses `os.Logger` with private interpolation. |
| 2 | Passport data sent to the server on every generate | **Accepted.** Inherent to filling forms; HTTPS + HSTS, never stored. |
| 3 | JWT in the OAuth callback URL (H8) | **Fixed** (auth-code exchange with `state`). The server's legacy branch is removed in 0.6.9 (N11), and PKCE closes the Android interception risk (N7). |
| 4 | No certificate pinning | **Accepted.** Pinning against Let's Encrypt rotation risks locking users out. |
| 5 | Legacy person ID fields | **Fixed.** |
| 6 | No request body encryption | **Accepted.** The server must read the data to fill the form. |
| 7 | CLI defaults to `http://` | **Open.** Low; add a warning for non-localhost `http://` URLs. |
| 8 | CLI people CSV on disk | **Accepted.** User-managed file. |
| 9 | Dev-mode CORS `*` | **Open, low.** Dev mode now refuses to start in production (an unknown `ENVIRONMENT` is not dev). |
| 10 | SessionMiddleware signed with the JWT secret | **Open.** Use a separate `SESSION_SECRET`. |
| 11 | Placeholder `JWT_SECRET` | **Fixed.** |
| 12 | ICAO validation | **Fixed.** Person dates were not validated, which allowed N8. |
| 13 | Template path traversal | **Fixed.** |
| 14 | Security headers | **Fixed.** |
| 15 | Dependency pinning | **Partly.** `flyfun-common` has no upper bound and there is no lock file. |
| 16 | Generated forms left in temp | **Fixed** (re-fixed 2026-09-26). On macOS a file handed to another app stays until the next form or launch. |
| 17 | No rate limit on `/generate` | **Fixed.** `/validate` and `/email-text` are not limited (cheap endpoints). |
| 18 | Error messages leaking paths | **Fixed.** |
| 19 | SwiftData file protection | **Recommendation changed.** `NSFileProtectionComplete` on the store would stop background CloudKit sync. Keep the store on the default class (documented in `PRIVACY.md`) and apply complete protection to generated form files instead. |

---

## Verified as sound (October 2026)

**Server**
- It stores no person data and logs nothing from request bodies.
- The GDPR export is scoped to the signed-in user and excludes secrets.
- Account deletion removes usage, preferences, tokens and OAuth grants.
- The container runs as non-root.

**Auth (flyfun-common)**
- JWTs are HS256-pinned with required `sub` and `exp`.
- Exchange codes and link tickets cannot be used as sessions.
- API tokens are 256-bit and stored hashed.
- OAuth login checks `state`, `nonce` and verified email.
- `next` redirects are restricted to relative paths.
- Stripe webhooks verify their signatures.

**iOS/macOS**
- The JWT is in the Keychain (this device only).
- CloudKit uses the private database only.
- There are no analytics or crash SDKs and no ATS exceptions.
- Scans are never saved.
- Generated forms are cleaned up after sharing.
- Debug and UI-test bypasses are compiled out of release builds.

**Android**
- Backup and device transfer are disabled.
- The token is encrypted with a non-exportable Keystore key.
- Only the launcher activity is exported.
- The FileProvider is limited to generated forms.
- Nothing is written to external storage.
- No personal data is logged.
- The web-form WebView data is cleared on exit.
