import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from gesture_detector import GestureDetector, GesturePhase, GestureState, Point, TrajectorySample
from test_logger import TestLogger, calculate_metrics


def arm(detector: GestureDetector, start_time: float = 0.0) -> float:
    detector.update(Point(500, 350), start_time)
    detector.update(Point(501, 350), start_time + 0.10)
    detector.update(Point(500, 351), start_time + 0.31)
    assert detector.state == GestureState.ARMED
    return start_time + 0.40


def check_points(variation: int = 0) -> list[Point]:
    start_x = 450 + (variation % 5) * 2
    start_y = 320 + (variation % 4) * 2
    points = []
    for index in range(13):
        jitter = ((index + variation) % 3 - 1) * 2
        points.append(Point(start_x + index * 6, start_y + index * 3 + jitter))
    for index in range(1, 16):
        jitter = ((index + variation + 1) % 3 - 1) * 2
        points.append(Point(start_x + 72 + index * 6, start_y + 39 - index * 5 + jitter))
    return points


def feed(detector: GestureDetector, points: list[Point], start_time: float = 0.4):
    results = []
    for index, point in enumerate(points):
        results.append(detector.update(point, start_time + index * 0.08))
    return results


class GestureDetectorTests(unittest.TestCase):
    def test_fast_entry_only_arms_and_never_starts_a_trial(self) -> None:
        detector = GestureDetector()
        detector.update(Point(250, 350), 0.0)
        result = detector.update(Point(500, 350), 0.05)
        self.assertEqual(result.state, GestureState.ARMING)
        self.assertFalse(result.started)
        self.assertFalse(result.terminal)
        self.assertEqual(detector.points, [])
        self.assertEqual(detector.samples, [])
        self.assertIsNone(detector.started_at)

    def test_stable_hand_becomes_armed_after_hold(self) -> None:
        detector = GestureDetector()
        arm(detector)
        self.assertEqual(detector.phase, GesturePhase.ARMED)
        self.assertTrue(detector.ready_to_draw)
        self.assertEqual(detector.arming_progress(0.4), 1.0)

    def test_random_armed_motion_does_not_fail_or_start_trial(self) -> None:
        detector = GestureDetector()
        start_time = arm(detector)
        results = feed(detector, [Point(480, 330), Point(460, 315), Point(445, 330)], start_time)
        self.assertEqual(detector.state, GestureState.ARMED)
        self.assertFalse(any(result.started or result.terminal for result in results))
        self.assertEqual(detector.points, [])

    def test_early_wrong_candidate_is_rejected_and_rearmed(self) -> None:
        detector = GestureDetector()
        start_time = arm(detector)
        # First meet the small ↘ candidate threshold, then decisively reverse.
        points = [
            Point(450, 320), Point(456, 324), Point(466, 332), Point(475, 340),
            Point(410, 270), Point(380, 240), Point(360, 220),
        ]
        results = feed(detector, points, start_time)
        rejection = next(result for result in results if result.candidate_rejected)
        self.assertEqual(rejection.fail_reason, "invalid_downstroke")
        self.assertEqual(detector.state, GestureState.ARMED)
        self.assertEqual(detector.phase, GesturePhase.ARMED)
        self.assertEqual(detector.last_candidate_reject_reason, "invalid_downstroke")
        self.assertEqual(detector.points, [])
        self.assertIsNone(detector.started_at)

    def test_online_check_mark_arms_then_visits_each_phase_then_succeeds(self) -> None:
        detector = GestureDetector()
        start_time = arm(detector)
        results = feed(detector, check_points(), start_time)
        phases = [result.phase for result in results]
        self.assertIn(GesturePhase.STARTED, phases)
        self.assertIn(GesturePhase.DOWNSTROKE_OK, phases)
        self.assertIn(GesturePhase.TURN_OK, phases)
        self.assertIn(GesturePhase.UPSTROKE_OK, phases)
        self.assertEqual(detector.state, GestureState.CHECKED)
        self.assertEqual(detector.phase, GesturePhase.SUCCESS)
        started = next(result for result in results if result.started)
        self.assertGreaterEqual(len(started.initial_samples), 4)

    def test_twenty_small_jitter_variations_are_detected(self) -> None:
        successes = 0
        for variation in range(20):
            detector = GestureDetector()
            start_time = arm(detector)
            feed(detector, check_points(variation), start_time)
            successes += detector.state == GestureState.CHECKED
        self.assertEqual(successes, 20)

    def test_actual_failed_trial_auto_rearms(self) -> None:
        detector = GestureDetector()
        start_time = arm(detector)
        results = feed(detector, check_points()[:10], start_time)
        last_time = start_time + len(check_points()[:10]) * 0.08
        failure = detector.update(None, last_time + 0.5)
        self.assertTrue(failure.terminal)
        self.assertEqual(detector.state, GestureState.FAILED)
        rearmed = detector.update(Point(500, 350), last_time + 1.1)
        self.assertEqual(rearmed.state, GestureState.ARMED)

    def test_metrics_handles_missing_denominators(self) -> None:
        metrics = calculate_metrics([])
        self.assertIsNone(metrics["metrics"]["precision"])
        self.assertIsNone(metrics["metrics"]["false_positive_rate"])

    def test_logger_writes_trials_trajectory_and_metrics(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            logger = TestLogger(Path(temporary_directory))
            sample = TrajectorySample(0.0, Point(500, 350), Point(500, 350), GesturePhase.STARTED)
            for expected, result in (("positive", "success"), ("positive", "fail"), ("negative", "fail"), ("negative", "success")):
                logger.start_trial(expected, 10.0)
                logger.append_sample(sample)
                logger.finish_trial(result, "" if result == "success" else "draw_timeout", 11.0)
            summary = json.loads(logger.summary_path.read_text(encoding="utf-8"))
            self.assertEqual((summary["tp"], summary["fn"], summary["tn"], summary["fp"]), (1, 1, 1, 1))
            self.assertEqual(summary["metrics"]["accuracy"], 0.5)
            self.assertTrue((logger.trajectory_dir / "trial_001.csv").exists())

    def test_discarded_candidate_does_not_create_a_trial_record(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            logger = TestLogger(Path(temporary_directory))
            logger.start_trial("positive", 10.0)
            logger.discard_active_trial()
            self.assertEqual(logger.records, [])
            self.assertEqual(logger._next_trial_id, 1)
            self.assertEqual(list(logger.trajectory_dir.glob("*.csv")), [])


if __name__ == "__main__":
    unittest.main()
