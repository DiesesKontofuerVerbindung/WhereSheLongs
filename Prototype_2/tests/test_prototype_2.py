import csv
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import config
from block_manager import BlockManager
from checklist_mapper import ChecklistMapper
from hand_tracker import map_normalized_y_to_screen, valid_finger_mode
from main import PrototypeApp
from motion_profiles import AccelMotionProfile, BaselineMotionProfile, MomentumMotionProfile, MomentumOneEuroMotionProfile
from one_euro_filter import OneEuroFilter
from swipe_detector import Point, SwipeDetector
from swipe_state import SwipeState
from test_logger import TestLogger, calculate_metrics


AUTO_SWIPE_START_X = 80
AUTO_SWIPE_START_Y = 500


def arm(detector: SwipeDetector, blocks: BlockManager, block_id: str, now: float = 0.0) -> float:
    block = blocks.get(block_id)
    assert block is not None
    x, y = AUTO_SWIPE_START_X, AUTO_SWIPE_START_Y
    detector.update(Point(x, y), now, blocks, config.ONE_FINGER)
    detector.update(Point(x, y), now + 0.10, blocks, config.ONE_FINGER)
    event = detector.update(Point(x, y), now + config.BLOCK_ARM_TIME + 0.02, blocks, config.ONE_FINGER)
    assert event.state == SwipeState.BLOCK_ARMED
    return now + config.BLOCK_ARM_TIME + 0.03


