"""Webcam + MediaPipe Hand Landmarker wrapper.

The rest of the prototype only receives a screen-space index-finger point.
Camera/model failures are converted into a readable error string so the UI
can remain usable with the mouse fallback.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

try:
    import cv2
    import mediapipe as mp
except ImportError as exc:  # Keep importable enough for the mouse-only fallback.
    cv2 = None
    mp = None
    IMPORT_ERROR = exc
else:
    IMPORT_ERROR = None

import config


@dataclass(frozen=True)
class FingerPoint:
    """Index fingertip in both MediaPipe-normalized and window coordinates."""

    normalized_x: float
    normalized_y: float
    screen_x: int
    screen_y: int


class HandTracker:
    """Owns the camera and one MediaPipe Hand Landmarker instance."""

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
        self._timestamp_ms = 0

    @property
    def available(self) -> bool:
        return self.capture is not None and self.landmarker is not None

    def camera_info(self) -> dict[str, object]:
        """Return only values OpenCV can actually report for this opened camera."""

        if self.capture is None:
            return {"resolution": "unknown", "fps": "unknown"}
        width = int(self.capture.get(cv2.CAP_PROP_FRAME_WIDTH))
        height = int(self.capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
        fps = float(self.capture.get(cv2.CAP_PROP_FPS))
        return {
            "resolution": f"{width}x{height}" if width > 0 and height > 0 else "unknown",
            "fps": round(fps, 3) if fps > 0 else "unknown",
        }

    def start(self) -> bool:
        """Try to initialize MediaPipe and the webcam; never raises to the UI."""

        if IMPORT_ERROR is not None:
            self.error = f"依赖缺失: {IMPORT_ERROR}"
            return False
        if not self.model_path.exists():
            self.error = (
                f"缺少模型文件: {self.model_path.name}。"
                "先运行 python download_model.py。"
            )
            return False

        try:
            # Passing bytes avoids a Windows/MediaPipe native-loader issue with
            # non-ASCII project paths such as "Prototyp_über_Hand".
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
                # CAP_DSHOW is reliable on many Windows machines, but not all.
                self.capture.release()
                self.capture = cv2.VideoCapture(self.camera_index)
            if not self.capture.isOpened():
                self.error = f"无法打开摄像头 index={self.camera_index}。"
                self.close()
                return False

            self.capture.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
            self.capture.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)
            self.error = None
            return True
        except Exception as exc:  # MediaPipe/OpenCV errors must not kill fallback UI.
            self.error = f"手部追踪初始化失败: {exc}"
            self.close()
            return False

    def read_index_finger(
        self,
        window_width: int = config.WINDOW_WIDTH,
        window_height: int = config.WINDOW_HEIGHT,
    ) -> Optional[FingerPoint]:
        """Read one frame and return INDEX_FINGER_TIP mapped to window pixels."""

        if not self.available:
            return None

        ok, frame = self.capture.read()
        if not ok or frame is None:
            self.error = "摄像头暂时无法读取画面。"
            return None

        if config.MIRROR_CAMERA:
            frame = cv2.flip(frame, 1)

        try:
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            self._timestamp_ms += max(1, int(1000 / config.TARGET_FPS))
            result = self.landmarker.detect_for_video(image, self._timestamp_ms)
            if not result.hand_landmarks:
                return None

            # Landmark 8 is INDEX_FINGER_TIP in MediaPipe's 21-point hand model.
            tip = result.hand_landmarks[0][8]
            normalized_x = min(1.0, max(0.0, float(tip.x)))
            normalized_y = min(1.0, max(0.0, float(tip.y)))
            return FingerPoint(
                normalized_x=normalized_x,
                normalized_y=normalized_y,
                screen_x=min(window_width - 1, int(normalized_x * window_width)),
                screen_y=min(window_height - 1, int(normalized_y * window_height)),
            )
        except Exception as exc:
            self.error = f"手部追踪单帧失败: {exc}"
            return None

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
