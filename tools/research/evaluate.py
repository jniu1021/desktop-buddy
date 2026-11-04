#!/usr/bin/env python3
"""Local shadow-policy replay. No network, dependencies, or real notifications."""
import argparse
import bisect
import json
import html
import math
import statistics
from pathlib import Path

VERSION = 'shadow-v1.1'


def decide(policy, sample, priority='ordinary'):
    if priority == 'urgent':
        return 'notify_now', 'urgent_override'
    if policy == 'A':
        return 'notify_now', 'static_default'
    if sample is None or sample['category'] in ('unknown', 'research_console') or sample.get('idleSeconds') is None:
        return 'delay', 'unknown_fallback'
    if sample.get('fullscreen') is True:
        return 'delay', 'fullscreen_geometry'
    if sample['idleSeconds'] > 45:
        return 'delay', 'inactive_not_assumed_available'
    if policy == 'C':
        if sample.get('switchCount', 0) >= 3:
            return 'delay', 'rapid_switching'
        if sample.get('stableSeconds', 0) < 10:
            return 'delay', 'transition_settling'
        if sample['category'] in ('development', 'terminal', 'writing', 'design', 'office') and sample.get('stableSeconds', 0) >= 60:
            return 'delay', 'sustained_work_heuristic'
    return 'notify_now', 'available_by_rule'


def infer_activity(sample):
    # App category is insufficient for semantic activity labels in this prototype.
    return 'unknown'


def load(path):
    events = []
    with open(path, encoding='utf-8') as handle:
        for number, line in enumerate(handle, 1):
            try:
                event = json.loads(line)
                if event.get('schema') != 1 or not math.isfinite(event['t']) or event['t'] < 0:
                    raise ValueError('invalid schema or time')
                if events and event['t'] < events[-1]['t']:
                    raise ValueError('timestamps must be nondecreasing')
                events.append(event)
            except (ValueError, TypeError, KeyError) as error:
                raise ValueError(f'{path}:{number}: {error}') from error
    if not events:
        raise ValueError('empty recording')
    return events


def evaluate(events):
    samples = [e['sample'] for e in events if e['kind'] == 'sample']
    times = [s['t'] for s in samples]
    labels = {e['candidateID']: e for e in events if e['kind'] == 'label'}
    end = events[-1]['t']
    rows = []
    for candidate in (e for e in events if e['kind'] == 'candidate'):
        start = candidate['t']
        index = bisect.bisect_right(times, start) - 1
        sample = samples[index] if index >= 0 and start - times[index] <= 5 else None
        label = labels.get(candidate['candidateID'])
        # Fixed policy deadline is independent of participant labels.
        deadline = start + (0 if candidate['priority'] == 'urgent' else 120)
        for policy in ('A', 'B', 'C'):
            initial, reason = decide(policy, sample, candidate['priority'])
            delivery = start if initial == 'notify_now' else None
            delivery_reason = reason if delivery is not None else None
            if delivery is None:
                for future in samples:
                    if future['t'] <= start or future['t'] > min(end, deadline):
                        continue
                    action, why = decide(policy, future, candidate['priority'])
                    if action == 'notify_now':
                        delivery = future['t']; delivery_reason = why; break
                if delivery is None and end >= deadline:
                    delivery = deadline; delivery_reason = 'deadline_override'
            rows.append(dict(candidate=candidate['candidateID'], policy=policy, t=start,
                initial=initial, reason=reason, delivery=delivery,
                noticeID=candidate.get('noticeID', 'unspecified_legacy'),
                noticeText=candidate.get('noticeText', 'Notice content was not recorded.'),
                followup=end - start,
                delay=None if delivery is None else delivery - start,
                deliveryReason=delivery_reason, label=label,
                activityPrediction=infer_activity(sample)))
    return rows, samples


def ratio(numerator, denominator):
    return None if denominator == 0 else numerator / denominator


def summarize(rows):
    report = {}
    for policy in ('A', 'B', 'C'):
        group = [r for r in rows if r['policy'] == policy]
        labeled = [r for r in group if r['label']]
        immediate = [r for r in labeled if r['initial'] == 'notify_now']
        useful = [r for r in labeled if r['label']['useful']]
        delays = sorted(r['delay'] for r in group if r['delay'] is not None)
        # An uncompleted observation is censored, not automatically a failure.
        observed_useful = [r for r in useful if r['delay'] is not None or r.get('followup', 0) >= r['label']['maxDelay']]
        missed = [r for r in observed_useful if r['delay'] is None or r['delay'] > r['label']['maxDelay']]
        report[policy] = dict(candidates=len(group), labeled=len(labeled),
            unwantedImmediateNumerator=sum(r['label']['preference'] != 'notify_now' for r in immediate),
            unwantedImmediateDenominator=len(immediate),
            unwantedImmediateRate=ratio(sum(r['label']['preference'] != 'notify_now' for r in immediate), len(immediate)),
            agreement=ratio(sum(r['initial'] == r['label']['preference'] for r in labeled), len(labeled)),
            usefulObserved=len(observed_useful), usefulCensored=len(useful) - len(observed_useful),
            missedUseful=len(missed), missedUsefulRate=ratio(len(missed), len(observed_useful)),
            delivered=len(delays), notDelivered=len(group) - len(delays),
            delayMedian=statistics.median(delays) if delays else None,
            delayP95=delays[max(0, math.ceil(len(delays) * .95) - 1)] if delays else None,
            deadlineOverrides=sum(r['deliveryReason'] == 'deadline_override' for r in group))
    return report


