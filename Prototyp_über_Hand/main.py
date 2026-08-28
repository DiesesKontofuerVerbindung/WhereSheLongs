"""Runnable v0.3 UI: p1 scene + fullscreen invisible ✓; success swaps to p2."""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

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
    scene: str = "p1"  # p1 -> p2 after successful gesture/mouse check
    hint_started_at: float = field(default_factory=time.perf_counter)


def _load_scene(path: Path) -> np.ndarray:
    image = None
    try:
        data = np.fromfile(str(path), dtype=np.uint8)
        if data.size > 0:
            image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    except OSError:
        image = None
    if image is None:
        blank = np.full((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), 32, dtype=np.uint8)
        cv2.putText(
            blank,
            f"Missing scene: {path.name}",
            (40, config.WINDOW_HEIGHT // 2),
            cv2.FONT_HERSHEY_SIMPLEX,
            0.8,
            (80, 80, 255),
            2,
            cv2.LINE_AA,
        )
        return blank
    if image.shape[1] != config.WINDOW_WIDTH or image.shape[0] != config.WINDOW_HEIGHT:
        image = cv2.resize(image, (config.WINDOW_WIDTH, config.WINDOW_HEIGHT), interpolation=cv2.INTER_AREA)
    return image


def _chinese_font(size: int) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    candidates = (
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\msyh.ttf"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsun.ttc"),
    )
    for path in candidates:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


_HINT_FONT = _chinese_font(config.HINT_FONT_SIZE)


def _draw_hint(canvas: np.ndarray, text: str, center: tuple[int, int], alpha: float = 1.0) -> None:
    """Draw centered Chinese hint below the checklist; alpha fades out."""

    if alpha <= 0.02:
        return
    rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)
    pil = Image.fromarray(rgb)
    draw = ImageDraw.Draw(pil)
    bbox = draw.textbbox((0, 0), text, font=_HINT_FONT)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = int(center[0] - text_w / 2)
    y = int(center[1] - text_h / 2)
    pad = 10
    # Soft dark plate so light checklist background stays readable.
    overlay = Image.new("RGBA", pil.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    plate_alpha = int(110 * alpha)
    text_alpha = int(255 * alpha)
    overlay_draw.rounded_rectangle(
        (x - pad, y - pad // 2, x + text_w + pad, y + text_h + pad // 2),
        radius=8,
        fill=(30, 28, 24, plate_alpha),
    )
    overlay_draw.text((x, y), text, font=_HINT_FONT, fill=(245, 240, 230, text_alpha))
    composed = Image.alpha_composite(pil.convert("RGBA"), overlay).convert("RGB")
    canvas[:, :, :] = cv2.cvtColor(np.asarray(composed), cv2.COLOR_RGB2BGR)


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
        self.scene_p1 = _load_scene(config.SCENE_P1_PATH)
        self.scene_p2 = _load_scene(config.SCENE_P2_PATH)

    def reset(self) -> None:
        now = time.perf_counter()
        if self.logger.active is not None:
            self.logger.finish_trial("aborted", "reset", now)
        self.state = AppState(scene="p1", hint_started_at=now)
        self.detector.reset()

    def complete(self, source: str) -> None:
        now = time.perf_counter()
        if source == "mouse" and self.logger.active is not None:
            self.logger.finish_trial("aborted", "mouse_fallback", now)
        self.state.checked = True
        self.state.check_source = source
        self.state.gesture_success = source == "gesture"
        self.detector.mark_checked()
        self.state.scene = "p2"
        self.state.status_message = f"checked via {source} -> p2"

    def mouse_callback(self, event: int, x: int, y: int, _flags: int, _param) -> None:
        # Fullscreen hit area: any click on p1 completes (mouse fallback).
        if event != cv2.EVENT_LBUTTONDOWN or self.state.checked or self.state.scene != "p1":
            return
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
        if self.state.scene == "p1" and not self.state.checked:
            point = None if finger is None else Point(finger.screen_x, finger.screen_y)
            result = self.detector.update(point, now)
            if result.started:
                self.logger.start_trial(self.expected_type, now)
                for initial_sample in result.initial_samples:
                    self.logger.append_sample(initial_sample)
            if result.candidate_rejected:
                self.logger.discard_active_trial()
                self.state.status_message = f"candidate rejected: {result.fail_reason}"
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
        canvas = (self.scene_p2 if self.state.scene == "p2" else self.scene_p1).copy()

        if self.state.scene == "p1":
            if config.SHOW_DETECTION_CIRCLE:
                cv2.circle(
                    canvas,
                    config.CHECK_CENTER,
                    config.CHECK_RADIUS,
                    (0, 200, 255),
                    2,
                    cv2.LINE_AA,
                )
            if config.SHOW_STROKE_TRAIL:
                for first, second in zip(self.detector.trail, self.detector.trail[1:]):
                    cv2.line(
                        canvas,
                        (int(first.x), int(first.y)),
                        (int(second.x), int(second.y)),
                        (90, 150, 255),
                        3,
                        cv2.LINE_AA,
                    )

            elapsed = time.perf_counter() - self.state.hint_started_at
            if elapsed < config.HINT_DURATION_SEC:
                # Soft fade in the last 0.4s.
                remain = config.HINT_DURATION_SEC - elapsed
                alpha = 1.0 if remain > 0.4 else max(0.0, remain / 0.4)
                _draw_hint(canvas, config.HINT_TEXT, config.HINT_CENTER, alpha)

        if self.state.last_finger is not None:
            finger = self.state.last_finger
            cursor = (finger.screen_x, finger.screen_y)
            cv2.circle(canvas, cursor, config.CURSOR_RADIUS, (0, 180, 255), -1, cv2.LINE_AA)
            cv2.circle(canvas, cursor, config.CURSOR_RADIUS + 4, (255, 255, 255), 1, cv2.LINE_AA)
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
