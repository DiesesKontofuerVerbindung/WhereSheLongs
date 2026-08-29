#!/usr/bin/env python3
"""Headless webcam eye-state detector for Godot. No preview window / no JPEG — state only."""

from __future__ import annotations

import json
import math
import os
import socket
import sys
import threading
import time
import traceback

HOST = "127.0.0.1"
PORT = 8766
CLOSE_EAR = 0.21
OPEN_EAR = 0.24
CLOSE_BLINK = 0.45
OPEN_BLINK = 0.22
LEFT_EYE = (33, 160, 158, 133, 153, 144)
RIGHT_EYE = (362, 385, 387, 263, 373, 380)
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "face_landmarker.task")
LOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "native_webcam.log")

_clients: list[socket.socket] = []
_clients_lock = threading.Lock()
_last_frame = {
    "type": "frame",
    "cameraConnected": False,
    "faceDetected": False,
    "leftEye": "unknown",
    "rightEye": "unknown",
}


def log(msg: str) -> None:
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(time.strftime("%H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def pt(landmark) -> tuple[float, float]:
    return float(landmark.x), float(landmark.y)


def dist(a, b) -> float:
    ax, ay = pt(a)
    bx, by = pt(b)
    return math.hypot(ax - bx, ay - by)


def ear(lm, idx) -> float:
    p1, p2, p3, p4, p5, p6 = (lm[i] for i in idx)
    h = dist(p1, p4)
    if h < 1e-6:
        return 1.0
    return (dist(p2, p6) + dist(p3, p5)) / (2.0 * h)


def blend_score(categories, name: str) -> float | None:
    if not categories:
        return None
    target = name.lower()
    for item in categories:
        n = (getattr(item, "category_name", None) or "")
        if n.lower() == target:
            return float(item.score)
    return None


def classify(ear_val: float | None, blink: float | None) -> str:
    if blink is not None:
        if blink >= CLOSE_BLINK:
            return "closed"
        if blink <= OPEN_BLINK:
            return "open"
    if ear_val is None:
        return "unknown"
    if ear_val < CLOSE_EAR:
        return "closed"
    if ear_val > OPEN_EAR:
        return "open"
    if blink is not None and blink >= 0.32:
        return "closed"
    return "open"


def broadcast(msg: dict) -> None:
    payload = (json.dumps(msg, ensure_ascii=True) + "\n").encode("ascii", errors="ignore")
    dead: list[socket.socket] = []
    with _clients_lock:
        for client in _clients:
            try:
                client.sendall(payload)
            except OSError:
                dead.append(client)
        for client in dead:
            _clients.remove(client)
            try:
                client.close()
            except OSError:
                pass


def accept_loop(server: socket.socket) -> None:
    while True:
        try:
            client, _addr = server.accept()
        except OSError:
            break
        with _clients_lock:
            _clients.append(client)
        try:
            client.sendall((json.dumps({"type": "hello", "lastFrame": _last_frame}, ensure_ascii=True) + "\n").encode("ascii"))
        except OSError:
            pass


def ensure_model() -> str:
    if os.path.isfile(MODEL_PATH) and os.path.getsize(MODEL_PATH) > 100000:
        return MODEL_PATH
    import urllib.request

    log("downloading face_landmarker.task")
    urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    return MODEL_PATH


def run() -> None:
    import cv2
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions
    from mediapipe.tasks.python.vision import FaceLandmarker, FaceLandmarkerOptions, RunningMode

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((HOST, PORT))
    except OSError:
        log("port_in_use")
        raise SystemExit("port_in_use")
    server.listen(4)
    threading.Thread(target=accept_loop, args=(server,), daemon=True).start()
    log("server_listening")

    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        log("camera_open_failed")
        _last_frame["cameraConnected"] = False
        broadcast({**_last_frame, "error": "camera_open_failed"})
        time.sleep(2)
        raise SystemExit("camera_open_failed")
    log("camera_opened")

    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=ensure_model()),
        running_mode=RunningMode.VIDEO,
        num_faces=1,
        output_face_blendshapes=True,
    )
    landmarker = FaceLandmarker.create_from_options(options)
    started = time.time()
    frame_i = 0
    try:
        while True:
            ok, frame = cap.read()
            frame_i += 1
            if not ok:
                _last_frame.update(
                    {
                        "cameraConnected": False,
                        "faceDetected": False,
                        "leftEye": "unknown",
                        "rightEye": "unknown",
                    }
                )
                broadcast(_last_frame)
                time.sleep(0.05)
                continue

            rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
            ts = int((time.time() - started) * 1000)
            left = "unknown"
            right = "unknown"
            face = None
            left_ear = 0.0
            right_ear = 0.0
            left_blink = 0.0
            right_blink = 0.0
            try:
                result = landmarker.detect_for_video(mp_image, ts)
                face = result.face_landmarks[0] if result.face_landmarks else None
                blends = result.face_blendshapes[0] if result.face_blendshapes else None
                if face:
                    left_ear = ear(face, LEFT_EYE)
                    right_ear = ear(face, RIGHT_EYE)
                    left_blink_raw = blend_score(blends, "eyeBlinkLeft")
                    right_blink_raw = blend_score(blends, "eyeBlinkRight")
                    left_blink = left_blink_raw if left_blink_raw is not None else 0.0
                    right_blink = right_blink_raw if right_blink_raw is not None else 0.0
                    left = classify(left_ear, left_blink_raw)
                    right = classify(right_ear, right_blink_raw)
            except Exception:
                log("detect_error " + traceback.format_exc().splitlines()[-1])

            _last_frame.update(
                {
                    "type": "frame",
                    "cameraConnected": True,
                    "faceDetected": bool(face),
                    "leftEye": left,
                    "rightEye": right,
                    "leftEar": round(left_ear, 3),
                    "rightEar": round(right_ear, 3),
                    "leftBlink": round(left_blink, 3),
                    "rightBlink": round(right_blink, 3),
                }
            )
            broadcast(_last_frame)
            if frame_i % 30 == 0:
                log(
                    "face=%s L=%s/%.2f/%.2f R=%s/%.2f/%.2f clients=%d"
                    % (
                        bool(face),
                        left,
                        left_ear,
                        left_blink,
                        right,
                        right_ear,
                        right_blink,
                        len(_clients),
                    )
                )
    finally:
        try:
            landmarker.close()
        except Exception:
            pass
        cap.release()
        server.close()
        log("camera_closed")


def _ensure_deps() -> None:
    try:
        import cv2  # noqa: F401
        import mediapipe  # noqa: F401
        import numpy  # noqa: F401
        return
    except ImportError:
        pass
    import subprocess

    py = sys.executable
    subprocess.check_call(
        [py, "-m", "pip", "install", "--user", "opencv-python-headless", "mediapipe", "numpy"],
        stdout=sys.stdout,
        stderr=sys.stderr,
    )


if __name__ == "__main__":
    try:
        _ensure_deps()
        run()
    except KeyboardInterrupt:
        sys.exit(0)
