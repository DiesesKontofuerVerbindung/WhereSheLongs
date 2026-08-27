"""Explainable continuous Open-Palm horizontal Fan Gesture detector."""

from __future__ import annotations

from dataclasses import dataclass
from math import hypot

import config
from fan_state import FanState


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class TrajectorySample:
    timestamp: float
    raw: Point
    smoothed: Point
    open_palm: bool
    state: FanState
    direction: str
    horizontal_velocity: float
    fan_strength: float
    horizontal_amplitude: float
    sweep_count: int


@dataclass(frozen=True)
class FanEvent:
    state: FanState
    palm_center: Point | None
    direction: str = "center"
    sweep_count: int = 0
    horizontal_amplitude: float = 0.0
    horizontal_velocity: float = 0.0
    fan_strength: float = 0.0
    sample: TrajectorySample | None = None
    initial_samples: tuple[TrajectorySample, ...] = ()
    started: bool = False
    completed: bool = False
    reset: bool = False
    terminal: bool = False
    fail_reason: str = ""
    high_level_event: dict[str, object] | None = None


class FanDetector:
    """Convert palm features into stable direction, sweep and strength output."""

    def __init__(self) -> None:
        self.state = FanState.TRACKING
        self.direction = "center"
        self.sweep_count = 0
        self.horizontal_amplitude = 0.0
        self.horizontal_velocity = 0.0
        self.fan_strength = 0.0
        self.anchor_x: float | None = None
        self.anchor_y: float | None = None
        self.last_fail_reason = ""
        self.last_raw_point: Point | None = None
        self.last_point: Point | None = None
        self.last_seen_at: float | None = None
        self.last_open_palm_at: float | None = None
        self._last_point_at: float | None = None
        self._arming_anchor: Point | None = None
        self._arming_started_at: float | None = None
        self._ready_at: float | None = None
        self._last_significant_motion_at: float | None = None
        self._segment_origin_x: float | None = None
        self._direction_extreme_x: float | None = None
        self._sweep_timestamps: list[float] = []
        self._completed_emitted = False
        self._prefill: list[TrajectorySample] = []
        self._path: list[Point] = []

    @property
    def trail(self) -> list[Point]:
        return self._path[-config.TRAIL_LENGTH:]

    @property
    def arming_progress(self) -> float:
        if self.state != FanState.PALM_ARMING or self._arming_started_at is None or self._last_point_at is None:
            return 0.0
        return min(1.0, max(0.0, (self._last_point_at - self._arming_started_at) / config.PALM_ARM_TIME))

    def reset(self) -> None:
        self._clear_session()
        self.last_fail_reason = ""

    def update(self, raw_point: Point | None, open_palm: bool, now: float) -> FanEvent:
        if raw_point is None:
            if (
                self.state != FanState.TRACKING
                and self.last_seen_at is not None
                and now - self.last_seen_at > config.MAX_MISSING_HAND_TIME
            ):
                return self._reset_event("hand_lost", now, terminal=self.state in {FanState.FAN_READY, FanState.FANNING})
            return self._event()

        previous_point = self.last_point
        previous_time = self._last_point_at
        self.last_seen_at = now
        self.last_raw_point = raw_point
        smoothed = self._smooth(raw_point)
        self.last_point = smoothed
        self._last_point_at = now
        self._path.append(smoothed)
        self._path = self._path[-config.TRAIL_LENGTH:]

        if previous_point is not None and previous_time is not None:
            delta_time = max(1e-6, now - previous_time)
            instantaneous_velocity = (smoothed.x - previous_point.x) / delta_time
            factor = config.VELOCITY_SMOOTHING_FACTOR
            self.horizontal_velocity += factor * (instantaneous_velocity - self.horizontal_velocity)
            if abs(smoothed.x - previous_point.x) >= config.JITTER_DEADZONE:
                self._last_significant_motion_at = now
        else:
            self.horizontal_velocity = 0.0

        if open_palm:
            self.last_open_palm_at = now
        elif self.state != FanState.TRACKING and (
            self.last_open_palm_at is None or now - self.last_open_palm_at > config.OPEN_PALM_GRACE_TIME
        ):
            return self._reset_event("open_palm_lost", now, terminal=self.state in {FanState.FAN_READY, FanState.FANNING})
        elif self.state != FanState.TRACKING and not open_palm:
            sample = self._sample(now, False)
            return self._event(sample=sample)

        started = False
        completed = False
        initial_samples: tuple[TrajectorySample, ...] = ()

        if self.state == FanState.TRACKING:
            if not open_palm:
                return self._event()
            self.state = FanState.PALM_ARMING
            self._arming_anchor = smoothed
            self._arming_started_at = now
            self._prefill.clear()

        elif self.state == FanState.PALM_ARMING:
            if self._arming_anchor is None or self._arming_started_at is None:
                self._arming_anchor = smoothed
                self._arming_started_at = now
            elif hypot(smoothed.x - self._arming_anchor.x, smoothed.y - self._arming_anchor.y) > config.PALM_ARM_MAX_DRIFT:
                self._arming_anchor = smoothed
                self._arming_started_at = now
                self._prefill.clear()
            elif now - self._arming_started_at >= config.PALM_ARM_TIME:
                self.state = FanState.FAN_READY
                self.anchor_x = smoothed.x
                self.anchor_y = smoothed.y
                self._segment_origin_x = smoothed.x
                self._direction_extreme_x = smoothed.x
                self._ready_at = now
                self._last_significant_motion_at = now
                started = True
                initial_samples = tuple(self._prefill[-config.TRAJECTORY_PREFILL_POINTS:])

        elif self.state == FanState.FAN_READY:
            if self._vertical_drift(smoothed) > config.MAX_VERTICAL_DRIFT:
                return self._reset_event("vertical_drift", now, terminal=True)
            if self._ready_at is not None and now - self._ready_at > config.FAN_IDLE_TIMEOUT:
                return self._reset_event("no_horizontal_motion", now, terminal=True)
            displacement = smoothed.x - (self.anchor_x if self.anchor_x is not None else smoothed.x)
            if abs(displacement) >= config.FAN_START_DISTANCE:
                self.state = FanState.FANNING
                self.direction = "right" if displacement > 0 else "left"
                self._segment_origin_x = self.anchor_x
                self._direction_extreme_x = smoothed.x
                self.horizontal_amplitude = abs(displacement)
                self._last_significant_motion_at = now

        elif self.state == FanState.FANNING:
            if self._vertical_drift(smoothed) > config.MAX_VERTICAL_DRIFT:
                return self._reset_event("vertical_drift", now, terminal=True)
            if (
                self._last_significant_motion_at is not None
                and now - self._last_significant_motion_at > config.FAN_IDLE_TIMEOUT
            ):
                return self._reset_event("no_horizontal_motion", now, terminal=True)
            self._update_sweeps(smoothed, now)
            completed = self.sweep_count >= config.MIN_SWEEPS_FOR_SUCCESS and not self._completed_emitted
            if completed:
                self._completed_emitted = True

        self.fan_strength = self._calculate_strength(now)
        sample = self._sample(now, open_palm)
        if self.state in {FanState.PALM_ARMING, FanState.FAN_READY} and not started:
            self._prefill.append(sample)
            self._prefill = self._prefill[-config.TRAJECTORY_PREFILL_POINTS:]
        return self._event(sample=sample, initial_samples=initial_samples, started=started, completed=completed)

    def _update_sweeps(self, point: Point, now: float) -> None:
        if self._segment_origin_x is None:
            self._segment_origin_x = point.x
        if self._direction_extreme_x is None:
            self._direction_extreme_x = point.x

        if self.direction == "right":
            self._direction_extreme_x = max(self._direction_extreme_x, point.x)
            segment_amplitude = self._direction_extreme_x - self._segment_origin_x
            opposite_distance = self._direction_extreme_x - point.x
            self.horizontal_amplitude = max(0.0, segment_amplitude)
            if (
                segment_amplitude >= config.MIN_HORIZONTAL_AMPLITUDE
                and opposite_distance >= max(config.DIRECTION_HYSTERESIS, config.MIN_DIRECTION_DISTANCE)
            ):
                self._accept_reversal("left", self._direction_extreme_x, point.x, segment_amplitude, now)
        elif self.direction == "left":
            self._direction_extreme_x = min(self._direction_extreme_x, point.x)
            segment_amplitude = self._segment_origin_x - self._direction_extreme_x
            opposite_distance = point.x - self._direction_extreme_x
            self.horizontal_amplitude = max(0.0, segment_amplitude)
            if (
                segment_amplitude >= config.MIN_HORIZONTAL_AMPLITUDE
                and opposite_distance >= max(config.DIRECTION_HYSTERESIS, config.MIN_DIRECTION_DISTANCE)
            ):
                self._accept_reversal("right", self._direction_extreme_x, point.x, segment_amplitude, now)

    def _accept_reversal(self, direction: str, old_extreme: float, current_x: float, amplitude: float, now: float) -> None:
        self.sweep_count += 1
        self._sweep_timestamps.append(now)
        self.direction = direction
        self._segment_origin_x = old_extreme
        self._direction_extreme_x = current_x
        self.horizontal_amplitude = max(amplitude, abs(current_x - old_extreme))
        self._last_significant_motion_at = now

    def _calculate_strength(self, now: float) -> float:
        cutoff = now - config.RECENT_SWEEP_WINDOW
        self._sweep_timestamps = [timestamp for timestamp in self._sweep_timestamps if timestamp >= cutoff]
        frequency = len(self._sweep_timestamps) / config.RECENT_SWEEP_WINDOW
        velocity_component = min(1.0, abs(self.horizontal_velocity) / config.STRENGTH_VELOCITY_REFERENCE)
        amplitude_component = min(1.0, self.horizontal_amplitude / config.STRENGTH_AMPLITUDE_REFERENCE)
        frequency_component = min(1.0, frequency / config.STRENGTH_FREQUENCY_REFERENCE)
        return round(0.50 * velocity_component + 0.30 * amplitude_component + 0.20 * frequency_component, 4)

    def _vertical_drift(self, point: Point) -> float:
        return 0.0 if self.anchor_y is None else abs(point.y - self.anchor_y)

    def _smooth(self, point: Point) -> Point:
        if self.last_point is None:
            return point
        factor = config.SMOOTHING_FACTOR
        return Point(
            self.last_point.x + factor * (point.x - self.last_point.x),
            self.last_point.y + factor * (point.y - self.last_point.y),
        )

    def _sample(self, now: float, open_palm: bool) -> TrajectorySample:
        point = self.last_point or self.last_raw_point or Point(0.0, 0.0)
        return TrajectorySample(
            now,
            self.last_raw_point or point,
            point,
            open_palm,
            self.state,
            self.direction,
            self.horizontal_velocity,
            self.fan_strength,
            self.horizontal_amplitude,
            self.sweep_count,
        )

    def _event(
        self,
        sample: TrajectorySample | None = None,
        initial_samples: tuple[TrajectorySample, ...] = (),
        started: bool = False,
        completed: bool = False,
    ) -> FanEvent:
        payload = None
        if self.state in {FanState.FAN_READY, FanState.FANNING}:
            payload = {
                "event": "fan_update",
                "strength": self.fan_strength,
                "direction": self.direction,
                "sweep_count": self.sweep_count,
            }
        return FanEvent(
            self.state,
            self.last_point,
            self.direction,
            self.sweep_count,
            self.horizontal_amplitude,
            self.horizontal_velocity,
            self.fan_strength,
            sample,
            initial_samples,
            started,
            completed,
            high_level_event=payload,
        )

    def _reset_event(self, reason: str, now: float, terminal: bool) -> FanEvent:
        sample = None if self.last_point is None else self._sample(now, False)
        event = FanEvent(
            FanState.TRACKING,
            self.last_point,
            self.direction,
            self.sweep_count,
            self.horizontal_amplitude,
            self.horizontal_velocity,
            self.fan_strength,
            sample=sample,
            reset=True,
            terminal=terminal,
            fail_reason=reason,
        )
        self._clear_session()
        self.last_fail_reason = reason
        return event

    def _clear_session(self) -> None:
        self.state = FanState.TRACKING
        self.direction = "center"
        self.sweep_count = 0
        self.horizontal_amplitude = 0.0
        self.horizontal_velocity = 0.0
        self.fan_strength = 0.0
        self.anchor_x = None
        self.anchor_y = None
        self.last_raw_point = None
        self.last_point = None
        self.last_seen_at = None
        self.last_open_palm_at = None
        self._last_point_at = None
        self._arming_anchor = None
        self._arming_started_at = None
        self._ready_at = None
        self._last_significant_motion_at = None
        self._segment_origin_x = None
        self._direction_extreme_x = None
        self._sweep_timestamps.clear()
        self._completed_emitted = False
        self._prefill.clear()
        self._path.clear()
