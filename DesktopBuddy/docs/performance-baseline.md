# DesktopBuddy private-alpha performance baseline

**Recorded:** 2026-09-17
**Build:** Debug, Apple Silicon, macOS 26.6.2
**Scenario:** Existing local preferences, app left idle with no panel interaction for 30 seconds.

This is a local engineering baseline, not product telemetry. DesktopBuddy does not collect,
persist, or upload these measurements at runtime. The Instruments trace was written to a
temporary directory and is not part of the repository.

## Result

The Activity Monitor Instruments template recorded one 30.3-second steady-state interval:

| Metric | Observation |
| --- | --- |
| CPU time delta | approximately 0.25 seconds, or 0.83% of one core on average |
| Idle wake-up delta | 190, or approximately 6.3 per second |
| Real memory | approximately 84.2–84.3 MiB, with no upward trend |
| Disk writes | 0 bytes during the measured interval |

The existing polling policy remained enabled during the recording. Device refresh runs every
60 seconds on external power, every 90 seconds on battery, and every 120 seconds in Low Power
Mode. Memory sampling runs every 10, 20, or 30 seconds respectively.

No runtime change is justified by this short baseline. Longer sessions and the minimum
supported 8 GB Apple Silicon hardware still need validation before private-alpha release.

## Same-machine regression gates

For an equivalent idle Debug build on this machine, investigate before release if any of the
following occur:

- average CPU exceeds 2% of one core over a 30-second idle interval;
- real memory grows by more than 5 MiB during the interval;
- idle wake-ups exceed 10 per second;
- steady-state disk writes appear without an explicit user action.

These are regression gates relative to this measurement, not universal performance promises.
Release profiling must also cover battery and Low Power Mode, an open status panel, active
Codex polling, sleep/wake, and a multi-hour idle session.

## Reproduction

1. Build and launch the Debug app.
2. Leave the status panel closed and do not interact with the pet.
3. Find the DesktopBuddy process identifier.
4. Record it for 30 seconds with Xcode Instruments' `Activity Monitor` template.
5. Compare the first and last process-ledger rows rather than treating lifetime totals as
   interval totals.

Example recording command:

```sh
xcrun xctrace record \
  --template 'Activity Monitor' \
  --attach <DesktopBuddy-PID> \
  --time-limit 30s \
  --output /tmp/DesktopBuddy-Activity.trace
```
