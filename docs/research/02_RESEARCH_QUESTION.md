# Research Question and Scope

**Working title:** Desktop Buddy: Evaluating Lightweight Temporal Context for Proactive Interaction Timing

**Status:** Research proposal draft, October 19, 2026. The engineering prototype exists; participant evaluation and resource-overhead measurements are pending.

## Motivation

A desktop companion can remain available throughout a work session, but availability does not tell it when to speak. Frequent prompts can interrupt a task; indiscriminate suppression can hide useful information. Continuous screen understanding is one possible approach, but it introduces additional sensing, processing, and privacy costs.

This project investigates how far a deliberately limited set of local operating-system signals can support interruption decisions. The companion provides an interaction surface, while the research contribution being investigated is the decision process and its measurable limitations.

## Primary question

On identical notification opportunities, does short-term temporal context improve agreement with a user's stated interruption preferences compared with static rules and instantaneous context, without unacceptable notification delay or resource overhead?

## Hypotheses to test

- H1: Instantaneous context can reduce unwanted immediate recommendations relative to a static immediate policy in selected scenarios.
- H2: Temporal history provides additional information at activity transitions and during sustained work, beyond instantaneous context.
- H3: Conservative handling of ambiguity trades fewer immediate recommendations for longer delays or missed useful notifications; both sides must be reported.

These are hypotheses, not established findings. C may perform worse than B, and a useful pilot should expose that possibility.

## Scope and existing work

Desktop Buddy is an existing native macOS application with a menu-bar/edge companion, device monitoring, and heuristic focus suppression. The research console reuses its sensor source files without changing the application's normal behavior. Prior exploration of Sei Backseat informs the interest in event timing and sampling costs; the applications are not merged, and Backseat implementation code is not copied into the console.

The current research extension records coarse app categories, time since input, geometric fullscreen observations, observed app switching, and context duration. It supports consent-based local logging, candidate-specific labels, and deterministic offline policy comparison. It does not perform semantic video recognition, infer emotion, or use a cloud model. Activity labels are participant reports; automatic semantic activity predictions remain unknown.

## Research fit

HiLab describes research that turns everyday interactions into signals for context understanding and builds adaptive, personalized systems. This project explores a desktop instance of that broader approach. Invisibility Cloak offers inspiration for making privacy an explicit systems design requirement; its smartwatch-guided camera obfuscation task is distinct from this project's interruption-timing problem.

This is an applicant's interpretation of research fit, not a claim of endorsement. A focused literature review of interruptibility, task boundaries, notification management, and context-aware systems is still needed before asserting novelty.

References:
- HiLab research overview, publications, and FAQ: https://hilab.dev/
- Invisibility Cloak project page: https://hilab-open-source.github.io/InvisibilityCloak/

## Deliverable and limits

The three-day deliverable is a working feasibility prototype, a documented pilot protocol, replayable local data, and an English project proposal with honest implementation and evaluation boundaries. A single-user pilot cannot establish population-level effectiveness or support claims that the system understands arbitrary desktop activity.
