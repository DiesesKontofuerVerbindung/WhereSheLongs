#!/usr/bin/env python3
"""Open the webcam immediately and stream eye state to Godot. No browser, no click."""

from __future__ import annotations

import base64
import json
import math
import os
import socket
import sys
import threading
import time

HOST = "127.0.0.1"
PORT = 8766
CLOSE_EAR = 0.19
OPEN_EAR = 0.23
HOLD_MS = 1500.0
LEFT_EYE = (33, 160, 158, 133, 153, 144)
RIGHT_EYE = (362, 385, 387, 263, 373, 380)
MODEL_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
MODEL_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "face_landmarker.task")

_clients: list[socket.socket] = []
_clients_lock = threading.Lock()
_last_frame = {
    "type": "frame",
    "cameraConnected": False,
    "faceDetected": False,
    "leftEye": "unknown",
    "rightEye": "unknown",
}


def dist(a, b) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def ear(lm, idx) -> float:
    p1, p2, p3, p4, p5, p6 = (lm[i] for i in idx)
    h = dist(p1, p4)
    if h < 1e-6:
        return 1.0
    return (dist(p2, p6) + dist(p3, p5)) / (2.0 * h)


def eye_state(value: float) -> str:
    if value < CLOSE_EAR:
        return "closed"
    if value > OPEN_EAR:
        return "open"
    return "uncertain"


def broadcast(msg: dict) -> None:
    payload = (json.dumps(msg) + "\n").encode("utf-8")
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
            client.sendall((json.dumps({"type": "hello", "lastFrame": _last_frame}) + "\n").encode("utf-8"))
        except OSError:
            pass


def ensure_model() -> str:
    if os.path.isfile(MODEL_PATH) and os.path.getsize(MODEL_PATH) > 100000:
        return MODEL_PATH
    import urllib.request

    urllib.request.urlretrieve(MODEL_URL, MODEL_PATH)
    return MODEL_PATH


def run() -> None:
    import cv2
    import mediapipe as mp
    from mediapipe.tasks.python import BaseOptions
    from mediapipe.tasks.python.vision import FaceLandmarker, FaceLandmarkerOptions, RunningMode

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind((HOST, PORT))
    server.listen(4)
    threading.Thread(target=accept_loop, args=(server,), daemon=True).start()

    cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
    cap.set(cv2.CAP_PROP_FRAME_WIDTH, 640)
    cap.set(cv2.CAP_PROP_FRAME_HEIGHT, 480)
    if not cap.isOpened():
        cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        with open(os.path.join(os.path.dirname(MODEL_PATH), "native_webcam.log"), "a", encoding="utf-8") as log:
            log.write("camera_open_failed\n")
        _last_frame["cameraConnected"] = False
        broadcast({**_last_frame, "error": "camera_open_failed"})
        time.sleep(2)
        raise SystemExit("camera_open_failed")

    options = FaceLandmarkerOptions(
        base_options=BaseOptions(model_asset_path=ensure_model()),
        running_mode=RunningMode.VIDEO,
        num_faces=1,
    )
    landmarker = FaceLandmarker.create_from_options(options)
    closed_started = -1.0
    fired = False
    started = time.time()
    try:
        while True:
            ok, frame = cap.read()
            now = time.time() * 1000.0
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
            result = landmarker.detect_for_video(mp_image, ts)
            face = result.face_landmarks[0] if result.face_landmarks else None
            left = "unknown"
            right = "unknown"
            if face:
                left = eye_state(ear(face, LEFT_EYE))
                right = eye_state(ear(face, RIGHT_EYE))

            both_closed = bool(face) and left == "closed" and right == "closed"
            if both_closed:
                if closed_started < 0:
                    closed_started = now
                hold_ms = now - closed_started
                if not fired and hold_ms >= HOLD_MS:
                    fired = True
                    broadcast({"type": "closed_hold", "durationMs": hold_ms})
            else:
                closed_started = -1.0
                fired = False

            preview = cv2.resize(frame, (320, 240))
            ok_jpg, buf = cv2.imencode(".jpg", preview, [int(cv2.IMWRITE_JPEG_QUALITY), 50])
            jpeg_b64 = base64.b64encode(buf.tobytes()).decode("ascii") if ok_jpg else ""

            _last_frame.update(
                {
                    "type": "frame",
                    "cameraConnected": True,
                    "faceDetected": bool(face),
                    "leftEye": left,
                    "rightEye": right,
                    "jpeg": jpeg_b64,
                }
            )
            broadcast(_last_frame)
    finally:
        landmarker.close()
        cap.release()
        server.close()


def _ensure_deps() -> None:
    try:
        import cv2  # noqa: F401
        import mediapipe  # noqa: F401
        return
    except ImportError:
        pass
    import subprocess

    py = sys.executable
    subprocess.check_call(
        [py, "-m", "pip", "install", "--user", "opencv-python-headless", "mediapipe"],
        stdout=sys.stdout,
        stderr=sys.stderr,
    )


if __name__ == "__main__":
    try:
        _ensure_deps()
        run()
    except KeyboardInterrupt:
        sys.exit(0)
