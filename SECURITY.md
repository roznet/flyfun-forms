# Security Policy

FlightForms is a personal, open-source project run by a single developer.
This document explains how to report a security problem and how a suspected
personal-data breach is handled. See also [`PRIVACY.md`](./PRIVACY.md),
[`legal/GDPR.md`](./legal/GDPR.md) and [`SECURITY_AUDIT.md`](./SECURITY_AUDIT.md)
(the code-level security review — this file is the process, that one is the findings).

## Reporting a vulnerability or suspected breach

If you believe you have found a security vulnerability, or that personal data
may have been exposed:

- **Preferred:** use GitHub's private **"Report a vulnerability"** button under
  the repository's **Security** tab. This opens a private security advisory only
  the maintainer can see.
- Please do **not** open a public GitHub issue for a security vulnerability, as
  that discloses it to everyone before it can be fixed.

Please include what you found, how to reproduce it, and (if relevant) what data
you think may be affected. I will acknowledge the report as quickly as I can.

## What a breach could look like here

The server stores no crew or passenger data (see `PRIVACY.md`), so the realistic
scenarios are narrower than for most apps — but not empty:

- **Account data exposure** — the shared `users` table (email, display name,
  sign-in provider) and the `usage` rows (which airport, which form, when).
  Low sensitivity, still reportable if it leaks.
- **Compromise of the running server** — an attacker able to observe request
  bodies in flight would see the passport and passenger details being filled
  into forms at that moment. This is the severe case: treat it as high risk to
  the people on those manifests, even though nothing was stored.
- **Stolen API token or session** — lets someone generate forms as that user and
  read their account data; revoke the token and assess what was requested.
- **Client-side issues** — a bug in the iOS, macOS or Android app that exposes
  data held on the pilot's device. The data is theirs, not ours, but a flaw in
  our code that exposes it is ours to fix and to tell users about.

## Personal-data breach process (UK GDPR Art. 33–34)

The controller is established in the **United Kingdom**, so the lead supervisory
authority is the **Information Commissioner's Office (ICO)** under UK GDPR and
the Data Protection Act 2018. The internal process when a breach is suspected:

1. **Record it.** Log the time it was discovered and keep a running note of the
   facts, the data and people potentially affected, and every action taken.
   (Art. 33(5) — all breaches are documented, whether or not they are reported.)
2. **Contain and assess.** Stop the exposure, then judge the risk to affected
   individuals: what data, how many people, how likely and how severe the harm.
3. **Notify the ICO within 72 hours** of becoming aware — unless the breach is
   *unlikely* to result in a risk to people's rights and freedoms. Reported via
   the ICO's online breach-reporting service or the personal-data-breach
   helpline (0303 123 1113). If the 72-hour deadline cannot be met, notify with
   reasons for the delay.
4. **Notify affected users** without undue delay **if the breach is high risk**
   to them, in clear plain language: what happened, the likely consequences, the
   measures taken, and a contact point.
   - This is **not** required if the affected data was encrypted/unintelligible,
     or if follow-up measures mean the high risk no longer applies, or if it
     would involve disproportionate effort (in which case a public notice is
     used instead).
5. **Where we are a processor.** For crew and passenger data we act on the
   pilot's instructions (`legal/GDPR.md` §5). If a breach touches that data, the
   pilots (or their organisations) are the controllers and must be told without
   undue delay, with enough detail for them to meet their own obligations —
   including telling their passengers.
6. **Cross-border users.** The app serves pilots across Europe. If a breach
   affects users in the EU/EEA, EU GDPR applies by territorial scope (Art. 3(2))
   and the relevant EU authority would be notified in addition to the ICO.

## Scope

This policy covers the FlightForms server (`forms.flyfun.aero`), the iOS, macOS
and Android apps, the CLI, and their source code. The account system is shared
with [FlyFun Weather](https://github.com/roznet/flyfun-weather/blob/main/SECURITY.md),
which follows the same process. Infrastructure and platform providers
(DigitalOcean, Apple iCloud, Google and Apple sign-in) run their own security
and breach-notification processes.