class Prototype2Tests(unittest.TestCase):
    def test_vertical_cursor_calibration_reaches_the_block_row(self) -> None:
        blocks = BlockManager()
        block = blocks.get("wood_5")
        assert block is not None
        raw_y_for_block_center = (
            block.center_y / (config.CURSOR_Y_OUTPUT_MAX_RATIO * config.WINDOW_HEIGHT)
            * (config.CURSOR_Y_INPUT_MAX - config.CURSOR_Y_INPUT_MIN)
            + config.CURSOR_Y_INPUT_MIN
        )
        mapped_y = map_normalized_y_to_screen(raw_y_for_block_center)
        self.assertLessEqual(abs(mapped_y - block.center_y), config.BLOCK_HEIGHT / 2 + config.BLOCK_HITBOX_MARGIN)
        self.assertEqual(
            map_normalized_y_to_screen(config.CURSOR_Y_INPUT_MAX),
            int(config.CURSOR_Y_OUTPUT_MAX_RATIO * config.WINDOW_HEIGHT),
        )

    def test_vertical_cursor_calibration_invariant_and_clamps(self) -> None:
        self.assertEqual(map_normalized_y_to_screen(0.00, 700), 0)
        self.assertIn(map_normalized_y_to_screen(0.31, 700), (437, 438))
        self.assertEqual(map_normalized_y_to_screen(0.62, 700), 875)
        self.assertEqual(map_normalized_y_to_screen(-0.20, 700), 0)
        self.assertEqual(map_normalized_y_to_screen(0.90, 700), 875)

    def test_top_wood_is_auto_locked_without_pointing_at_it(self) -> None:
        blocks = BlockManager()
        top = blocks.top_block
        assert top is not None
        self.assertEqual(top.block_id, "wood_5")
        detector = SwipeDetector()
        event = detector.update(Point(60, 250), 0.0, blocks, config.ONE_FINGER)
        self.assertEqual(event.target_block, "wood_5")
        self.assertEqual(event.state, SwipeState.BLOCK_HOVER)
        self.assertTrue(blocks.mark_completed("wood_5"))
        self.assertEqual(blocks.top_block.block_id, "wood_4")

    def test_two_finger_mode_requires_both_fingertips_extended(self) -> None:
        landmarks = [type("Landmark", (), {"x": 0.0, "y": 0.5})() for _ in range(21)]
        landmarks[8].y, landmarks[6].y = 0.20, 0.40
        landmarks[12].y, landmarks[10].y = 0.22, 0.42
        self.assertEqual(valid_finger_mode(landmarks, config.TWO_FINGER), (True, True))
        landmarks[12].y = 0.45
        self.assertEqual(valid_finger_mode(landmarks, config.TWO_FINGER), (False, False))

    def test_hover_does_not_move_or_start_trial_until_armed(self) -> None:
        blocks = BlockManager()
        detector = SwipeDetector()
        block = blocks.get("wood_5")
        assert block is not None
        original_y = block.center_y
        event = detector.update(Point(60, 250), 0.0, blocks, config.ONE_FINGER)
        self.assertEqual(event.state, SwipeState.BLOCK_HOVER)
        self.assertEqual(block.center_y, original_y)
        self.assertFalse(event.started)

    def test_one_finger_upward_swipe_completes_once(self) -> None:
        blocks = BlockManager()
        detector = SwipeDetector()
        block_id = "wood_5"
        now = arm(detector, blocks, block_id)
        block = blocks.get(block_id)
        assert block is not None
        events = []
        for index, y in enumerate((460, 350, 240, 130, 20, -90)):
            events.append(detector.update(Point(AUTO_SWIPE_START_X, y), now + index * 0.08, blocks, config.ONE_FINGER))
        success = next(event for event in events if event.success)
        self.assertEqual(success.state, SwipeState.BLOCK_REMOVED)
        self.assertTrue(blocks.mark_completed(block_id))
        self.assertFalse(blocks.mark_completed(block_id))

    def test_downward_and_horizontal_candidates_are_rejected_without_terminal_trial(self) -> None:
        for points, reason in (
            ((0, 45), "downward_motion"),
            ((45, 0), "horizontal_motion"),
        ):
            blocks = BlockManager()
            detector = SwipeDetector()
            now = arm(detector, blocks, "wood_5")
            block = blocks.get("wood_5")
            assert block is not None
            detector.update(Point(AUTO_SWIPE_START_X + points[0], AUTO_SWIPE_START_Y + points[1]), now, blocks, config.ONE_FINGER)
            detector.update(Point(AUTO_SWIPE_START_X + points[0], AUTO_SWIPE_START_Y + points[1]), now + 0.08, blocks, config.ONE_FINGER)
            event = detector.update(Point(AUTO_SWIPE_START_X + points[0], AUTO_SWIPE_START_Y + points[1]), now + 0.16, blocks, config.ONE_FINGER)
            self.assertTrue(event.candidate_rejected)
            self.assertFalse(event.terminal)
            self.assertEqual(event.fail_reason, reason)
            self.assertEqual(detector.state, SwipeState.TRACKING)

    def test_downward_motion_during_swipe_does_not_pull_locked_wood_down(self) -> None:
        blocks = BlockManager()
        detector = SwipeDetector()
        now = arm(detector, blocks, "wood_5")
        block = blocks.get("wood_5")
        assert block is not None
        detector.update(Point(AUTO_SWIPE_START_X, 450), now, blocks, config.ONE_FINGER)
        detector.update(Point(AUTO_SWIPE_START_X, 350), now + 0.08, blocks, config.ONE_FINGER)
        detector.update(Point(AUTO_SWIPE_START_X, 150), now + 0.16, blocks, config.ONE_FINGER)
        held_y = block.center_y
        event = detector.update(Point(AUTO_SWIPE_START_X, 450), now + 0.24, blocks, config.ONE_FINGER)
        self.assertEqual(event.state, SwipeState.SWIPING)
        self.assertEqual(block.center_y, held_y)

    def test_baseline_profile_keeps_peak_only_behavior(self) -> None:
        profile = BaselineMotionProfile()
        profile.start(500.0, 500.0, 0.0, 0.0)
        up = profile.update(400.0, 0.10)
        recovery = profile.update(440.0, 0.20)
        self.assertEqual(up.block_y, 400.0)
        self.assertEqual(recovery.block_y, 400.0)

    def test_accel_profile_is_velocity_dependent_and_capped(self) -> None:
        slow = AccelMotionProfile()
        slow.start(500.0, 500.0, 0.0, 0.0)
        slow_output = slow.update(400.0, 1.0)
        fast = AccelMotionProfile()
        fast.start(500.0, 500.0, 0.0, 0.0)
        fast_output = fast.update(400.0, 0.10)
        self.assertAlmostEqual(slow_output.gain, config.ACCEL_GAIN_MIN)
        self.assertGreater(fast_output.block_y * -1.0, slow_output.block_y * -1.0)
        self.assertLessEqual(fast_output.gain, config.ACCEL_GAIN_MAX)

    def test_momentum_keeps_moving_after_fast_upward_input(self) -> None:
        profile = MomentumMotionProfile()
        profile.start(500.0, 500.0, 0.0, 0.0)
        first = profile.update(400.0, 0.05)
        second = profile.release(0.10)
        self.assertLess(first.block_velocity_y, 0.0)
        self.assertLess(second.block_velocity_y, 0.0)
        self.assertLess(second.block_y, first.block_y)

    def test_momentum_downward_recovery_does_not_pull_block_down(self) -> None:
        profile = MomentumMotionProfile()
        profile.start(500.0, 500.0, 0.0, 0.0)
        profile.update(400.0, 0.05)
        before_recovery = profile.block_y
        recovery = profile.update(420.0, 0.10)
        self.assertLessEqual(recovery.block_y, before_recovery)

    def test_momentum_fling_continues_without_new_cursor_motion(self) -> None:
        profile = MomentumMotionProfile()
        profile.start(500.0, 500.0, 0.0, 0.0)
        launch = profile.update(440.0, 0.05)
        self.assertTrue(launch.flinging)
        now = 0.05
        for _ in range(30):
            now += 0.05
            output = profile.release(now)
        self.assertLess(output.block_y, config.REMOVE_THRESHOLD_Y)

    def test_momentum_does_not_false_fling_from_small_jitter(self) -> None:
        profile = MomentumMotionProfile()
        profile.start(500.0, 500.0, 0.0, 0.0)
        for index, cursor_y in enumerate((496.0, 501.0, 497.0, 500.0), start=1):
            output = profile.update(cursor_y, index * 0.10)
        self.assertFalse(output.flinging)

    def test_one_euro_reduces_slow_jitter_without_large_fast_swipe_lag(self) -> None:
        raw = (500.0, 505.0, 495.0, 504.0, 496.0, 503.0, 497.0)
        filter_ = OneEuroFilter(config.ONE_EURO_MIN_CUTOFF, config.ONE_EURO_BETA, config.ONE_EURO_D_CUTOFF)
        filtered = [filter_.apply(value, index * 0.10) for index, value in enumerate(raw)]
        raw_variance = sum((value - sum(raw) / len(raw)) ** 2 for value in raw) / len(raw)
        filtered_variance = sum((value - sum(filtered) / len(filtered)) ** 2 for value in filtered) / len(filtered)
        self.assertLess(filtered_variance, raw_variance)
        profile = MomentumOneEuroMotionProfile()
        profile.start(500.0, 500.0, 0.0, 0.0)
        fast = profile.update(400.0, 0.05)
        self.assertLess(fast.motion_y, 460.0)

    def test_checklist_mapping_is_separate_and_idempotent(self) -> None:
        checklist = ChecklistMapper()
        self.assertTrue(checklist.complete_for_block("wood_1"))
        self.assertFalse(checklist.complete_for_block("wood_1"))
        self.assertEqual(checklist.completed_count, 1)
        self.assertEqual(checklist.block_to_checklist["wood_1"], "item_1")

    def test_logger_writes_required_trial_and_trajectory_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            logger = TestLogger(Path(temporary_directory))
            blocks = BlockManager()
            block = blocks.get("wood_5")
            assert block is not None
            detector = SwipeDetector()
            sample = detector.update(Point(block.center_x, block.center_y), 0.0, blocks, config.ONE_FINGER)
            self.assertIsNotNone(sample.sample)
            logger.start_trial("positive", config.ONE_FINGER, "wood_5", "gesture", 0.0, config.MOTION_PROFILE_MOMENTUM)
            logger.append_sample(sample.sample)
            logger.finish_trial("success", "", 1.0, 300.0, 4.0, {"fling_triggered": True, "cursor_travel_distance": 300.0})
            with logger.trials_path.open(newline="", encoding="utf-8") as file:
                row = next(csv.DictReader(file))
            for field in ("trial_id", "finger_mode", "target_block", "start_x", "end_y", "vertical_distance", "horizontal_distance", "motion_profile", "fling_triggered"):
                self.assertIn(field, row)
            trajectory = next(logger.trajectory_dir.glob("*.csv"))
            with trajectory.open(newline="", encoding="utf-8") as file:
                trajectory_row = next(csv.DictReader(file))
            for field in ("raw_x", "raw_y", "virtual_x", "virtual_y", "motion_x", "motion_y", "finger_velocity_y", "gain", "block_velocity_y", "motion_profile", "flinging"):
                self.assertIn(field, trajectory_row)
            summary = json.loads(logger.summary_path.read_text(encoding="utf-8"))
            self.assertEqual(summary["tp"], 1)
            self.assertEqual(summary["accuracy"], 1.0)
            self.assertEqual(summary["profiles"][config.MOTION_PROFILE_MOMENTUM]["fling_count"], 1)

    def test_metrics_keep_zero_denominators_null(self) -> None:
        metrics = calculate_metrics([])
        self.assertIsNone(metrics["precision"])
        self.assertIsNone(metrics["false_positive_rate"])

    def test_full_reset_restores_all_blocks_and_checklist_items(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            app = PrototypeApp(Path(temporary_directory))
            self.assertTrue(app.complete_block("wood_5", "test"))
            app.reset_all_blocks()
            self.assertEqual(app.blocks.completed_count, 0)
            self.assertEqual(app.checklist.completed_count, 0)
            app.close()


if __name__ == "__main__":
    unittest.main()
