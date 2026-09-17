# DesktopBuddy — Direction Update

**Status:** Task-level priority update. `PRODUCT_DESIGN.md` remains the approved product
baseline and is authoritative for scope. This document changes *sequencing and emphasis
only*. If this file and the design doc conflict on scope, the design doc wins.
**Date:** 2026-09-16
**Applies to:** the implementation agent working in this repo.

## 0. Read first

- `PRODUCT_DESIGN.md` — especially §6 (memory semantics), §8 (state model), §12 (alpha
  scope), §13 (exclusions), §17 (milestones). Do not re-derive product scope.
- `DesktopBuddy/docs/fan-control-feasibility.md` — a **negative result**. Fan write
  access is deliberately parked. Do not "finish" it.

## 1. Guiding principle

**Ship a product that has standalone value with no AI present.** The AI-free base mode
(§7) is the strategy, not a fallback. The current phase exists to prove that the local
core is worth keeping installed on its own.

Do **not** start diary, encryption, conversational, emotional-summary, or hosted-AI work
in this phase. That design is intentionally not yet fixed; leave it undefined rather than
guessing at it.

## 2. Verified current state (do not rediscover this)

Build and tests are green:
`xcodebuild -project DesktopBuddy.xcodeproj -scheme DesktopBuddy -destination 'platform=macOS' -derivedDataPath .derivedData test`
→ `** TEST SUCCEEDED **`, 61 test functions in `Tests/CoreTests`.

**Real and working — build on these, don't rewrite:**
- Sensors: battery (`IOKit.ps`), memory (`host_statistics64`, non-cache occupancy as §6
  specifies), memory pressure (`DispatchSourceMemoryPressure`), swap (`sysctl vm.swapusage`),
  read-only fan SMC.
- Codex adapter (`Platform/macOS/CodexIntegration/CodexAppServerAllowanceSensor.swift`):
  real `codex app-server` JSON-RPC, `initialize` → `initialized` → `account/rateLimits/read`,
  8 s timeout, no credential access.
- Menu-bar pet (animated), status panel (live data), settings persistence (11 settings),
  edge window transparency, edge selection, multi-display placement, full-screen retreat,
  notice dedup (by kind, cap 3), accessibility labels. **Zero TCC permission prompts** —
  this is a real differentiator; protect it.

**Known gaps and defects (the work):**
1. `Core/DecisionEngine/NoticeEligibility.swift` is **dead code** — only its own tests and
   a UI string reference it. `AppCoordinator.handle` (`App/AppCoordinator.swift:149-163`)
   never calls it, so Quiet/Balanced/Lively behave identically.
2. Notice expiry is **never scheduled**: `expiresAt` is set but `expire()` runs only on
   enqueue and popover-open. No timer exists anywhere in `App/` or `Features/`.
3. Presentation states: §8 specifies seven (`MENU_IDLE, EMERGING, EDGE_IDLE, RETREATING,
   FOCUS_HIDDEN, DEVICE_NOTICE, SPEAKING`). `FOCUS_HIDDEN` and `SPEAKING` have no pose,
   frames, or driver at all. The sprite has 4 frames that differ only in 3 ear rows.
4. `ForegroundFullscreenSensor.swift:34` tests `displays.contains(where:)` across **all**
   screens, so a full-screen window on *any* display suppresses the pet globally.
5. Manual summon cannot override suppression (`EdgePetWindowController.swift:168`).
6. Full-screen state is only re-evaluated on app-activate/space-change, so it goes stale.
7. `BatteryState.isOnACPower` is captured but never used for polling backoff; only
   `ProcessInfo.isLowPowerModeEnabled` is. The 10 s memory timer is unthrottled.
8. Focus classification is a hardcoded allowlist of 4 bundle IDs plus a `com.jetbrains.`
   prefix (`Core/DecisionEngine/FocusActivityTracker.swift:4-15`).
9. `Core` imports `Combine` in three files (`BuddyStateStore.swift:1`,
   `FocusActivityStore.swift:1`, `DeviceNoticeEngine.swift:1`) — not platform-independent.
10. Zero `OSLog` usage despite §11 naming it. No crash handler. Built app is ad-hoc signed,
    `TeamIdentifier=not set`.
11. One force unwrap in non-test code: `SystemForegroundActivitySensor.swift:7`.
12. Codex adapter sends no `"jsonrpc":"2.0"` field and does no server version/capability
    detection. Its timeout is best-effort: SIGTERM only, no SIGKILL escalation, no
    `waitUntilExit`, and the reader is a blocking `read` with no `select`/poll, so a child
    that ignores SIGTERM hangs the task indefinitely.
13. Memory parity with Activity Monitor is asserted in the code comment but **untested** —
    the only test checks `used > 0 && used <= total`. Subtracting all of
    `external_page_count` may diverge from Activity Monitor on mapped executables.
14. `FanControlling` is a dead protocol with zero conformers and is absent from
    `DependencyContainer`.
15. Repo has **zero git commits**; everything is unversioned and `default.profraw` is not
    ignored.

## 3. Priority work, in order

### P0 — makes the phase's claim true

