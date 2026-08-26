"""Online check-mark recognition with explicit arming and gesture segmentation."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from math import hypot
from typing import Iterable, Optional

import config
from gesture_state import GesturePhase, GestureState


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class TrajectorySample:
    timestamp: float
    raw: Point
    smoothed: Point
    phase: GesturePhase


@dataclass(frozen=True)
class _CandidateSample:
    timestamp: float
    raw: Point
    smoothed: Point


@dataclass(frozen=True)
class GestureResult:
    state: GestureState
    phase: GesturePhase
    checked: bool = False
    started: bool = False
    terminal: bool = False
    candidate_rejected: bool = False
    fail_reason: str = ""
    sample: TrajectorySample | None = None
    initial_samples: tuple[TrajectorySample, ...] = ()


class GestureDetector:
    """Separates hover/entry motion from a deliberate, logged drawing attempt."""

    def __init__(
        self,
        center: tuple[int, int] = config.CHECK_CENTER,
        arm_radius: float = config.ARM_RADIUS,
        tracking_radius: float = config.TRACKING_RADIUS,
    ) -> None:
        self.center = Point(float(center[0]), float(center[1]))
        self.arm_radius = arm_radius
        self.tracking_radius = tracking_radius
        self.points: list[Point] = []
        self.samples: list[TrajectorySample] = []
        self.state = GestureState.IDLE
        self.phase = GesturePhase.IDLE
        self.started_at: Optional[float] = None
        self.last_seen_at: Optional[float] = None
        self.arming_started_at: Optional[float] = None
        self._arming_last_point: Optional[Point] = None
        self._arming_last_time: Optional[float] = None
        self._candidate_buffer: deque[_CandidateSample] = deque()
        self._last_candidate_reject_at: Optional[float] = None
        self.last_candidate_reject_reason = ""
        self._last_smoothed: Optional[Point] = None
        self._terminal_reason = ""
        self._failed_at: Optional[float] = None

    @property
    def trail(self) -> list[Point]:
        return self.points[-config.MAX_TRAIL_POINTS :]

    @property
    def active(self) -> bool:
        return self.state == GestureState.DRAWING and self.started_at is not None

    @property
    def candidate_points(self) -> int:
        return len(self._candidate_buffer)

    @property
    def ready_to_draw(self) -> bool:
        return self.state == GestureState.ARMED

    @property
    def progress(self) -> int:
        return {
            GesturePhase.STARTED: 0,
            GesturePhase.DOWNSTROKE_OK: 1,
            GesturePhase.TURN_OK: 2,
            GesturePhase.UPSTROKE_OK: 3,
            GesturePhase.SUCCESS: 3,
        }.get(self.phase, 0)

    def arming_progress(self, now: float) -> float:
        if self.state == GestureState.ARMED:
            return 1.0
        if self.state != GestureState.ARMING or self.arming_started_at is None:
            return 0.0
        return min(1.0, max(0.0, (now - self.arming_started_at) / config.ARM_HOLD_TIME))

    def draw_time(self, now: float) -> float:
        return 0.0 if self.started_at is None else max(0.0, now - self.started_at)

    def reset(self) -> None:
        self._clear_drawing()
        self._candidate_buffer.clear()
        self.state = GestureState.IDLE
        self.phase = GesturePhase.IDLE
        self.last_seen_at = None
        self.arming_started_at = None
        self._arming_last_point = None
        self._arming_last_time = None
        self._last_candidate_reject_at = None
        self.last_candidate_reject_reason = ""
        self._terminal_reason = ""
        self._failed_at = None

    def mark_checked(self) -> None:
        self.state = GestureState.CHECKED
        self.phase = GesturePhase.SUCCESS

    def update(self, raw_point: Optional[Point], now: float) -> GestureResult:
        """Advance segmentation or recognition using one optional fingertip point."""

        if self.state == GestureState.CHECKED:
            return GestureResult(self.state, self.phase, checked=True)
        if self.state == GestureState.FAILED:
            return self._after_failure(raw_point, now)

        if raw_point is None:
            return self._handle_missing_hand(now)

        distance_from_center = _distance(raw_point, self.center)
        if self.state in {GestureState.IDLE, GestureState.TRACKING}:
            return self._update_tracking(raw_point, distance_from_center, now)
        if self.state == GestureState.ARMING:
            return self._update_arming(raw_point, distance_from_center, now)
        if self.state == GestureState.ARMED:
            return self._update_armed(raw_point, distance_from_center, now)
        return self._update_drawing(raw_point, distance_from_center, now)

    def _update_tracking(self, point: Point, distance_from_center: float, now: float) -> GestureResult:
        if distance_from_center <= self.arm_radius:
            self.state = GestureState.ARMING
            self.phase = GesturePhase.ARMING
            self.arming_started_at = now
            self._arming_last_point = point
            self._arming_last_time = now
            self._last_smoothed = point
            return GestureResult(self.state, self.phase)
        self.state = GestureState.TRACKING
        self.phase = GesturePhase.TRACKING
        return GestureResult(self.state, self.phase)

    def _update_arming(self, point: Point, distance_from_center: float, now: float) -> GestureResult:
        if distance_from_center > self.arm_radius:
            self._return_to_tracking()
            return GestureResult(self.state, self.phase)

        speed = self._arming_speed(point, now)
        self._arming_last_point = point
        self._arming_last_time = now
        if speed > config.ARM_MAX_SPEED:
            self.arming_started_at = now
            return GestureResult(self.state, self.phase)

        if self.arming_started_at is not None and now - self.arming_started_at >= config.ARM_HOLD_TIME:
            self._enter_armed(point)
        return GestureResult(self.state, self.phase)

    def _update_armed(self, raw_point: Point, distance_from_center: float, now: float) -> GestureResult:
        if distance_from_center > self.tracking_radius:
            self._return_to_tracking()
            return GestureResult(self.state, self.phase)
        if self._last_candidate_reject_at is not None:
            if now - self._last_candidate_reject_at < config.CANDIDATE_REARM_DELAY:
                return GestureResult(self.state, self.phase)

        # Candidate motion must start from the real armed position. Carrying the
        # hover smoother into this buffer delays the apparent downstroke.
        smoothed = raw_point if not self._candidate_buffer else self._smooth(raw_point)
        self._last_smoothed = smoothed
        self._candidate_buffer.append(_CandidateSample(now, raw_point, smoothed))
        self._trim_candidate_buffer(now)
        start_index = self._candidate_valid_start_index()
        if start_index is None:
            return GestureResult(self.state, self.phase)
        return self._begin_drawing_from_candidate(start_index, now)

    def _update_drawing(self, raw_point: Point, distance_from_center: float, now: float) -> GestureResult:
        self.last_seen_at = now
        if distance_from_center > self.tracking_radius:
            return self._fail("left_tracking_zone", now)
        if self.draw_time(now) > config.MAX_DRAW_TIME:
            return self._fail("draw_timeout", now)

        smoothed = self._smooth(raw_point)
        self._last_smoothed = smoothed
        if _distance(smoothed, self.points[-1]) >= config.MIN_POINT_DISTANCE:
            self.points.append(smoothed)
        terminal = self._advance_phase(now)
        if terminal is not None and terminal.candidate_rejected:
            return terminal
        sample = TrajectorySample(self.draw_time(now), raw_point, smoothed, self.phase)
        self.samples.append(sample)
        if terminal is not None:
            return GestureResult(
                self.state,
                self.phase,
                checked=self.state == GestureState.CHECKED,
                terminal=terminal.terminal,
                candidate_rejected=terminal.candidate_rejected,
                fail_reason=terminal.fail_reason,
                sample=sample if not terminal.candidate_rejected else None,
            )
        return GestureResult(self.state, self.phase, sample=sample)

    def _handle_missing_hand(self, now: float) -> GestureResult:
        if self.active and self.last_seen_at is not None:
            if now - self.last_seen_at > config.MAX_MISSING_HAND_TIME:
                if self.phase == GesturePhase.UPSTROKE_OK and self._is_check_mark(self.points):
                    return self._succeed()
                return self._fail("hand_lost", now)
            return GestureResult(self.state, self.phase)
        if self.state in {GestureState.ARMING, GestureState.ARMED, GestureState.TRACKING}:
            self._return_to_idle()
        return GestureResult(self.state, self.phase)

    def _arming_speed(self, point: Point, now: float) -> float:
        if self._arming_last_point is None or self._arming_last_time is None:
            return 0.0
        elapsed = now - self._arming_last_time
        return 0.0 if elapsed <= 0 else _distance(point, self._arming_last_point) / elapsed

    def _enter_armed(self, point: Point) -> None:
        self.state = GestureState.ARMED
        self.phase = GesturePhase.ARMED
        self.arming_started_at = None
        self._candidate_buffer.clear()
        self._last_smoothed = point

    def _candidate_valid_start_index(self) -> int | None:
        candidates = list(self._candidate_buffer)
        if len(candidates) < config.START_MIN_POINTS:
            return None
        current = candidates[-1].raw
        for index in range(0, len(candidates) - config.START_MIN_POINTS + 1):
            segment = candidates[index:]
            start = segment[0].raw
            points = [candidate.smoothed for candidate in segment]
            if (
                current.y - start.y >= config.START_DOWN_DISTANCE
                and current.x - start.x >= config.START_RIGHT_DISTANCE
                and _trend_ratio(points, "down") >= config.MIN_TREND_RATIO
                and _rightward_trend_ratio(points) >= config.MIN_TREND_RATIO
            ):
                return index
        return None

    def _begin_drawing_from_candidate(self, start_index: int, now: float) -> GestureResult:
        candidates = list(self._candidate_buffer)[start_index:]
        start_time = candidates[0].timestamp
        self.points = _filter_points([candidate.smoothed for candidate in candidates])
        self.samples = [
            TrajectorySample(
                timestamp=candidate.timestamp - start_time,
                raw=candidate.raw,
                smoothed=candidate.smoothed,
                phase=GesturePhase.STARTED,
            )
            for candidate in candidates
        ]
        self.started_at = start_time
        self.last_seen_at = now
        self.state = GestureState.DRAWING
        self.phase = GesturePhase.STARTED
        self._candidate_buffer.clear()
        return GestureResult(
            self.state,
            self.phase,
            started=True,
            initial_samples=tuple(self.samples),
        )

    def _advance_phase(self, now: float) -> GestureResult | None:
        if self.phase == GesturePhase.STARTED:
            if self._downstroke_valid():
                self.phase = GesturePhase.DOWNSTROKE_OK
            elif self._clearly_invalid_downstroke():
                return self._reject_candidate("invalid_downstroke", now)
            return None

        if self.phase == GesturePhase.DOWNSTROKE_OK:
            if self._turn_valid():
                self.phase = GesturePhase.TURN_OK
            elif self._clearly_invalid_turn_direction():
                return self._fail("invalid_upstroke", now)
            return None

        if self.phase == GesturePhase.TURN_OK:
            if self._upstroke_valid():
                self.phase = GesturePhase.UPSTROKE_OK
            elif self._clearly_invalid_upstroke():
                return self._fail("invalid_upstroke", now)
            return None

        if self.phase == GesturePhase.UPSTROKE_OK and self._is_check_mark(self.points):
            return self._succeed()
        return None

    def _reject_candidate(self, reason: str, now: float) -> GestureResult:
        self.last_candidate_reject_reason = reason
        self._clear_drawing()
        self._candidate_buffer.clear()
        self.state = GestureState.ARMED
        self.phase = GesturePhase.ARMED
        self._last_candidate_reject_at = now
        return GestureResult(self.state, self.phase, candidate_rejected=True, fail_reason=reason)

    def _fail(self, reason: str, now: float) -> GestureResult:
        self.state = GestureState.FAILED
        self.phase = GesturePhase.FAILED
        self._terminal_reason = reason
        self._failed_at = now
        return GestureResult(self.state, self.phase, terminal=True, fail_reason=reason)

    def _after_failure(self, raw_point: Point | None, now: float) -> GestureResult:
        if self._failed_at is None or now - self._failed_at < config.FAIL_AUTO_REARM_TIME:
            return GestureResult(self.state, self.phase)
        self._clear_drawing()
        self._candidate_buffer.clear()
        self._failed_at = None
        self._terminal_reason = ""
        if raw_point is not None and _distance(raw_point, self.center) <= self.arm_radius:
            self._enter_armed(raw_point)
        else:
            self._return_to_tracking()
        return GestureResult(self.state, self.phase)

    def _succeed(self) -> GestureResult:
        self.state = GestureState.CHECKED
        self.phase = GesturePhase.SUCCESS
        return GestureResult(self.state, self.phase, checked=True, terminal=True)

    def _downstroke_valid(self) -> bool:
        if len(self.points) < 2:
            return False
        start, current = self.points[0], self.points[-1]
        return (
            current.y - start.y >= config.MIN_DOWN_DISTANCE
            and current.x - start.x >= config.MIN_HORIZONTAL_DISTANCE
            and _trend_ratio(self.points, "down") >= config.MIN_TREND_RATIO
        )

    def _turn_valid(self) -> bool:
        if len(self.points) < 4:
            return False
        turn_index = _lowest_index(self.points)
        if turn_index >= len(self.points) - 1:
            return False
        start, turn, current = self.points[0], self.points[turn_index], self.points[-1]
        return (
            turn.y - start.y >= config.MIN_DOWN_DISTANCE
            and turn.x - start.x >= config.MIN_HORIZONTAL_DISTANCE
            and turn.y - current.y >= config.TURN_TOLERANCE
            and current.x >= turn.x - config.DIRECTION_TOLERANCE
        )

    def _upstroke_valid(self) -> bool:
        turn_index = _lowest_index(self.points)
        turn, current = self.points[turn_index], self.points[-1]
        return (
            turn.y - current.y >= config.MIN_UP_DISTANCE
            and current.x - turn.x >= config.MIN_HORIZONTAL_DISTANCE
            and _trend_ratio(self.points[turn_index:], "up") >= config.MIN_TREND_RATIO
        )

    def _clearly_invalid_downstroke(self) -> bool:
        if _path_length(self.points) < config.MIN_EARLY_VALIDATION_PATH_LENGTH:
            return False
        start, current = self.points[0], self.points[-1]
        return (
            current.y - start.y <= -config.INVALID_DIRECTION_DISTANCE
            or current.x - start.x <= -config.INVALID_DIRECTION_DISTANCE
        )

    def _clearly_invalid_upstroke(self) -> bool:
        turn, current = self.points[_lowest_index(self.points)], self.points[-1]
        return current.x - turn.x <= -config.INVALID_DIRECTION_DISTANCE

    def _clearly_invalid_turn_direction(self) -> bool:
        if len(self.points) < 4:
            return False
        turn_index = _lowest_index(self.points)
        if turn_index >= len(self.points) - 1:
            return False
        turn, current = self.points[turn_index], self.points[-1]
        return (
            turn.y - current.y >= config.TURN_TOLERANCE
            and current.x - turn.x <= -config.INVALID_DIRECTION_DISTANCE
        )

    def _smooth(self, point: Point) -> Point:
        previous = self._last_smoothed or point
        alpha = config.SMOOTHING_FACTOR
        return Point(
            previous.x + alpha * (point.x - previous.x),
            previous.y + alpha * (point.y - previous.y),
        )

    @staticmethod
    def _is_check_mark(points: list[Point]) -> bool:
        if len(points) < config.MIN_POINTS or _path_length(points) < config.MIN_PATH_LENGTH:
            return False
        turn_index = _lowest_index(points)
        turn_fraction = turn_index / (len(points) - 1)
        if not config.MIN_TURN_FRACTION <= turn_fraction <= config.MAX_TURN_FRACTION:
            return False
        start, turn, end = points[0], points[turn_index], points[-1]
        if turn.y - start.y < config.MIN_DOWN_DISTANCE or turn.y - end.y < config.MIN_UP_DISTANCE:
            return False
        if turn.x - start.x < config.MIN_HORIZONTAL_DISTANCE or end.x - turn.x < config.MIN_HORIZONTAL_DISTANCE:
            return False
        return (
            _trend_ratio(points[: turn_index + 1], "down") >= config.MIN_TREND_RATIO
            and _trend_ratio(points[turn_index:], "up") >= config.MIN_TREND_RATIO
        )

    def _clear_drawing(self) -> None:
        self.points.clear()
        self.samples.clear()
        self.started_at = None
        self.last_seen_at = None
        self._last_smoothed = None

    def _return_to_tracking(self) -> None:
        self._candidate_buffer.clear()
        self.state = GestureState.TRACKING
        self.phase = GesturePhase.TRACKING
        self.arming_started_at = None
        self._arming_last_point = None
        self._arming_last_time = None
        self._last_smoothed = None

    def _return_to_idle(self) -> None:
        self._candidate_buffer.clear()
        self.state = GestureState.IDLE
        self.phase = GesturePhase.IDLE
        self.arming_started_at = None
        self._arming_last_point = None
        self._arming_last_time = None
        self._last_smoothed = None

    def _trim_candidate_buffer(self, now: float) -> None:
        while self._candidate_buffer and now - self._candidate_buffer[0].timestamp > config.CANDIDATE_BUFFER_SECONDS:
            self._candidate_buffer.popleft()


def _distance(first: Point, second: Point) -> float:
    return hypot(first.x - second.x, first.y - second.y)


def _path_length(points: Iterable[Point]) -> float:
    points = list(points)
    return sum(_distance(first, second) for first, second in zip(points, points[1:]))


def _lowest_index(points: list[Point]) -> int:
    return max(range(1, len(points) - 1), key=lambda index: points[index].y)


def _filter_points(points: list[Point]) -> list[Point]:
    filtered = [points[0]]
    for point in points[1:]:
        if _distance(point, filtered[-1]) >= config.MIN_POINT_DISTANCE:
            filtered.append(point)
    return filtered


def _trend_ratio(points: list[Point], direction: str) -> float:
    if len(points) < 2:
        return 0.0
    good = 0
    for previous, current in zip(points, points[1:]):
        dy = current.y - previous.y
        if direction == "down" and dy >= -config.DIRECTION_TOLERANCE:
            good += 1
        if direction == "up" and dy <= config.DIRECTION_TOLERANCE:
            good += 1
    return good / (len(points) - 1)


def _rightward_trend_ratio(points: list[Point]) -> float:
    if len(points) < 2:
        return 0.0
    good = sum(
        current.x - previous.x >= -config.DIRECTION_TOLERANCE
        for previous, current in zip(points, points[1:])
    )
    return good / (len(points) - 1)
