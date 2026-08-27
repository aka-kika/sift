<!--
Security Policy — PER PROJECT. From TAMPLATES/4-github/security-policy.
GitHub links this from the security tab and the "Report a vulnerability" button.
Style: no emojis. Monochrome.
-->

# Security Policy

## Supported versions

| Version | Supported |
|---|---|
| 1.10.x | Yes |
| < 1.10 | No — update to the [latest release](https://sift.akakika.com/Sift.dmg) |

Sift ships as a Developer ID–signed, Apple-notarized DMG. Only builds obtained
from [sift.akakika.com](https://sift.akakika.com/Sift.dmg) (or delivered by its
Sparkle update feed) are supported.

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private reporting:

**[Report a vulnerability](https://github.com/aka-kika/sift/security/advisories/new)**

If that is unavailable, reach out through [akakika.com](https://akakika.com).

Please include the Sift version, macOS version, what an attacker could achieve,
and the steps to reproduce it. A proof of concept helps, but a clear description
is enough to start.

**Never include a real licence key** in a report — a redacted example is always
sufficient.

## What to expect

- Acknowledgement within a few days. Sift is maintained by one person, so allow for that.
- An assessment of severity and scope, shared with you.
- A fix in a patch release, credited to you unless you'd rather stay anonymous.
- Public disclosure only after a fix ships.

## Scope

What is in scope — anything that lets code or a person get at data they
shouldn't, or make Sift act beyond what the user asked:

- Extraction of licence keys from the Keychain without local authentication
- Bypassing the Touch ID gate on revealing or copying a key
- Anything causing the uninstall sweep to touch a path outside the target app's bundle-ID-matched set, or to delete rather than move to the Trash
- Analysis prompts or licence data leaving the machine when the provider is set to local Ollama
- Injection through untrusted input Sift reads — app metadata, `Info.plist` fields, fetched link content, or a project folder's README — that changes what Sift does rather than what it says
- Anything that abuses the Finder Apple Event handoff to move a path the user did not select

Out of scope:

- Vulnerabilities in Ollama, Anthropic, OpenAI, Google Gemini, OpenRouter, Sparkle, Homebrew, or macOS itself — report those upstream
- The consequences of a user's own choice: switching to a cloud provider sends data to that provider by design
- Physical access to an unlocked Mac
- Ad-hoc-signed local builds you compiled yourself

## Design notes worth knowing before you test

- Licence keys are stored with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and a Keychain service derived from the bundle ID — side-builds cannot read the primary app's keys.
- Sift is **not sandboxed**; it reads `/Applications`, `~/Applications`, and user-level Library folders in order to do its job. See [docs/privacy.md](docs/privacy.md).
- The uninstall sweep moves to the Trash only. Apple system apps (`com.apple.*`) and Sift itself are refused.
- Root-owned bundles are handed to Finder by Apple Event rather than escalated in-process; the reasoning is in [ADR 0003](docs/decisions/0003-finder-does-privileged-trash-moves.md).
