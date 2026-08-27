"""CSV/JSON/trajectory logger for positive and negative Fan trials."""

from __future__ import annotations

import csv
import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Literal

import config
from environment_recorder import write_config_snapshot, write_environment
from fan_detector import FanEvent, TrajectorySample


ExpectedType = Literal["positive", "negative"]
TrialResult = Literal["success", "fail", "aborted"]


@dataclass
class ActiveTrial:
    trial_id: int
    expected_type: ExpectedType
    started_at: float
    samples: list[TrajectorySample] = field(default_factory=list)


class TestLogger:
    trial_columns = (
        "trial_id", "expected_type", "result", "classification", "fail_reason",
        "duration", "sweep_count", "max_amplitude", "mean_amplitude",
        "peak_horizontal_velocity", "mean_fan_strength", "path_points", "timestamp",
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

    def update_environment(self, camera_info: dict[str, object]) -> None:
        write_environment(self.environment_path, camera_info)

    def start_trial(self, expected_type: ExpectedType, now: float) -> ActiveTrial:
        if self.active is not None:
            raise RuntimeError("Cannot start a new trial while another is active.")
        self.active = ActiveTrial(self._next_trial_id, expected_type, now)
        self._next_trial_id += 1
        return self.active

    def append_sample(self, sample: TrajectorySample) -> None:
        if self.active is not None:
            self.active.samples.append(sample)

    def finish_trial(
        self,
        result: TrialResult,
        fail_reason: str,
        now: float,
        event: FanEvent | None = None,
    ) -> dict[str, object] | None:
        if self.active is None:
            return None
        active = self.active
        self.active = None
        amplitudes = [sample.horizontal_amplitude for sample in active.samples]
        velocities = [abs(sample.horizontal_velocity) for sample in active.samples]
        strengths = [sample.fan_strength for sample in active.samples]
        sweep_count = max((sample.sweep_count for sample in active.samples), default=0)
        if event is not None:
            sweep_count = max(sweep_count, event.sweep_count)
        record: dict[str, object] = {
            "trial_id": active.trial_id,
            "expected_type": active.expected_type,
            "result": result,
            "classification": _classification(active.expected_type, result),
            "fail_reason": fail_reason,
            "duration": round(max(0.0, now - active.started_at), 3),
            "sweep_count": sweep_count,
            "max_amplitude": round(max(amplitudes, default=0.0), 3),
            "mean_amplitude": round(_mean(amplitudes), 3),
            "peak_horizontal_velocity": round(max(velocities, default=0.0), 3),
            "mean_fan_strength": round(_mean(strengths), 4),
            "path_points": len(active.samples),
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
        summary = {
            "run_directory": str(self.run_dir),
            "target_positive_trials": config.TARGET_POSITIVE_TRIALS,
            "target_negative_trials": config.TARGET_NEGATIVE_TRIALS,
            "completed_trials": self.completed_trials,
            "aborted_trials": sum(record["result"] == "aborted" for record in self.records),
            **calculate_metrics(self.records),
        }
        self.summary_path.write_text(json.dumps(summary, indent=2, ensure_ascii=False), encoding="utf-8")

    def close(self, now: float) -> None:
        if self.active is not None:
            self.finish_trial("aborted", "application_closed", now)
        self.write_summary()

    def _write_trajectory(self, active: ActiveTrial) -> None:
        path = self.trajectory_dir / f"trial_{active.trial_id:03d}.csv"
        fields = (
            "timestamp", "raw_palm_x", "raw_palm_y", "smoothed_palm_x", "smoothed_palm_y",
            "open_palm", "state", "direction", "horizontal_velocity", "fan_strength",
        )
        with path.open("w", newline="", encoding="utf-8") as file:
            writer = csv.DictWriter(file, fieldnames=fields)
            writer.writeheader()
            for sample in active.samples:
                writer.writerow({
                    "timestamp": f"{sample.timestamp:.3f}",
                    "raw_palm_x": f"{sample.raw.x / config.WINDOW_WIDTH:.5f}",
                    "raw_palm_y": f"{sample.raw.y / config.WINDOW_HEIGHT:.5f}",
                    "smoothed_palm_x": f"{sample.smoothed.x / config.WINDOW_WIDTH:.5f}",
                    "smoothed_palm_y": f"{sample.smoothed.y / config.WINDOW_HEIGHT:.5f}",
                    "open_palm": int(sample.open_palm),
                    "state": sample.state.value,
                    "direction": sample.direction,
                    "horizontal_velocity": f"{sample.horizontal_velocity:.3f}",
                    "fan_strength": f"{sample.fan_strength:.4f}",
                })

    def _print_progress(self, record: dict[str, object]) -> None:
        print(
            f"Trial {int(record['trial_id']):02d}/{self.target_total} "
            f"{str(record['expected_type']).upper()} {str(record['result']).upper()} "
            f"{record['classification'] or record['fail_reason']}".rstrip()
        )


def calculate_metrics(records: list[dict[str, object]]) -> dict[str, object]:
    counts = {name: sum(record["classification"] == name for record in records) for name in ("TP", "TN", "FP", "FN")}
    tp, tn, fp, fn = counts["TP"], counts["TN"], counts["FP"], counts["FN"]
    return {
        "positive_trials": tp + fn,
        "negative_trials": tn + fp,
        "tp": tp, "tn": tn, "fp": fp, "fn": fn,
        "positive_success_rate": _safe_divide(tp, tp + fn),
        "false_positive_rate": _safe_divide(fp, fp + tn),
        "precision": _safe_divide(tp, tp + fp),
        "recall": _safe_divide(tp, tp + fn),
        "accuracy": _safe_divide(tp + tn, tp + tn + fp + fn),
    }


def _classification(expected_type: ExpectedType, result: TrialResult) -> str:
    if result == "aborted":
        return ""
    if expected_type == "positive":
        return "TP" if result == "success" else "FN"
    return "FP" if result == "success" else "TN"


def _safe_divide(numerator: int, denominator: int) -> float | None:
    return None if denominator == 0 else round(numerator / denominator, 6)


def _mean(values: list[float]) -> float:
    return 0.0 if not values else sum(values) / len(values)
