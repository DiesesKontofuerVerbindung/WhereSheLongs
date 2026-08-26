"""Motion-only A/B/C/D profiles used after gesture recognition has started a swipe."""

from __future__ import annotations

from dataclasses import dataclass
import math

import config
from one_euro_filter import OneEuroFilter


@dataclass(frozen=True)
class MotionOutput:
    target_y: float
    block_y: float
    block_velocity_y: float | None
    finger_velocity_y: float
    gain: float
    flinging: bool
    motion_y: float


class MotionProfile:
    """Common lifecycle for motion profiles; all positions are virtual pixels."""

    name = ""

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self.block_y = 0.0
        self.initial_block_y = 0.0
        self.target_y = 0.0
        self.block_velocity_y: float | None = None
        self.previous_motion_y: float | None = None
        self.previous_raw_y: float | None = None
        self.previous_time: float | None = None
        self.start_cursor_y: float | None = None
        self.peak_cursor_y: float | None = None
        self.cursor_travel_distance = 0.0
        self.peak_finger_up_speed = 0.0
        self.peak_block_up_speed = 0.0
        self.flinging = False
        self.fling_triggered = False
        self._last_output: MotionOutput | None = None

    def start(self, block_y: float, cursor_y: float, now: float, block_offset_y: float) -> MotionOutput:
        self.reset()
        self.block_y = block_y
        self.initial_block_y = block_y
        self.target_y = block_y
        self.block_offset_y = block_offset_y
        self.previous_motion_y = cursor_y
        self.previous_raw_y = cursor_y
        self.previous_time = now
        self.start_cursor_y = cursor_y
        self.peak_cursor_y = cursor_y
        self._last_output = self._output(cursor_y, 0.0, 1.0)
        return self._last_output

    @property
    def output(self) -> MotionOutput | None:
        return self._last_output

    @property
    def vertical_distance(self) -> float:
        if self.start_cursor_y is None or self.peak_cursor_y is None:
            return 0.0
        return self.start_cursor_y - self.peak_cursor_y

    def update(self, cursor_y: float, now: float) -> MotionOutput:
        if self.previous_time is None:
            return self.start(self.block_y, cursor_y, now, getattr(self, "block_offset_y", 0.0))
        elapsed = max(1e-4, now - self.previous_time)
        dt = min(config.MOTION_MAX_DT, elapsed)
        motion_y = self._motion_y(cursor_y, now)
        previous_motion_y = self.previous_motion_y if self.previous_motion_y is not None else motion_y
        previous_raw_y = self.previous_raw_y if self.previous_raw_y is not None else cursor_y
        delta_y = motion_y - previous_motion_y
        # Measure cursor speed over the real sample interval. Only the physics
        # integration is capped, so a slow camera frame is not mislabeled fast.
        finger_velocity_y = delta_y / elapsed
        self.cursor_travel_distance += abs(cursor_y - previous_raw_y)
        self.peak_cursor_y = min(self.peak_cursor_y if self.peak_cursor_y is not None else motion_y, motion_y)
        self.peak_finger_up_speed = max(self.peak_finger_up_speed, max(0.0, -finger_velocity_y))
        self.previous_motion_y = motion_y
        self.previous_raw_y = cursor_y
        self.previous_time = now
        self._last_output = self._update_motion(motion_y, delta_y, finger_velocity_y, dt)
        return self._last_output

    def release(self, now: float) -> MotionOutput:
        motion_y = self.previous_motion_y if self.previous_motion_y is not None else 0.0
        return self.update(motion_y, now)

    def _motion_y(self, cursor_y: float, now: float) -> float:
        return cursor_y

    def _update_motion(self, motion_y: float, delta_y: float, finger_velocity_y: float, dt: float) -> MotionOutput:
        raise NotImplementedError

    def _output(self, motion_y: float, finger_velocity_y: float, gain: float) -> MotionOutput:
        block_speed = self.block_velocity_y
        if block_speed is not None:
            self.peak_block_up_speed = max(self.peak_block_up_speed, max(0.0, -block_speed))
        return MotionOutput(
            target_y=self.target_y,
            block_y=self.block_y,
            block_velocity_y=block_speed,
            finger_velocity_y=finger_velocity_y,
            gain=gain,
            flinging=self.flinging,
            motion_y=motion_y,
        )


