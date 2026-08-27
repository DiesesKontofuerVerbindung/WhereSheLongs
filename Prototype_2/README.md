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

## Run

```powershell
python -m pip install -r requirements.txt
python download_model.py
python main.py
```

Keys: `P` positive trial, `N` negative trial, `R` reset, `Q`/`Esc` quit.

The UI shows Open Palm, raw/mapped palm center, state, direction, sweep count, amplitude, horizontal velocity and fan strength. Every launch writes a reproducible `results/run_*` directory with config/environment snapshots, trial summaries and per-frame trajectories.

Recommended negative trials: fist movement, vertical open-palm movement, stationary open palm, small horizontal jitter and one-way horizontal movement.

## Tests

```powershell
python -m unittest discover -s tests -v
```
