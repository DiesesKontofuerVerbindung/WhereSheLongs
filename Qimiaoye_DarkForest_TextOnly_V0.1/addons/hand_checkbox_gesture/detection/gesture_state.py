"""Runtime state and online recognition phases for the check gesture."""

from enum import Enum


class GestureState(str, Enum):
    IDLE = "IDLE"
    TRACKING = "TRACKING"
    ARMING = "ARMING"
    ARMED = "ARMED"
    DRAWING = "DRAWING"
    CHECKED = "CHECKED"
    FAILED = "FAILED"


class GesturePhase(str, Enum):
    IDLE = "IDLE"
    TRACKING = "TRACKING"
    ARMING = "ARMING"
    ARMED = "ARMED"
    STARTED = "STARTED"
    DOWNSTROKE_OK = "DOWNSTROKE_OK"
    TURN_OK = "TURN_OK"
    UPSTROKE_OK = "UPSTROKE_OK"
    SUCCESS = "SUCCESS"
    FAILED = "FAILED"
