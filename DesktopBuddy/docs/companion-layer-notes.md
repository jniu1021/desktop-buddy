# Companion layer — design notes

**Status:** Design note for a **post-MVP feature**. This is **not an implementation order.**
**Recorded:** 2026-09-19
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
the current scope. The only currently permitted action from this note is the non-AI
break-offer step in §8, and only if the user asks for it explicitly.

## 1. The design, consolidated

The session loop, in order:

1. **Observe context** — application category, session length, and state transitions such as
   leaving full screen. (Already largely built: `WorkApplicationCategory`,
   `FocusActivityTracker`, `ForegroundFullscreenSensor`.)
2. **Offer an optional micro-interaction at a transition boundary** — a break offer such as
   "that was a long stretch — 60 seconds off screen?" The offer carries a real, immediate
   functional benefit for the user.
3. **Optional, never-required self-report** — the user may additionally tap a fixed mood
   category (plus an optional single keyword). Skipping is normal and is never followed up.
4. **End-of-day synthesis (the payoff, and the last thing built)** — either at day end or when
   the user chooses to write, AI organizes what was reported alongside what the machine
   observed, producing a diary and a sense of being accompanied.

### Why this shape is sound

- **Input labor is why journaling products fail.** Small taps replace writing paragraphs.
- **The tap has a functional payoff.** This is the key correction: recording alone has no
  immediate reward and no one repeats it. A break that actually helps means the user receives
  value even if they never engage with the emotional layer — so the feature earns its place in
  the menu bar on its own merits.
- **The pet's unique advantage** over a journaling app is that it already knows the shape of
  the day, so offers can be contextual rather than generic.
- **The emotional layer depends on one capability:** the pet initiating something *at a moment
  the user welcomes*. The break offer is the cheapest, least sensitive way to test that
  capability without collecting a single emotional record.

## 2. Non-negotiable design constraints

Decided before implementation. Requirements, not preferences. They are numbered so they can be
cited individually in review.

### C1 — Never infer emotional state

The product must not claim, guess, or imply how the user feels. Context determines **timing and
candidate options only**; the user supplies the state by choosing.

*Why:* application metadata cannot distinguish absorbed-and-happy from stuck-and-miserable —
both look like four hours in the same editor. So do not attempt the inference at all. Offer,
and let the user answer. This is what §4 already requires: use uncertainty, never invent
details, never diagnose.

### C2 — Never interrupt a running session

Offers may only fire on **state transitions** — leaving full screen, a long session ending,
returning from idle. There must be **no timer** and no mid-session prompt.

*Why:* the existing focus and full-screen suppression (§5, `FullscreenPresentationPolicy`)
exists precisely to prevent interruption during engaged work, and an offer that fires mid-flow
will hit the user's best moments. Interrupting flow is among the most reliably resented
behaviours in software.

> **Hazard to record explicitly.** C1 and C2 are separate problems and were deliberately
> split. C1 concerns *whether the app claims to know how you feel*; C2 concerns *when an offer
> appears*. A future change that moves the offer earlier "because we never infer anything"
> would satisfy C1 while reintroducing the interruption problem. Do not merge these two rules.

### C3 — Structured, minimal input

Fixed mood/status categories plus an optional single free-form keyword, exactly as specified in
`PRODUCT_DESIGN.md` §9. No open text field as the primary input. A small fixed vocabulary keeps
later synthesis honest instead of inviting over-interpretation.

### C4 — Ignored offers are signal

Track, locally: offers **shown**, **accepted**, and **ignored**. An ignored offer is data, not
a failure.

Two reasons:

1. **Validation.** Acceptance ratio is the measure of whether the pet's initiative is welcome
   at all.
2. **The diary would otherwise be systematically blind.** If reports only arise when a user
   pauses, then the person who works ten hours straight and declines every offer generates no
   emotional data — and those are exactly the days that matter most. The diary would read as
   permanently calm for the user who most needs noticing. "The pet offered four breaks today
   and you took one" is itself a meaningful signal, and is arguably more informative than any
   self-report.

This failure is invisible in testing: it does not error, it only shows up as a diary that
always sounds fine. It must be designed in from the start.

### C5 — Two tracks, never merged into causal claims

The diary presents two parallel sections:

1. **What you noted** — user reports.
2. **What your machine did** — sessions, durations, device notices.

Generation must not assert, imply, or hint at a causal link between application usage and
reported mood. Phrasings such as "X makes you tired", "you seem stressed when using Y", or
"coding drains you" are forbidden.

*Why:* correlating work patterns with reported mood is an inference about a person's psychology
derived from behavioural monitoring. §4 forbids diagnosing and inventing details; §10's "useful
with every sensitive permission denied" posture depends on not doing this.

### C6 — Never name applications in a mood context

The status panel already promises the user, in the UI:

> "Stored only on this Mac. These counters contain no application names, window titles, typed
> content, or timeline, and are never uploaded."

`ForegroundActivitySnapshot.bundleIdentifier` is currently held **in memory only** and is not
persisted anywhere on disk. A diary that names applications, or correlates named applications
with mood, either breaks that promise or requires renegotiating it deliberately. Do not break
it by accident.

