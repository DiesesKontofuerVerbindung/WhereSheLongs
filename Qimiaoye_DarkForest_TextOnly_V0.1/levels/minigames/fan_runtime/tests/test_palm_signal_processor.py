"""Focused behavioral checks for the independent palm signal streams."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parents[1]
if str(PROJECT_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECT_DIR))

import config
from palm_signal_processor import PalmSignalProcessor


class PalmSignalProcessorTests(unittest.TestCase):
    def make_processor(self) -> PalmSignalProcessor:
        return PalmSignalProcessor(config.SENSITIVITY_ADAPTIVE)

    def test_stationary_jitter_is_held_by_the_physics_deadzone(self) -> None:
        processor = self.make_processor()
        positions = [
            processor.update(x, 350.0, index * 0.05, True, True).physics_x
            for index, x in enumerate((500.0, 501.0, 499.0, 502.0, 500.0))
        ]
        self.assertLessEqual(max(positions) - min(positions), config.PHYSICS_DEADZONE)

    def test_slow_motion_remains_controllable(self) -> None:
        processor = self.make_processor()
        first = processor.update(500.0, 350.0, 0.0, True, True)
        last = processor.update(518.0, 350.0, 0.20, True, True)
        self.assertIsNotNone(first.physics_x)
        self.assertIsNotNone(last.physics_x)
        self.assertGreater(last.physics_x, first.physics_x)
        self.assertGreater(last.velocity_x, 0.0)

    def test_fast_motion_uses_the_high_gain_cap_without_hard_lag(self) -> None:
        processor = self.make_processor()
        processor.update(500.0, 350.0, 0.0, True, True)
        motion = processor.update(700.0, 350.0, 0.10, True, True)
        self.assertGreaterEqual(motion.physics_gain, config.PALM_X_GAIN_MAX - 1e-6)
        self.assertGreater(motion.physics_x, 650.0)

    def test_gain_increases_from_slow_to_fast_motion(self) -> None:
        processor = self.make_processor()
        processor.update(500.0, 350.0, 0.0, True, True)
        slow = processor.update(506.0, 350.0, 0.10, True, True)
        fast = processor.update(700.0, 350.0, 0.20, True, True)
        self.assertGreater(fast.physics_gain, slow.physics_gain)
        self.assertLessEqual(fast.physics_gain, config.PALM_X_GAIN_MAX)

    def test_right_then_left_motion_keeps_its_sign(self) -> None:
        processor = self.make_processor()
        processor.update(500.0, 350.0, 0.0, True, True)
        right = processor.update(620.0, 350.0, 0.10, True, True)
        left = processor.update(420.0, 350.0, 0.20, True, True)
        self.assertGreater(right.velocity_x, 0.0)
        self.assertLess(left.velocity_x, 0.0)

    def test_tracking_loss_holds_briefly_then_becomes_inactive(self) -> None:
        processor = self.make_processor()
        processor.update(500.0, 350.0, 0.0, True, True)
        held = processor.update(None, None, config.CURSOR_HOLD_TIME / 2, False, False)
        lost = processor.update(None, None, config.CURSOR_HOLD_TIME + 0.01, False, False)
        self.assertTrue(held.active)
        self.assertEqual(held.velocity_x, 0.0)
        self.assertFalse(lost.active)

    def test_physics_and_gesture_streams_have_independent_filter_state(self) -> None:
        processor = self.make_processor()
        for index, x in enumerate((500.0, 620.0, 640.0)):
            motion = processor.update(x, 350.0, index * 0.10, True, True)
        self.assertIsNot(processor._physics_x_filter, processor._gesture_x_filter)
        self.assertNotEqual(motion.physics_x, motion.gesture_x)

    def test_baseline_profile_preserves_direct_screen_mapping(self) -> None:
        processor = PalmSignalProcessor(config.SENSITIVITY_BASELINE)
        motion = processor.update(650.0, 350.0, 0.0, True, True)
        self.assertEqual(motion.physics_x, 650.0)
        self.assertEqual(motion.gesture_x, 650.0)
        self.assertEqual(motion.physics_gain, 1.0)


if __name__ == "__main__":
    unittest.main()
