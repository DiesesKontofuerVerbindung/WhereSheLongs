"""Download the official MediaPipe Hand Landmarker task model."""

from pathlib import Path
import sys
from urllib.request import urlopen

import config


if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")


MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/hand_landmarker/"
    "hand_landmarker/float16/1/hand_landmarker.task"
)


def main() -> None:
    target: Path = config.MODEL_PATH
    if target.exists() and target.stat().st_size > 100_000:
        print(f"Model already exists: {target}")
        return

    print(f"Downloading official Hand Landmarker model to {target} ...")
    with urlopen(MODEL_URL, timeout=60) as response:
        data = response.read()
    if len(data) <= 100_000:
        raise RuntimeError("Downloaded model is unexpectedly small; check the URL/network.")
    target.write_bytes(data)
    print(f"Downloaded {len(data) / 1024 / 1024:.1f} MiB")


if __name__ == "__main__":
    main()
