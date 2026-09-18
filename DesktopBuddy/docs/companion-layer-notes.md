# Companion layer — design notes

**Status:** Design note for a **post-MVP feature**. This is **not an implementation order.**
**Recorded:** 2026-09-18
**Relationship to `PRODUCT_DESIGN.md`:** `PRODUCT_DESIGN.md` remains the authoritative scope
baseline. Its §13 explicitly excludes both *conversational emotional-support AI* and
*automatic AI diary summarization* from the MVP. This note exists so the direction is not
lost, and so that if this layer is ever built, it is built under the constraints below.

---

## 0. Read this before doing anything

**Do not implement this layer now.** It is out of private-alpha and public-MVP scope by §13.

Building it now would:

- expand scope past the approved baseline;
- invert the agreed sequencing (the current phase is the AI-free core, §7);
- require the deferred privacy architecture (§9 encryption/deletion) before the product has
  validated that anyone wants the feature at all.

**If you are the implementation agent:** your task list is in `docs/direction-update.md`.
This document changes nothing about it. Do **not** add mood, diary, prompt, or AI features to
the current scope. The only currently permitted action from this note is the validation test
in §7, and only if the user asks for it explicitly.

## 1. The idea being kept

- Accumulate small emotional self-reports gradually through the day.
- Combine them with context the pet already has (focus sessions, session length, device
  conditions).
- Let AI synthesize the result into a daily diary.
- Goal: a feeling of companionship.

**Why the mechanism is sound.** Input labor is the reason journaling products fail; this
removes it. And the pet has an advantage no journaling app has: it already knows the shape of
the day, so it can prompt and reflect *contextually* rather than generically. AI is a
legitimate choice here — turning scattered points into a narrative is what language models
are good at and what rules cannot do (`PRODUCT_DESIGN.md` §7).

The mechanism is kept. What follows are the two places the original idea would have broken
the product.

## 2. Non-negotiable design constraints

These were decided before implementation. Treat them as requirements, not preferences.

### C1. Pull, never push

The pet must **not** proactively ask "how do you feel?". It is *available to be told*; it does
not solicit. No mood prompt in the scheduler.

*Why:* the product's differentiator is restraint (§1 "silence is an intentional action"; §4
modes are eligibility ceilings, not schedules). A recurring "how do you feel?" is pull-based
interruption on a timer. It creates a structural obligation loop even if the copy never
guilt-trips, and it contradicts §4's "never guilt-trips the user for dismissal, silence,
absence, or disabling features". The feature's success metric (answer the pings) also points
opposite to the product promise (do not demand attention).

*Consequence:* if a future variant ever does prompt, it must be an **ordinary notice routed
through `NoticeEligibility`** so cooldowns and focus suppression apply. Never a separate
prompt channel.

### C2. Structured, minimal input

Fixed mood/status categories plus an optional single free-form keyword — exactly what
`PRODUCT_DESIGN.md` §9 already specifies. No open text field as the primary input. A small
fixed vocabulary keeps synthesis honest instead of inviting over-interpretation.

### C3. Two tracks stay separate; the AI must never merge them

The diary presents two parallel sections:

1. **What you noted** — user reports.
2. **What your machine did** — focus sessions, session length, device notices.

Generation must not assert, imply, or hint at a causal link between application usage and
reported mood. Phrasings such as "X makes you tired", "you seem stressed when using Y", or
"coding drains you" are forbidden.

*Why:* correlating work patterns with reported mood is an inference about a person's
psychology derived from behavioral monitoring. §4 forbids diagnosing and forbids inventing
details; §10's "useful with every sensitive permission denied" posture depends on not doing
this.

### C4. Never name applications in a mood context

The status panel already promises the user, in the UI:

> "Stored only on this Mac. These counters contain no application names, window titles, typed
> content, or timeline, and are never uploaded."

`ForegroundActivitySnapshot.bundleIdentifier` is currently held **in memory only** and is not
persisted anywhere on disk. A diary that names applications, or correlates named applications
with mood, either breaks that promise or requires renegotiating it deliberately. Do not break
it by accident.

### C5. Volume gate

