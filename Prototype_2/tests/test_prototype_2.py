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
from hand_tracker import valid_finger_mode
from swipe_detector import Point, SwipeDetector
from swipe_state import SwipeState
from test_logger import TestLogger, calculate_metrics


def arm(detector: SwipeDetector, blocks: BlockManager, block_id: str, now: float = 0.0) -> float:
    block = blocks.get(block_id)
    assert block is not None
    x, y = block.center_x, block.center_y
    detector.update(Point(x, y), now, blocks, config.ONE_FINGER)
    detector.update(Point(x, y), now + 0.10, blocks, config.ONE_FINGER)
    event = detector.update(Point(x, y), now + config.BLOCK_ARM_TIME + 0.02, blocks, config.ONE_FINGER)
    assert event.state == SwipeState.BLOCK_ARMED
    return now + config.BLOCK_ARM_TIME + 0.03


class Prototype2Tests(unittest.TestCase):
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
        block = blocks.get("block_1")
        assert block is not None
        original_y = block.center_y
        event = detector.update(Point(block.center_x, block.center_y), 0.0, blocks, config.ONE_FINGER)
        self.assertEqual(event.state, SwipeState.BLOCK_HOVER)
        self.assertEqual(block.center_y, original_y)
        self.assertFalse(event.started)

    def test_one_finger_upward_swipe_completes_once(self) -> None:
        blocks = BlockManager()
        detector = SwipeDetector()
        block_id = "block_1"
        now = arm(detector, blocks, block_id)
        block = blocks.get(block_id)
        assert block is not None
        events = []
        for index, y in enumerate((block.center_y - 40, block.center_y - 140, block.center_y - 250, block.center_y - 320, block.center_y - 430, block.center_y - 540)):
            events.append(detector.update(Point(block.center_x, y), now + index * 0.08, blocks, config.ONE_FINGER))
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
            now = arm(detector, blocks, "block_1")
            block = blocks.get("block_1")
            assert block is not None
            detector.update(Point(block.center_x + points[0], block.center_y + points[1]), now, blocks, config.ONE_FINGER)
            detector.update(Point(block.center_x + points[0], block.center_y + points[1]), now + 0.08, blocks, config.ONE_FINGER)
            event = detector.update(Point(block.center_x + points[0], block.center_y + points[1]), now + 0.16, blocks, config.ONE_FINGER)
            self.assertTrue(event.candidate_rejected)
            self.assertFalse(event.terminal)
            self.assertEqual(event.fail_reason, reason)
            self.assertEqual(detector.state, SwipeState.TRACKING)

    def test_checklist_mapping_is_separate_and_idempotent(self) -> None:
        checklist = ChecklistMapper()
        self.assertTrue(checklist.complete_for_block("block_1"))
        self.assertFalse(checklist.complete_for_block("block_1"))
        self.assertEqual(checklist.completed_count, 1)
        self.assertEqual(checklist.block_to_checklist["block_1"], "item_1")

    def test_logger_writes_required_trial_and_trajectory_fields(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            logger = TestLogger(Path(temporary_directory))
            blocks = BlockManager()
            block = blocks.get("block_1")
            assert block is not None
            detector = SwipeDetector()
            sample = detector.update(Point(block.center_x, block.center_y), 0.0, blocks, config.ONE_FINGER)
            self.assertIsNotNone(sample.sample)
            logger.start_trial("positive", config.ONE_FINGER, "block_1", "gesture", 0.0)
            logger.append_sample(sample.sample)
            logger.finish_trial("success", "", 1.0, 300.0, 4.0)
            with logger.trials_path.open(newline="", encoding="utf-8") as file:
                row = next(csv.DictReader(file))
            for field in ("trial_id", "finger_mode", "target_block", "start_x", "end_y", "vertical_distance", "horizontal_distance"):
                self.assertIn(field, row)
            trajectory = next(logger.trajectory_dir.glob("*.csv"))
            with trajectory.open(newline="", encoding="utf-8") as file:
                trajectory_row = next(csv.DictReader(file))
            for field in ("raw_x", "raw_y", "smoothed_x", "smoothed_y", "finger_mode", "state", "target_block", "block_x", "block_y"):
                self.assertIn(field, trajectory_row)
            summary = json.loads(logger.summary_path.read_text(encoding="utf-8"))
            self.assertEqual(summary["tp"], 1)
            self.assertEqual(summary["accuracy"], 1.0)

    def test_metrics_keep_zero_denominators_null(self) -> None:
        metrics = calculate_metrics([])
        self.assertIsNone(metrics["precision"])
        self.assertIsNone(metrics["false_positive_rate"])


if __name__ == "__main__":
    unittest.main()
