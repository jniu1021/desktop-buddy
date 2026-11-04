#!/usr/bin/env python3
"""Summarize an explicitly exported native activity diary. Local processing only."""
import argparse
from collections import Counter, defaultdict
from datetime import datetime
import json
import math
from pathlib import Path

VALID_ACTIVITIES = {'coding', 'reading', 'video', 'meeting', 'chatting', 'gaming', 'other', 'away'}


def summarize(payload):
    if payload.get('schema') != 1:
        raise ValueError('Unsupported diary schema')
    totals = defaultdict(float)
    sources = defaultdict(float)
    previous_end = None
    for interval in payload['intervals']:
        start, end = (datetime.fromisoformat(interval[key].replace('Z', '+00:00')) for key in ('start', 'end'))
        seconds = (end - start).total_seconds()
        if not math.isfinite(seconds) or seconds < 0 or (previous_end is not None and start < previous_end):
            raise ValueError('Negative or overlapping intervals')
        previous_end = end
        totals[interval['activity']] += seconds
        sources[interval['source']] += seconds
    answers = [r for r in payload['feedback'] if r.get('answer') in VALID_ACTIVITIES]
    labeled = len(answers)
    known_predictions = [r for r in answers if r['prediction'] != 'unknown']
    correct = sum(r['prediction'] == r['answer'] for r in answers)
    confusion = Counter((r['answer'], r['prediction']) for r in answers)
    return dict(intervalSeconds=dict(totals), sourceSeconds=dict(sources),
                feedbackTotal=len(payload['feedback']), evaluatedLabels=labeled,
                excludedUncertainLabels=len(payload['feedback']) - labeled,
                accuracyIncludingUnknown=None if not labeled else correct / labeled,
                predictionCoverage=None if not labeled else len(known_predictions) / labeled,
                conditionalAccuracy=None if not known_predictions else correct / len(known_predictions),
                confusion=[dict(answer=a, prediction=p, count=n) for (a, p), n in sorted(confusion.items())],
                limitations=[
                    'Self-reports are not independent ground truth; visible predictions may bias answers.',
                    'Predictions refer to interval endpoints; answers label at most the final ten seconds.',
                    'Selective feedback cannot establish population-level accuracy or unbiased duration error.',
                    'Tentative durations and self-reported durations must remain separate.',
                    'Unknown does not mean absent; possibly away does not mean confirmed absence.',
                    'No focus, energy or overall CPU/memory claim follows from this export.'
                ])


def markdown(report):
    def rate(value):
        return 'N/A' if value is None else f'{100 * value:.1f}%'
    lines = ['# Desktop Buddy — Local Diary Review', '',
             'This is a descriptive self-report analysis, not a validated activity-recognition result.', '',
             f"Evaluated labels: {report['evaluatedLabels']}; excluded uncertain labels: {report['excludedUncertainLabels']}.",
             f"Accuracy including unknown predictions: {rate(report['accuracyIncludingUnknown'])}.",
             f"Prediction coverage on labeled examples: {rate(report['predictionCoverage'])}.",
             f"Accuracy conditional on non-unknown predictions: {rate(report['conditionalAccuracy'])}.", '',
             '| Recorded category | Minutes |', '| --- | ---: |']
    for activity, seconds in sorted(report['intervalSeconds'].items()):
        lines.append(f'| {activity} | {seconds / 60:.2f} |')
    lines += ['', '| User answer | Endpoint prediction | Count |', '| --- | --- | ---: |']
    for cell in report['confusion']:
        lines.append(f"| {cell['answer']} | {cell['prediction']} | {cell['count']} |")
    lines += ['', '## Limitations', ''] + ['- ' + s for s in report['limitations']]
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('export', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    report = summarize(json.loads(args.export.read_text(encoding='utf-8')))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(markdown(report), encoding='utf-8')
    print(f"Local English review written to {args.output}. Labels: {report['evaluatedLabels']}")


if __name__ == '__main__':
    main()
