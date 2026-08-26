"""Online, explainable recognition of a short air-drawn check mark."""

from __future__ import annotations

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
    """One raw and smoothed fingertip observation from an active attempt."""

    timestamp: float
    raw: Point
    smoothed: Point
    phase: GesturePhase


@dataclass(frozen=True)
class GestureResult:
    state: GestureState
    phase: GesturePhase
    checked: bool = False
    started: bool = False
    terminal: bool = False
    fail_reason: str = ""
    sample: TrajectorySample | None = None


class GestureDetector:
    """Tracks a ✓ online and exposes an auditable phase at every frame."""

    def __init__(
        self,
        center: tuple[int, int] = config.CHECK_CENTER,
        start_radius: float = config.START_ZONE_RADIUS,
        tracking_radius: float = config.TRACKING_RADIUS,
    ) -> None:
        self.center = Point(float(center[0]), float(center[1]))
        self.start_radius = start_radius
        self.tracking_radius = tracking_radius
        self.points: list[Point] = []
        self.samples: list[TrajectorySample] = []
        self.state = GestureState.IDLE
        self.phase = GesturePhase.IDLE
        self.started_at: Optional[float] = None
        self.last_seen_at: Optional[float] = None
        self._last_smoothed: Optional[Point] = None
        self._terminal_reason = ""

    @property
    def trail(self) -> list[Point]:
        return self.points[-config.MAX_TRAIL_POINTS :]

    @property
    def active(self) -> bool:
        return self.started_at is not None and self.state not in {
            GestureState.CHECKED,
            GestureState.FAILED,
        }

    @property
    def progress(self) -> int:
        return {
            GesturePhase.STARTED: 0,
            GesturePhase.DOWNSTROKE_OK: 1,
            GesturePhase.TURN_OK: 2,
            GesturePhase.UPSTROKE_OK: 3,
            GesturePhase.SUCCESS: 3,
        }.get(self.phase, 0)

    def draw_time(self, now: float) -> float:
        return 0.0 if self.started_at is None else max(0.0, now - self.started_at)

    def reset(self) -> None:
        self.points.clear()
        self.samples.clear()
        self.state = GestureState.IDLE
        self.phase = GesturePhase.IDLE
        self.started_at = None
        self.last_seen_at = None
        self._last_smoothed = None
        self._terminal_reason = ""

    def mark_checked(self) -> None:
        """Used by the mouse fallback so visual completion stays shared."""

        self.state = GestureState.CHECKED
        self.phase = GesturePhase.SUCCESS

    def update(self, raw_point: Optional[Point], now: float) -> GestureResult:
        """Consume one fingertip sample and advance the online phase."""

        if self.state in {GestureState.CHECKED, GestureState.FAILED}:
            return GestureResult(self.state, self.phase, checked=self.state == GestureState.CHECKED)

        if raw_point is None:
            if self.active and self.last_seen_at is not None:
                if now - self.last_seen_at > config.MAX_MISSING_HAND_TIME:
                    if self.phase == GesturePhase.UPSTROKE_OK and self._is_check_mark(self.points):
                        return self._succeed()
                    return self._fail("hand_lost")
            elif not self.active:
                self.state = GestureState.IDLE
                self.phase = GesturePhase.IDLE
            return GestureResult(self.state, self.phase)

        self.last_seen_at = now
        distance_from_center = _distance(raw_point, self.center)
        if not self.active:
            if distance_from_center <= self.start_radius:
                return self._start(raw_point, now)
            self.state = GestureState.TRACKING
            self.phase = GesturePhase.TRACKING
            return GestureResult(self.state, self.phase)

        if distance_from_center > self.tracking_radius:
            return self._fail("left_tracking_zone")
        if self.draw_time(now) > config.MAX_DRAW_TIME:
            return self._fail("draw_timeout")

        smoothed = self._smooth(raw_point)
        self._last_smoothed = smoothed
        if _distance(smoothed, self.points[-1]) >= config.MIN_POINT_DISTANCE:
            self.points.append(smoothed)

        terminal = self._advance_phase()
        sample = TrajectorySample(self.draw_time(now), raw_point, smoothed, self.phase)
        self.samples.append(sample)
        if terminal is not None:
            return GestureResult(
                self.state,
                self.phase,
                checked=self.state == GestureState.CHECKED,
                terminal=True,
                fail_reason=self._terminal_reason,
                sample=sample,
            )
        return GestureResult(self.state, self.phase, sample=sample)

    def _start(self, raw_point: Point, now: float) -> GestureResult:
        self.points = [raw_point]
        self.started_at = now
        self.last_seen_at = now
        self._last_smoothed = raw_point
        self.state = GestureState.DRAWING
        self.phase = GesturePhase.STARTED
        sample = TrajectorySample(0.0, raw_point, raw_point, self.phase)
        self.samples = [sample]
        return GestureResult(self.state, self.phase, started=True, sample=sample)

    def _advance_phase(self) -> Optional[GestureResult]:
        if self.phase == GesturePhase.STARTED:
            if self._downstroke_valid():
                self.phase = GesturePhase.DOWNSTROKE_OK
            elif self._clearly_invalid_downstroke():
                return self._fail("invalid_downstroke")
            return None

        if self.phase == GesturePhase.DOWNSTROKE_OK:
            if self._turn_valid():
                self.phase = GesturePhase.TURN_OK
            elif self._clearly_invalid_turn_direction():
                return self._fail("invalid_upstroke")
            return None

        if self.phase == GesturePhase.TURN_OK:
            if self._upstroke_valid():
                self.phase = GesturePhase.UPSTROKE_OK
            elif self._clearly_invalid_upstroke():
                return self._fail("invalid_upstroke")
            return None

        if self.phase == GesturePhase.UPSTROKE_OK and self._is_check_mark(self.points):
            return self._succeed()
        return None

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
        """A rising leg that has decisively gone left is a V, not a check mark."""

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

    def _fail(self, reason: str) -> GestureResult:
        self.state = GestureState.FAILED
        self.phase = GesturePhase.FAILED
        self._terminal_reason = reason
        return GestureResult(self.state, self.phase, terminal=True, fail_reason=reason)

    def _succeed(self) -> GestureResult:
        self.state = GestureState.CHECKED
        self.phase = GesturePhase.SUCCESS
        return GestureResult(self.state, self.phase, checked=True, terminal=True)


def _distance(first: Point, second: Point) -> float:
    return hypot(first.x - second.x, first.y - second.y)


def _path_length(points: Iterable[Point]) -> float:
    points = list(points)
    return sum(_distance(first, second) for first, second in zip(points, points[1:]))


def _lowest_index(points: list[Point]) -> int:
    return max(range(1, len(points) - 1), key=lambda index: points[index].y)


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