### C7 — Limit what application category is allowed to do

Category may:

- set **timing and thresholds** (different kinds of work have different natural session
  lengths);

Category may also select **which offer candidates** appear, but only if they are framed as
options and it is acknowledged internally that this is a guess about the person, not knowledge
of them.

Category must **never** drive emotional interpretation. "Development work means the user needs
X kind of break" is a stereotype about the work, not knowledge about the individual, and some
users will find it presumptuous.

### C8 — Volume gate

Below a minimum number of reports, the pet must say something like "not much to remember today"
rather than generating a narrative. A language model will always produce a confident,
warm-sounding diary from sparse noise; that is a **fabricated emotional history**. Under-claim
is required. When in doubt, report fewer things and hedge more.

### C9 — Everything is labeled as reported, not inferred

The diary is a summary of what the user said plus what the machine observed. §9 already
requires inferred tone to be "explicitly labeled as inferred"; extend that rule to the whole
artifact. Tone follows §4: acknowledges work without inventing details.

### C10 — Deletion and encryption are prerequisites, not follow-ups

Emotional self-reports are the most sensitive data class in this product. Once persisted and
associated with activity, the deferred §9 encryption and deletion controls stop being deferrable
and become table stakes.

On-device / local-model processing is strongly preferred. A cloud path would upload mood plus
work patterns and would undo the local-first posture protected by §10. **Do not ship this layer
before the privacy work lands.**

### C11 — No new TCC permissions

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

- **Offers are ordinary notices.** Route them through `NoticeEligibility` +
  `PendingNoticeStore` so the existing relevance/confidence scoring, per-mode cooldowns, and
  suppression all apply. Session length is a natural input to a relevance score. Do not create
  a second prompt channel.
- **Persistence** goes behind a protocol in `Core/Protocols` with a macOS implementation, per
  the existing repository pattern (`PreferencesStoring`, `AlphaMetricsPersisting`,
  `SessionLifecyclePersisting`).
- **Keep `Core` platform-independent:** no `AppKit`, `Combine`, or `SwiftUI` imports in `Core`.
  State stores needing Apple frameworks belong in `App/`.
- **Do not invent new surfaces.** Map any mood capture onto existing presentation states (§8).
  New animation states require an explicit decision first.
- **Instrument locally** using the existing alpha-metrics pattern — local only, no network, no
  analytics SDK. This is required for §8.

## 6. Acceptance criteria (for whenever this is built)

- No inference of emotional state appears in any user-facing text.
- No `Timer` or scheduled trigger exists for offers; they fire only on state transitions.
- Offers are suppressed during focus and full screen, consistent with §5.
- Offers shown / accepted / ignored are all recorded locally.
- Generated diaries contain **no** causal usage↔mood statements and **no** application names.
  Test with fixtures that do contain app names and mood reports, and assert their absence.
- Below-threshold days take the "not much to remember" path, not the generated-narrative path.
- All persisted mood data is covered by the encryption and deletion controls.
- No new TCC permission is requested.

## 7. Two questions that must be measured separately

These are distinct and must not be bundled, or the results cannot be interpreted.

| Question | Metric | Why separate |
| --- | --- | --- |
| **Is the pet's initiative welcome?** | offers accepted ÷ offers shown | Measures whether an unprompted offer feels helpful or annoying |
| **Will anyone volunteer how they feel?** | mood taps **without** an offer, per day | Measures intrinsic willingness to self-report, not agreeableness to a prompt |

If mood data arises *only* after a break offer, the second question is contaminated by the
first: you cannot tell whether the user wanted to record a feeling or was simply being
agreeable to something that just helped them. Keep a quiet, always-available, never-solicited
mood tap so the second number exists independently.

## 8. The one thing that may be done now: the non-AI step

Requires **no AI, no cloud, no new permissions, no encryption work**:

1. Add the break offer, triggered only on a state transition (for example leaving full screen,
   or a session exceeding a conservative length threshold).
2. Route it through `NoticeEligibility` as an ordinary notice, so cooldowns and suppression
   apply.
3. The offer performs a real micro-interaction (breathe, stretch, 60 seconds off screen).
4. After it, optionally and without insistence, allow a single fixed mood category plus an
   optional keyword.
5. Keep a separate always-available mood tap that is never solicited.
6. Record offers shown / accepted / ignored and mood distribution locally.
7. Show a plain, non-AI daily list.

Run it for roughly two weeks. Decision rules:

- **Offers mostly ignored** → the pet's initiative is not welcome. Stop before building the
  emotional layer.
- **Unprompted mood taps near zero over two weeks** → people do not want to record feelings;
  the AI diary would have no input. Do not build it.
- **Both show engagement** → proceed to design AI synthesis under the constraints above.

### Limits of this test — state them honestly

A two-week self-test can **kill** the idea, or **justify building a prototype**. It cannot
validate demand. The developer is not a representative sample. Validating demand requires
roughly 5–10 external users running the same non-AI step. Do not treat a positive self-test as
market evidence.
