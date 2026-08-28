"""Runnable UI: p1 -> gesture check -> p2, invisible full-screen detector."""

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
    scene: str = "p1"
    started_at: float = field(default_factory=time.perf_counter)


def _load_scene(path: Path) -> np.ndarray:
    # cv2.imread fails on non-ASCII Windows paths (e.g. Prototyp_über_Hand).
    image = None
    if path.exists():
        data = np.fromfile(str(path), dtype=np.uint8)
        image = cv2.imdecode(data, cv2.IMREAD_COLOR)
    if image is None:
        blank = np.full((config.WINDOW_HEIGHT, config.WINDOW_WIDTH, 3), 32, dtype=np.uint8)
        return blank
    if image.shape[1] != config.WINDOW_WIDTH or image.shape[0] != config.WINDOW_HEIGHT:
        image = cv2.resize(image, (config.WINDOW_WIDTH, config.WINDOW_HEIGHT), interpolation=cv2.INTER_AREA)
    return image


def _load_hint_font(size: int) -> ImageFont.ImageFont:
    candidates = [
        Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\msyh.ttf"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsun.ttc"),
    ]
    for path in candidates:
        if path.exists():
            try:
                return ImageFont.truetype(str(path), size=size)
            except OSError:
                continue
    return ImageFont.load_default()


class PrototypeApp:
    def __init__(self) -> None:
        self.state = AppState()
        self.detector = GestureDetector()
        self.tracker = HandTracker()
        self.logger = TestLogger()
        self.expected_type: ExpectedType = "positive"
        self.scene_p1 = _load_scene(config.SCENE_P1_PATH)
        self.scene_p2 = _load_scene(config.SCENE_P2_PATH)
        self._hint_font = _load_hint_font(config.HINT_FONT_SIZE)

    def reset(self) -> None:
        now = time.perf_counter()
        if self.logger.active is not None:
            self.logger.finish_trial("aborted", "reset", now)
        self.state = AppState(scene="p1", started_at=now)
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

    def mouse_callback(self, event: int, x: int, y: int, _flags: int, _param) -> None:
        # Full-screen invisible target: any click on p1 counts as fallback check.
        if event != cv2.EVENT_LBUTTONDOWN or self.state.checked or self.state.scene != "p1":
            return
        self.complete("mouse")

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
            if result.sample is not None:
                self.logger.append_sample(result.sample)
            if result.terminal:
                if result.checked:
                    self.logger.finish_trial("success", "", now)
                    self.complete("gesture")
                else:
                    self.logger.finish_trial("fail", result.fail_reason, now)

    def _draw_hint(self, canvas: np.ndarray, now: float) -> np.ndarray:
        if self.state.scene != "p1":
            return canvas
        age = now - self.state.started_at
        if age >= config.HINT_DURATION_SEC:
            return canvas
        # Fade out in the last 0.6s.
        alpha = 1.0
        fade_start = config.HINT_DURATION_SEC - 0.6
        if age > fade_start:
            alpha = max(0.0, 1.0 - (age - fade_start) / 0.6)

        rgb = cv2.cvtColor(canvas, cv2.COLOR_BGR2RGB)
        pil_image = Image.fromarray(rgb)
        draw = ImageDraw.Draw(pil_image)
        text = config.HINT_TEXT
        bbox = draw.textbbox((0, 0), text, font=self._hint_font)
        text_w = bbox[2] - bbox[0]
        text_h = bbox[3] - bbox[1]
        x = int(config.HINT_CENTER[0] - text_w / 2)
        y = int(config.HINT_CENTER[1] - text_h / 2)
        fill = (55, 48, 42, int(255 * alpha))
        # Pillow RGB image has no alpha channel; blend manually via overlay.
        overlay = Image.new("RGBA", pil_image.size, (0, 0, 0, 0))
        overlay_draw = ImageDraw.Draw(overlay)
        overlay_draw.text((x, y), text, font=self._hint_font, fill=fill)
        composed = Image.alpha_composite(pil_image.convert("RGBA"), overlay).convert("RGB")
        return cv2.cvtColor(np.array(composed), cv2.COLOR_RGB2BGR)

    def _draw_camera_preview(self, canvas: np.ndarray) -> np.ndarray:
        """Small live webcam PIP so it's obvious the camera is running."""

        if not getattr(config, "SHOW_CAMERA_PREVIEW", True):
            return canvas
        frame = self.tracker.last_frame
        preview_w, preview_h = 192, 108
        margin = 16
        x0 = margin
        y0 = config.WINDOW_HEIGHT - preview_h - margin
        if frame is None:
            cv2.rectangle(canvas, (x0, y0), (x0 + preview_w, y0 + preview_h), (30, 30, 30), -1)
            cv2.putText(
                canvas,
                "CAM?",
                (x0 + 60, y0 + 60),
                cv2.FONT_HERSHEY_SIMPLEX,
                0.7,
                (80, 80, 255),
                2,
                cv2.LINE_AA,
            )
            return canvas
        preview = cv2.resize(frame, (preview_w, preview_h), interpolation=cv2.INTER_AREA)
        # Draw fingertip on preview when detected.
        if self.state.last_finger is not None:
            px = int(self.state.last_finger.normalized_x * preview_w)
            py = int(self.state.last_finger.normalized_y * preview_h)
            cv2.circle(preview, (px, py), 5, (0, 220, 255), -1, cv2.LINE_AA)
        canvas[y0 : y0 + preview_h, x0 : x0 + preview_w] = preview
        cv2.rectangle(canvas, (x0, y0), (x0 + preview_w, y0 + preview_h), (220, 220, 220), 1)
        return canvas

    def render(self) -> np.ndarray:
        canvas = (self.scene_p2 if self.state.scene == "p2" else self.scene_p1).copy()
        canvas = self._draw_hint(canvas, time.perf_counter())
        return self._draw_camera_preview(canvas)

    def close(self) -> None:
        self.logger.close(time.perf_counter())
        self.tracker.close()


def main() -> None:
    app = PrototypeApp()
    cv2.namedWindow(config.WINDOW_NAME, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(config.WINDOW_NAME, config.WINDOW_WIDTH, config.WINDOW_HEIGHT)
    cv2.setMouseCallback(config.WINDOW_NAME, app.mouse_callback)
    ok = app.tracker.start()
    app.logger.update_environment(app.tracker.camera_info())
    print(f"Results run: {app.logger.run_dir}")
    print(f"Camera start: {ok} error={app.tracker.error!r} info={app.tracker.camera_info()}")
    log_path = config.PROJECT_DIR / "camera_status.txt"
    log_path.write_text(
        f"ok={ok}\nerror={app.tracker.error}\ninfo={app.tracker.camera_info()}\n",
        encoding="utf-8",
    )
    try:
        while True:
            app.tick()
            cv2.imshow(config.WINDOW_NAME, app.render())
            key = cv2.waitKey(max(1, int(1000 / config.TARGET_FPS))) & 0xFF
            if key in (ord("q"), ord("Q"), 27):
                break
            if key in (ord("r"), ord("R")):
                app.reset()
    finally:
        app.close()
        cv2.destroyAllWindows()


if __name__ == "__main__":
    main()
