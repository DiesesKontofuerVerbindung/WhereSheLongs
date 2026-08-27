import csv
import math
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import config
from fan_detector import FanDetector, Point, TrajectorySample
from fan_state import FanState
from hand_tracker import extract_hand_features
from interference_field import CYRILLIC_GLYPHS, LATIN_GLYPHS, InterferenceField
from test_logger import TestLogger


class Landmark:
    def __init__(self, x: float, y: float) -> None:
        self.x = x
        self.y = y


def open_palm_landmarks(rotation_degrees: float = 0.0) -> list[Landmark]:
    points = [Landmark(0.5, 0.65) for _ in range(21)]
    points[0] = Landmark(0.5, 0.78)
    for x, indices in zip((0.36, 0.45, 0.54, 0.63), ((5, 6, 7, 8), (9, 10, 11, 12), (13, 14, 15, 16), (17, 18, 19, 20))):
        for y, index in zip((0.62, 0.48, 0.34, 0.20), indices):
            points[index] = Landmark(x, y)
    radians = math.radians(rotation_degrees)
    cosine, sine = math.cos(radians), math.sin(radians)
    for point in points:
        dx, dy = point.x - 0.5, point.y - 0.5
        point.x = 0.5 + dx * cosine - dy * sine
        point.y = 0.5 + dx * sine + dy * cosine
    return points


def arm(detector: FanDetector, start_time: float = 0.0) -> float:
    detector.update(Point(500, 350), True, start_time)
    detector.update(Point(501, 350), True, start_time + 0.10)
    event = detector.update(Point(500, 351), True, start_time + config.PALM_ARM_TIME + 0.02)
    assert event.state == FanState.FAN_READY
    assert event.started
    return start_time + config.PALM_ARM_TIME + 0.02


def feed_x(detector: FanDetector, x: float, y: float, now: float, count: int = 4) -> tuple[float, list]:
    events = []
    for _ in range(count):
        now += 0.06
        events.append(detector.update(Point(x, y), True, now))
    return now, events


