"""All adjustable Prototype 2 parameters live in this file."""

from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent
MODEL_PATH = PROJECT_DIR / "hand_landmarker.task"
RESULTS_DIR = PROJECT_DIR / "results"

# Window and camera.
WINDOW_NAME = "Swipe Checklist Prototype 2"
WINDOW_WIDTH = 1000
WINDOW_HEIGHT = 700
CAMERA_INDEX = 0
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
MIRROR_CAMERA = True
TARGET_FPS = 30
CAMERA_BUFFER_SIZE = 1

# Layout: five 2D logs overlap into one stack; only its top log is interactable.
SECTION_COUNT = 6
SECTION_HEIGHT = WINDOW_HEIGHT / SECTION_COUNT
BLOCK_COUNT = 5
BLOCK_WIDTH = 500
BLOCK_HEIGHT = 68
BLOCK_GAP = 0
BLOCK_SECTION = 5
WOOD_STACK_CENTER_X = WINDOW_WIDTH / 2
WOOD_STACK_BASE_Y = WINDOW_HEIGHT * 0.82
WOOD_STACK_LAYER_STEP = 48
WOOD_STACK_X_OFFSETS = (0, -22, 18, -12, 10)

# Interaction and swipe geometry.
INTERACTION_BOTTOM_RATIO = 1.25
INTERACTION_BOTTOM_Y = WINDOW_HEIGHT * INTERACTION_BOTTOM_RATIO
REMOVE_THRESHOLD_Y = WINDOW_HEIGHT * 2 / 6

# Camera-to-screen calibration. A webcam often sees only the upper portion of
# the player's reachable hand range, so raw MediaPipe Y is compressed into the
# full playable height instead of being copied one-to-one.
CURSOR_Y_INPUT_MIN = 0.0
CURSOR_Y_INPUT_MAX = 0.62
CURSOR_Y_OUTPUT_MIN_RATIO = 0.0
CURSOR_Y_OUTPUT_MAX_RATIO = INTERACTION_BOTTOM_RATIO

# Completed blocks visibly leave the top of the window instead of vanishing
# the instant their success threshold is crossed.
BLOCK_FLY_OUT_DURATION = 0.28
BLOCK_FLY_OUT_TARGET_Y = -BLOCK_HEIGHT

# Calibration evidence is sampled independently from formal swipe trajectories.
COORDINATE_MONITOR_HZ = 10.0

BLOCK_ARM_TIME = 0.22
BLOCK_HITBOX_MARGIN = 22
MIN_SWIPE_START_DISTANCE = 26.0
MIN_SWIPE_UP_DISTANCE = 230.0
MAX_HORIZONTAL_DRIFT = 90.0
MAX_SWIPE_TIME = 2.5
FAIL_AUTO_REARM_TIME = 0.35
SMOOTHING_FACTOR = 0.35
MAX_MISSING_HAND_TIME = 0.35
CURSOR_HOLD_TIME = 0.12
CANDIDATE_REJECT_DISTANCE = 30.0
FINGER_EXTENSION_MARGIN = 0.02
TRAIL_LENGTH = 80
TRAJECTORY_PREFILL_POINTS = 30

# MediaPipe.
NUM_HANDS = 1
MIN_HAND_DETECTION_CONFIDENCE = 0.45
MIN_HAND_PRESENCE_CONFIDENCE = 0.45
MIN_HAND_TRACKING_CONFIDENCE = 0.45

# Reproducible interactive test targets.
TARGET_POSITIVE_TRIALS = 20
TARGET_NEGATIVE_TRIALS = 20

ONE_FINGER = "ONE_FINGER"
TWO_FINGER = "TWO_FINGER"
MOUSE_FINGER = "MOUSE"
