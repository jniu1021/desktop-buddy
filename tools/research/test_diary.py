import unittest
from analyze_diary import summarize
from profile_process import cpu_seconds


class DiaryAnalysisTests(unittest.TestCase):
    def test_unknown_predictions_count_against_accuracy(self):
        report = summarize(dict(schema=1, intervals=[], feedback=[
            dict(answer='coding', prediction='coding'),
            dict(answer='reading', prediction='unknown'),
            dict(answer='uncertain', prediction='video')]))
        self.assertEqual(report['evaluatedLabels'], 2)
        self.assertEqual(report['accuracyIncludingUnknown'], .5)
        self.assertEqual(report['predictionCoverage'], .5)
        self.assertEqual(report['conditionalAccuracy'], 1)

    def test_missing_labels_are_not_zero_accuracy(self):
        report = summarize(dict(schema=1, intervals=[], feedback=[]))
        self.assertIsNone(report['accuracyIncludingUnknown'])

    def test_tentative_and_confirmed_are_separate(self):
        report = summarize(dict(schema=1, feedback=[], intervals=[
            dict(start='2026-11-04T10:00:00Z', end='2026-11-04T10:01:00Z', activity='tentative_coding', source='heuristic'),
            dict(start='2026-11-04T10:01:00Z', end='2026-11-04T10:01:10Z', activity='coding', source='self_report')]))
        self.assertEqual(report['intervalSeconds']['coding'], 10)
        self.assertEqual(report['intervalSeconds']['tentative_coding'], 60)

    def test_overlapping_intervals_are_rejected(self):
        row = dict(start='2026-11-04T10:00:00Z', end='2026-11-04T10:01:00Z', activity='unknown', source='metadata')
        with self.assertRaises(ValueError):
            summarize(dict(schema=1, feedback=[], intervals=[row, row]))

    def test_cpu_clock_supports_ps_formats(self):
        self.assertAlmostEqual(cpu_seconds('01:02.50'), 62.5)
        self.assertEqual(cpu_seconds('01:02:03'), 3723)
        self.assertEqual(cpu_seconds('1-01:00:00'), 90000)
