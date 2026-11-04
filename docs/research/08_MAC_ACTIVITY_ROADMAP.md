# macOS Activity Awareness — Milestones

Updated: November 4, 2026. Final application-facing research materials will be in English; collaboration may be in Chinese.

## Stage 1: integrated self-report foundation

Implemented in the native menu-bar status panel:
- Explicit per-launch opt-in for a local activity diary.
- Ten-second metadata sampling, independent of the existing focus-preference toggle.
- Recorded intervals and today's totals, with unknown, feedback-UI and possibly-away categories separated from self-reported activities.
- Manual multiple-choice feedback for at most the final ten seconds of the most recent recorded interval.
- Sleep/session-inactive suspension, long-gap rejection, daily boundary splitting, seven-day retention pruning, and local clear action.
- Batched persistence approximately once per minute and on disable/stop/correction.

No screen or audio capture is enabled in this milestone. No raw application identifiers, window titles, screenshots, audio, or typed content are stored by this diary. Unknown time is not focus time; inactivity is not confirmed absence. Metadata does not populate semantic activities automatically. Existing research-console recordings are separate and are not imported.

## Stage 2: screen evidence

Implemented initial preview: separate per-launch opt-in with a system permission action; macOS 14+ single-window ScreenCaptureKit snapshots; maximum dimension 1280 pixels; local fast English Vision OCR; conservative code/meeting/video text-cue rules with unknown for insufficient/conflicting cues. Normal sampling attempts every 30 seconds, 120 seconds in Low Power Mode, skipped when the companion is frontmost or input inactivity exceeds 120 seconds. One request is allowed in flight; stale results after disable, suspension, or foreground-app changes are discarded. OCR runs in a utility-priority task. Images and text are not saved or uploaded; tentative evidence is memory-only and does not populate confirmed activity totals. No YOLO or trained activity classifier is included.

Limitations: selecting the largest normal visible window is not guaranteed to select the focused window; the window capture may include text outside the visible desktop region. Inactivity gating can miss passive reading/video. Fast English OCR does not establish Chinese-interface support. Simple cue rules can produce false positives. This milestone has compile/unit-test checks, but actual capture permission behavior, sustained memory/energy overhead and recognition accuracy remain unverified.

Further work:

Introduce a separate screen-capture opt-in, explicit permission explanation, transient low-resolution frames, and a bounded inference path. Compare lightweight classification against metadata-only behavior before choosing YOLO. Evaluate capture overhead independently of inference overhead. Suspend capture when inactive; drop stale frames rather than queueing inference. Do not save screenshots by default.

## Stage 3: system-audio evidence

Implemented initial preview: separate per-launch playback-analysis opt-in; explicit explanation that ScreenCaptureKit may require Screen Recording access; five-second audio bursts no more frequently than every 60 seconds (180 in Low Power Mode). The diary must be active. Uses 16 kHz mono PCM and the built-in Sound Analysis classifier, with coarse speech/music/other/unknown cues. No microphone output is registered; microphone capture is explicitly disabled on macOS 15+. The current process audio is excluded. No audio files, transcript or raw model labels are persisted. A tiny, low-rate screen configuration is used for the ScreenCaptureKit source, but only audio output is registered and consumed. This is not a claim of zero screen-capture infrastructure overhead.

A single burst is allowed in flight. Disable/suspend invalidates the result, cancels the task and requests stream stop during cleanup. Analyzer state is released after the burst. Missing samples mean unknown, not silence. Model scores are not activity probabilities. Audio preview does not change confirmed activity totals.

Verification: build/regression and four coarse-label tests. Actual playback capture, permission denial/revocation, audio-source changes, stop behavior, sustained resource usage and classification accuracy need on-device verification. Intermittent capture misses sounds between bursts. The model may be the dominant memory cost; no low-memory guarantee is established.

Further work:

Capture computer playback, not microphone audio. Prefer local coarse sound classification, with bounded buffers and exclusion of the companion's own sound. No speech transcription in the first version. Speech and music are cues, not meeting/video ground truth. Quantify incremental utility and overhead before enabling ongoing sampling.

## Stage 4: feedback and evaluation

Add opt-in, infrequent feedback requests anchored to an explicit interval. Hide the predicted answer while collecting independent evaluation labels; allow other, uncertain, away and skip. Keep calibration sessions separate from held-out evaluation sessions. Compare metadata, metadata+screen, and metadata+screen+audio, reporting activity-duration errors, unknown coverage, passive-activity versus absence errors, and measured CPU/memory/energy overhead.

## GitHub workflow

Use a private repository. Commit working milestones after checks, then push explicitly during the development session. No recurring background automation is configured. Exclude raw research recordings, participant-derived result documents, generated reports, caches and credentials. Existing unrelated local Codex-integration edits remain outside these milestone commits.

## Verification boundaries

Stage 1 has build/unit-test validation. It still needs interactive usability checks and matched resource measurements. No new power or memory budget has been demonstrated, and no visual/audio model accuracy is claimed.
