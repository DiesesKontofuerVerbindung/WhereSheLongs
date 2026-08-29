"""State names for the continuous Fan Gesture interaction."""

from enum import Enum


class FanState(str, Enum):
    TRACKING = "TRACKING"
    PALM_ARMING = "PALM_ARMING"
    FAN_READY = "FAN_READY"
    FANNING = "FANNING"
