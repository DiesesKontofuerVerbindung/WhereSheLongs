"""Dual low-latency physics and conservative gesture palm signal streams."""

from __future__ import annotations

from dataclasses import dataclass

import config
from one_euro_filter import OneEuroFilter


@dataclass(frozen=True)
class PalmMotion:
    raw_x: float | None
    raw_y: float | None
    physics_x: float | None
    physics_y: float | None
    gesture_x: float | None
    gesture_y: float | None
    velocity_x: float
    velocity_y: float
    speed: float
    physics_gain: float
    raw_delta_x: float
    physics_delta_x: float
    open_palm: bool
    hand_detected: bool
    active: bool


class PalmSignalProcessor:
    """Keep interaction input independent from Fan gesture recognition input."""

    def __init__(self, profile: str = config.DEFAULT_SENSITIVITY_PROFILE) -> None:
        self.profile = profile
        self._physics_x_filter = OneEuroFilter(
            config.PHYSICS_ONE_EURO_MIN_CUTOFF,
            config.PHYSICS_ONE_EURO_BETA,
            config.PHYSICS_ONE_EURO_D_CUTOFF,
        )
        self._physics_y_filter = OneEuroFilter(
            config.PHYSICS_ONE_EURO_MIN_CUTOFF,
            config.PHYSICS_ONE_EURO_BETA,
            config.PHYSICS_ONE_EURO_D_CUTOFF,
        )
        self._gesture_x_filter = OneEuroFilter(
            config.GESTURE_ONE_EURO_MIN_CUTOFF,
            config.GESTURE_ONE_EURO_BETA,
            config.GESTURE_ONE_EURO_D_CUTOFF,
        )
        self._gesture_y_filter = OneEuroFilter(
            config.GESTURE_ONE_EURO_MIN_CUTOFF,
            config.GESTURE_ONE_EURO_BETA,
            config.GESTURE_ONE_EURO_D_CUTOFF,
        )
        self._last_raw_x: float | None = None
        self._last_physics_x: float | None = None
        self._last_physics_y: float | None = None
        self._last_timestamp: float | None = None
        self._last_valid_at: float | None = None
        self._last_motion = PalmMotion(
            None, None, None, None, None, None, 0.0, 0.0, 0.0,
            config.PALM_X_GAIN_BASE, 0.0, 0.0, False, False, False,
        )

    def set_profile(self, profile: str) -> None:
        if profile not in {config.SENSITIVITY_BASELINE, config.SENSITIVITY_ADAPTIVE}:
            raise ValueError(f"Unknown sensitivity profile: {profile}")
        if profile != self.profile:
            self.profile = profile
            self.reset()

    def reset(self) -> None:
        self._physics_x_filter.reset()
        self._physics_y_filter.reset()
        self._gesture_x_filter.reset()
        self._gesture_y_filter.reset()
        self._last_raw_x = None
        self._last_physics_x = None
        self._last_physics_y = None
        self._last_timestamp = None
        self._last_valid_at = None
        self._last_motion = PalmMotion(
            None, None, None, None, None, None, 0.0, 0.0, 0.0,
            config.PALM_X_GAIN_BASE, 0.0, 0.0, False, False, False,
        )

    def update(
        self,
        raw_x: float | None,
        raw_y: float | None,
        timestamp: float,
        open_palm: bool,
        hand_detected: bool,
    ) -> PalmMotion:
        timestamp = float(timestamp)
        if raw_x is None or raw_y is None:
            return self._handle_loss(timestamp, open_palm, hand_detected)
        raw_x = float(raw_x)
        raw_y = float(raw_y)
        delta_time = self._safe_delta_time(timestamp)
        raw_delta_x = 0.0 if self._last_raw_x is None else raw_x - self._last_raw_x
        if self.profile == config.SENSITIVITY_ADAPTIVE:
            filtered_physics_x = self._physics_x_filter.filter(raw_x, timestamp)
            filtered_physics_y = self._physics_y_filter.filter(raw_y, timestamp)
            gesture_x = self._gesture_x_filter.filter(raw_x, timestamp)
            gesture_y = self._gesture_y_filter.filter(raw_y, timestamp)
        else:
            filtered_physics_x = raw_x
            filtered_physics_y = raw_y
            gesture_x = raw_x
            gesture_y = raw_y
        provisional_delta_x = (
            0.0 if self._last_physics_x is None else filtered_physics_x - self._last_physics_x
        )
        provisional_velocity = provisional_delta_x / delta_time
        gain = (
            self._adaptive_gain(provisional_velocity)
            if self.profile == config.SENSITIVITY_ADAPTIVE
            else 1.0
        )
        physics_x = _clamp(
            config.WINDOW_WIDTH / 2
            + (filtered_physics_x - config.WINDOW_WIDTH / 2) * gain,
            0.0,
            float(config.WINDOW_WIDTH - 1),
        )
        physics_y = _clamp(filtered_physics_y * config.PALM_Y_GAIN, 0.0, float(config.WINDOW_HEIGHT - 1))
        physics_delta_x = 0.0 if self._last_physics_x is None else physics_x - self._last_physics_x
        physics_delta_y = 0.0 if self._last_physics_y is None else physics_y - self._last_physics_y
        if abs(physics_delta_x) < config.PHYSICS_DEADZONE:
            physics_x = self._last_physics_x if self._last_physics_x is not None else physics_x
            physics_delta_x = 0.0
        velocity_x = physics_delta_x / delta_time
        velocity_y = physics_delta_y / delta_time
        motion = PalmMotion(
            raw_x,
            raw_y,
            physics_x,
            physics_y,
            gesture_x,
            gesture_y,
            velocity_x,
            velocity_y,
            (velocity_x * velocity_x + velocity_y * velocity_y) ** 0.5,
            gain,
            raw_delta_x,
            physics_delta_x,
            bool(open_palm),
            bool(hand_detected),
            True,
        )
        self._last_raw_x = raw_x
        self._last_physics_x = physics_x
        self._last_physics_y = physics_y
        self._last_timestamp = timestamp
        self._last_valid_at = timestamp
        self._last_motion = motion
        return motion

    def _handle_loss(self, timestamp: float, open_palm: bool, hand_detected: bool) -> PalmMotion:
        if (
            self._last_valid_at is not None
            and timestamp - self._last_valid_at <= config.CURSOR_HOLD_TIME
            and self._last_motion.physics_x is not None
        ):
            held = PalmMotion(
                self._last_motion.raw_x,
                self._last_motion.raw_y,
                self._last_motion.physics_x,
                self._last_motion.physics_y,
                self._last_motion.gesture_x,
                self._last_motion.gesture_y,
                0.0,
                0.0,
                0.0,
                self._last_motion.physics_gain,
                0.0,
                0.0,
                bool(open_palm),
                bool(hand_detected),
                True,
            )
            self._last_motion = held
            self._last_timestamp = timestamp
            return held
        inactive = PalmMotion(
            None, None, None, None, None, None, 0.0, 0.0, 0.0,
            config.PALM_X_GAIN_BASE, 0.0, 0.0, bool(open_palm), bool(hand_detected), False,
        )
        self._last_motion = inactive
        self._last_timestamp = timestamp
        return inactive

    def _safe_delta_time(self, timestamp: float) -> float:
        if self._last_timestamp is None:
            return 1.0 / config.CAMERA_TARGET_FPS
        delta_time = timestamp - self._last_timestamp
        return min(0.25, max(1.0 / 240.0, delta_time))

    @staticmethod
    def _adaptive_gain(velocity_x: float) -> float:
        speed = abs(velocity_x)
        span = max(1e-6, config.PALM_GAIN_SPEED_HIGH - config.PALM_GAIN_SPEED_LOW)
        fraction = _clamp((speed - config.PALM_GAIN_SPEED_LOW) / span, 0.0, 1.0)
        return config.PALM_X_GAIN_BASE + fraction * (config.PALM_X_GAIN_MAX - config.PALM_X_GAIN_BASE)


def _clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))
