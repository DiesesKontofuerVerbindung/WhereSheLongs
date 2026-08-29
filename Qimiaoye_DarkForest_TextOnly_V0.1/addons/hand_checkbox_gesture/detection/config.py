"""Addon-local config for Godot hand-checkbox TCP detector."""

from pathlib import Path
from math import hypot

PROJECT_DIR = Path(__file__).resolve().parent
MODEL_PATH = PROJECT_DIR / "hand_landmarker.task"
ASSETS_DIR = PROJECT_DIR.parent / "assets"
SCENE_P1_PATH = ASSETS_DIR / "p1.jpg"
SCENE_P2_PATH = ASSETS_DIR / "p2.jpg"
RESULTS_DIR = PROJECT_DIR / "results"

WINDOW_NAME = "Hand Checkbox Godot Bridge"
WINDOW_WIDTH = 1024
WINDOW_HEIGHT = 682
CAMERA_INDEX = 0
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
MIRROR_CAMERA = True

_SCREEN_DIAGONAL = hypot(WINDOW_WIDTH, WINDOW_HEIGHT)
CHECK_CENTER = (WINDOW_WIDTH // 2, WINDOW_HEIGHT // 2)
CHECK_RADIUS = int(_SCREEN_DIAGONAL)
START_ZONE_RADIUS = int(_SCREEN_DIAGONAL)
TRACKING_RADIUS = _SCREEN_DIAGONAL
CURSOR_RADIUS = 9
SHOW_GESTURE_OVERLAY = False
SHOW_CAMERA_PREVIEW = False

HINT_TEXT = "用手势在checklist上打勾（先下再右上）"
HINT_DURATION_SEC = 3.0
HINT_CENTER = (WINDOW_WIDTH // 2, 575)
HINT_FONT_SIZE = 28
HINT_COLOR = (55, 48, 42)

ARM_RADIUS = _SCREEN_DIAGONAL
ARM_HOLD_TIME = 0.03
ARM_MAX_SPEED = 4000.0
CANDIDATE_BUFFER_SECONDS = 1.5
START_DOWN_DISTANCE = 2.0
START_RIGHT_DISTANCE = 0.5
START_MIN_POINTS = 2
CANDIDATE_REARM_DELAY = 0.03
FAIL_AUTO_REARM_TIME = 0.15
SHOW_ARMING_PROGRESS = False

MIN_PATH_LENGTH = 12.0
MIN_DOWN_DISTANCE = 2.5
MIN_UP_DISTANCE = 2.5
MIN_HORIZONTAL_DISTANCE = 0.5
MIN_HORIZONTAL_SEGMENT = MIN_HORIZONTAL_DISTANCE
MIN_POINTS = 2
MAX_DRAW_TIME = 12.0
MAX_MISSING_HAND_TIME = 1.2
MIN_POINT_DISTANCE = 0.8
SMOOTHING_FACTOR = 0.3
TURN_TOLERANCE = 18.0
DIRECTION_TOLERANCE = 50.0
INVALID_DIRECTION_DISTANCE = 120.0
MIN_EARLY_VALIDATION_PATH_LENGTH = 24.0
MAX_BACKTRACK_PIXELS = DIRECTION_TOLERANCE
MIN_TREND_RATIO = 0.10
MIN_TURN_FRACTION = 0.01
MAX_TURN_FRACTION = 0.99
MAX_TRAIL_POINTS = 120

# 婚礼接入：再松——勾到转折完成即可成功；也可凭最短轨迹长度过关。
WEDDING_LOOSE_MODE = True
WEDDING_SUCCESS_FROM_PHASE = "TURN_OK"
WEDDING_MIN_PATH_FALLBACK = 36.0

CHECK_MARK_PROFILES = (
    {
        "name": "wide_tail",
        "min_path_length": 12.0,
        "min_down_distance": 2.5,
        "min_up_distance": 2.0,
        "min_down_right": 0.5,
        "min_up_right": 1.5,
        "min_turn_fraction": 0.01,
        "max_turn_fraction": 0.99,
    },
    {
        "name": "steep_tail",
        "min_path_length": 12.0,
        "min_down_distance": 2.5,
        "min_up_distance": 2.5,
        "min_down_right": 0.3,
        "min_up_right": 0.3,
        "min_turn_fraction": 0.01,
        "max_turn_fraction": 0.99,
    },
    {
        "name": "balanced",
        "min_path_length": MIN_PATH_LENGTH,
        "min_down_distance": MIN_DOWN_DISTANCE,
        "min_up_distance": MIN_UP_DISTANCE,
        "min_down_right": MIN_HORIZONTAL_DISTANCE,
        "min_up_right": 1.0,
        "min_turn_fraction": MIN_TURN_FRACTION,
        "max_turn_fraction": MAX_TURN_FRACTION,
    },
)

NUM_HANDS = 1
MIN_HAND_DETECTION_CONFIDENCE = 0.25
MIN_HAND_PRESENCE_CONFIDENCE = 0.25
MIN_HAND_TRACKING_CONFIDENCE = 0.25
TARGET_FPS = 30
TARGET_POSITIVE_TRIALS = 20
TARGET_NEGATIVE_TRIALS = 20

# Godot TCP bridge
HOST = "127.0.0.1"
PORT = 8771