def render_html(report):
    def esc(value):
        return html.escape(str(value))
    def percent(value):
        return 'N/A' if value is None else f'{value * 100:.1f}%'
    summaries = []
    for policy, value in report['policies'].items():
        summaries.append('<tr>' + ''.join(f'<td>{esc(v)}</td>' for v in [
            policy, value['candidates'], value['labeled'],
            f"{percent(value['unwantedImmediateRate'])} ({value['unwantedImmediateNumerator']}/{value['unwantedImmediateDenominator']})",
            percent(value['agreement']),
            f"{percent(value['missedUsefulRate'])} ({value['missedUseful']}/{value['usefulObserved']})",
            value['usefulCensored'], value['delayMedian'], value['notDelivered'], value['deadlineOverrides']]) + '</tr>')
    details = []
    for row in report['rows']:
        label = row['label'] or {}
        details.append('<tr>' + ''.join(f'<td>{esc(v)}</td>' for v in [
            f"{row['t']:.1f}", row['policy'], row['noticeID'], row['initial'], row['reason'],
            'Not delivered' if row['delay'] is None else f"{row['delay']:.1f}",
            row['deliveryReason'] or 'Observation ended', label.get('preference', 'Unlabeled'),
            label.get('activity', 'Unlabeled')]) + '</tr>')
    return """<!doctype html><html lang="en"><meta charset="utf-8">
<title>Desktop Buddy — Shadow Policy Report</title>
<style>body{font:15px system-ui;margin:40px auto;padding:0 24px;max-width:1300px;color:#172334;background:#f7f9fc}h1{font-size:30px}h2{margin-top:32px}.note{background:#e7eef8;padding:18px;border-radius:12px}table{border-collapse:collapse;width:100%;background:white}th,td{padding:12px;text-align:left;border-bottom:1px solid #dde3ed;font-size:13px}.scroll{overflow:auto}th{background:#e9eef5}p{line-height:1.6}</style>
<h1>Desktop Buddy: Shadow Policy Report</h1>
<p class="note"><strong>Offline simulation, not actual notification delivery.</strong> This report describes decisions on a recorded trace. It does not establish improved user experience or generalized efficacy. N/A means no eligible denominator.</p>
<p>Policy version: """ + esc(report['policyVersion']) + ' · Source: ' + esc(report['source']) + ' · Samples: ' + str(report['samples']) + """</p>
<h2>Policy comparison</h2><p>A: static immediate policy. B: instantaneous context. C: context plus temporal history. All use an urgent override and a 120-second ordinary deadline. Unwanted-immediate rates use only labeled immediate deliveries. Agreement compares initial decisions with user preferences; this prototype does not automatically suppress candidates.</p>
<div class="scroll"><table><tr><th>Policy</th><th>Candidates</th><th>Labeled</th><th>Unwanted immediate</th><th>Decision agreement</th><th>Missed useful</th><th>Useful censored</th><th>Median delay (s)</th><th>Not delivered</th><th>Deadline overrides</th></tr>""" + ''.join(summaries) + """</table></div>
<h2>Candidate timeline</h2><p>Each candidate is evaluated under all three policies on the same trace. Reasons are heuristic rules, not calibrated confidence estimates. Labels describe the candidate time, not the later annotation time.</p>
<div class="scroll"><table><tr><th>Time (s)</th><th>Policy</th><th>Notice</th><th>Initial decision</th><th>Reason</th><th>Delay (s)</th><th>Delivery reason</th><th>User preference</th><th>User activity label</th></tr>""" + ''.join(details) + """</table></div>
<h2>Measurement limits</h2><p>Semantic activity recognition is not implemented. Browser identity does not establish video watching; idle input does not establish absence. Foreground console samples are treated conservatively. Polling may miss brief app switches. Delays are simulated; behavior may change under real notifications. Small self-study traces support feasibility debugging, not population-level claims.</p>
<p>Reports include participant labels. Store locally and delete when no longer needed. Automatic session retention does not delete exported reports.</p></html>"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('recording', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--html', type=Path, help='Optional English standalone report')
    args = parser.parse_args()
    events = load(args.recording)
    rows, samples = evaluate(events)
    end = events[-1]['t']
    for row in rows:
        row['followup'] = end - row['t']
    report = dict(policyVersion=VERSION, mode='offline_simulation_not_actual_delivery',
        source=args.recording.name, samples=len(samples), policies=summarize(rows), rows=rows,
        activityRecognition='Not implemented: semantic activities remain unknown. Labels retained for future evaluation.',
        sensingMSMedian=statistics.median(s['sensingMS'] for s in samples) if samples else None)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding='utf-8')
    if args.html:
        args.html.parent.mkdir(parents=True, exist_ok=True)
        args.html.write_text(render_html(report), encoding='utf-8')
    print('离线模拟结果（不是实际通知效果）；空值表示无可用分母或未完成观测。')
    for policy, values in report['policies'].items():
        print(policy, json.dumps(values, ensure_ascii=False))
    print('完整报告：', args.output)


if __name__ == '__main__':
    main()
