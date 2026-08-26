"""Runnable v0.2 UI: online phases plus reproducible experiment logging."""

from __future__ import annotations

import time
from dataclasses import dataclass

import cv2
import numpy as np

import config
from gesture_detector import GestureDetector, Point
from hand_tracker import FingerPoint, HandTracker
from test_logger import ExpectedType, TestLogger


@dataclass
class AppState:
    checked: bool = False
    check_source: str = ""
    gesture_success: bool = False
    last_finger: FingerPoint | None = None
    status_message: str = ""


class PrototypeApp:
    def __init__(self) -> None:
        self.state = AppState()
        self.detector = GestureDetector()
        self.tracker = HandTracker()
        self.logger = TestLogger()
        self.expected_type: ExpectedType = "positive"
        self.fps = 0.0
        self._last_frame_time = time.perf_counter()
        self._fps_samples: list[float] = []

    def reset(self) -> None:
        now = time.perf_counter()
        if self.logger.active is not None:
            self.logger.finish_trial("aborted", "reset", now)
        self.state = AppState()
        self.detector.reset()

    def complete(self, source: str) -> None:
        now = time.perf_counter()
        if source == "mouse" and self.logger.active is not None:
            self.logger.finish_trial("aborted", "mouse_fallback", now)
        self.state.checked = True
        self.state.check_source = source
        self.state.gesture_success = source == "gesture"
        self.detector.mark_checked()

    def mouse_callback(self, event: int, x: int, y: int, _flags: int, _param) -> None:
        if event != cv2.EVENT_LBUTTONDOWN or self.state.checked:
            return
        center = config.CHECK_CENTER
        if (x - center[0]) ** 2 + (y - center[1]) ** 2 <= config.CHECK_RADIUS ** 2:
            self.complete("mouse")

    def update_fps(self) -> None:
        now = time.perf_counter()
        delta = max(1e-6, now - self._last_frame_time)
        self._last_frame_time = now
        self._fps_samples.append(1.0 / delta)
        self._fps_samples = self._fps_samples[-20:]
        self.fps = sum(self._fps_samples) / len(self._fps_samples)

    def tick(self) -> None:
        now = time.perf_counter()
        finger = self.tracker.read_index_finger()
        self.state.last_finger = finger
        if not self.state.checked:
            point = None if finger is None else Point(finger.screen_x, finger.screen_y)
            result = self.detector.update(point, now)
            if result.started:
                self.logger.start_trial(self.expected_type, now)
            if result.sample is not None:
                self.logger.append_sample(result.sample)
            if result.terminal:
                if result.checked:
                    self.logger.finish_trial("success", "", now)
                    self.complete("gesture")
                else:
                    self.logger.finish_trial("fail", result.fail_reason, now)
                    self.state.status_message = result.fail_reason
            else:
                self.state.status_message = result.phase.value
        self.update_fps()

    def render(self) -> np.ndarray:
        canvas = np.zeros((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), dtype=np.uint8)
        center = config.CHECK_CENTER
        cv2.putText(
            canvas,
            "Air check: P positive | N negative | R next/reset | Mouse fallback | Q quit",
            (24, 36), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (190, 190, 190), 1, cv2.LINE_AA,
        )
        circle_color = (60, 210, 120) if self.state.checked else (220, 220, 220)
        cv2.circle(canvas, center, config.CHECK_RADIUS, circle_color, 3, cv2.LINE_AA)
        for first, second in zip(self.detector.trail, self.detector.trail[1:]):
            cv2.line(canvas, (int(first.x), int(first.y)), (int(second.x), int(second.y)), (90, 150, 255), 3, cv2.LINE_AA)

        if self.state.checked:
            check_points = [(center[0] - 52, center[1] - 2), (center[0] - 12, center[1] + 40), (center[0] + 62, center[1] - 48)]
            cv2.line(canvas, check_points[0], check_points[1], (60, 220, 120), 8, cv2.LINE_AA)
            cv2.line(canvas, check_points[1], check_points[2], (60, 220, 120), 8, cv2.LINE_AA)
            cv2.putText(canvas, "CHECKED", (center[0] - 68, center[1] + config.CHECK_RADIUS + 58), cv2.FONT_HERSHEY_SIMPLEX, 0.9, (60, 220, 120), 2, cv2.LINE_AA)

        if self.state.last_finger is not None:
            finger = self.state.last_finger
            cursor = (finger.screen_x, finger.screen_y)
            cv2.circle(canvas, cursor, config.CURSOR_RADIUS, (0, 180, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, cursor, config.CURSOR_RADIUS + 4, (255, 255, 255), 1, cv2.LINE_AA)

        finger_text = "-- / --"
        if self.state.last_finger is not None:
            finger_text = f"{self.state.last_finger.normalized_x:.2f} / {self.state.last_finger.normalized_y:.2f}"
        debug_lines = [
            f"FPS: {self.fps:5.1f}",
            f"Hand detected: {'YES' if self.state.last_finger else 'NO'}",
            f"Finger: x/y={finger_text}",
            f"State: {self.detector.state.value}",
            f"Gesture phase: {self.detector.phase.value}",
            f"Progress: {self.detector.progress} / 3",
            f"Path points: {len(self.detector.points)}",
            f"Draw time: {self.detector.draw_time(time.perf_counter()):.2f}s",
            f"Checked: {'TRUE' if self.state.checked else 'FALSE'}",
            f"Expected trial: {self.expected_type.upper()}",
            f"Completed: {self.logger.completed_trials} / {self.logger.target_total}",
        ]
        for index, line in enumerate(debug_lines):
            cv2.putText(canvas, line, (24, config.WINDOW_HEIGHT - 245 + index * 21), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (170, 210, 230), 1, cv2.LINE_AA)

        if self.tracker.error:
            cv2.putText(canvas, self.tracker.error[:120], (24, 76), cv2.FONT_HERSHEY_SIMPLEX, 0.52, (80, 120, 255), 1, cv2.LINE_AA)
        return canvas

    def close(self) -> None:
        self.logger.close(time.perf_counter())
        self.tracker.close()


def main() -> None:
    app = PrototypeApp()
    cv2.namedWindow(config.WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(config.WINDOW_NAME, config.WINDOW_WIDTH, config.WINDOW_HEIGHT)
    cv2.setMouseCallback(config.WINDOW_NAME, app.mouse_callback)
    app.tracker.start()
    app.logger.update_environment(app.tracker.camera_info())
    print(f"Results run: {app.logger.run_dir}")
    try:
        while True:
            app.tick()
            cv2.imshow(config.WINDOW_NAME, app.render())
            key = cv2.waitKey(max(1, int(1000 / config.TARGET_FPS))) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if key in (ord("r"), ord("R")):
                app.reset()
            if key in (ord("p"), ord("P")):
                app.expected_type = "positive"
            if key in (ord("n"), ord("N")):
                app.expected_type = "negative"
    finally:
        app.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
