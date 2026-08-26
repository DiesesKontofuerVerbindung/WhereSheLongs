"""CSV/JSON/trajectory logger for formal positive and negative Swipe Trials."""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

import config
from environment_recorder import write_config_snapshot, write_environment
from swipe_detector import TrajectorySample


ExpectedType = Literal["positive", "negative"]
TrialResult = Literal["success", "fail", "aborted"]


@dataclass
class ActiveTrial:
    trial_id: int
    expected_type: ExpectedType
    finger_mode: str
    target_block: str
    source: str
    started_at: float
    samples: list[TrajectorySample] = field(default_factory=list)


class TestLogger:
    trial_columns = (
        "trial_id", "expected_type", "finger_mode", "target_block", "source", "result",
        "classification", "fail_reason", "duration", "path_points", "start_x", "start_y",
        "end_x", "end_y", "vertical_distance", "horizontal_distance", "timestamp",
    )

    def __init__(self, results_root: Path = config.RESULTS_DIR) -> None:
        run_name = datetime.now().strftime("run_%Y%m%d_%H%M%S_%f")
        self.run_dir = Path(results_root) / run_name
        self.trajectory_dir = self.run_dir / "trajectories"
        self.trajectory_dir.mkdir(parents=True, exist_ok=False)
        self.trials_path = self.run_dir / "trials.csv"
        self.summary_path = self.run_dir / "summary.json"
        self.environment_path = self.run_dir / "environment.json"
        self.active: ActiveTrial | None = None
        self.records: list[dict[str, object]] = []
        self._next_trial_id = 1
        self.blocks_completed = 0
        with self.trials_path.open("w", newline="", encoding="utf-8") as file:
            csv.DictWriter(file, fieldnames=self.trial_columns).writeheader()
        write_config_snapshot(self.run_dir / "config_snapshot.json")
        write_environment(self.environment_path)
        self.write_summary()

    @property
    def target_total(self) -> int:
        return config.TARGET_POSITIVE_TRIALS + config.TARGET_NEGATIVE_TRIALS

    @property
    def completed_trials(self) -> int:
        return sum(record["result"] in {"success", "fail"} for record in self.records)

    def set_blocks_completed(self, count: int) -> None:
        self.blocks_completed = int(count)
        self.write_summary()

    def update_environment(self, camera_info: dict[str, object]) -> None:
        write_environment(self.environment_path, camera_info)

    def start_trial(self, expected_type: ExpectedType, finger_mode: str, target_block: str, source: str, now: float) -> ActiveTrial:
        if self.active is not None:
            raise RuntimeError("Cannot start a new trial while another is active.")
        self.active = ActiveTrial(self._next_trial_id, expected_type, finger_mode, target_block, source, now)
        self._next_trial_id += 1
        return self.active

    def append_sample(self, sample: TrajectorySample) -> None:
        if self.active is not None:
            self.active.samples.append(sample)

    def discard_active_trial(self) -> None:
        if self.active is None:
            return
        self._next_trial_id -= 1
        self.active = None

    def finish_trial(
        self,
        result: TrialResult,
        fail_reason: str,
        now: float,
        vertical_distance: float | None = None,
        horizontal_distance: float | None = None,
    ) -> dict[str, object] | None:
        if self.active is None:
            return None
        active = self.active
        self.active = None
        first = active.samples[0].raw if active.samples else None
        last = active.samples[-1].raw if active.samples else None
        vertical = vertical_distance if vertical_distance is not None else (0.0 if first is None or last is None else first.y - last.y)
        horizontal = horizontal_distance if horizontal_distance is not None else (0.0 if first is None or last is None else last.x - first.x)
        record: dict[str, object] = {
            "trial_id": active.trial_id,
            "expected_type": active.expected_type,
            "finger_mode": active.finger_mode,
            "target_block": active.target_block,
            "source": active.source,
            "result": result,
            "classification": _classification(active.expected_type, result),
            "fail_reason": fail_reason,
            "duration": round(max(0.0, now - active.started_at), 3),
            "path_points": len(active.samples),
            "start_x": _coordinate(first, "x"),
            "start_y": _coordinate(first, "y"),
            "end_x": _coordinate(last, "x"),
            "end_y": _coordinate(last, "y"),
            "vertical_distance": round(float(vertical), 3),
            "horizontal_distance": round(float(horizontal), 3),
            "timestamp": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        }
        self.records.append(record)
        self._write_trajectory(active)
        with self.trials_path.open("a", newline="", encoding="utf-8") as file:
            csv.DictWriter(file, fieldnames=self.trial_columns).writerow(record)
        self.write_summary()
        self._print_progress(record)
        return record

    def write_summary(self) -> None:
        metrics = calculate_metrics(self.records)
        summary = {
            "run_directory": str(self.run_dir),
            "target_positive_trials": config.TARGET_POSITIVE_TRIALS,
            "target_negative_trials": config.TARGET_NEGATIVE_TRIALS,
            "completed_trials": self.completed_trials,
            "aborted_trials": sum(record["result"] == "aborted" for record in self.records),
            "blocks_completed": self.blocks_completed,
            "one_finger_trials": sum(record["finger_mode"] == config.ONE_FINGER for record in self.records),
            "two_finger_trials": sum(record["finger_mode"] == config.TWO_FINGER for record in self.records),
            **metrics,
        }
        self.summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    def close(self, now: float) -> None:
        if self.active is not None:
            self.finish_trial("aborted", "application_closed", now)
        self.write_summary()

    def _write_trajectory(self, active: ActiveTrial) -> None:
        path = self.trajectory_dir / f"trial_{active.trial_id:03d}.csv"
        fields = (
            "timestamp", "raw_x", "raw_y", "smoothed_x", "smoothed_y", "finger_mode",
            "state", "target_block", "block_x", "block_y",
        )
        with path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fields)
            writer.writeheader()
            for sample in active.samples:
                writer.writerow({
                    "timestamp": f"{sample.timestamp:.3f}",
                    "raw_x": f"{sample.raw.x:.3f}",
                    "raw_y": f"{sample.raw.y:.3f}",
                    "smoothed_x": f"{sample.smoothed.x:.3f}",
                    "smoothed_y": f"{sample.smoothed.y:.3f}",
                    "finger_mode": sample.finger_mode,
                    "state": sample.state.value,
                    "target_block": sample.target_block or "",
                    "block_x": "" if sample.block_x is None else f"{sample.block_x:.3f}",
                    "block_y": "" if sample.block_y is None else f"{sample.block_y:.3f}",
                })

    def _print_progress(self, record: dict[str, object]) -> None:
        print(
            f"Trial {int(record['trial_id']):02d}/{self.target_total}\n"
            f"Expected: {str(record['expected_type']).upper()}\n"
            f"Finger: {record['finger_mode']}\n"
            f"Target: {record['target_block']}\n"
            f"Result: {str(record['result']).upper()}\n"
            f"Classification: {record['classification'] or '--'}"
            + (f"\nFAIL\nReason: {record['fail_reason']}" if record["fail_reason"] else "")
        )
        print(f"Checklist: {self.blocks_completed}/{config.BLOCK_COUNT}\n")


def calculate_metrics(records: list[dict[str, object]]) -> dict[str, object]:
    classified = [record for record in records if record["classification"]]
    counts = {name: sum(record["classification"] == name for record in classified) for name in ("TP", "TN", "FP", "FN")}
    tp, tn, fp, fn = counts["TP"], counts["TN"], counts["FP"], counts["FN"]
    return {
        "positive_trials": tp + fn,
        "negative_trials": tn + fp,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn,
        "precision": _safe_divide(tp, tp + fp),
        "recall": _safe_divide(tp, tp + fn),
        "accuracy": _safe_divide(tp + tn, tp + tn + fp + fn),
        "false_positive_rate": _safe_divide(fp, fp + tn),
    }


def _classification(expected_type: ExpectedType, result: TrialResult) -> str:
    if result == "aborted":
        return ""
    if expected_type == "positive":
        return "TP" if result == "success" else "FN"
    return "FP" if result == "success" else "TN"


def _safe_divide(numerator: int, denominator: int) -> float | None:
    return None if denominator == 0 else round(numerator / denominator, 6)


def _coordinate(point: object, axis: str) -> float | None:
    if point is None:
        return None
    return round(float(getattr(point, axis)), 3)
