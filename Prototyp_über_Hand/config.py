"""All adjustable prototype parameters live here."""

from pathlib import Path


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

# Fullscreen invisible detection zone (circle not drawn).
CHECK_CENTER = (WINDOW_WIDTH // 2, WINDOW_HEIGHT // 2)
_FULLSCREEN_RADIUS = ((WINDOW_WIDTH**2 + WINDOW_HEIGHT**2) ** 0.5) / 2 + 40.0
CHECK_RADIUS = int(_FULLSCREEN_RADIUS)
START_ZONE_RADIUS = int(_FULLSCREEN_RADIUS)
TRACKING_RADIUS = _FULLSCREEN_RADIUS
CURSOR_RADIUS = 9
SHOW_DETECTION_CIRCLE = False
SHOW_STROKE_TRAIL = True

# Hint under the checklist card (Chinese); auto-hides.
HINT_TEXT = "用手势在checklist上打勾"
HINT_DURATION_SEC = 3.0
HINT_CENTER = (WINDOW_WIDTH // 2, 605)
HINT_FONT_SIZE = 28

# Gesture segmentation: entering the circle is only preparation, never a trial.
ARM_RADIUS = _FULLSCREEN_RADIUS
ARM_HOLD_TIME = 0.12
ARM_MAX_SPEED = 420.0
CANDIDATE_BUFFER_SECONDS = 0.90
START_DOWN_DISTANCE = 6.0
START_RIGHT_DISTANCE = 4.0
START_MIN_POINTS = 3
CANDIDATE_REARM_DELAY = 0.08
FAIL_AUTO_REARM_TIME = 0.35
SHOW_ARMING_PROGRESS = False

# Gesture detector thresholds — looser ✓ acceptance
MIN_PATH_LENGTH = 45.0
MIN_DOWN_DISTANCE = 8.0
MIN_UP_DISTANCE = 8.0
MIN_HORIZONTAL_DISTANCE = 4.0
# Kept as an alias for v0.1 callers.
MIN_HORIZONTAL_SEGMENT = MIN_HORIZONTAL_DISTANCE
MIN_POINTS = 6
MAX_DRAW_TIME = 6.0
MAX_MISSING_HAND_TIME = 0.45
MIN_POINT_DISTANCE = 1.5
SMOOTHING_FACTOR = 0.35
TURN_TOLERANCE = 22.0
DIRECTION_TOLERANCE = 24.0
INVALID_DIRECTION_DISTANCE = 70.0
MIN_EARLY_VALIDATION_PATH_LENGTH = 30.0
MAX_BACKTRACK_PIXELS = DIRECTION_TOLERANCE
MIN_TREND_RATIO = 0.32
MIN_TURN_FRACTION = 0.05
MAX_TURN_FRACTION = 0.95
MAX_TRAIL_POINTS = 90

# Accepted ✓ families. Size itself is scale-independent inside TRACKING_RADIUS;
# these profiles cover genuinely different second-stroke shapes. Every family
# still requires right-down -> lowest turn -> right-up, so arbitrary scribbles
# are not free passes.
CHECK_MARK_PROFILES = (
    {
        "name": "wide_tail",
        "min_path_length": 40.0,
        "min_down_distance": 6.0,
        "min_up_distance": 6.0,
        "min_down_right": 3.0,
        "min_up_right": 8.0,
        "min_turn_fraction": 0.04,
        "max_turn_fraction": 0.96,
    },
    {
        "name": "steep_tail",
        "min_path_length": 40.0,
        "min_down_distance": 6.0,
        "min_up_distance": 10.0,
        "min_down_right": 3.0,
        "min_up_right": 2.0,
        "min_turn_fraction": 0.04,
        "max_turn_fraction": 0.96,
    },
    {
        "name": "balanced",
        "min_path_length": MIN_PATH_LENGTH,
        "min_down_distance": MIN_DOWN_DISTANCE,
        "min_up_distance": MIN_UP_DISTANCE,
        "min_down_right": MIN_HORIZONTAL_DISTANCE,
        "min_up_right": 6.0,
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
