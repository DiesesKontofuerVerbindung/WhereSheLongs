"""Runnable Prototype 2 UI: webcam Swipe-up Checklist plus permanent mouse fallback."""

from __future__ import annotations

import time
from dataclasses import dataclass

import cv2
import numpy as np

import config
from block_manager import BlockManager
from checklist_mapper import ChecklistMapper
from coordinate_monitor import CoordinateMonitor
from environment_recorder import write_config_snapshot
from hand_tracker import HandTracker, TrackingFrame
from swipe_detector import Point, SwipeDetector, TrajectorySample
from swipe_state import SwipeState
from test_logger import ExpectedType, TestLogger, calculate_metrics


@dataclass
class MouseDrag:
    block_id: str
    started_at: float
    start_x: float
    start_y: float
    offset_y: float


@dataclass
class AppState:
    finger_mode: str = config.ONE_FINGER
    expected_type: ExpectedType = "positive"
    last_frame: TrackingFrame | None = None
    status_message: str = "等待手指进入方块"
    mouse_drag: MouseDrag | None = None
    last_vertical_distance: float = 0.0
    last_horizontal_distance: float = 0.0


class PrototypeApp:
    def __init__(self, results_root=None) -> None:
        self.state = AppState()
        self.blocks = BlockManager()
        self.checklist = ChecklistMapper()
        self.detector = SwipeDetector()
        self.tracker = HandTracker()
        self.logger = TestLogger(results_root or config.RESULTS_DIR)
        self.coordinate_monitor = CoordinateMonitor(self.logger.run_dir)
        self.fps = 0.0
        self._last_frame_time = time.perf_counter()
        self._fps_samples: list[float] = []

    def complete_block(self, block_id: str, source: str, now: float | None = None) -> bool:
        """Single completion path shared by gesture and mouse input."""

        if not self.blocks.mark_completed(block_id):
            return False
        self.blocks.start_removal_animation(block_id, time.perf_counter() if now is None else now)
        self.checklist.complete_for_block(block_id)
        self.logger.set_blocks_completed(self.blocks.completed_count)
        self.state.status_message = f"{block_id} completed via {source}"
        return True

    def reset_current_interaction(self) -> None:
        if self.logger.active is not None:
            self.logger.finish_trial("aborted", "reset", time.perf_counter())
        self.state.mouse_drag = None
        self.detector.reset(self.blocks)
        self.blocks.reset_uncompleted_positions()
        self.state.last_vertical_distance = 0.0
        self.state.last_horizontal_distance = 0.0
        self.state.status_message = "当前交互已 reset；已完成方块保留"

    def reset_all_blocks(self) -> None:
        if self.logger.active is not None:
            self.logger.finish_trial("aborted", "full_reset", time.perf_counter())
        self.state.mouse_drag = None
        self.detector.reset(self.blocks)
        self.blocks.reset_all()
        self.checklist.reset()
        self.logger.set_blocks_completed(0)
        self.state.last_vertical_distance = 0.0
        self.state.last_horizontal_distance = 0.0
        self.state.status_message = "五个方块与 Checklist 已全部重置"

    def update_fps(self) -> None:
        now = time.perf_counter()
        delta = max(1e-6, now - self._last_frame_time)
        self._last_frame_time = now
        self._fps_samples = (self._fps_samples + [1.0 / delta])[-20:]
        self.fps = sum(self._fps_samples) / len(self._fps_samples)

    def tick(self) -> None:
        now = time.perf_counter()
        self.blocks.update_removal_animations(now)
        frame = self.tracker.read(self.state.finger_mode)
        self.state.last_frame = frame
        if self.state.mouse_drag is None and not self.blocks.all_completed:
            point = None if frame.cursor is None else Point(frame.cursor.screen_x, frame.cursor.screen_y)
            event = self.detector.update(point, now, self.blocks, self.state.finger_mode)
            if event.started:
                self.logger.start_trial(self.state.expected_type, self.state.finger_mode, event.target_block or "", "gesture", now)
                for sample in event.initial_samples:
                    self.logger.append_sample(sample)
            if event.sample is not None and self.logger.active is not None:
                self.logger.append_sample(event.sample)
            self.state.last_vertical_distance = event.vertical_distance
            self.state.last_horizontal_distance = event.horizontal_distance
            if event.candidate_rejected:
                self.state.status_message = f"candidate reject: {event.fail_reason}"
            elif event.terminal:
                if event.success and event.target_block is not None:
                    self.complete_block(event.target_block, "gesture", now)
                    self.logger.finish_trial("success", "", now, event.vertical_distance, event.horizontal_distance)
                else:
                    self.logger.finish_trial("fail", event.fail_reason, now, event.vertical_distance, event.horizontal_distance)
                    self.state.status_message = f"FAIL: {event.fail_reason}"
            elif event.state == SwipeState.BLOCK_ARMED:
                self.state.status_message = "BLOCK_ARMED：保持目标后向上划"
            elif event.state == SwipeState.SWIPING:
                self.state.status_message = "SWIPING：方块跟随手指"
        self.coordinate_monitor.record(frame, self.detector, now)
        self.update_fps()

    def mouse_callback(self, event: int, x: int, y: int, _flags: int, _param) -> None:
        now = time.perf_counter()
        if event == cv2.EVENT_LBUTTONDOWN:
            block = self.blocks.hit_test(x, y)
            if block is None or self.state.mouse_drag is not None:
                return
            self.state.mouse_drag = MouseDrag(block.block_id, now, x, y, block.center_y - y)
            self.logger.start_trial(self.state.expected_type, config.MOUSE_FINGER, block.block_id, "mouse", now)
            self.logger.append_sample(self._mouse_sample(now, x, y, block.block_id))
            self.state.status_message = f"Mouse SWIPING: {block.block_id}"
        elif event == cv2.EVENT_MOUSEMOVE and self.state.mouse_drag is not None:
            drag = self.state.mouse_drag
            block = self.blocks.get(drag.block_id)
            if block is None or block.completed:
                return
            block.center_y = y + drag.offset_y
            self.logger.append_sample(self._mouse_sample(now, x, y, drag.block_id))
            vertical = drag.start_y - y
            horizontal = x - drag.start_x
            self.state.last_vertical_distance = vertical
            self.state.last_horizontal_distance = horizontal
            if block.center_y < config.REMOVE_THRESHOLD_Y and vertical >= config.MIN_SWIPE_UP_DISTANCE:
                self.complete_block(drag.block_id, "mouse", now)
                self.logger.finish_trial("success", "", now, vertical, horizontal)
                self.state.mouse_drag = None
        elif event == cv2.EVENT_LBUTTONUP and self.state.mouse_drag is not None:
            drag = self.state.mouse_drag
            self.blocks.restore(drag.block_id)
            self.logger.finish_trial(
                "fail", "insufficient_upward_distance", now,
                drag.start_y - y, x - drag.start_x,
            )
            self.state.mouse_drag = None
            self.state.status_message = "FAIL: mouse drag did not cross threshold"

    def _mouse_sample(self, now: float, x: int, y: int, block_id: str) -> TrajectorySample:
        block = self.blocks.get(block_id)
        point = Point(float(x), float(y))
        return TrajectorySample(
            timestamp=now, raw=point, smoothed=point, finger_mode=config.MOUSE_FINGER,
            state=SwipeState.SWIPING, target_block=block_id,
            block_x=None if block is None else block.center_x,
            block_y=None if block is None else block.center_y,
        )

    def render(self) -> np.ndarray:
        canvas = np.full((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), (0, 0, 0), dtype=np.uint8)
        cv2.putText(canvas, "WOOD STACK — swipe the locked top log upward", (24, 36), cv2.FONT_HERSHEY_SIMPLEX, 0.72, (220, 220, 220), 2, cv2.LINE_AA)
        for section in range(1, config.SECTION_COUNT):
            y = int(section * config.SECTION_HEIGHT)
            cv2.line(canvas, (0, y), (config.WINDOW_WIDTH, y), (42, 42, 42), 1)
            cv2.putText(canvas, str(section), (8, y - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (100, 100, 100), 1, cv2.LINE_AA)
        if config.INTERACTION_BOTTOM_Y < config.WINDOW_HEIGHT:
            cv2.line(canvas, (0, int(config.INTERACTION_BOTTOM_Y)), (config.WINDOW_WIDTH, int(config.INTERACTION_BOTTOM_Y)), (0, 150, 220), 2)
            cv2.putText(canvas, "interaction bottom", (config.WINDOW_WIDTH - 190, int(config.INTERACTION_BOTTOM_Y) - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 180, 235), 1, cv2.LINE_AA)
        else:
            cv2.putText(canvas, f"interaction bottom: y={int(config.INTERACTION_BOTTOM_Y)} (outside)", (config.WINDOW_WIDTH - 330, config.WINDOW_HEIGHT - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 180, 235), 1, cv2.LINE_AA)
        cv2.line(canvas, (0, int(config.REMOVE_THRESHOLD_Y)), (config.WINDOW_WIDTH, int(config.REMOVE_THRESHOLD_Y)), (0, 190, 120), 2)
        cv2.putText(canvas, "REMOVE THRESHOLD", (config.WINDOW_WIDTH - 190, int(config.REMOVE_THRESHOLD_Y) - 8), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 220, 150), 1, cv2.LINE_AA)

        target = self.detector.target_block
        locked = self.blocks.top_block
        for block in self.blocks.blocks:
            if block.completed and block.removal_started_at is None:
                continue
            self._draw_wood_log(
                canvas,
                block,
                is_locked=locked is not None and block.block_id == locked.block_id,
                is_active=target == block.block_id,
            )

        if self.detector.trail:
            for first, second in zip(self.detector.trail, self.detector.trail[1:]):
                cv2.line(canvas, (int(first.x), int(first.y)), (int(second.x), int(second.y)), (120, 150, 255), 2, cv2.LINE_AA)
        if self.state.last_frame and self.state.last_frame.cursor is not None:
            cursor = self.state.last_frame.cursor
            cv2.circle(canvas, (cursor.screen_x, cursor.screen_y), 10, (0, 210, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, (cursor.screen_x, cursor.screen_y), 15, (255, 255, 255), 1, cv2.LINE_AA)

        frame = self.state.last_frame
        finger_xy = "-- / --" if frame is None or frame.cursor is None else f"{frame.cursor.normalized_x:.2f} / {frame.cursor.normalized_y:.2f}"
        mapped_xy = "-- / --" if frame is None or frame.cursor is None else f"{frame.cursor.screen_x} / {frame.cursor.screen_y}"
        virtual_status = "--" if frame is None or frame.cursor is None else "OUTSIDE" if not (0 <= frame.cursor.screen_x < config.WINDOW_WIDTH and 0 <= frame.cursor.screen_y < config.WINDOW_HEIGHT) else "INSIDE"
        hand_status = "HOLD" if frame and frame.cursor_held else "YES" if frame and frame.hand_detected else "NO"
        extensions = "--" if frame is None else f"index={'UP' if frame.index_extended else 'DOWN'} middle={'UP' if frame.middle_extended else 'DOWN'}"
        metrics = calculate_metrics(self.logger.records)
        accuracy = metrics["accuracy"]
        accuracy_text = "n/a" if accuracy is None else f"{float(accuracy) * 100:.1f}%"
        debug_lines = [
            "P positive | N negative | 1 one finger | 2 two fingers | R current reset | T all reset | Q quit",
            f"FPS: {self.fps:5.1f}    Hand: {hand_status}    Mode: {self.state.finger_mode.replace('_FINGER', '')}    {extensions}",
            f"Raw x/y: {finger_xy}    Virtual x/y: {mapped_xy} ({virtual_status})    State: {self.detector.state.value}    Locked: {locked.block_id if locked else '--'}",
            f"Swipe dy/dx: {self.state.last_vertical_distance:6.1f} / {self.state.last_horizontal_distance:6.1f}    Checklist: {self.blocks.completed_count} / {config.BLOCK_COUNT}",
            f"Expected: {self.state.expected_type.upper()}    Trials: {self.logger.completed_trials} / {self.logger.target_total}    TP/TN/FP/FN: {metrics['tp']}/{metrics['tn']}/{metrics['fp']}/{metrics['fn']}    Acc: {accuracy_text}",
            f"Camera: {self.tracker.error or 'ready'}    Status: {self.state.status_message}",
        ]
        base_y = config.WINDOW_HEIGHT - len(debug_lines) * 22 - 10
        for index, line in enumerate(debug_lines):
            cv2.putText(canvas, line, (24, base_y + index * 22), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (185, 215, 230), 1, cv2.LINE_AA)

        checklist_y = 76
        cv2.putText(canvas, "Checklist", (24, checklist_y), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (235, 235, 235), 2, cv2.LINE_AA)
        for index, item in enumerate(self.checklist.snapshot(), start=1):
            mark = "[x]" if item["completed"] else "[ ]"
            cv2.putText(canvas, f"{mark} {item['label']}", (24, checklist_y + index * 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (120, 230, 160) if item["completed"] else (190, 195, 205), 1, cv2.LINE_AA)
        return canvas

    @staticmethod
    def _draw_wood_log(canvas: np.ndarray, block, is_locked: bool, is_active: bool) -> None:
        """Draw one flat 2D log with a visible end grain and lock feedback."""

        radius = int(block.height / 2)
        left = int(block.center_x - block.width / 2)
        right = int(block.center_x + block.width / 2)
        center_y = int(block.center_y)
        body_color = (42, 104, 166) if not block.completed else (90, 120, 210)
        edge_color = (70, 165, 245) if is_locked else (75, 125, 190)
        if is_active:
            edge_color = (0, 230, 255)
        cv2.rectangle(canvas, (left + radius, center_y - radius), (right - radius, center_y + radius), body_color, -1, cv2.LINE_AA)
        cv2.circle(canvas, (left + radius, center_y), radius, (55, 130, 196), -1, cv2.LINE_AA)
        cv2.circle(canvas, (right - radius, center_y), radius, (50, 118, 180), -1, cv2.LINE_AA)
        cv2.rectangle(canvas, (left + radius, center_y - radius), (right - radius, center_y + radius), edge_color, 3 if is_locked else 2, cv2.LINE_AA)
        cv2.circle(canvas, (left + radius, center_y), radius, edge_color, 3 if is_locked else 2, cv2.LINE_AA)
        cv2.circle(canvas, (right - radius, center_y), radius, edge_color, 3 if is_locked else 2, cv2.LINE_AA)
        cv2.ellipse(canvas, (right - radius, center_y), (max(4, radius // 2), max(4, radius // 2)), 0, 0, 360, (85, 70, 45), 2, cv2.LINE_AA)
        cv2.putText(canvas, block.block_id.replace("wood_", "WOOD "), (left + radius + 20, center_y + 8), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (235, 235, 220), 2, cv2.LINE_AA)
        if is_locked:
            cv2.putText(canvas, "LOCKED", (left + radius + 170, center_y - radius - 12), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (0, 235, 255), 2, cv2.LINE_AA)

    def close(self) -> None:
        self.logger.close(time.perf_counter())
        self.coordinate_monitor.close()
        self.tracker.close()


def main() -> None:
    app = PrototypeApp()
    cv2.namedWindow(config.WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(config.WINDOW_NAME, config.WINDOW_WIDTH, config.WINDOW_HEIGHT)
    cv2.setMouseCallback(config.WINDOW_NAME, app.mouse_callback)
    app.tracker.start()
    app.logger.update_environment(app.tracker.camera_info())
    print(f"Results run: {app.logger.run_dir}")
    print(f"Coordinate monitor: {app.coordinate_monitor.path}")
    try:
        while True:
            app.tick()
            cv2.imshow(config.WINDOW_NAME, app.render())
            key = cv2.waitKey(max(1, int(1000 / config.TARGET_FPS))) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if key in (ord("r"), ord("R")):
                app.reset_current_interaction()
            elif key in (ord("t"), ord("T")):
                app.reset_all_blocks()
            elif key in (ord("p"), ord("P")):
                app.state.expected_type = "positive"
                app.state.status_message = "Expected trial = POSITIVE"
            elif key in (ord("n"), ord("N")):
                app.state.expected_type = "negative"
                app.state.status_message = "Expected trial = NEGATIVE"
            elif key == ord("1"):
                app.state.finger_mode = config.ONE_FINGER
                app.reset_current_interaction()
            elif key == ord("2"):
                app.state.finger_mode = config.TWO_FINGER
                app.reset_current_interaction()
    finally:
        app.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
