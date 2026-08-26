"""Small dependency-free One Euro filter for post-calibration motion input."""

from __future__ import annotations

import math


def _alpha(cutoff: float, dt: float) -> float:
    tau = 1.0 / (2.0 * math.pi * max(cutoff, 1e-6))
    return 1.0 / (1.0 + tau / max(dt, 1e-6))


class _LowPass:
    def __init__(self) -> None:
        self.value: float | None = None

    def reset(self) -> None:
        self.value = None

    def apply(self, value: float, alpha: float) -> float:
        if self.value is None:
            self.value = value
        else:
            self.value += alpha * (value - self.value)
        return self.value


class OneEuroFilter:
    """Adaptive filter: strong smoothing while slow, reduced lag while fast."""

    def __init__(self, min_cutoff: float, beta: float, d_cutoff: float) -> None:
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self._value_filter = _LowPass()
        self._derivative_filter = _LowPass()
        self._previous_raw: float | None = None
        self._previous_time: float | None = None

    def reset(self) -> None:
        self._value_filter.reset()
        self._derivative_filter.reset()
        self._previous_raw = None
        self._previous_time = None

    def apply(self, value: float, now: float) -> float:
        if self._previous_raw is None or self._previous_time is None:
            self._previous_raw = value
            self._previous_time = now
            return self._value_filter.apply(value, 1.0)
        dt = max(1e-4, now - self._previous_time)
        derivative = (value - self._previous_raw) / dt
        derivative_hat = self._derivative_filter.apply(derivative, _alpha(self.d_cutoff, dt))
        cutoff = self.min_cutoff + self.beta * abs(derivative_hat)
        filtered = self._value_filter.apply(value, _alpha(cutoff, dt))
        self._previous_raw = value
        self._previous_time = now
        return filtered
