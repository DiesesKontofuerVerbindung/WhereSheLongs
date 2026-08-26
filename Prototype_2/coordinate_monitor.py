"""Low-rate calibration log for distinguishing camera loss from mapping issues."""

from __future__ import annotations

import csv
from pathlib import Path

import config
from hand_tracker import TrackingFrame
from swipe_detector import SwipeDetector


class CoordinateMonitor:
    fields = (
        "timestamp", "hand_detected", "cursor_held", "finger_mode", "index_extended",
        "middle_extended", "raw_x", "raw_y", "virtual_x", "virtual_y",
        "inside_window", "inside_interaction", "state", "target_block",
    )

    def __init__(self, run_dir: Path) -> None:
        self.path = Path(run_dir) / "coordinate_monitor.csv"
        self._file = self.path.open("w", newline="", encoding="utf-8")
        self._writer = csv.DictWriter(self._file, fieldnames=self.fields)
        self._writer.writeheader()
        self._last_recorded_at: float | None = None

    def record(self, frame: TrackingFrame, detector: SwipeDetector, now: float) -> None:
        if self._last_recorded_at is not None and now - self._last_recorded_at < 1.0 / config.COORDINATE_MONITOR_HZ:
            return
        self._last_recorded_at = now
        cursor = frame.cursor
        virtual_x = None if cursor is None else cursor.screen_x
        virtual_y = None if cursor is None else cursor.screen_y
        self._writer.writerow({
            "timestamp": f"{now:.3f}",
            "hand_detected": frame.hand_detected,
            "cursor_held": frame.cursor_held,
            "finger_mode": frame.finger_mode,
            "index_extended": frame.index_extended,
            "middle_extended": frame.middle_extended,
            "raw_x": "" if cursor is None else f"{cursor.normalized_x:.5f}",
            "raw_y": "" if cursor is None else f"{cursor.normalized_y:.5f}",
            "virtual_x": "" if virtual_x is None else virtual_x,
            "virtual_y": "" if virtual_y is None else virtual_y,
            "inside_window": cursor is not None and 0 <= virtual_x < config.WINDOW_WIDTH and 0 <= virtual_y < config.WINDOW_HEIGHT,
            "inside_interaction": cursor is not None and 0 <= virtual_y <= config.INTERACTION_BOTTOM_Y,
            "state": detector.state.value,
            "target_block": detector.target_block or "",
        })
        self._file.flush()

    def close(self) -> None:
        self._file.close()
