"""Webcam + MediaPipe palm feature extraction for the Fan prototype."""

from __future__ import annotations

from dataclasses import dataclass
from math import acos, degrees, hypot
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
class PalmPoint:
    normalized_x: float
    normalized_y: float
    screen_x: int
    screen_y: int


@dataclass(frozen=True)
class TrackingFrame:
    hand_detected: bool
    palm_center: PalmPoint | None
    open_palm: bool
    index_extended: bool = False
    middle_extended: bool = False
    ring_extended: bool = False
    pinky_extended: bool = False
    palm_held: bool = False


@dataclass(frozen=True)
class HandFeatures:
    normalized_x: float
    normalized_y: float
    index_extended: bool
    middle_extended: bool
    ring_extended: bool
    pinky_extended: bool

    @property
    def open_palm(self) -> bool:
        return all((self.index_extended, self.middle_extended, self.ring_extended, self.pinky_extended))


def _xy(landmark: object) -> tuple[float, float]:
    return float(landmark.x), float(landmark.y)

def _joint_angle(first: object, joint: object, last: object) -> float:
    first_x, first_y = _xy(first)
    joint_x, joint_y = _xy(joint)
    last_x, last_y = _xy(last)
    left = (first_x - joint_x, first_y - joint_y)
    right = (last_x - joint_x, last_y - joint_y)
    denominator = hypot(*left) * hypot(*right)
    if denominator <= 1e-9:
        return 0.0
    cosine = max(-1.0, min(1.0, (left[0] * right[0] + left[1] * right[1]) / denominator))
    return degrees(acos(cosine))

def _finger_extended(landmarks: list[object], mcp: int, pip: int, dip: int, tip: int, palm: tuple[float, float]) -> bool:
    angle = _joint_angle(landmarks[mcp], landmarks[pip], landmarks[tip])
    palm_x, palm_y = palm
    tip_x, tip_y = _xy(landmarks[tip])
    pip_x, pip_y = _xy(landmarks[pip])
    tip_radius = hypot(tip_x - palm_x, tip_y - palm_y)
    pip_radius = hypot(pip_x - palm_x, pip_y - palm_y)
    return (
        angle >= config.FINGER_EXTENDED_MIN_ANGLE
        and tip_radius >= pip_radius * config.FINGER_EXTENDED_DISTANCE_RATIO
        and _joint_angle(landmarks[pip], landmarks[dip], landmarks[tip]) >= config.FINGER_EXTENDED_MIN_ANGLE
    )


def extract_hand_features(landmarks: list[object]) -> HandFeatures:
    """Return rotation-tolerant palm center and four-finger extension flags."""

    if len(landmarks) < 21:
        raise ValueError("MediaPipe hand landmarks must contain 21 points")
    palm_indices = (0, 5, 9, 13, 17)
    palm_x = sum(float(landmarks[index].x) for index in palm_indices) / len(palm_indices)
    palm_y = sum(float(landmarks[index].y) for index in palm_indices) / len(palm_indices)
    palm = (palm_x, palm_y)
    fingers = (
        _finger_extended(landmarks, 5, 6, 7, 8, palm),
        _finger_extended(landmarks, 9, 10, 11, 12, palm),
        _finger_extended(landmarks, 13, 14, 15, 16, palm),
        _finger_extended(landmarks, 17, 18, 19, 20, palm),
    )
    return HandFeatures(palm_x, palm_y, *fingers)


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
        self._last_valid_frame: TrackingFrame | None = None
        self._last_valid_frame_at: float | None = None

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

    def read(self) -> TrackingFrame:
        now = time.monotonic()
        if not self.available:
            self.hand_detected = False
            return self._held_or_empty_frame(now)
        ok, frame = self.capture.read()
        if not ok or frame is None:
            self.hand_detected = False
            self.error = "摄像头暂时无法读取画面。"
            return self._held_or_empty_frame(now)
        if config.MIRROR_CAMERA:
            frame = cv2.flip(frame, 1)
        try:
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            self._timestamp_ms += max(1, int(1000 / config.TARGET_FPS))
            result = self.landmarker.detect_for_video(image, self._timestamp_ms)
            if not result.hand_landmarks:
                self.hand_detected = False
                return self._held_or_empty_frame(now)
            landmarks = result.hand_landmarks[0]
            self.hand_detected = True
            features = extract_hand_features(landmarks)
            normalized_x = max(0.0, min(1.0, features.normalized_x))
            normalized_y = max(0.0, min(1.0, features.normalized_y))
            palm = PalmPoint(
                normalized_x=normalized_x,
                normalized_y=normalized_y,
                screen_x=min(config.WINDOW_WIDTH - 1, int(normalized_x * config.WINDOW_WIDTH)),
                screen_y=min(config.WINDOW_HEIGHT - 1, int(normalized_y * config.WINDOW_HEIGHT)),
            )
            frame = TrackingFrame(
                True,
                palm,
                features.open_palm,
                features.index_extended,
                features.middle_extended,
                features.ring_extended,
                features.pinky_extended,
            )
            self._last_valid_frame = frame
            self._last_valid_frame_at = now
            return frame
        except Exception as exc:
            self.hand_detected = False
            self.error = f"手部追踪单帧失败: {exc}"
            return self._held_or_empty_frame(now)

    def _held_or_empty_frame(self, now: float) -> TrackingFrame:
        if (
            self._last_valid_frame is not None
            and self._last_valid_frame_at is not None
            and now - self._last_valid_frame_at <= config.CURSOR_HOLD_TIME
        ):
            previous = self._last_valid_frame
            return TrackingFrame(
                False,
                previous.palm_center,
                previous.open_palm,
                previous.index_extended,
                previous.middle_extended,
                previous.ring_extended,
                previous.pinky_extended,
                palm_held=True,
            )
        return TrackingFrame(False, None, False)

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
        self._last_valid_frame = None
        self._last_valid_frame_at = None
