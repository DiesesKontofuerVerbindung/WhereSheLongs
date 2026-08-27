# Prototype 2 — Fan Gesture

Independent webcam prototype for the final **Open Palm → horizontal back-and-forth fan** interaction. It does not integrate with Godot.

## Architecture

```text
Camera / MediaPipe
        ↓
rotation-tolerant palm feature extraction
        ↓
TRACKING → PALM_ARMING → FAN_READY → FANNING
        ↓
fan_update { strength, direction, sweep_count }
```

`hand_tracker.py` reduces the 21 MediaPipe landmarks to a palm center plus four explainable finger-extension flags. `fan_detector.py` only consumes those high-level features and screen-space points; future game code therefore does not need MediaPipe landmark indices.

Each valid direction reversal increments `sweep_count` by one sweep segment. Thresholds for arming, jitter, amplitude, hysteresis, vertical drift, timeouts and strength normalization are all in `config.py`.

The validation scene also contains 28 mixed Latin/Cyrillic letter entities. They begin as one noisy central cluster; active `fan_strength` gives alternating entities opposite outward acceleration, and every confirmed sweep adds an outward impulse. The letters therefore peel apart toward both screen edges while the UI reports a live clear percentage. Pillow plus a Unicode Windows font is used because OpenCV's built-in font cannot render Cyrillic.

## Run

```powershell
python -m pip install -r requirements.txt
python download_model.py
python main.py
```

Keys: `P` positive trial, `N` negative trial, `R` reset, `Q`/`Esc` quit.

The UI shows Open Palm, raw/mapped palm center, state, direction, sweep count, amplitude, horizontal velocity, fan strength and letter-clear percentage. Every launch writes a reproducible `results/run_*` directory with config/environment snapshots, trial summaries and per-frame trajectories.

Recommended negative trials: fist movement, vertical open-palm movement, stationary open palm, small horizontal jitter and one-way horizontal movement.

## Tests

```powershell
python -m unittest discover -s tests -v
```
