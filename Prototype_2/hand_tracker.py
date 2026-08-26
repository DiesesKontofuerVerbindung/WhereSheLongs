"""Webcam + MediaPipe tracker with one-finger and two-finger control modes."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import time
from typing import Optional

try:
    import cv2
    import mediapipe as mp
except ImportError as exc:  # The UI remains mouse-usable without camera dependencies.
    cv2 = None
    mp = None
    IMPORT_ERROR = exc
else:
    IMPORT_ERROR = None

import config


@dataclass(frozen=True)
class CursorPoint:
    normalized_x: float
    normalized_y: float
    screen_x: int
    screen_y: int


@dataclass(frozen=True)
class TrackingFrame:
    hand_detected: bool
    finger_mode: str
    cursor: CursorPoint | None
    index_extended: bool = False
    middle_extended: bool = False
    cursor_held: bool = False


def _is_extended(landmarks: list[object], tip_index: int, pip_index: int) -> bool:
    tip = landmarks[tip_index]
    pip = landmarks[pip_index]
    return float(tip.y) < float(pip.y) - config.FINGER_EXTENSION_MARGIN


def valid_finger_mode(landmarks: list[object], finger_mode: str) -> tuple[bool, bool]:
    """Return index/middle extension flags and reject folded fingers in TWO_FINGER mode."""

    index_extended = _is_extended(landmarks, 8, 6)
    middle_extended = _is_extended(landmarks, 12, 10)
    if finger_mode == config.TWO_FINGER:
        return index_extended and middle_extended, middle_extended
    return index_extended, middle_extended


def map_normalized_y_to_screen(
    normalized_y: float,
    window_height: int = config.WINDOW_HEIGHT,
) -> int:
    """Map the reachable camera Y band into the full playable screen height."""

    input_span = config.CURSOR_Y_INPUT_MAX - config.CURSOR_Y_INPUT_MIN
    if input_span <= 0:
        raise ValueError("CURSOR_Y_INPUT_MAX must be greater than CURSOR_Y_INPUT_MIN")
    input_progress = (normalized_y - config.CURSOR_Y_INPUT_MIN) / input_span
    input_progress = max(0.0, min(1.0, input_progress))
    output_ratio = config.CURSOR_Y_OUTPUT_MIN_RATIO + input_progress * (
        config.CURSOR_Y_OUTPUT_MAX_RATIO - config.CURSOR_Y_OUTPUT_MIN_RATIO
    )
    return int(output_ratio * window_height)


class HandTracker:
    def __init__(
        self,
        model_path: Path = config.MODEL_PATH,
        camera_index: int = config.CAMERA_INDEX,
    ) -> None:
        self.model_path = Path(model_path)
        self.camera_index = camera_index
        self.capture = None
        self.landmarker = None
        self.error: Optional[str] = None
        self.hand_detected = False
        self._timestamp_ms = 0
        self._last_valid_cursor: CursorPoint | None = None
        self._last_valid_cursor_at: float | None = None

    @property
    def available(self) -> bool:
        return self.capture is not None and self.landmarker is not None

    def camera_info(self) -> dict[str, object]:
        if self.capture is None or cv2 is None:
            return {"resolution": "unknown", "fps": "unknown"}
        width = int(self.capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(self.capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = float(self.capture.get(cv2.CAP_PROP_FPS))
        return {
            "resolution": f"{width}x{height}" if width > 0 and height > 0 else "unknown",
            "fps": round(fps, 3) if fps > 0 else "unknown",
        }

    def start(self) -> bool:
        if IMPORT_ERROR is not None:
            self.error = f"依赖缺失: {IMPORT_ERROR}"
            return False
        if not self.model_path.exists():
            self.error = f"缺少模型文件: {self.model_path.name}。摄像头停用，鼠标 fallback 仍可用。"
            return False
        try:
            model_bytes = self.model_path.read_bytes()
            base_options = mp.tasks.BaseOptions(model_asset_buffer=model_bytes)
            options = mp.tasks.vision.HandLandmarkerOptions(
                base_options=base_options,
                running_mode=mp.tasks.vision.RunningMode.VIDEO,
                num_hands=config.NUM_HANDS,
                min_hand_detection_confidence=config.MIN_HAND_DETECTION_CONFIDENCE,
                min_hand_presence_confidence=config.MIN_HAND_PRESENCE_CONFIDENCE,
                min_tracking_confidence=config.MIN_HAND_TRACKING_CONFIDENCE,
            )
            self.landmarker = mp.tasks.vision.HandLandmarker.create_from_options(options)
            self.capture = cv2.VideoCapture(self.camera_index, cv2.CAP_DSHOW)
            if not self.capture.isOpened():
                self.capture.release()
                self.capture = cv2.VideoCapture(self.camera_index)
            if not self.capture.isOpened():
                self.error = f"无法打开摄像头 index={self.camera_index}。鼠标 fallback 仍可用。"
                self.close()
                return False
            self.capture.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
            self.capture.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)
            self.capture.set(cv2.CAP_PROP_BUFFERSIZE, config.CAMERA_BUFFER_SIZE)
            self.error = None
            return True
        except Exception as exc:
            self.error = f"手部追踪初始化失败: {exc}"
            self.close()
            return False

    def read(self, finger_mode: str) -> TrackingFrame:
        now = time.monotonic()
        if not self.available:
            self.hand_detected = False
            return self._held_or_empty_frame(finger_mode, now)
        ok, frame = self.capture.read()
        if not ok or frame is None:
            self.hand_detected = False
            self.error = "摄像头暂时无法读取画面。"
            return self._held_or_empty_frame(finger_mode, now)
        if config.MIRROR_CAMERA:
            frame = cv2.flip(frame, 1)
        try:
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            self._timestamp_ms += max(1, int(1000 / config.TARGET_FPS))
            result = self.landmarker.detect_for_video(image, self._timestamp_ms)
            if not result.hand_landmarks:
                self.hand_detected = False
                return self._held_or_empty_frame(finger_mode, now)
            landmarks = result.hand_landmarks[0]
            self.hand_detected = True
            mode_valid, middle_extended = valid_finger_mode(landmarks, finger_mode)
            index_extended = _is_extended(landmarks, 8, 6)
            if not mode_valid:
                return TrackingFrame(True, finger_mode, None, index_extended, middle_extended)
            points = [landmarks[8]] if finger_mode == config.ONE_FINGER else [landmarks[8], landmarks[12]]
            normalized_x = max(0.0, min(1.0, sum(float(point.x) for point in points) / len(points)))
            normalized_y = max(0.0, min(1.0, sum(float(point.y) for point in points) / len(points)))
            cursor = CursorPoint(
                normalized_x=normalized_x,
                normalized_y=normalized_y,
                screen_x=min(config.WINDOW_WIDTH - 1, int(normalized_x * config.WINDOW_WIDTH)),
                screen_y=map_normalized_y_to_screen(normalized_y),
            )
            self._last_valid_cursor = cursor
            self._last_valid_cursor_at = now
            return TrackingFrame(True, finger_mode, cursor, index_extended, middle_extended)
        except Exception as exc:
            self.hand_detected = False
            self.error = f"手部追踪单帧失败: {exc}"
            return self._held_or_empty_frame(finger_mode, now)

    def _held_or_empty_frame(self, finger_mode: str, now: float) -> TrackingFrame:
        if (
            self._last_valid_cursor is not None
            and self._last_valid_cursor_at is not None
            and now - self._last_valid_cursor_at <= config.CURSOR_HOLD_TIME
        ):
            return TrackingFrame(False, finger_mode, self._last_valid_cursor, cursor_held=True)
        return TrackingFrame(False, finger_mode, None)

    def close(self) -> None:
        if self.capture is not None:
            self.capture.release()
            self.capture = None
        if self.landmarker is not None:
            try:
                self.landmarker.close()
            except Exception:
                pass
            self.landmarker = None
        self._last_valid_cursor = None
        self._last_valid_cursor_at = None