Below a minimum number of self-reports, the pet must say something like "not much to remember
today" rather than generating a narrative. A language model will always produce a confident,
warm-sounding diary from sparse noise; that is a **fabricated emotional history**. Under-claim
is required. When in doubt, report fewer things and hedge more.

### C6. Everything is labeled as reported, not inferred

The diary is a summary of what the user said plus what the machine observed. §9 already
requires inferred tone to be "explicitly labeled as inferred"; extend that rule to the whole
artifact. Tone follows §4: uses uncertainty when interpreting behavior, acknowledges work
without inventing details.

### C7. Deletion and encryption are prerequisites, not follow-ups

Emotional self-reports are the most sensitive data class in this product. Once persisted and
associated with activity, the deferred §9 encryption and deletion controls stop being deferrable
and become table stakes.

On-device / local-model processing is strongly preferred. A cloud path would upload mood plus
work patterns and would undo the local-first posture protected by §10. **Do not ship this layer
before the privacy work lands.**

### C8. No new TCC permissions

The zero-permission property is a genuine competitive advantage. This feature must not require
Accessibility, Screen Recording, input monitoring, or any new usage-description key.

## 3. Product framing: the diary is supporting cast

Companionship is **being known**, not reading a document. A diary is read once; it is a content
artifact. Its real contribution is *evidence that something was paying attention* — which
matters, but makes it supporting cast.

The primary mechanism of the companion feeling is small, low-cost **callbacks that demonstrate
continuity** ("yesterday you stopped early"). Design implication: prioritize the callback loop
over the diary artifact. If effort is limited, build callbacks first.

## 4. Explicitly out of scope for this layer

- Conversational emotional support or chat (§13)
- Diagnosis, or claims about stress, mood disorders, or attention (§4, §13)
- Any claim of feelings, needs, suffering, or emotional dependence (§1 non-goals)
- Cloud/remote processing of mood data
- Copy that induces guilt about dismissal, absence, or disabling features
- Inferring medical or psychological facts

## 5. Architectural fit — reuse what exists

- **Persistence:** store self-reports behind a protocol in `Core/Protocols`, with a macOS
  implementation behind it, following the existing repository pattern
  (`PreferencesStoring`, `AlphaMetricsPersisting`, `SessionLifecyclePersisting`).
- **Keep `Core` platform-independent:** no `AppKit`, `Combine`, or `SwiftUI` imports in `Core`.
  State stores that need Apple frameworks belong in `App/`.
- **Do not invent new surfaces.** Map any mood capture onto existing presentation states (§8).
  Adding new animation states requires an explicit decision first.
- **Instrument the feature locally** using the existing alpha-metrics pattern — local only, no
  network, no analytics SDK. This is required to answer the validation question in §7.
- **Route any prompt through `NoticeEligibility` + `PendingNoticeStore`** so the existing
  cooldown and suppression machinery applies.

## 6. Acceptance criteria (for whenever this is built)

- No proactive mood prompt exists in the scheduler.
- Generated diaries contain **no** causal usage↔mood statements and **no** application names.
  Test with fixtures that do contain app names and mood reports, and assert their absence.
- Below-threshold days take the "not much to remember" path, not the generated-narrative path.
- All persisted mood data is covered by the encryption and deletion controls.
- No new TCC permission is requested.

## 7. The one thing that may be done now: the validation test

The load-bearing question is **"will anyone tell the pet how they feel?"** It cannot be
answered by building the AI version first, and it is answerable with a fraction of the work.

Cheapest version, requiring **no AI and no new privacy architecture**:

1. Add a manual mood-tap path (fixed categories + optional single keyword), stored locally.
2. Leave the existing context track unchanged.
3. Show a plain, non-AI daily list of what was noted.
4. Use it for roughly two weeks and read the existing local counters.

Decision rule:

- **Meaningful manual use appears** → the companion premise has legs. Proceed to design AI
  synthesis under the constraints above.
- **Almost nothing is recorded** → the prompts, synthesis, and encryption work would have been
  wasted effort. Do not build them.

This is the same sequencing that worked for the AI-free core: validate the premise before
building the feature that depends on it.
