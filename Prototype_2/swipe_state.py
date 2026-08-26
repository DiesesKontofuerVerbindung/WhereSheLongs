"""State names for the Prototype 2 swipe interaction."""

from enum import Enum


class SwipeState(str, Enum):
    TRACKING = "TRACKING"
    BLOCK_HOVER = "BLOCK_HOVER"
    BLOCK_ARMED = "BLOCK_ARMED"
    SWIPING = "SWIPING"
    BLOCK_REMOVED = "BLOCK_REMOVED"
    FAILED = "FAILED"
