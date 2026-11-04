import unittest
from evaluate import decide, evaluate, summarize, load
import tempfile
from pathlib import Path


def sample(t=0, category='browser', **kwargs):
    return dict(t=t, category=category, idleSeconds=1, fullscreen=False,
                switchCount=0, stableSeconds=20, sensingMS=.2, **kwargs)


def event(kind, t, **kwargs):
    return dict(schema=1, kind=kind, t=t, **kwargs)


class PolicyTests(unittest.TestCase):
    def test_baseline_does_not_use_history(self):
        s = sample(); s.update(switchCount=8, stableSeconds=2)
        self.assertEqual(decide('B', s)[0], 'notify_now')
        self.assertEqual(decide('C', s)[0], 'delay')

    def test_urgent_overrides_unknown_and_idle(self):
        self.assertEqual(decide('C', None, 'urgent')[0], 'notify_now')
        s = sample(); s['idleSeconds'] = 1000
        self.assertEqual(decide('C', s, 'urgent')[0], 'notify_now')

    def test_idle_and_console_are_not_available(self):
        for policy in ('B', 'C'):
            self.assertEqual(decide(policy, sample(category='research_console'))[0], 'delay')
            s = sample(); s['idleSeconds'] = 100
            self.assertEqual(decide(policy, s)[0], 'delay')

    def test_deadline_no_future_leakage(self):
        s = sample(category='unknown')
        events = [event('sample', 0, sample=s), event('candidate', 1, candidateID='x', priority='ordinary'),
                  event('sample', 140, sample=sample(140)), event('session_end', 150)]
        rows, _ = evaluate(events)
        row = next(r for r in rows if r['policy'] == 'B')
        self.assertEqual(row['initial'], 'delay')
        self.assertEqual(row['delivery'], 121)
        self.assertEqual(row['deliveryReason'], 'deadline_override')

    def test_end_before_deadline_is_censored(self):
        events = [event('sample', 0, sample=sample(category='unknown')),
                  event('candidate', 1, candidateID='x', priority='ordinary'),
                  event('label', 5, candidateID='x', useful=True, preference='delay', maxDelay=60),
                  event('session_end', 10)]
        rows, _ = evaluate(events)
        for row in rows: row['followup'] = 10 - row['t']
        report = summarize(rows)['C']
        self.assertEqual(report['usefulCensored'], 1)
        self.assertIsNone(report['missedUsefulRate'])

    def test_stale_observation_falls_back(self):
        rows, _ = evaluate([event('sample', 0, sample=sample()),
            event('candidate', 20, candidateID='x', priority='ordinary'), event('session_end', 21)])
        self.assertEqual(next(r for r in rows if r['policy'] == 'B')['reason'], 'unknown_fallback')

    def test_rejects_time_reversal(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'bad.jsonl'
            path.write_text('{"schema":1,"t":2}\n{"schema":1,"t":1}\n')
            with self.assertRaises(ValueError): load(path)


if __name__ == '__main__': unittest.main()

class ReportTests(unittest.TestCase):
    def test_html_escapes_participant_source(self):
        from evaluate import render_html
        report = dict(policyVersion='test', source='<script>bad</script>', samples=0,
                      policies=summarize([]), rows=[])
        rendered = render_html(report)
        self.assertNotIn('<script>', rendered)
        self.assertIn('&lt;script&gt;', rendered)

    def test_followup_is_included_without_caller_mutation(self):
        rows, _ = evaluate([event('sample', 0, sample=sample(category='unknown')),
            event('candidate', 1, candidateID='x', priority='ordinary'),
            event('label', 5, candidateID='x', useful=True, preference='delay', maxDelay=10),
            event('session_end', 20)])
        report = summarize(rows)['B']
        self.assertEqual(report['missedUseful'], 1)
        self.assertEqual(report['usefulCensored'], 0)

class RecordingSelectionTests(unittest.TestCase):
    def test_partial_and_corrupt_sessions_are_not_selected(self):
        import json
        from analyze_latest import latest_completed
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            valid = root / 'session-complete.jsonl'
            valid.write_text('\n'.join(json.dumps(e) for e in [
                event('session_start', 0), event('session_end', 10)]))
            (root / 'session-active.jsonl').write_text(json.dumps(event('session_start', 0)))
            (root / 'session-corrupt.jsonl').write_text('broken')
            self.assertEqual(latest_completed(root), valid)

    def test_empty_directory_has_no_recording(self):
        from analyze_latest import latest_completed
        with tempfile.TemporaryDirectory() as directory:
            self.assertIsNone(latest_completed(Path(directory)))
