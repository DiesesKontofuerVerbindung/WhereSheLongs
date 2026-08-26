"""All adjustable prototype parameters live here."""

from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent
MODEL_PATH = PROJECT_DIR / "hand_landmarker.task"
RESULTS_DIR = PROJECT_DIR / "results"

# Window and camera
WINDOW_NAME = "Hand Checkbox Prototype"
WINDOW_WIDTH = 1000
WINDOW_HEIGHT = 700
CAMERA_INDEX = 0
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
MIRROR_CAMERA = True

# Checkbox and hand cursor
CHECK_CENTER = (WINDOW_WIDTH // 2, WINDOW_HEIGHT // 2)
CHECK_RADIUS = 145
START_ZONE_RADIUS = 185
TRACKING_RADIUS = 330
CURSOR_RADIUS = 9

# Gesture segmentation: entering the circle is only preparation, never a trial.
ARM_RADIUS = 150.0
ARM_HOLD_TIME = 0.30
ARM_MAX_SPEED = 180.0
CANDIDATE_BUFFER_SECONDS = 0.80
START_DOWN_DISTANCE = 12.0
START_RIGHT_DISTANCE = 10.0
START_MIN_POINTS = 4
CANDIDATE_REARM_DELAY = 0.12
FAIL_AUTO_REARM_TIME = 0.50
SHOW_ARMING_PROGRESS = True

# Gesture detector thresholds
MIN_PATH_LENGTH = 95.0
MIN_DOWN_DISTANCE = 18.0
MIN_UP_DISTANCE = 18.0
MIN_HORIZONTAL_DISTANCE = 10.0
# Kept as an alias for v0.1 callers.
MIN_HORIZONTAL_SEGMENT = MIN_HORIZONTAL_DISTANCE
MIN_POINTS = 10
MAX_DRAW_TIME = 4.2
MAX_MISSING_HAND_TIME = 0.35
MIN_POINT_DISTANCE = 2.0
SMOOTHING_FACTOR = 0.35
TURN_TOLERANCE = 14.0
DIRECTION_TOLERANCE = 16.0
INVALID_DIRECTION_DISTANCE = 45.0
MIN_EARLY_VALIDATION_PATH_LENGTH = 70.0
MAX_BACKTRACK_PIXELS = DIRECTION_TOLERANCE
MIN_TREND_RATIO = 0.52
MIN_TURN_FRACTION = 0.10
MAX_TURN_FRACTION = 0.88
MAX_TRAIL_POINTS = 90

# Accepted ✓ families. Size itself is scale-independent inside TRACKING_RADIUS;
# these profiles cover genuinely different second-stroke shapes. Every family
# still requires right-down -> lowest turn -> right-up, so arbitrary scribbles
# are not free passes.
CHECK_MARK_PROFILES = (
    {
        "name": "wide_tail",
        "min_path_length": 105.0,
        "min_down_distance": 18.0,
        "min_up_distance": 12.0,
        "min_down_right": 10.0,
        "min_up_right": 22.0,
        "min_turn_fraction": 0.08,
        "max_turn_fraction": 0.92,
    },
    {
        "name": "steep_tail",
        "min_path_length": 105.0,
        "min_down_distance": 18.0,
        "min_up_distance": 28.0,
        "min_down_right": 10.0,
        "min_up_right": 6.0,
        "min_turn_fraction": 0.08,
        "max_turn_fraction": 0.90,
    },
    {
        "name": "balanced",
        "min_path_length": MIN_PATH_LENGTH,
        "min_down_distance": MIN_DOWN_DISTANCE,
        "min_up_distance": MIN_UP_DISTANCE,
        "min_down_right": MIN_HORIZONTAL_DISTANCE,
        "min_up_right": 15.0,
        "min_turn_fraction": MIN_TURN_FRACTION,
        "max_turn_fraction": MAX_TURN_FRACTION,
    },
)

# MediaPipe confidence values
NUM_HANDS = 1
MIN_HAND_DETECTION_CONFIDENCE = 0.55
MIN_HAND_PRESENCE_CONFIDENCE = 0.55
MIN_HAND_TRACKING_CONFIDENCE = 0.55

# OpenCV loop
TARGET_FPS = 30

# Reproducible interactive-test targets. P/N switches the expected label.
TARGET_POSITIVE_TRIALS = 20
TARGET_NEGATIVE_TRIALS = 20