**P0.1 Wire the eligibility rules.** Call `NoticeEligibility.evaluate` from
`AppCoordinator.handle`, track `lastOrdinaryNoticeAt`, and honour the per-mode cooldowns
(60/45/20 min). *Done when:* Quiet, Balanced, and Lively produce measurably different
notice frequency for the same event stream, and a coordinator-level test proves it.

**P0.2 Complete the presentation-state contract.** Introduce a `PetPresentation` state
(even as an enum with a single consumer) that drives the menu-bar and edge renderers, and
make all seven §8 states reachable and driven by the engine. **Placeholder rendering is
explicitly acceptable and preferred** — a static frame per missing state is enough.
*Do not invest in art assets.* *Done when:* every §8 state can be entered and produces a
distinct, intentional rendering path, and the art can later be replaced without touching
the decision engine.

**P0.3 Schedule notice expiry.** Expire notices while the panel is closed, and surface the
remaining time in the panel. *Done when:* a notice enqueued with a 30-minute TTL is gone
without the panel ever being opened, proven by test.

**P0.4 Add local-only instrumentation.** Count, on-device only: notices shown, dismissed,
and acted on; metric glances; session length. **No network, no upload, no analytics SDK.**
*Done when:* the alpha can answer "did the user look, did they act, did they keep it
running" from local data alone.

### P1 — correctness and the differentiator

**P1.1 Define the differentiator numerically.** §4 and §6 require "a relevant event exists"
and "confidence is sufficient", but neither is defined anywhere. Write the definition into
`PRODUCT_DESIGN.md` and implement it. Restraint is the product's stated differentiator; it
is currently unspecified, not merely unimplemented.

**P1.2 Scope full-screen suppression to the pet's screen**, so a full-screen window on a
different display does not hide a pet the user is working next to. Fix the
`displays.contains(where:)` test to consider the display the pet occupies.

**P1.3 Let manual summon override suppression.** An explicit user request to show the pet
must win over full-screen and focus suppression.

**P1.4 Re-evaluate full-screen state on a slow cadence** rather than only on
app-activate/space-change, so the pet cannot stay hidden after a full-screen app exits.

**P1.5 Use battery state for backoff** (`isOnACPower`) and throttle the 10 s memory timer
under Low Power Mode, per the §18 risk mitigation.

**P1.6 Broaden focus classification** beyond the hardcoded 4-bundle-ID allowlist, or make
the list user-editable.

### P2 — hardening and hygiene

- Codex adapter: add `"jsonrpc":"2.0"`, add capability/version detection, escalate to
  SIGKILL after SIGTERM, add an outer timeout, and cancel the `asyncAfter` stopper on the
  success path.
- Fix the force unwrap at `SystemForegroundActivitySensor.swift:7`.
- Adopt `OSLog` for local diagnostics (§11).
- Add an Activity Monitor parity test for the memory metric, or document the known
  divergence explicitly.
- Remove `Combine` from `Core`, or record a decision that Core is Apple-only.
- Resolve the fan subsystem: delete the dead `FanControlling` protocol, **or** implement it
  behind `FanControlPolicy`'s safety gate (helper verification + fresh temperature). Do not
  enable any SMC write path without that gate.
- Make the initial git commit and ignore `default.profraw`.
- Decide the hit-testing tolerance at `EdgePetView.swift:78-85` (currently a ~2 pt halo on
  transparent gaps contradicts §5's "transparent pixels pass clicks through"). Either make
  it strict or document it as intentional.

## 4. Guardrails — do not do these

- **Do not add TCC permission prompts.** The zero-permission property is a genuine
  competitive advantage. No Accessibility, no Screen Recording, no new usage descriptions.
- **Do not add network calls or uploaded telemetry.** Local counters only.
- **Do not add sensors beyond §6**, and do not add temperature monitoring (§13).
- **Do not build a fan write path or a privileged helper.**
- **Do not add diary, encryption, AI, conversation, or emotional-summary features** in
  this phase.
- **Do not grow the animation list and do not commission or draw art assets yet.** The
  art investment is deferred on purpose until the core is proven. Contracts and state
  vocabulary are *not* deferred — those are code, and they are what P0.2 covers.
- **Do not keep `Core` free of AppKit at the cost of architecture** — but do not make the
  portability problem worse either.

## 5. Engineering standards already established in this repo — keep them

- Every platform capability sits behind a protocol in `Core/Protocols` and is injected in
  `App/DependencyContainer.swift`. No fakes, mocks, or no-ops in production paths.
- Policies are pure, testable types with XCTest coverage. This is done well; continue it.
- Sensor failure returns an honest `.unavailable`. Never fabricate or default a reading.
- No `TODO`/`FIXME`/`fatalError` markers (the repo currently has none — keep it that way).
- No force unwraps in non-test code.

## 6. Verification for every change

- The full test command in §2 must stay green.
- New decision/policy logic requires new tests; prefer testing the policy type rather than
  the view.
- If a change touches the interaction modes, notice queue, or presentation states, state
  explicitly in your summary which §8 state or §4 rule it affects.
