import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from gesture_detector import GestureDetector, GesturePhase, GestureState, Point, TrajectorySample
from test_logger import TestLogger, calculate_metrics


def check_points(variation: int = 0) -> list[Point]:
    start_x = 385 + (variation % 5) * 3
    start_y = 332 + (variation % 4) * 3
    points = []
    for index in range(13):
        jitter = ((index + variation) % 3 - 1) * 2
        points.append(Point(start_x + index * 6, start_y + index * 3 + jitter))
    for index in range(1, 16):
        jitter = ((index + variation + 1) % 3 - 1) * 2
        points.append(Point(start_x + 72 + index * 6, start_y + 39 - index * 5 + jitter))
    return points


def feed(detector: GestureDetector, points: list[Point]):
    results = []
    for index, point in enumerate(points):
        results.append(detector.update(point, index * 0.08))
    return results


class GestureDetectorTests(unittest.TestCase):
    def test_online_check_mark_visits_each_phase_then_succeeds(self) -> None:
        detector = GestureDetector()
        results = feed(detector, check_points())
        phases = [result.phase for result in results]
        self.assertIn(GesturePhase.STARTED, phases)
        self.assertIn(GesturePhase.DOWNSTROKE_OK, phases)
        self.assertIn(GesturePhase.TURN_OK, phases)
        self.assertIn(GesturePhase.UPSTROKE_OK, phases)
        self.assertEqual(detector.state, GestureState.CHECKED)
        self.assertEqual(detector.phase, GesturePhase.SUCCESS)
        self.assertGreaterEqual(len(detector.samples), 10)
        self.assertEqual(detector.samples[-1].phase, GesturePhase.SUCCESS)

    def test_twenty_small_jitter_variations_are_detected(self) -> None:
        successes = 0
        for variation in range(20):
            detector = GestureDetector()
            feed(detector, check_points(variation))
            successes += detector.state == GestureState.CHECKED
        self.assertEqual(successes, 20)

    def test_wrong_upstroke_is_rejected(self) -> None:
        points = [Point(390 + index * 6, 345 + index * 3) for index in range(14)]
        points += [Point(468 - index * 7, 387 - index * 5) for index in range(1, 14)]
        detector = GestureDetector()
        results = feed(detector, points)
        self.assertEqual(detector.state, GestureState.FAILED)
        terminal = next(result for result in results if result.terminal)
        self.assertEqual(terminal.fail_reason, "invalid_upstroke")

    def test_hand_loss_fails_only_after_tolerance(self) -> None:
        detector = GestureDetector()
        detector.update(Point(390, 345), 0.0)
        self.assertFalse(detector.update(None, 0.1).terminal)
        result = detector.update(None, 0.5)
        self.assertTrue(result.terminal)
        self.assertEqual(result.fail_reason, "hand_lost")

    def test_valid_upstroke_can_finish_after_hand_stops(self) -> None:
        detector = GestureDetector()
        points = check_points()
        results = feed(detector, points[:-2])
        self.assertIn(GesturePhase.UPSTROKE_OK, [result.phase for result in results])
        result = detector.update(None, len(points) * 0.08 + 0.5)
        self.assertTrue(result.checked)
        self.assertEqual(detector.phase, GesturePhase.SUCCESS)

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
            self.assertTrue((logger.run_dir / "config_snapshot.json").exists())
            self.assertTrue((logger.run_dir / "environment.json").exists())
            self.assertTrue((logger.trajectory_dir / "trial_001.csv").exists())


if __name__ == "__main__":
    unittest.main()
