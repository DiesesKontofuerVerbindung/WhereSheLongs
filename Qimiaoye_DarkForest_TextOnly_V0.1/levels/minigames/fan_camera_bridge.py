"""Run Prototype_2_Fan and stream its physical world to Godot."""

from __future__ import annotations

import argparse
import importlib
import json
import os
from pathlib import Path
import socket
import sys
import time
from types import SimpleNamespace


HOST = "127.0.0.1"
RUNTIME_DIR = Path(__file__).resolve().with_name("fan_runtime")
DEFAULT_ENTITY_COUNT = 72
PHYSICS_PACKET_RATE = 60.0


def _load_runtime(entity_count: int) -> SimpleNamespace:
    runtime_path = str(RUNTIME_DIR)
    if runtime_path not in sys.path:
        sys.path.insert(0, runtime_path)
    config = importlib.import_module("config")
    config.INTERFERENCE_TEXT_ENTITY_COUNT = int(entity_count)
    return SimpleNamespace(
        config=config,
        fan_detector=importlib.import_module("fan_detector"),
        hand_tracker=importlib.import_module("hand_tracker"),
        interference_field=importlib.import_module("interference_field"),
        palm_signal_processor=importlib.import_module("palm_signal_processor"),
    )


def _send(sock: socket.socket, port: int, payload: dict[str, object]) -> None:
    data = json.dumps(payload, ensure_ascii=True, separators=(",", ":")).encode("utf-8")
    sock.sendto(data, (HOST, port))


