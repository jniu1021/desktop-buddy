# Private-alpha local installation check

**Checked:** 2026-09-17
**Scope:** Local developer-machine installation only

DesktopBuddy `0.1` was archived in Release configuration, copied to
`~/Applications/Desktop Buddy Alpha.app`, and launched from that installed location.

## Verified

- Release archive builds successfully for `arm64` only.
- The app targets macOS 13 or later and runs as a menu-bar agent (`LSUIElement`).
- The application category is `public.app-category.utilities`.
- Hardened Runtime is enabled.
- Release entitlements are empty; the installed build adds no TCC permission request.
- The bundle passes strict local code-signature structure verification.
- The installed process starts successfully and uses the expected bundle identifier,
  `com.desktopbuddy.app`.
- A normal macOS termination clears the active-session marker.
- Relaunch from the installed location starts normally and does not enter unclean-exit
  recovery.

## Distribution boundary

The current archive is signed ad hoc (`Sign to Run Locally`). It has no TeamIdentifier and
Gatekeeper correctly rejects it as a distributable application. It must not be sent to alpha
testers as if it were an authenticated build.

External private-alpha distribution remains parked until an Apple Developer Program team and
a valid Developer ID Application identity are available. At that point the remaining checks
are Developer ID signing, notarization, stapling, and installation on a separate clean Mac.