class FanGestureTests(unittest.TestCase):
    def test_interference_cluster_mixes_latin_and_cyrillic_glyphs(self) -> None:
        field = InterferenceField(seed=7)
        glyphs = {entity.glyph for entity in field.entities}
        self.assertTrue(glyphs.intersection(LATIN_GLYPHS))
        self.assertTrue(glyphs.intersection(CYRILLIC_GLYPHS))
        self.assertEqual(len(field.entities), config.INTERFERENCE_ENTITY_COUNT)

    def test_fan_strength_pushes_entities_outward_on_both_sides(self) -> None:
        field = InterferenceField(seed=7)
        initial_left = sum(entity.x for entity in field.entities if entity.side < 0) / 14
        initial_right = sum(entity.x for entity in field.entities if entity.side > 0) / 14
        for step in range(40):
            field.update(0.05, 0.90, "right" if step % 2 == 0 else "left", step // 10)
        final_left = sum(entity.x for entity in field.entities if entity.side < 0) / 14
        final_right = sum(entity.x for entity in field.entities if entity.side > 0) / 14
        self.assertLess(final_left, initial_left - 100.0)
        self.assertGreater(final_right, initial_right + 100.0)

    def test_zero_strength_does_not_disperse_and_reset_restores_cluster(self) -> None:
        field = InterferenceField(seed=11)
        initial = [(entity.x, entity.y) for entity in field.entities]
        for _ in range(20):
            field.update(0.05, 0.0, "center", 0)
        self.assertEqual([entity.x for entity in field.entities], [point[0] for point in initial])
        self.assertEqual(field.dispersed_count, 0)
        field.update(0.10, 1.0, "right", 2)
        field.reset()
        self.assertEqual([(entity.x, entity.y) for entity in field.entities], initial)
        self.assertEqual(field.dispersed_ratio, 0.0)

    def test_unicode_entities_render_onto_opencv_canvas(self) -> None:
        field = InterferenceField(seed=7)
        canvas = np.zeros((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), dtype=np.uint8)
        field.render(canvas)
        self.assertGreater(int(np.count_nonzero(canvas)), 0)

    def test_open_palm_feature_is_rotation_tolerant(self) -> None:
        for rotation in (0.0, 45.0, 90.0, 180.0):
            features = extract_hand_features(open_palm_landmarks(rotation))
            self.assertTrue(features.open_palm, rotation)

    def test_open_palm_is_required_to_arm(self) -> None:
        detector = FanDetector()
        for index in range(10):
            event = detector.update(Point(500, 350), False, index * 0.05)
        self.assertEqual(event.state, FanState.TRACKING)
        self.assertEqual(event.sweep_count, 0)

    def test_stationary_open_palm_never_produces_a_sweep(self) -> None:
        detector = FanDetector()
        now = arm(detector)
        for index in range(10):
            event = detector.update(Point(500, 350), True, now + index * 0.05)
        self.assertEqual(event.sweep_count, 0)
        self.assertNotEqual(event.state, FanState.FANNING)

    def test_vertical_motion_never_produces_a_sweep(self) -> None:
        detector = FanDetector()
        now = arm(detector)
        events = [
            detector.update(Point(500, y), True, now + index * 0.08)
            for index, y in enumerate((300, 240, 190, 140), start=1)
        ]
        self.assertTrue(any(event.fail_reason == "vertical_drift" for event in events))
        self.assertTrue(all(event.sweep_count == 0 for event in events))

    def test_small_horizontal_jitter_does_not_produce_a_sweep(self) -> None:
        detector = FanDetector()
        now = arm(detector)
        for index in range(30):
            x = 500 + (5 if index % 2 else -5)
            event = detector.update(Point(x, 350), True, now + (index + 1) * 0.03)
        self.assertEqual(event.sweep_count, 0)
        self.assertNotEqual(event.state, FanState.FANNING)

    def test_back_and_forth_motion_increments_sweep_count(self) -> None:
        detector = FanDetector()
        now = arm(detector)
        now, _ = feed_x(detector, 680, 350, now)
        now, left_events = feed_x(detector, 320, 350, now)
        now, right_events = feed_x(detector, 680, 350, now)
        events = left_events + right_events
        self.assertGreaterEqual(max(event.sweep_count for event in events), 2)
        completed = next(event for event in events if event.completed)
        self.assertEqual(completed.state, FanState.FANNING)
        self.assertEqual(completed.high_level_event["event"], "fan_update")
        self.assertGreater(completed.fan_strength, 0.0)

    def test_missing_hand_timeout_resets_active_fan(self) -> None:
        detector = FanDetector()
        now = arm(detector)
        now, _ = feed_x(detector, 680, 350, now)
        event = detector.update(None, False, now + config.MAX_MISSING_HAND_TIME + 0.01)
        self.assertTrue(event.reset)
        self.assertTrue(event.terminal)
        self.assertEqual(event.fail_reason, "hand_lost")
        self.assertEqual(detector.state, FanState.TRACKING)

    def test_logger_writes_fan_trial_and_trajectory_fields(self) -> None:
        sample = TrajectorySample(
            1.0, Point(400, 300), Point(405, 302), True, FanState.FANNING,
            "right", 350.0, 0.6, 120.0, 2,
        )
        with tempfile.TemporaryDirectory() as temporary_directory:
            logger = TestLogger(Path(temporary_directory))
            logger.start_trial("positive", 0.0)
            logger.append_sample(sample)
            logger.finish_trial("success", "", 1.0)
            with logger.trials_path.open(newline="", encoding="utf-8") as file:
                trial = next(csv.DictReader(file))
            for field in (
                "expected_type", "result", "fail_reason", "duration", "sweep_count",
                "max_amplitude", "mean_amplitude", "peak_horizontal_velocity", "mean_fan_strength",
            ):
                self.assertIn(field, trial)
            with next(logger.trajectory_dir.glob("*.csv")).open(newline="", encoding="utf-8") as file:
                trajectory = next(csv.DictReader(file))
            for field in (
                "timestamp", "raw_palm_x", "raw_palm_y", "smoothed_palm_x", "smoothed_palm_y",
                "open_palm", "state", "direction", "horizontal_velocity", "fan_strength",
            ):
                self.assertIn(field, trajectory)


if __name__ == "__main__":
    unittest.main()
