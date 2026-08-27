"""Runnable webcam UI for continuous Open-Palm Fan Gesture validation."""

from __future__ import annotations

import time
from dataclasses import dataclass

import cv2
import numpy as np

import config
from fan_detector import FanDetector, Point
from fan_state import FanState
from hand_tracker import HandTracker, TrackingFrame
from interference_field import InterferenceField, PalmPhysicsInput
from palm_signal_processor import PalmMotion, PalmSignalProcessor
from test_logger import ExpectedType, TestLogger, calculate_metrics


@dataclass
class AppState:
    expected_type: ExpectedType = "positive"
    last_frame: TrackingFrame | None = None
    status_message: str = "Show an open palm and hold it steady"


class PrototypeApp:
    def __init__(self, results_root=None) -> None:
        self.state = AppState()
        self.detector = FanDetector()
        self.interference = InterferenceField()
        self.signal_processor = PalmSignalProcessor()
        self.palm_signal = PalmMotion(
            None, None, None, None, None, None, 0.0, 0.0, 0.0,
            1.0, 0.0, 0.0, False, False, False,
        )
        self.physics_palm: PalmPhysicsInput | None = None
        self._previous_physics_x: float | None = None
        self._previous_physics_y: float | None = None
        self._physics_stroke_id = 0
        self._physics_direction = 0
        self.tracker = HandTracker()
        self.logger = TestLogger(results_root or config.RESULTS_DIR)
        self.fps = 0.0
        self._last_frame_time = time.perf_counter()
        self._last_entity_time = self._last_frame_time
        self._last_tracking_sample_id = -1
        self._fps_samples: list[float] = []

    def reset(self, reason: str = "manual_reset") -> None:
        now = time.perf_counter()
        if self.logger.active is not None:
            self.logger.finish_trial("aborted", reason, now)
        self.detector.reset()
        self.interference.reset()
        self.signal_processor.reset()
        self.physics_palm = None
        self._previous_physics_x = None
        self._previous_physics_y = None
        self._physics_stroke_id = 0
        self._physics_direction = 0
        self._last_entity_time = now
        self.state.status_message = "Gesture reset"

    def update_fps(self) -> None:
        now = time.perf_counter()
        delta = max(1e-6, now - self._last_frame_time)
        self._last_frame_time = now
        self._fps_samples = (self._fps_samples + [1.0 / delta])[-20:]
        self.fps = sum(self._fps_samples) / len(self._fps_samples)

    def set_sensitivity_profile(self, profile: str) -> None:
        self.signal_processor.set_profile(profile)
        self.physics_palm = None
        self._previous_physics_x = None
        self._previous_physics_y = None
        self._physics_direction = 0
        self.state.status_message = f"Sensitivity profile: {profile.upper()}"

    def tick(self) -> None:
        now = time.perf_counter()
        entity_delta = max(0.0, min(0.10, now - self._last_entity_time))
        self._last_entity_time = now
        frame = self.tracker.read()
        self.state.last_frame = frame
        event = None
        if frame.sample_id != self._last_tracking_sample_id:
            self._last_tracking_sample_id = frame.sample_id
            sample_time = frame.sample_time if frame.sample_time > 0.0 else now
            palm_x = None if frame.palm_center is None else float(frame.palm_center.screen_x)
            palm_y = None if frame.palm_center is None else float(frame.palm_center.screen_y)
            self.palm_signal = self.signal_processor.update(
                palm_x,
                palm_y,
                sample_time,
                frame.open_palm,
                frame.hand_detected,
            )
            self.logger.append_signal(self.palm_signal, sample_time)
            point = None
            if self.palm_signal.active and self.palm_signal.gesture_x is not None:
                point = Point(self.palm_signal.gesture_x, self.palm_signal.gesture_y or 0.0)
            event = self.detector.update(point, frame.open_palm, sample_time)
            self.physics_palm = self._make_physics_palm()
        self.interference.update(entity_delta, self.physics_palm)

        if event is None:
            self.update_fps()
            return
        if event.started:
            self.logger.start_trial(self.state.expected_type, event.sample.timestamp if event.sample else now)
            for sample in event.initial_samples:
                self.logger.append_sample(sample)
        if event.sample is not None and self.logger.active is not None:
            self.logger.append_sample(event.sample)
        if event.completed:
            self.logger.finish_trial("success", "", now, event)
            self.state.status_message = "VALID FAN: continuous updates remain active"
        elif event.terminal:
            self.logger.finish_trial("fail", event.fail_reason, now, event)
            self.state.status_message = f"RESET: {event.fail_reason}"
        elif event.state == FanState.PALM_ARMING:
            self.state.status_message = "PALM_ARMING: keep the open palm steady"
        elif event.state == FanState.FAN_READY:
            self.state.status_message = "FAN_READY: move horizontally"
        elif event.state == FanState.FANNING:
            self.state.status_message = "FANNING: reverse direction with full sweeps"
        self.update_fps()

    def _make_physics_palm(self) -> PalmPhysicsInput | None:
        signal = self.palm_signal
        if (
            not signal.active
            or not signal.open_palm
            or signal.physics_x is None
            or signal.physics_y is None
        ):
            return None
        direction = 1 if signal.velocity_x > 0.0 else -1 if signal.velocity_x < 0.0 else 0
        if direction and direction != self._physics_direction:
            self._physics_stroke_id += 1
            self._physics_direction = direction
        previous_x = signal.physics_x if self._previous_physics_x is None else self._previous_physics_x
        previous_y = signal.physics_y if self._previous_physics_y is None else self._previous_physics_y
        self._previous_physics_x = signal.physics_x
        self._previous_physics_y = signal.physics_y
        return PalmPhysicsInput(
            signal.physics_x,
            signal.physics_y,
            signal.velocity_x,
            signal.velocity_y,
            previous_x,
            previous_y,
            stroke_phase="active",
            stroke_direction=direction,
            stroke_id=self._physics_stroke_id,
            auto_dispersion=True,
        )

    def render(self) -> np.ndarray:
        canvas = np.full((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), (10, 12, 18), dtype=np.uint8)
        split_x = int(config.INTERFERENCE_CENTER_X)
        for y in range(285, config.WINDOW_HEIGHT - 30, 22):
            cv2.line(canvas, (split_x, y), (split_x, min(y + 10, config.WINDOW_HEIGHT - 30)), (42, 48, 62), 1, cv2.LINE_AA)
        cv2.putText(canvas, "< DISPERSE", (40, config.WINDOW_HEIGHT - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.60, (125, 150, 185), 1, cv2.LINE_AA)
        cv2.putText(canvas, "DISPERSE >", (config.WINDOW_WIDTH - 170, config.WINDOW_HEIGHT - 24), cv2.FONT_HERSHEY_SIMPLEX, 0.60, (125, 150, 185), 1, cv2.LINE_AA)
        center_y = int(self.detector.anchor_y if self.detector.anchor_y is not None else config.WINDOW_HEIGHT / 2)
        cv2.line(canvas, (0, center_y), (config.WINDOW_WIDTH, center_y), (65, 70, 85), 1, cv2.LINE_AA)
        if self.detector.anchor_y is not None:
            upper = int(max(0, self.detector.anchor_y - config.MAX_VERTICAL_DRIFT))
            lower = int(min(config.WINDOW_HEIGHT - 1, self.detector.anchor_y + config.MAX_VERTICAL_DRIFT))
            cv2.line(canvas, (0, upper), (config.WINDOW_WIDTH, upper), (55, 105, 125), 1, cv2.LINE_AA)
            cv2.line(canvas, (0, lower), (config.WINDOW_WIDTH, lower), (55, 105, 125), 1, cv2.LINE_AA)

        self.interference.render(canvas)

        for first, second in zip(self.detector.trail, self.detector.trail[1:]):
            cv2.line(canvas, (int(first.x), int(first.y)), (int(second.x), int(second.y)), (100, 155, 255), 3, cv2.LINE_AA)

        frame = self.state.last_frame
        signal = self.palm_signal
        if signal.raw_x is not None and signal.raw_y is not None:
            cv2.circle(canvas, (int(signal.raw_x), int(signal.raw_y)), 8, (80, 90, 240), 1, cv2.LINE_AA)
        if signal.gesture_x is not None and signal.gesture_y is not None:
            cv2.circle(canvas, (int(signal.gesture_x), int(signal.gesture_y)), 11, (240, 170, 80), 1, cv2.LINE_AA)
        if signal.physics_x is not None and signal.physics_y is not None:
            color = (80, 235, 120) if signal.open_palm else (90, 100, 235)
            cv2.circle(canvas, (int(signal.physics_x), int(signal.physics_y)), 10, color, -1, cv2.LINE_AA)
            cv2.circle(canvas, (int(signal.physics_x), int(signal.physics_y)), 16, (245, 245, 245), 1, cv2.LINE_AA)

        metrics = calculate_metrics(self.logger.records)
        accuracy = metrics["accuracy"]
        accuracy_text = "n/a" if accuracy is None else f"{float(accuracy) * 100:.1f}%"
        raw_xy = "-- / --"
        physics_xy = "-- / --"
        gesture_xy = "-- / --"
        extensions = "I- M- R- P-"
        hand_status = "NO"
        if frame is not None:
            hand_status = "HOLD" if frame.palm_held else "YES" if frame.hand_detected else "NO"
            extensions = " ".join((
                f"I{'+' if frame.index_extended else '-'}",
                f"M{'+' if frame.middle_extended else '-'}",
                f"R{'+' if frame.ring_extended else '-'}",
                f"P{'+' if frame.pinky_extended else '-'}",
            ))
            if frame.palm_center is not None:
                raw_xy = f"{frame.palm_center.normalized_x:.3f} / {frame.palm_center.normalized_y:.3f}"
        if signal.physics_x is not None and signal.physics_y is not None:
            physics_xy = f"{signal.physics_x:.1f} / {signal.physics_y:.1f}"
        if signal.gesture_x is not None and signal.gesture_y is not None:
            gesture_xy = f"{signal.gesture_x:.1f} / {signal.gesture_y:.1f}"

        debug_lines = [
            "P positive | N negative | A adaptive | B baseline | R reset | Q quit",
            f"Loop FPS: {self.fps:5.1f}/{config.TARGET_FPS}    Tracking FPS: {self.tracker.tracking_fps:5.1f}    Hand: {hand_status}    Open Palm: {'YES' if frame and frame.open_palm else 'NO'}    {extensions}",
            f"Raw palm x/y: {raw_xy}    Physics x/y: {physics_xy}    Gesture x/y: {gesture_xy}",
            f"Fan State: {self.detector.state.value}    Arming: {self.detector.arming_progress * 100:5.1f}%",
            f"Direction: {self.detector.direction.upper()}    Sweep Count: {self.detector.sweep_count}",
            f"Amplitude: {self.detector.horizontal_amplitude:7.1f}px    Horizontal Velocity: {self.detector.horizontal_velocity:8.1f}px/s",
            f"Fan Strength: {self.detector.fan_strength:.3f}    Expected: {self.state.expected_type.upper()}",
            f"Raw dx / Physics dx: {signal.raw_delta_x:7.1f} / {signal.physics_delta_x:7.1f} px    Physics velocity X/Y: {signal.velocity_x:8.1f} / {signal.velocity_y:8.1f} px/s",
            f"Profile: {self.signal_processor.profile.upper()}    X gain: {signal.physics_gain:.2f}    Physics deadzone: {config.PHYSICS_DEADZONE:.1f}px    Input: {'ACTIVE' if signal.active and signal.open_palm else 'IDLE'}",
            f"Hand force: {'YES' if self.interference.hand_force_active else 'NO'}    Letters hit: {self.interference.letters_inside_influence_radius}    Auto scatter: {self.interference.auto_dispersion_strength:.2f}",
            f"Last impulse: {self.interference.last_impulse_strength:.1f}    Hit stroke: {self.interference.last_impulse_stroke_id}",
            f"Gravity: {config.LETTER_GRAVITY:.1f} px/s2    Mean letter vx/vy: {self.interference.mean_velocity_x:7.1f} / {self.interference.mean_velocity_y:7.1f}",
            f"Letters dispersed: {self.interference.dispersed_count}/{len(self.interference.entities)}    Clear: {self.interference.dispersed_ratio * 100:5.1f}%",
            f"Trials: {self.logger.completed_trials}/{self.logger.target_total}    TP/TN/FP/FN: {metrics['tp']}/{metrics['tn']}/{metrics['fp']}/{metrics['fn']}    Acc: {accuracy_text}",
            f"Camera: {self.tracker.error or 'ready'}",
            f"Status: {self.state.status_message}",
        ]
        for index, line in enumerate(debug_lines):
            cv2.putText(canvas, line, (24, 32 + index * 24), cv2.FONT_HERSHEY_SIMPLEX, 0.53, (195, 220, 235), 1, cv2.LINE_AA)
        return canvas

    def close(self) -> None:
        self.logger.close(time.perf_counter())
        self.tracker.close()


def main() -> None:
    app = PrototypeApp()
    cv2.namedWindow(config.WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(config.WINDOW_NAME, config.WINDOW_WIDTH, config.WINDOW_HEIGHT)
    app.tracker.start()
    app.logger.update_environment(app.tracker.camera_info())
    print(f"Results run: {app.logger.run_dir}")
    frame_interval = 1.0 / config.TARGET_FPS
    next_frame_at = time.perf_counter()
    try:
        while True:
            app.tick()
            cv2.imshow(config.WINDOW_NAME, app.render())
            key = cv2.waitKey(1) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if key in (ord("r"), ord("R")):
                app.reset()
            elif key in (ord("p"), ord("P")):
                app.state.expected_type = "positive"
            elif key in (ord("n"), ord("N")):
                app.state.expected_type = "negative"
            elif key in (ord("a"), ord("A")):
                app.set_sensitivity_profile(config.SENSITIVITY_ADAPTIVE)
            elif key in (ord("b"), ord("B")):
                app.set_sensitivity_profile(config.SENSITIVITY_BASELINE)
            next_frame_at += frame_interval
            remaining = next_frame_at - time.perf_counter()
            if remaining > 0.0:
                time.sleep(remaining)
            else:
                next_frame_at = time.perf_counter()
    finally:
        app.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
