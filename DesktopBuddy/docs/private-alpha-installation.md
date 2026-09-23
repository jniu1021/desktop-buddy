# Private-alpha local installation check

**Checked:** 2026-09-17
**Scope:** Local developer-machine installation only

DesktopBuddy `0.1` was archived in Release configuration, copied to
`~/Applications/Desktop Buddy.app`, and launched from that installed location.

## Verified

- Release archive builds successfully for `arm64` only.
- The app targets macOS 13 or later and runs as a menu-bar agent (`LSUIElement`).
- The application category is `public.app-category.utilities`.
- Hardened Runtime is enabled.
- The target declares no `.entitlements` file. Earlier ad-hoc local Release signing injected
  `com.apple.security.get-task-allow = true` as a base entitlement despite that absence.
  Release now disables base-entitlement injection; every candidate artifact must be checked
  and remain free of `get-task-allow` before distribution. This adds no TCC permission request.
- The bundle passes strict local code-signature structure verification.
- The installed process starts successfully and uses the expected bundle identifier,
  `com.desktopbuddy.app`.
- The product, executable, bundle display name, and installed filename consistently use
  `Desktop Buddy`; Spotlight metadata resolves the installed app by both display name and
  bundle identifier.
- The Release bundle contains the compiled `AppIcon.icns` generated from the project's
  standard macOS `AppIcon.appiconset`.
- A normal macOS termination clears the active-session marker.
- Relaunch from the installed location starts normally and does not enter unclean-exit
  recovery.

## Sleep and wake validation

On 2026-09-18, the installed Release build was put through a real overnight sleep and wake
cycle. Local unified logs recorded runtime sampling suspension at 23:06:43 and resumption at
10:01:09. After wake, the edge pet remained visible, could still move between screen edges,
and could open the status panel.

The validation also exposed an interaction inconsistency: clicking the edge pet always
requested an open operation, while the menu-bar pet toggled the panel. Both entry points now
use the same toggle behavior, so a second click on either pet closes the open panel.

## Distribution boundary

The current archive is signed ad hoc (`Sign to Run Locally`). It has no TeamIdentifier and
Gatekeeper correctly rejects it as a distributable application. It must not be sent to alpha
testers as if it were an authenticated build.

Release builds with `get-task-allow` removed cannot be attached to a debugger. Profiling that
requires debugger attachment must use a Debug build or an explicit local-only diagnostic
configuration; the entitlement must not be silently restored on a Release candidate.

External private-alpha distribution remains parked until an Apple Developer Program team and
a valid Developer ID Application identity are available. At that point the remaining checks
are Developer ID signing, notarization, stapling, and installation on a separate clean Mac.

## Entitlement-free Release installation

On 2026-09-20, the local Alpha installation was replaced with the archived Release candidate
built with `CODE_SIGN_INJECT_BASE_ENTITLEMENTS = NO`. Strict signature verification passed,
the installed app relaunched with bundle identifier `com.desktopbuddy.app`, and
`codesign -d --entitlements -` printed only the executable path—no entitlement dictionary and
no `com.apple.security.get-task-allow` entry. This verifies the installed local candidate as
well as the archive; it does not change the external-distribution boundary above.
