"""All adjustable prototype parameters live here."""

from pathlib import Path
from math import hypot


PROJECT_DIR = Path(__file__).resolve().parent
MODEL_PATH = PROJECT_DIR / "hand_landmarker.task"
RESULTS_DIR = PROJECT_DIR / "results"
ASSETS_DIR = PROJECT_DIR / "assets"
SCENE_P1_PATH = ASSETS_DIR / "p1.jpg"
SCENE_P2_PATH = ASSETS_DIR / "p2.jpg"

# Window and camera — match p1/p2 art (1024x682)
WINDOW_NAME = "Hand Checkbox Prototype"
WINDOW_WIDTH = 1024
WINDOW_HEIGHT = 682
CAMERA_INDEX = 0
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
MIRROR_CAMERA = True

# Invisible full-screen hit zone (circle not drawn).
_SCREEN_DIAGONAL = hypot(WINDOW_WIDTH, WINDOW_HEIGHT)
CHECK_CENTER = (WINDOW_WIDTH // 2, WINDOW_HEIGHT // 2)
CHECK_RADIUS = int(_SCREEN_DIAGONAL)
START_ZONE_RADIUS = int(_SCREEN_DIAGONAL)
TRACKING_RADIUS = _SCREEN_DIAGONAL
CURSOR_RADIUS = 9
SHOW_GESTURE_OVERLAY = False

# Hint under the checklist card
HINT_TEXT = "用手势在checklist上打勾"
HINT_DURATION_SEC = 3.0
HINT_CENTER = (WINDOW_WIDTH // 2, 575)
HINT_FONT_SIZE = 28
HINT_COLOR = (55, 48, 42)  # BGR for OpenCV compositing after PIL RGB

# Fast arming anywhere on screen; loose check-mark thresholds.
ARM_RADIUS = _SCREEN_DIAGONAL
ARM_HOLD_TIME = 0.05
ARM_MAX_SPEED = 2000.0
CANDIDATE_BUFFER_SECONDS = 1.2
START_DOWN_DISTANCE = 4.0
START_RIGHT_DISTANCE = 2.0
START_MIN_POINTS = 2
CANDIDATE_REARM_DELAY = 0.05
FAIL_AUTO_REARM_TIME = 0.25
SHOW_ARMING_PROGRESS = False
SHOW_CAMERA_PREVIEW = False

# Gesture detector thresholds (very loose for demo)
MIN_PATH_LENGTH = 28.0
MIN_DOWN_DISTANCE = 5.0
MIN_UP_DISTANCE = 5.0
MIN_HORIZONTAL_DISTANCE = 2.0
MIN_HORIZONTAL_SEGMENT = MIN_HORIZONTAL_DISTANCE
MIN_POINTS = 4
MAX_DRAW_TIME = 8.0
MAX_MISSING_HAND_TIME = 0.7
MIN_POINT_DISTANCE = 1.2
SMOOTHING_FACTOR = 0.4
TURN_TOLERANCE = 10.0
DIRECTION_TOLERANCE = 36.0
INVALID_DIRECTION_DISTANCE = 90.0
MIN_EARLY_VALIDATION_PATH_LENGTH = 40.0
MAX_BACKTRACK_PIXELS = DIRECTION_TOLERANCE
MIN_TREND_RATIO = 0.22
MIN_TURN_FRACTION = 0.03
MAX_TURN_FRACTION = 0.97
MAX_TRAIL_POINTS = 90

CHECK_MARK_PROFILES = (
    {
        "name": "wide_tail",
        "min_path_length": 28.0,
        "min_down_distance": 5.0,
        "min_up_distance": 4.0,
        "min_down_right": 2.0,
        "min_up_right": 4.0,
        "min_turn_fraction": 0.03,
        "max_turn_fraction": 0.97,
    },
    {
        "name": "steep_tail",
        "min_path_length": 28.0,
        "min_down_distance": 5.0,
        "min_up_distance": 6.0,
        "min_down_right": 1.0,
        "min_up_right": 1.0,
        "min_turn_fraction": 0.03,
        "max_turn_fraction": 0.97,
    },
    {
        "name": "balanced",
        "min_path_length": MIN_PATH_LENGTH,
        "min_down_distance": MIN_DOWN_DISTANCE,
        "min_up_distance": MIN_UP_DISTANCE,
        "min_down_right": MIN_HORIZONTAL_DISTANCE,
        "min_up_right": 3.0,
        "min_turn_fraction": MIN_TURN_FRACTION,
        "max_turn_fraction": MAX_TURN_FRACTION,
    },
)

# MediaPipe confidence values
NUM_HANDS = 1
MIN_HAND_DETECTION_CONFIDENCE = 0.35
MIN_HAND_PRESENCE_CONFIDENCE = 0.35
MIN_HAND_TRACKING_CONFIDENCE = 0.35

# OpenCV loop
TARGET_FPS = 30

TARGET_POSITIVE_TRIALS = 20
TARGET_NEGATIVE_TRIALS = 20