class PrototypeRuntime:
    """Prototype_2_Fan's update loop with only its debug UI and logger removed."""

    def __init__(self, runtime: SimpleNamespace, model_path: Path, camera_index: int) -> None:
        self.runtime = runtime
        self.detector = runtime.fan_detector.FanDetector()
        self.interference = runtime.interference_field.InterferenceField()
        self.signal_processor = runtime.palm_signal_processor.PalmSignalProcessor()
        self.palm_signal = runtime.palm_signal_processor.PalmMotion(
            None, None, None, None, None, None, 0.0, 0.0, 0.0,
            1.0, 0.0, 0.0, False, False, False,
        )
        self.physics_palm = None
        self._previous_physics_x: float | None = None
        self._previous_physics_y: float | None = None
        self._physics_stroke_id = 0
        self._physics_direction = 0
        self.tracker = runtime.hand_tracker.HandTracker(model_path=model_path, camera_index=camera_index)
        self._last_entity_time = time.perf_counter()
        self._last_tracking_sample_id = -1
        self._gesture_completed = False

    def start(self) -> None:
        if not self.tracker.start():
            raise RuntimeError(self.tracker.error or "camera unavailable")

    def reset(self) -> None:
        """Mirror Prototype_2_Fan's manual reset without reopening the camera."""
        now = time.perf_counter()
        self.detector.reset()
        self.interference.reset()
        self.signal_processor.reset()
        self.physics_palm = None
        self._previous_physics_x = None
        self._previous_physics_y = None
        self._physics_stroke_id = 0
        self._physics_direction = 0
        self._last_entity_time = now
        self._gesture_completed = False

    def tick(self) -> dict[str, object]:
        now = time.perf_counter()
        entity_delta = max(0.0, min(0.10, now - self._last_entity_time))
        self._last_entity_time = now
        frame = self.tracker.read()
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
            point = None
            if self.palm_signal.active and self.palm_signal.gesture_x is not None:
                point = self.runtime.fan_detector.Point(
                    self.palm_signal.gesture_x,
                    self.palm_signal.gesture_y or 0.0,
                )
            event = self.detector.update(point, frame.open_palm, sample_time)
            if event.completed:
                self._gesture_completed = True
            self.physics_palm = self._make_physics_palm()
        self.interference.update(entity_delta, self.physics_palm)
        return self._snapshot(frame, event)

    def _make_physics_palm(self):
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
        return self.runtime.interference_field.PalmPhysicsInput(
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

    def _snapshot(self, frame, event) -> dict[str, object]:
        signal = self.palm_signal
        entities = [
            {
                "index": index,
                "text": entity.text,
                "x": round(entity.x, 3),
                "y": round(entity.y, 3),
                "width": round(entity.width, 3),
                "height": round(entity.height, 3),
                "mass": round(entity.mass, 5),
                "font_size": entity.font_size,
                "color": list(entity.color),
                "opacity": round(entity.opacity, 4),
                "velocity_x": round(entity.velocity_x, 3),
                "velocity_y": round(entity.velocity_y, 3),
                "side": entity.side,
                "dispersed": entity.dispersed,
            }
            for index, entity in enumerate(self.interference.entities)
        ]
        return {
            "event": "prototype2_physics_frame",
            "field_width": self.runtime.config.WINDOW_WIDTH,
            "field_height": self.runtime.config.WINDOW_HEIGHT,
            "state": self.detector.state.value,
            "direction": self.detector.direction,
            "sweep_count": self.detector.sweep_count,
            "fan_strength": round(self.detector.fan_strength, 4),
            "horizontal_amplitude": round(self.detector.horizontal_amplitude, 3),
            "horizontal_velocity": round(self.detector.horizontal_velocity, 3),
            "gesture_completed": self._gesture_completed,
            "event_completed": bool(event is not None and event.completed),
            "hand_detected": frame.hand_detected,
            "open_palm": frame.open_palm,
            "palm": None if signal.physics_x is None else {
                "x": round(signal.physics_x, 3),
                "y": round(signal.physics_y or 0.0, 3),
                "velocity_x": round(signal.velocity_x, 3),
                "velocity_y": round(signal.velocity_y, 3),
                "gain": round(signal.physics_gain, 4),
            },
            "entities": entities,
            "metrics": {
                "dispersed_count": self.interference.dispersed_count,
                "dispersed_ratio": round(self.interference.dispersed_ratio, 5),
                "hand_force_active": self.interference.hand_force_active,
                "local_force_strength": round(self.interference.local_force_strength, 5),
                "texts_inside_influence_area": self.interference.texts_inside_influence_area,
                "last_impulse_strength": round(self.interference.last_impulse_strength, 5),
                "last_impulse_stroke_id": self.interference.last_impulse_stroke_id,
                "stroke_phase": self.interference.stroke_phase,
                "stroke_direction": self.interference.stroke_direction,
                "auto_dispersion_strength": round(self.interference.auto_dispersion_strength, 5),
                "mean_velocity_x": round(self.interference.mean_velocity_x, 3),
                "mean_velocity_y": round(self.interference.mean_velocity_y, 3),
            },
            "clear_ready": self._gesture_completed and self.interference.dispersed_ratio >= 1.0,
        }

    def close(self) -> None:
        self.tracker.close()


def _self_test(runtime: SimpleNamespace) -> int:
    field = runtime.interference_field.InterferenceField(seed=runtime.config.INTERFERENCE_RANDOM_SEED)
    initial_x = [entity.x for entity in field.entities]
    initial_centers_x = [entity.x for entity in field.entities]
    initial_centers_y = [entity.y for entity in field.entities]
    screen_covered = (
        max(initial_centers_x) - min(initial_centers_x) >= 650.0
        and max(initial_centers_y) - min(initial_centers_y) >= 380.0
    )
    palm = runtime.interference_field.PalmPhysicsInput(
        runtime.config.INTERFERENCE_CENTER_X,
        runtime.config.INTERFERENCE_CENTER_Y,
        runtime.config.AUTO_DISPERSION_SPEED_REFERENCE,
        0.0,
        runtime.config.INTERFERENCE_CENTER_X - 100.0,
        runtime.config.INTERFERENCE_CENTER_Y,
        stroke_phase="active",
        stroke_direction=1,
        stroke_id=1,
        auto_dispersion=True,
    )
    force_seen = False
    auto_dispersion_seen = False
    for _ in range(480):
        field.update(1.0 / runtime.config.TARGET_FPS, palm)
        force_seen = force_seen or field.hand_force_active
        auto_dispersion_seen = auto_dispersion_seen or field.auto_dispersion_strength > 0.0
    moved_outward = all(
        entity.dispersed or abs(entity.x - start_x) > 1.0
        for entity, start_x in zip(field.entities, initial_x)
    )
    if (
        len(field.entities) != DEFAULT_ENTITY_COUNT
        or not screen_covered
        or not moved_outward
        or not auto_dispersion_seen
    ):
        print("PROTOTYPE2_RUNTIME_SELF_TEST_FAIL")
        return 1
    print(
        "PROTOTYPE2_RUNTIME_SELF_TEST_PASS "
        f"entities={len(field.entities)} screen_covered={screen_covered} local_force={force_seen} "
        f"auto_dispersion={auto_dispersion_seen} dispersed={field.dispersed_count}"
    )
    return 0


def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--model")
    parser.add_argument("--port", type=int)
    parser.add_argument("--command-port", type=int)
    parser.add_argument("--camera", default=0, type=int)
    parser.add_argument("--entities", default=DEFAULT_ENTITY_COUNT, type=int)
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args()


def _reset_requested(command_socket: socket.socket) -> bool:
    reset = False
    while True:
        try:
            packet, _address = command_socket.recvfrom(4096)
        except BlockingIOError:
            return reset
        try:
            command = json.loads(packet.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            continue
        if isinstance(command, dict) and command.get("command") == "reset":
            reset = True


def main() -> int:
    args = _parse_args()
    os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
    runtime = _load_runtime(args.entities)
    if args.self_test:
        return _self_test(runtime)
    if not args.model or args.port is None or args.command_port is None:
        raise SystemExit("--model, --port and --command-port are required")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    command_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    command_socket.bind((HOST, args.command_port))
    command_socket.setblocking(False)
    engine = PrototypeRuntime(runtime, Path(args.model), args.camera)
    try:
        engine.start()
        _send(sock, args.port, {
            "event": "bridge_status",
            "state": "ready",
            "detail": "runtime=Prototype_2_Fan camera=0",
        })
        target_interval = 1.0 / runtime.config.TARGET_FPS
        packet_interval = 1.0 / PHYSICS_PACKET_RATE
        next_tick = time.perf_counter()
        next_packet = next_tick
        while True:
            if _reset_requested(command_socket):
                engine.reset()
                _send(sock, args.port, {
                    "event": "bridge_status",
                    "state": "reset",
                    "detail": "Prototype_2_Fan state reset",
                })
            snapshot = engine.tick()
            now = time.perf_counter()
            if now >= next_packet:
                _send(sock, args.port, snapshot)
                next_packet = now + packet_interval
            next_tick += target_interval
            remaining = next_tick - time.perf_counter()
            if remaining > 0.0:
                time.sleep(remaining)
            else:
                next_tick = time.perf_counter()
    except (BrokenPipeError, ConnectionError, KeyboardInterrupt):
        return 0
    except Exception as exc:
        try:
            _send(sock, args.port, {
                "event": "bridge_status",
                "state": "error",
                "detail": f"Prototype_2_Fan 启动失败：{exc}",
            })
        except OSError:
            pass
        return 2
    finally:
        engine.close()
        command_socket.close()
        sock.close()


if __name__ == "__main__":
    sys.exit(main())
