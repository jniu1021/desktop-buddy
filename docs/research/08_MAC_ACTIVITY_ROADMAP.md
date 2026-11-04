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

Introduce a separate screen-capture opt-in, explicit permission explanation, transient low-resolution frames, and a bounded inference path. Compare lightweight classification against metadata-only behavior before choosing YOLO. Evaluate capture overhead independently of inference overhead. Suspend capture when inactive; drop stale frames rather than queueing inference. Do not save screenshots by default.

## Stage 3: system-audio evidence

Capture computer playback, not microphone audio. Prefer local coarse sound classification, with bounded buffers and exclusion of the companion's own sound. No speech transcription in the first version. Speech and music are cues, not meeting/video ground truth. Quantify incremental utility and overhead before enabling ongoing sampling.

## Stage 4: feedback and evaluation

Add opt-in, infrequent feedback requests anchored to an explicit interval. Hide the predicted answer while collecting independent evaluation labels; allow other, uncertain, away and skip. Keep calibration sessions separate from held-out evaluation sessions. Compare metadata, metadata+screen, and metadata+screen+audio, reporting activity-duration errors, unknown coverage, passive-activity versus absence errors, and measured CPU/memory/energy overhead.

## GitHub workflow

Use a private repository. Commit working milestones after checks, then push explicitly during the development session. No recurring background automation is configured. Exclude raw research recordings, participant-derived result documents, generated reports, caches and credentials. Existing unrelated local Codex-integration edits remain outside these milestone commits.

## Verification boundaries

Stage 1 has build/unit-test validation. It still needs interactive usability checks and matched resource measurements. No new power or memory budget has been demonstrated, and no visual/audio model accuracy is claimed.
