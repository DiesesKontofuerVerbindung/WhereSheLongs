#!/usr/bin/env python3
"""Headless hand-checkbox detector for Godot (TCP 8771)."""

from __future__ import annotations

import json
import os
import socket
import sys
import threading
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)
os.chdir(HERE)

import config
from gesture_detector import GestureDetector, Point
from hand_tracker import HandTracker

HOST = getattr(config, "HOST", "127.0.0.1")
PORT = int(getattr(config, "PORT", 8771))
LOG_PATH = os.path.join(HERE, "native_hand_checkbox.log")

_clients: list[socket.socket] = []
_clients_lock = threading.Lock()
_checked_sent = False


def log(msg: str) -> None:
    try:
        with open(LOG_PATH, "a", encoding="utf-8") as handle:
            handle.write(time.strftime("%H:%M:%S ") + msg + "\n")
            handle.flush()
    except OSError:
        pass
    print(msg, flush=True)


def broadcast(payload: dict) -> None:
    raw = (json.dumps(payload, ensure_ascii=False) + "\n").encode("utf-8")
    dead: list[socket.socket] = []
    with _clients_lock:
        for client in list(_clients):
            try:
                client.sendall(raw)
            except OSError:
                dead.append(client)
        for client in dead:
            try:
                client.close()
            except OSError:
                pass
            if client in _clients:
                _clients.remove(client)


def accept_loop(server: socket.socket) -> None:
    while True:
        try:
            client, addr = server.accept()
            client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            with _clients_lock:
                _clients.append(client)
            log(f"client connected {addr}")
            broadcast({"type": "hello", "plugin": "hand_checkbox_gesture", "ts": time.time()})
        except OSError:
            break


def main() -> int:
    global _checked_sent
    # Fresh log each run
    try:
        open(LOG_PATH, "w", encoding="utf-8").write(time.strftime("%H:%M:%S ") + "boot\n")
    except OSError:
        pass
    log(f"cwd={os.getcwd()} model={config.MODEL_PATH} exists={config.MODEL_PATH.exists()}")

    server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        server.bind((HOST, PORT))
    except OSError as exc:
        log(f"bind failed {HOST}:{PORT} {exc}")
        return 2
    server.listen(4)
    log(f"listening {HOST}:{PORT}")
    threading.Thread(target=accept_loop, args=(server,), daemon=True).start()

    broadcast({"type": "camera", "ok": False, "error": "starting"})
    tracker = HandTracker()
    detector = GestureDetector()
    log("opening camera…")
    camera_ok = tracker.start()
    payload = {
        "type": "camera",
        "ok": bool(camera_ok),
        "error": tracker.error,
        "info": tracker.camera_info(),
    }
    broadcast(payload)
    log(f"camera_ok={camera_ok} error={tracker.error} info={tracker.camera_info()}")

    try:
        import cv2  # local import — preview only
    except ImportError:
        cv2 = None

    try:
        while True:
            now = time.perf_counter()
            finger = tracker.read_index_finger()
            point = None if finger is None else Point(finger.screen_x, finger.screen_y)
            result = detector.update(point, now)

            # 婚礼宽松：转折完成即可；或轨迹够长也直接过关。
            loose_hit = False
            if not _checked_sent and getattr(config, "WEDDING_LOOSE_MODE", False):
                success_phase = getattr(config, "WEDDING_SUCCESS_FROM_PHASE", "TURN_OK")
                path_len = 0.0
                if len(detector.points) >= 2:
                    from math import hypot as _hypot

                    for i in range(1, len(detector.points)):
                        a = detector.points[i - 1]
                        b = detector.points[i]
                        path_len += _hypot(b.x - a.x, b.y - a.y)
                if result.phase.value in (success_phase, "UPSTROKE_OK", "SUCCESS"):
                    loose_hit = True
                    detector.last_match_profile = f"wedding_loose_{result.phase.value.lower()}"
                elif path_len >= float(getattr(config, "WEDDING_MIN_PATH_FALLBACK", 36.0)) and result.state.value == "DRAWING":
                    loose_hit = True
                    detector.last_match_profile = "wedding_loose_path"
            if loose_hit:
                from gesture_state import GesturePhase, GestureState
                from gesture_detector import GestureResult as GR

                detector.mark_checked()
                result = GR(
                    GestureState.CHECKED,
                    GesturePhase.SUCCESS,
                    checked=True,
                    terminal=True,
                )

            frame_payload = {
                "type": "frame",
                "hand": finger is not None,
                "state": result.state.value,
                "phase": result.phase.value,
                "fail": result.fail_reason or detector.last_candidate_reject_reason or "",
                "progress": int(getattr(detector, "progress", 0)),
            }
            if finger is not None:
                frame_payload["x"] = finger.screen_x
                frame_payload["y"] = finger.screen_y
            broadcast(frame_payload)

            if config.SHOW_CAMERA_PREVIEW and cv2 is not None and tracker.last_frame is not None:
                preview = tracker.last_frame.copy()
                if finger is not None:
                    # Map window coords back roughly onto camera frame.
                    h, w = preview.shape[:2]
                    px = int(finger.normalized_x * w)
                    py = int(finger.normalized_y * h)
                    cv2.circle(preview, (px, py), 12, (40, 220, 80), 2)
                    cv2.putText(
                        preview,
                        f"{result.state.value}/{result.phase.value}",
                        (16, 36),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.9,
                        (40, 220, 80),
                        2,
                    )
                else:
                    cv2.putText(
                        preview,
                        "no hand",
                        (16, 36),
                        cv2.FONT_HERSHEY_SIMPLEX,
                        0.9,
                        (80, 80, 220),
                        2,
                    )
                cv2.imshow(config.WINDOW_NAME, preview)
                cv2.waitKey(1)

            if result.terminal and result.checked and not _checked_sent:
                _checked_sent = True
                checked = {
                    "type": "checked",
                    "source": "gesture",
                    "profile": detector.last_match_profile or "",
                    "ts": time.time(),
                }
                broadcast(checked)
                log(f"checked {checked}")
            elif result.terminal and result.fail_reason:
                log(f"fail phase={result.phase.value} reason={result.fail_reason}")
            time.sleep(max(0.001, 1.0 / config.TARGET_FPS))
    except KeyboardInterrupt:
        log("interrupted")
    except Exception:
        log(traceback.format_exc())
        return 1
    finally:
        if cv2 is not None:
            try:
                cv2.destroyAllWindows()
            except Exception:
                pass
        tracker.close()
        server.close()
        with _clients_lock:
            for client in _clients:
                try:
                    client.close()
                except OSError:
                    pass
            _clients.clear()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