class BaselineMotionProfile(MotionProfile):
    name = config.MOTION_PROFILE_BASELINE

    def __init__(self) -> None:
        super().__init__()
        self.block_peak_y: float | None = None

    def start(self, block_y: float, cursor_y: float, now: float, block_offset_y: float) -> MotionOutput:
        output = super().start(block_y, cursor_y, now, block_offset_y)
        self.block_peak_y = cursor_y
        return output

    def _update_motion(self, motion_y: float, _delta_y: float, finger_velocity_y: float, _dt: float) -> MotionOutput:
        if self.block_peak_y is None or motion_y < self.block_peak_y:
            self.block_peak_y = motion_y
            self.block_y = self.block_peak_y + self.block_offset_y
            self.target_y = self.block_y
        return self._output(motion_y, finger_velocity_y, 1.0)


class AccelMotionProfile(MotionProfile):
    name = config.MOTION_PROFILE_ACCEL

    def _update_motion(self, motion_y: float, delta_y: float, finger_velocity_y: float, dt: float) -> MotionOutput:
        up_speed = max(0.0, -finger_velocity_y)
        span = max(1e-6, config.ACCEL_SPEED_HIGH - config.ACCEL_SPEED_LOW)
        progress = max(0.0, min(1.0, (up_speed - config.ACCEL_SPEED_LOW) / span))
        gain = config.ACCEL_GAIN_MIN + progress * (config.ACCEL_GAIN_MAX - config.ACCEL_GAIN_MIN)
        if delta_y < 0.0:
            movement = delta_y * gain
            self.block_y += movement
            self.target_y = self.block_y
            self.block_velocity_y = movement / dt
        else:
            self.block_velocity_y = 0.0
        return self._output(motion_y, finger_velocity_y, gain)


class MomentumMotionProfile(MotionProfile):
    name = config.MOTION_PROFILE_MOMENTUM

    def start(self, block_y: float, cursor_y: float, now: float, block_offset_y: float) -> MotionOutput:
        output = super().start(block_y, cursor_y, now, block_offset_y)
        self.block_velocity_y = 0.0
        self._last_output = self._output(cursor_y, 0.0, 1.0)
        return self._last_output

    def _update_motion(self, motion_y: float, delta_y: float, finger_velocity_y: float, dt: float) -> MotionOutput:
        if delta_y < 0.0:
            self.target_y += delta_y
        if not self.flinging and (
            max(0.0, -finger_velocity_y) >= config.FLING_VELOCITY_THRESHOLD
            and self.vertical_distance >= config.FLING_MIN_DISTANCE
        ):
            self.flinging = True
            self.fling_triggered = True
            current_velocity = self.block_velocity_y or 0.0
            launch_velocity = -max(config.FLING_VELOCITY_THRESHOLD, max(0.0, -finger_velocity_y) * 0.85)
            self.block_velocity_y = min(current_velocity, launch_velocity)
        if self.flinging:
            self.block_velocity_y = (self.block_velocity_y or 0.0) * math.exp(-config.FLING_DRAG * dt)
            self.block_y += self.block_velocity_y * dt
        else:
            velocity = self.block_velocity_y or 0.0
            error = self.target_y - self.block_y
            acceleration = config.SPRING_K * error - config.SPRING_DAMPING * velocity
            if finger_velocity_y < 0.0:
                acceleration += finger_velocity_y * config.MOMENTUM_VELOCITY_ASSIST
            velocity += acceleration * dt
            velocity = max(-config.MAX_BLOCK_SPEED, min(0.0, velocity))
            self.block_velocity_y = velocity
            self.block_y += velocity * dt
        return self._output(motion_y, finger_velocity_y, 1.0)


class MomentumOneEuroMotionProfile(MomentumMotionProfile):
    name = config.MOTION_PROFILE_MOMENTUM_1EURO

    def __init__(self) -> None:
        self.filter = OneEuroFilter(
            config.ONE_EURO_MIN_CUTOFF,
            config.ONE_EURO_BETA,
            config.ONE_EURO_D_CUTOFF,
        )
        super().__init__()

    def reset(self) -> None:
        self.filter.reset()
        super().reset()

    def _motion_y(self, cursor_y: float, now: float) -> float:
        return self.filter.apply(cursor_y, now)


def create_motion_profile(name: str) -> MotionProfile:
    profiles: dict[str, type[MotionProfile]] = {
        config.MOTION_PROFILE_BASELINE: BaselineMotionProfile,
        config.MOTION_PROFILE_ACCEL: AccelMotionProfile,
        config.MOTION_PROFILE_MOMENTUM: MomentumMotionProfile,
        config.MOTION_PROFILE_MOMENTUM_1EURO: MomentumOneEuroMotionProfile,
    }
    try:
        return profiles[name]()
    except KeyError as exc:
        raise ValueError(f"Unknown motion profile: {name}") from exc
