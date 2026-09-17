# Fan control feasibility spike — 2026-09-15

Fan control is a user-requested addition outside the approved private-alpha MVP in
`PRODUCT_DESIGN.md`. It must remain an optional macOS adapter, not a new dependency
for battery, memory, Codex, or pet presentation. The app must be useful when fan
control is unsupported or declined.

## Read-only observation on this Mac

- Hardware: MacBook Pro, Apple M5 Pro, model `Mac17,8`; macOS 26.6.2.
- The SMC reports two fans, both currently under system automatic control.
- Fan 0: approximately 1350–5349 RPM; observed around 1345 RPM.
- Fan 1: approximately 1350–5777 RPM; observed around 1454 RPM.
- The readable mode key is `F%dmd`; `Ftst` was absent.
- `F0ID` and `F1ID` were absent. Fan index 0/1 cannot yet be labeled left/right
  without a separate physical-direction validation.

Observation used the unprivileged, read-only `fanpro fans` command from the
MIT-licensed [fanpro source](https://github.com/omar16100/fanpro), built only in
a temporary directory. No daemon was installed; `smc probe`, `smc hold`, and
every fan-writing command were **not** run. Its upstream support claims should
not be mistaken for validation of our own adapter on this model.

## Safety and architecture gate before any manual write

1. A macOS read adapter must report each fan's actual RPM, hardware bounds,
   target, mode, and unknown/unavailable values honestly. No left/right labels
   until verified.
2. A separate, signed privileged helper must be the only owner of SMC writes.
   The ordinary app sends bounded requests through an authenticated IPC path.
   No arbitrary key, shell command, executable path, or RPM is accepted over IPC.
3. System automatic mode is the default and must remain available at all times.
   Manual control is opt-in and may not slow a fan below a recent firmware-owned
   reference. A hardware minimum is **not** a thermal safety floor.
4. The helper must monitor fresh thermal data, hardware readback, ownership,
   heartbeat, sleep/wake, and competing fan tools. If any check fails, it must
   return **both** fans to firmware automatic mode and confirm that release.
5. A watchdog must handle app crash/disconnect and helper failure. A release
   that cannot be confirmed is a fault requiring explicit user-visible warning,
   not a claim that automatic mode succeeded.
6. Only after a controlled hardware validation on `Mac17,8` should the UI offer
   two independent manual sliders and an automatic choice. Unknown/unverified
   models and older macOS releases stay read-only until separately tested.

The caution is concrete: [fanpro's measured study](https://github.com/omar16100/fanpro)
reports that firmware did not override a manually held fan on one Apple Silicon
machine. This is not proof that every Mac behaves identically, but it makes an
unmonitored low-speed slider unacceptable. Apple documents [system power modes](https://support.apple.com/en-us/101613)
and automatic thermal fan behavior, not a public per-fan slider API.

## 2026-09-16 read-only adapter milestone

`SystemFanSensor` now reads `FNum` and each fan's actual RPM, bounds, target, and
mode directly through AppleSMC from the ordinary app. It issues only key-info
and read-bytes commands. `FanSensing` is the platform boundary. A dedicated
read-only Fans page refreshes while open and displays unknown values as
unavailable. An on-device XCTest passed on this `Mac17,8` and reported two fans.

`FanControlPolicy` remains a tested record of the safety conditions that any
future write-capable implementation would have to satisfy. The unused
`FanControlling` protocol was removed so the current product does not expose a
misleading write boundary without an approved backend. The UI remains
read-only, does not claim fan-speed control, and provides no manual sliders.
