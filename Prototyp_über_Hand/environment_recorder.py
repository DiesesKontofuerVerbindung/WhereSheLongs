"""Collect reproducibility metadata without guessing unavailable hardware."""

from __future__ import annotations

import importlib.metadata
import json
import platform
import subprocess
from pathlib import Path
from typing import Any

import config


def write_config_snapshot(destination: Path) -> None:
    snapshot = {name: _json_value(value) for name, value in vars(config).items() if name.isupper()}
    destination.write_text(json.dumps(snapshot, indent=2, ensure_ascii=False), encoding="utf-8")


def collect_environment(camera_info: dict[str, Any] | None = None) -> dict[str, Any]:
    camera_info = camera_info or {}
    return {
        "hardware": {
            "device": platform.node() or "unknown",
            "cpu": platform.processor() or "unknown",
            "gpu": "unknown",
            "webcam": "unknown",
            "camera_resolution": camera_info.get("resolution", "unknown"),
            "camera_fps": camera_info.get("fps", "unknown"),
        },
        "operating_system": {
            "os": platform.system() or "unknown",
            "windows_version": platform.version() if platform.system() == "Windows" else "unknown",
            "release": platform.release() or "unknown",
            "architecture": platform.machine() or "unknown",
        },
        "software": {
            "python": platform.python_version(),
            "opencv": _package_version("opencv-python"),
            "mediapipe": _package_version("mediapipe"),
            "numpy": _package_version("numpy"),
        },
        "git": _git_metadata(config.PROJECT_DIR),
    }


def write_environment(destination: Path, camera_info: dict[str, Any] | None = None) -> None:
    destination.write_text(
        json.dumps(collect_environment(camera_info), indent=2, ensure_ascii=False),
        encoding="utf-8",
    )


def _package_version(name: str) -> str:
    try:
        return importlib.metadata.version(name)
    except importlib.metadata.PackageNotFoundError:
        return "unknown"


def _git_metadata(start_dir: Path) -> dict[str, Any]:
    def run_git(*args: str) -> str | None:
        try:
            completed = subprocess.run(
                ["git", "-C", str(start_dir), *args],
                capture_output=True,
                text=True,
                check=False,
                timeout=3,
            )
        except (OSError, subprocess.TimeoutExpired):
            return None
        return completed.stdout.strip() if completed.returncode == 0 else None

    if run_git("rev-parse", "--show-toplevel") is None:
        return {"git_commit": None, "git_branch": None, "git_dirty": None}
    dirty = run_git("status", "--porcelain")
    return {
        "git_commit": run_git("rev-parse", "HEAD"),
        "git_branch": run_git("rev-parse", "--abbrev-ref", "HEAD"),
        "git_dirty": bool(dirty) if dirty is not None else None,
    }


def _json_value(value: Any) -> Any:
    if isinstance(value, Path):
        return str(value)
    if isinstance(value, tuple):
        return list(value)
    return value
