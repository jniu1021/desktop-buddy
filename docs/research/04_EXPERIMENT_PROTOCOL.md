# Pilot Experiment Protocol

**Version:** 0.2, October 19, 2026. **Analysis policy:** shadow-v1.1.

## Objective

Test the feasibility of comparing interruption policies on identical local context traces and user-labeled notification candidates. The first study is a single-user engineering pilot, not a controlled demonstration of improved real-world user experience.

## Conditions

- A: immediately recommend delivery for every scheduled candidate.
- B: delay under unknown/console context, input inactivity over 45 seconds, or observed geometric fullscreen; otherwise recommend immediate delivery.
- C: apply B, then delay for at least three observed app switches in the preceding 60 seconds, context stability below 10 seconds, or a recognized work category held for at least 60 seconds.

All conditions immediately process urgent candidates. Ordinary candidates are re-evaluated on subsequent samples and forced to simulated delivery after 120 seconds if the recorded observation extends that far. Candidate labels do not affect policy decisions. There is no automatic permanent suppression in this version. Exact preference agreement therefore exposes cases where participants want a notification suppressed.

## Notification semantics

Two fixed candidate types are stored in the recording:

1. `optional_break`: “You have been working for a while. Would you like to take a short break?”
2. `simulated_critical_battery`: “Simulated critical battery: your battery is nearly empty. Please connect power.”

The second is a hypothetical scenario, not a statement about actual battery state. Label its timing preference under that hypothetical condition. Analyze notice types separately when sample sizes permit; urgency and message content differ, so their effects cannot be separated in this pilot.

## Sessions

Use six planned scenarios: video watching, coding/debugging, browsing, idle/away, rapid switching, and ambiguous transitions. A planned scenario is not ground truth. Record what actually happened at each candidate.

First run two usability sessions, then record separate evaluation sessions after freezing thresholds. Aim for two 5-minute segments per scenario if feasible. Preselect candidate timing (e.g., 60 seconds after scheduling) and priority order. Do not schedule candidates only when an interruption seems convenient. Use a longer delay for idle and sustained-task scenarios. Switching back to the console changes context; retain and report this measurement effect.

## Procedure

1. Open Desktop Buddy and the research console. Read the local collection notice and explicitly enable the session.
2. Select the planned scenario and start recording.
3. Select a fixed candidate type, schedule it for a chosen delay, and return to the task. No real notification is displayed.
4. After the candidate time, return to annotate the actual activity, immediate/delay/suppress preference, usefulness, and maximum acceptable delay in seconds. If the moment cannot be recalled, skip the label; never guess to fill the dataset.
5. Save or skip the pending label before stopping. Continue recording at least 120 seconds after the final candidate if feasible.
6. Stop, inspect the JSONL, and run the evaluator. Record any protocol deviations.

## Analysis

Report candidate counts and labeled counts per policy. Unwanted-immediate rate uses labeled immediate recommendations as its denominator. Missed-useful rate counts useful candidates whose simulated delivery exceeds the participant's tolerance or remains undelivered after that tolerance has elapsed. If recording ends before an undelivered candidate's tolerance, count it as censored rather than a failure. Report median/P95 simulated delay, undelivered counts, and deadline overrides.

No semantic activity-recognition accuracy is claimed in this version. A browser or IDE category alone is insufficient to identify the user's activity. Keep participant activity labels for subsequent development. Function execution time is recorded as sensingMS; it is not end-to-end sensing latency, CPU utilization, or total process overhead. Resource measurements require a separate matched performance run.

## Interpretation and privacy

Offline recommendations cannot reproduce how actual notifications change behavior. Retrospective labels may have recall bias. Samples within a session are correlated. Do not treat each two-second sample as an independent participant. Report failures, ambiguous context, skipped labels, and short follow-up.

Data remains local. The console stores no screenshots, raw titles, URLs, or typed content. Raw app identifiers are used only in memory. It stores coarse categories and timing, which still reveal behavior. UUID session files older than seven days are cleaned when another session begins; exported reports are not automatically deleted. Delete raw data and reports when no longer needed. Additional participants require appropriate consent and a review of applicable institutional requirements before recruitment.
