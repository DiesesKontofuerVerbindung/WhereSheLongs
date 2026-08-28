"""Webcam + MediaPipe Hand Landmarker wrapper."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

try:
    import cv2
    import mediapipe as mp
except ImportError as exc:
    cv2 = None
    mp = None
    IMPORT_ERROR = exc
else:
    IMPORT_ERROR = None

import config


@dataclass(frozen=True)
class FingerPoint:
    normalized_x: float
    normalized_y: float
    screen_x: int
    screen_y: int


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
        self._timestamp_ms = 0
        self.last_frame = None  # BGR preview frame
        self._fail_reads = 0

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
            "index": self.camera_index,
        }

    def _open_capture(self, index: int):
        backends = [cv2.CAP_DSHOW, cv2.CAP_MSMF, cv2.CAP_ANY]
        for backend in backends:
            cap = cv2.VideoCapture(index, backend)
            if not cap.isOpened():
                cap.release()
                continue
            cap.set(cv2.CAP_PROP_FRAME_WIDTH, config.CAMERA_WIDTH)
            cap.set(cv2.CAP_PROP_FRAME_HEIGHT, config.CAMERA_HEIGHT)
            # Warm up — some webcams return empty frames for the first few reads.
            ok = False
            frame = None
            for _ in range(12):
                ok, frame = cap.read()
                if ok and frame is not None and frame.size > 0:
                    break
            if ok and frame is not None:
                self.last_frame = frame.copy()
                return cap
            cap.release()
        return None

    def start(self) -> bool:
        if IMPORT_ERROR is not None:
            self.error = f"依赖缺失: {IMPORT_ERROR}"
            return False
        if not self.model_path.exists():
            self.error = f"缺少模型文件: {self.model_path.name}"
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

            indices = [self.camera_index] + [i for i in range(3) if i != self.camera_index]
            for index in indices:
                cap = self._open_capture(index)
                if cap is not None:
                    self.capture = cap
                    self.camera_index = index
                    self.error = None
                    self._fail_reads = 0
                    print(f"[camera] opened index={index} info={self.camera_info()}")
                    return True

            self.error = "无法打开摄像头（请检查隐私设置：允许桌面应用访问相机）"
            self.close()
            print(f"[camera] FAILED: {self.error}")
            return False
        except Exception as exc:
            self.error = f"手部追踪初始化失败: {exc}"
            self.close()
            print(f"[camera] EXCEPTION: {self.error}")
            return False

    def _reopen(self) -> None:
        print("[camera] reopening after read failures...")
        if self.capture is not None:
            self.capture.release()
            self.capture = None
        for index in range(3):
            cap = self._open_capture(index)
            if cap is not None:
                self.capture = cap
                self.camera_index = index
                self._fail_reads = 0
                self.error = None
                print(f"[camera] reopened index={index}")
                return
        self.error = "摄像头重连失败"

    def read_index_finger(
        self,
        window_width: int = config.WINDOW_WIDTH,
        window_height: int = config.WINDOW_HEIGHT,
    ) -> Optional[FingerPoint]:
        if not self.available:
            return None

        ok, frame = self.capture.read()
        if not ok or frame is None or frame.size == 0:
            self._fail_reads += 1
            self.error = "摄像头暂时无法读取画面。"
            if self._fail_reads >= 15:
                self._reopen()
            return None

        self._fail_reads = 0
        if config.MIRROR_CAMERA:
            frame = cv2.flip(frame, 1)
        self.last_frame = frame

        try:
            rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
            self._timestamp_ms += max(1, int(1000 / config.TARGET_FPS))
            result = self.landmarker.detect_for_video(image, self._timestamp_ms)
            if not result.hand_landmarks:
                return None

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
        self.last_frame = None
