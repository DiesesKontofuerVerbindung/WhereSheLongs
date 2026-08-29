"""Small deterministic One Euro filter for real-time palm control."""

from __future__ import annotations

from math import pi


class OneEuroFilter:
    """Adapt smoothing to speed: stable at rest, responsive during motion."""

    def __init__(self, min_cutoff: float, beta: float, derivative_cutoff: float) -> None:
        self.min_cutoff = float(min_cutoff)
        self.beta = float(beta)
        self.derivative_cutoff = float(derivative_cutoff)
        self._last_timestamp: float | None = None
        self._last_raw: float | None = None
        self._filtered: float | None = None
        self._filtered_derivative = 0.0

    def reset(self) -> None:
        self._last_timestamp = None
        self._last_raw = None
        self._filtered = None
        self._filtered_derivative = 0.0

    def filter(self, value: float, timestamp: float) -> float:
        value = float(value)
        timestamp = float(timestamp)
        if self._last_timestamp is None or self._last_raw is None or self._filtered is None:
            self._last_timestamp = timestamp
            self._last_raw = value
            self._filtered = value
            return value
        delta_time = timestamp - self._last_timestamp
        if delta_time <= 1e-6 or delta_time > 0.5:
            self._last_timestamp = timestamp
            self._last_raw = value
            self._filtered = value
            self._filtered_derivative = 0.0
            return value
        derivative = (value - self._last_raw) / delta_time
        derivative_alpha = _alpha(self.derivative_cutoff, delta_time)
        self._filtered_derivative += derivative_alpha * (derivative - self._filtered_derivative)
        cutoff = self.min_cutoff + self.beta * abs(self._filtered_derivative)
        value_alpha = _alpha(cutoff, delta_time)
        self._filtered += value_alpha * (value - self._filtered)
        self._last_timestamp = timestamp
        self._last_raw = value
        return self._filtered


def _alpha(cutoff: float, delta_time: float) -> float:
    cutoff = max(1e-6, float(cutoff))
    tau = 1.0 / (2.0 * pi * cutoff)
    return 1.0 / (1.0 + tau / delta_time)
