"""Explainable Swipe-up detector with hover, arm, reject, and formal-trial gates."""

from __future__ import annotations

from dataclasses import dataclass
import config
from block_manager import BlockManager
from swipe_state import SwipeState


@dataclass(frozen=True)
class Point:
    x: float
    y: float


@dataclass(frozen=True)
class TrajectorySample:
    timestamp: float
    raw: Point
    smoothed: Point
    finger_mode: str
    state: SwipeState
    target_block: str | None
    block_x: float | None
    block_y: float | None


@dataclass(frozen=True)
class SwipeEvent:
    state: SwipeState
    target_block: str | None = None
    sample: TrajectorySample | None = None
    initial_samples: tuple[TrajectorySample, ...] = ()
    started: bool = False
    terminal: bool = False
    success: bool = False
    candidate_rejected: bool = False
    fail_reason: str = ""
    vertical_distance: float = 0.0
    horizontal_distance: float = 0.0


class SwipeDetector:
    def __init__(self) -> None:
        self.state = SwipeState.TRACKING
        self.target_block: str | None = None
        self.hover_started_at: float | None = None
        self.armed_anchor: Point | None = None
        self.start_point: Point | None = None
        self.last_point: Point | None = None
        self.last_raw_point: Point | None = None
        self.last_seen_at: float | None = None
        self.swipe_started_at: float | None = None
        self.block_offset_y = 0.0
        self.path: list[Point] = []
        self.samples: list[TrajectorySample] = []
        self.last_candidate_reject_reason = ""
        self.last_fail_reason = ""
        self._failed_at: float | None = None

    @property
    def trail(self) -> list[Point]:
        return self.path[-config.TRAIL_LENGTH:]

    @property
    def vertical_distance(self) -> float:
        if self.start_point is None or self.last_point is None:
            return 0.0
        return self.start_point.y - self.last_point.y

    @property
    def horizontal_distance(self) -> float:
        if self.start_point is None or self.last_point is None:
            return 0.0
        return self.last_point.x - self.start_point.x

    def reset(self, blocks: BlockManager | None = None) -> None:
        if blocks is not None:
            blocks.restore(self.target_block)
        self.state = SwipeState.TRACKING
        self.target_block = None
        self.hover_started_at = None
        self.armed_anchor = None
        self.start_point = None
        self.last_point = None
        self.last_raw_point = None
        self.last_seen_at = None
        self.swipe_started_at = None
        self.block_offset_y = 0.0
        self.path.clear()
        self.samples.clear()
        self._failed_at = None

    def update(
        self,
        point: Point | None,
        now: float,
        blocks: BlockManager,
        finger_mode: str,
    ) -> SwipeEvent:
        if self.state == SwipeState.BLOCK_REMOVED:
            self._clear_candidate()
        if self.state == SwipeState.FAILED and self._failed_at is not None:
            if now - self._failed_at < config.FAIL_AUTO_REARM_TIME:
                return SwipeEvent(self.state, self.target_block, fail_reason=self.last_fail_reason)
            self._clear_candidate()
        if point is None:
            if self.last_seen_at is not None and now - self.last_seen_at > config.MAX_MISSING_HAND_TIME:
                if self.state == SwipeState.SWIPING:
                    return self._fail(blocks, "hand_lost", now, finger_mode)
                self._clear_candidate()
            return SwipeEvent(self.state, self.target_block, fail_reason=self.last_fail_reason)

        self.last_seen_at = now
        self.last_raw_point = point
        smoothed = self._smooth(point)
        self.last_point = smoothed
        self.path.append(smoothed)

        if smoothed.y > config.INTERACTION_BOTTOM_Y and self.state in {
            SwipeState.TRACKING,
            SwipeState.BLOCK_HOVER,
            SwipeState.BLOCK_ARMED,
        }:
            self._clear_candidate()
            return SwipeEvent(self.state, None)

        if self.state in {SwipeState.TRACKING, SwipeState.BLOCK_HOVER}:
            return self._update_hover(smoothed, now, blocks, finger_mode)
        if self.state == SwipeState.BLOCK_ARMED:
            return self._update_armed(smoothed, now, blocks, finger_mode)
        if self.state == SwipeState.SWIPING:
            return self._update_swiping(smoothed, now, blocks, finger_mode)
        return SwipeEvent(self.state, self.target_block)

    def _update_hover(self, point: Point, now: float, blocks: BlockManager, finger_mode: str) -> SwipeEvent:
        locked = blocks.top_block
        if locked is None:
            self._clear_candidate()
            return SwipeEvent(SwipeState.TRACKING)
        if locked.block_id != self.target_block:
            self.target_block = locked.block_id
            self.hover_started_at = now
            self.armed_anchor = point
            self.path = [point]
            self.samples.clear()
            self.state = SwipeState.BLOCK_HOVER
        sample = self._sample(now, point, finger_mode, blocks)
        self.samples.append(sample)
        if self.hover_started_at is not None and now - self.hover_started_at >= config.BLOCK_ARM_TIME:
            self.state = SwipeState.BLOCK_ARMED
            self.armed_anchor = point
            sample = self._sample(now, point, finger_mode, blocks)
            self.samples.append(sample)
        return SwipeEvent(self.state, self.target_block, sample=sample)

    def _update_armed(self, point: Point, now: float, blocks: BlockManager, finger_mode: str) -> SwipeEvent:
        if self.target_block is None or self.armed_anchor is None:
            self._clear_candidate()
            return SwipeEvent(SwipeState.TRACKING)
        anchor = self.armed_anchor
        upward = anchor.y - point.y
        downward = point.y - anchor.y
        horizontal = abs(point.x - anchor.x)
        sample = self._sample(now, point, finger_mode, blocks)
        self.samples.append(sample)
        if downward >= config.CANDIDATE_REJECT_DISTANCE:
            return self._reject("downward_motion")
        if horizontal >= config.CANDIDATE_REJECT_DISTANCE and upward < config.MIN_SWIPE_START_DISTANCE:
            return self._reject("horizontal_motion")
        if upward >= config.MIN_SWIPE_START_DISTANCE:
            block = blocks.get(self.target_block)
            if block is None or block.completed:
                self._clear_candidate()
                return SwipeEvent(SwipeState.TRACKING)
            self.state = SwipeState.SWIPING
            self.start_point = point
            self.swipe_started_at = now
            self.block_offset_y = block.center_y - point.y
            self.samples.append(self._sample(now, point, finger_mode, blocks))
            return SwipeEvent(
                SwipeState.SWIPING,
                self.target_block,
                sample=self.samples[-1],
                initial_samples=tuple(self.samples[:-1][-config.TRAJECTORY_PREFILL_POINTS:]),
                started=True,
            )
        return SwipeEvent(self.state, self.target_block, sample=sample)

    def _update_swiping(self, point: Point, now: float, blocks: BlockManager, finger_mode: str) -> SwipeEvent:
        if self.target_block is None or self.start_point is None or self.swipe_started_at is None:
            return self._fail(blocks, "missing_swipe_start", now, finger_mode)
        block = blocks.get(self.target_block)
        if block is None or block.completed:
            return self._fail(blocks, "target_unavailable", now, finger_mode)
        blocks.move_vertical(self.target_block, point.y + self.block_offset_y)
        sample = self._sample(now, point, finger_mode, blocks)
        self.samples.append(sample)
        vertical = self.start_point.y - point.y
        horizontal = abs(point.x - self.start_point.x)
        if horizontal > config.MAX_HORIZONTAL_DRIFT:
            return self._fail(blocks, "horizontal_drift", now, finger_mode, sample)
        if now - self.swipe_started_at > config.MAX_SWIPE_TIME:
            return self._fail(blocks, "swipe_timeout", now, finger_mode, sample)
        if vertical >= config.MIN_SWIPE_UP_DISTANCE and block.center_y < config.REMOVE_THRESHOLD_Y:
            self.state = SwipeState.BLOCK_REMOVED
            return SwipeEvent(
                SwipeState.BLOCK_REMOVED,
                self.target_block,
                sample=sample,
                terminal=True,
                success=True,
                vertical_distance=vertical,
                horizontal_distance=point.x - self.start_point.x,
            )
        return SwipeEvent(
            SwipeState.SWIPING,
            self.target_block,
            sample=sample,
            vertical_distance=vertical,
            horizontal_distance=point.x - self.start_point.x,
        )

    def _fail(
        self,
        blocks: BlockManager,
        reason: str,
        now: float,
        finger_mode: str,
        sample: TrajectorySample | None = None,
    ) -> SwipeEvent:
        if sample is None and self.last_point is not None:
            sample = self._sample(now, self.last_point, finger_mode, blocks)
            self.samples.append(sample)
        blocks.restore(self.target_block)
        vertical = self.vertical_distance
        horizontal = self.horizontal_distance
        target = self.target_block
        self.state = SwipeState.FAILED
        self.last_fail_reason = reason
        self._failed_at = now
        return SwipeEvent(
            SwipeState.FAILED,
            target,
            sample=sample,
            terminal=True,
            fail_reason=reason,
            vertical_distance=vertical,
            horizontal_distance=horizontal,
        )

    def _reject(self, reason: str) -> SwipeEvent:
        target = self.target_block
        self.last_candidate_reject_reason = reason
        self._clear_candidate()
        return SwipeEvent(
            SwipeState.TRACKING,
            target,
            candidate_rejected=True,
            fail_reason=reason,
        )

    def _smooth(self, point: Point) -> Point:
        if self.last_point is None:
            return point
        factor = config.SMOOTHING_FACTOR
        return Point(
            self.last_point.x + factor * (point.x - self.last_point.x),
            self.last_point.y + factor * (point.y - self.last_point.y),
        )

    def _sample(self, now: float, point: Point, finger_mode: str, blocks: BlockManager | None = None) -> TrajectorySample:
        block = None if blocks is None else blocks.get(self.target_block)
        return TrajectorySample(
            timestamp=now,
            raw=self.last_raw_point or point,
            smoothed=point,
            finger_mode=finger_mode,
            state=self.state,
            target_block=self.target_block,
            block_x=None if block is None else block.center_x,
            block_y=None if block is None else block.center_y,
        )

    def _clear_candidate(self, keep_state: SwipeState = SwipeState.TRACKING) -> None:
        self.state = keep_state
        self.target_block = None if keep_state == SwipeState.TRACKING else self.target_block
        self.hover_started_at = None
        self.armed_anchor = None
        self.start_point = None
        self.last_point = None
        self.last_raw_point = None
        self.swipe_started_at = None
        self.block_offset_y = 0.0
        self.samples.clear()
        if keep_state == SwipeState.TRACKING:
            self.path.clear()
