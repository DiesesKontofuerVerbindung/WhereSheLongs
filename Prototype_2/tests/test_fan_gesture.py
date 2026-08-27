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
from hand_tracker import HandFeatures, extract_hand_features
from interference_field import (
    CYRILLIC_GLYPHS,
    LATIN_GLYPHS,
    InterferenceField,
    LetterEntity,
    PalmMotionTracker,
    PalmPhysicsInput,
)
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


def letter_entity(
    x: float = 500.0,
    y: float = 400.0,
    mass: float = 1.0,
    radius: float = 15.0,
    velocity_x: float = 0.0,
    velocity_y: float = 0.0,
) -> LetterEntity:
    return LetterEntity(
        glyph="A",
        x=x,
        y=y,
        mass=mass,
        radius=radius,
        size=32,
        color=(255, 255, 255),
        velocity_x=velocity_x,
        velocity_y=velocity_y,
    )


def physics_field(*entities: LetterEntity) -> InterferenceField:
    field = InterferenceField(seed=1)
    field.entities = list(entities)
    return field


class FanGestureTests(unittest.TestCase):
    def test_responsive_runtime_calibration(self) -> None:
        self.assertEqual(config.TARGET_FPS, 240)
        self.assertLessEqual(config.PALM_ARM_TIME, 0.15)
        self.assertLessEqual(config.FAN_START_DISTANCE, 35.0)
        self.assertGreater(config.SMOOTHING_FACTOR, 0.5)

    def test_interference_cluster_mixes_latin_and_cyrillic_glyphs(self) -> None:
        field = InterferenceField(seed=7)
        glyphs = {entity.glyph for entity in field.entities}
        self.assertTrue(glyphs.intersection(LATIN_GLYPHS))
        self.assertTrue(glyphs.intersection(CYRILLIC_GLYPHS))
        self.assertEqual(len(field.entities), config.INTERFERENCE_ENTITY_COUNT)

    def test_disabled_gravity_keeps_stationary_letter_at_its_height(self) -> None:
        field = physics_field(letter_entity(y=300.0))
        field.update(0.05, None)
        letter = field.entities[0]
        self.assertEqual(config.LETTER_GRAVITY, 0.0)
        self.assertEqual(letter.acceleration_y, 0.0)
        self.assertEqual(letter.velocity_y, 0.0)
        self.assertEqual(letter.y, 300.0)

    def test_floor_prevents_tunneling_and_small_bounce_settles(self) -> None:
        letter = letter_entity(
            y=config.LETTER_FLOOR_Y - 16.0,
            radius=15.0,
            velocity_y=200.0,
        )
        field = physics_field(letter)
        field.update(0.05, None)
        self.assertEqual(letter.y, config.LETTER_FLOOR_Y - letter.radius)
        self.assertLessEqual(letter.velocity_y, 0.0)
        letter.velocity_y = 1.0
        field.update(0.05, None)
        self.assertEqual(letter.y, config.LETTER_FLOOR_Y - letter.radius)
        self.assertEqual(letter.velocity_y, 0.0)

    def test_hand_force_is_local_to_influence_radius(self) -> None:
        near = letter_entity(x=500.0, y=400.0)
        far = letter_entity(x=800.0, y=400.0)
        field = physics_field(near, far)
        field.update(0.02, PalmPhysicsInput(500.0, 400.0, 300.0, 0.0))
        self.assertGreater(near.acceleration_x, 0.0)
        self.assertEqual(far.acceleration_x, 0.0)
        self.assertEqual(field.letters_inside_influence_radius, 1)

    def test_palm_velocity_controls_force_direction(self) -> None:
        right = physics_field(letter_entity(x=500.0, y=400.0))
        right.update(0.02, PalmPhysicsInput(500.0, 400.0, 300.0, 0.0))
        left = physics_field(letter_entity(x=500.0, y=400.0))
        left.update(0.02, PalmPhysicsInput(500.0, 400.0, -300.0, 0.0))
        self.assertGreater(right.entities[0].velocity_x, 0.0)
        self.assertLess(left.entities[0].velocity_x, 0.0)

    def test_fast_palm_triggers_impulse_but_slow_palm_does_not(self) -> None:
        slow = physics_field(letter_entity(x=500.0, y=400.0))
        slow.update(0.01, PalmPhysicsInput(500.0, 400.0, 300.0, 0.0))
        fast = physics_field(letter_entity(x=500.0, y=400.0))
        fast.update(0.01, PalmPhysicsInput(500.0, 400.0, 900.0, 0.0))
        self.assertEqual(slow.last_impulse_strength, 0.0)
        self.assertGreater(fast.last_impulse_strength, 0.0)
        self.assertGreater(fast.entities[0].velocity_x, slow.entities[0].velocity_x)

    def test_fast_palm_sweep_hits_letter_between_sampled_positions(self) -> None:
        letter = letter_entity(x=500.0, y=400.0)
        field = physics_field(letter)
        palm = PalmPhysicsInput(
            x=800.0,
            y=400.0,
            velocity_x=1200.0,
            velocity_y=0.0,
            previous_x=200.0,
            previous_y=400.0,
        )
        field.update(0.01, palm)
        self.assertEqual(field.letters_inside_influence_radius, 1)
        self.assertGreater(field.last_impulse_strength, 0.0)
        self.assertGreater(letter.velocity_x, 0.0)

    def test_brief_open_palm_flicker_keeps_current_sweep_segment(self) -> None:
        tracker = PalmMotionTracker()
        tracker.update(300.0, 400.0, 0.0, True)
        palm = tracker.update(
            700.0,
            400.0,
            config.PHYSICS_OPEN_PALM_GRACE_TIME / 2,
            False,
        )
        self.assertIsNotNone(palm)
        assert palm is not None
        self.assertEqual(palm.previous_x, 300.0)
        self.assertEqual(palm.x, 700.0)
        self.assertGreater(palm.velocity_x, config.HAND_IMPULSE_VELOCITY_THRESHOLD)

    def test_expired_open_palm_grace_disables_hand_physics(self) -> None:
        tracker = PalmMotionTracker()
        tracker.update(300.0, 400.0, 0.0, True)
        palm = tracker.update(
            700.0,
            400.0,
            config.PHYSICS_OPEN_PALM_GRACE_TIME + 0.01,
            False,
        )
        self.assertIsNone(palm)

    def test_letter_keeps_inertia_after_hand_disappears(self) -> None:
        field = physics_field(letter_entity(x=500.0, y=400.0))
        field.update(0.03, PalmPhysicsInput(500.0, 400.0, 400.0, 0.0))
        velocity_with_hand = field.entities[0].velocity_x
        x_with_hand = field.entities[0].x
        field.update(0.03, None)
        self.assertGreater(field.entities[0].velocity_x, 0.0)
        self.assertLess(field.entities[0].velocity_x, velocity_with_hand)
        self.assertGreater(field.entities[0].x, x_with_hand)

    def test_open_palm_loss_uses_grace_without_resetting_physical_world(self) -> None:
        tracker = PalmMotionTracker()
        tracker.update(480.0, 400.0, 0.0, True)
        palm = tracker.update(520.0, 400.0, 0.05, True)
        field = physics_field(letter_entity(x=500.0, y=400.0))
        field.update(0.03, palm)
        pushed_x = field.entities[0].x
        missing = tracker.update(520.0, 400.0, 0.08, False)
        field.update(0.03, missing)
        self.assertIsNotNone(missing)
        self.assertEqual(len(field.entities), 1)
        self.assertGreater(field.entities[0].x, pushed_x)

    def test_same_force_accelerates_lighter_letter_more(self) -> None:
        light = letter_entity(x=500.0, y=400.0, mass=0.8)
        heavy = letter_entity(x=500.0, y=400.0, mass=1.2)
        field = physics_field(light, heavy)
        field.update(0.01, PalmPhysicsInput(500.0, 400.0, 300.0, 0.0))
        self.assertGreater(light.acceleration_x, heavy.acceleration_x)
        self.assertGreater(light.velocity_x, heavy.velocity_x)

    def test_unicode_entities_render_onto_opencv_canvas(self) -> None:
        field = InterferenceField(seed=7)
        canvas = np.zeros((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), dtype=np.uint8)
        field.render(canvas)
        self.assertGreater(int(np.count_nonzero(canvas)), 0)

    def test_unicode_glyph_sprites_are_cached_after_first_render(self) -> None:
        field = physics_field(letter_entity())
        first = np.zeros((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), dtype=np.uint8)
        second = np.zeros_like(first)
        field.render(first)
        cache_size = len(field._glyph_cache)
        field.render(second)
        self.assertEqual(cache_size, 1)
        self.assertEqual(len(field._glyph_cache), cache_size)
        self.assertTrue(np.array_equal(first, second))

    def test_open_palm_feature_is_rotation_tolerant(self) -> None:
        for rotation in (0.0, 45.0, 90.0, 180.0):
            features = extract_hand_features(open_palm_landmarks(rotation))
            self.assertTrue(features.open_palm, rotation)

    def test_relaxed_open_palm_allows_one_bent_finger(self) -> None:
        features = HandFeatures(0.5, 0.5, True, True, True, False)
        self.assertTrue(features.open_palm)

    def test_two_extended_fingers_are_not_an_open_palm(self) -> None:
        features = HandFeatures(0.5, 0.5, True, True, False, False)
        self.assertFalse(features.open_palm)

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
