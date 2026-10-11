# Security policy

## Supported versions

Only the **latest release** of Glyph gets security fixes. Please update
before reporting: <https://github.com/spandan-kumar/glyph/releases/latest>.

## Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Report it privately using GitHub's private vulnerability reporting:
**Security → Report a vulnerability** on
<https://github.com/spandan-kumar/glyph/security/advisories/new>.

If that is unavailable, ask in the [Discord](https://discord.gg/9EeCFZAFvk)
for a private way to reach the maintainer, without posting details.

## What to include

- Glyph version and phone (model, Android or iOS version).
- What you found and why it matters.
- Steps to reproduce, or a proof of concept.
- WLED version and display type, if a device is involved.
- Whether it is already public.

Please don't include real Wi-Fi passwords or your own private data.

## What to expect

Glyph is a volunteer project, so these are best-effort goals, not promises:
a reply within about a week, a fix or a plan once confirmed, and credit in
the release notes if you want it. Please give a reasonable time to fix
before you publish.

## Scope

In scope: the Glyph app, its animation catalog delivery (signed manifest
and verification), file import and sharing, and the build and release
workflows in this repository.

Things that are by design, so not vulnerabilities on their own:

- **Glyph talks to WLED over your local network without authentication, and
  in plain HTTP.** WLED's API has no login. Anyone on the same Wi-Fi can
  control a WLED device without Glyph. Run it on a network you trust.
- **The settings PIN is WLED's.** Glyph can unlock a PIN-locked device if you
  enter the PIN, but the PIN is enforced by WLED firmware, and WLED's own
  notes say it is not strong protection.
- Wi-Fi details entered in the setup wizard travel to your device over that
  same local connection.

Out of scope here: bugs in **WLED firmware** or its web interface. Please
report those to WLED: <https://github.com/wled/WLED/security>. Also out of
scope: issues needing a rooted phone or physical access, and findings from
third parties (Open-Meteo, GitHub, Discord).

## Privacy

What Glyph sends and stores is described in [docs/PRIVACY.md](docs/PRIVACY.md).
