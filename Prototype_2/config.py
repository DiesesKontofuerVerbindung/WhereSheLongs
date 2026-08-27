"""All adjustable Fan Gesture Prototype parameters live in this file."""

from pathlib import Path


PROJECT_DIR = Path(__file__).resolve().parent
MODEL_PATH = PROJECT_DIR / "hand_landmarker.task"
RESULTS_DIR = PROJECT_DIR / "results"

# Window and camera.
WINDOW_NAME = "Fan Gesture Prototype 2"
WINDOW_WIDTH = 1000
WINDOW_HEIGHT = 700
CAMERA_INDEX = 0
CAMERA_WIDTH = 1280
CAMERA_HEIGHT = 720
MIRROR_CAMERA = True
TARGET_FPS = 30
CAMERA_BUFFER_SIZE = 1

# Explainable palm classification. Finger extension combines a PIP joint angle
# with fingertip distance from the palm; it does not assume an upright hand.
FINGER_EXTENDED_MIN_ANGLE = 150.0
FINGER_EXTENDED_DISTANCE_RATIO = 1.12

# Fan state machine and horizontal motion geometry (screen pixels / seconds).
PALM_ARM_TIME = 0.25
PALM_ARM_MAX_DRIFT = 36.0
FAN_START_DISTANCE = 55.0
MIN_HORIZONTAL_AMPLITUDE = 80.0
MIN_DIRECTION_DISTANCE = 45.0
MAX_VERTICAL_DRIFT = 105.0
JITTER_DEADZONE = 7.0
DIRECTION_HYSTERESIS = 18.0
FAN_IDLE_TIMEOUT = 1.20
OPEN_PALM_GRACE_TIME = 0.18
MIN_SWEEPS_FOR_SUCCESS = 2
SMOOTHING_FACTOR = 0.35
VELOCITY_SMOOTHING_FACTOR = 0.35
MAX_MISSING_HAND_TIME = 0.35
CURSOR_HOLD_TIME = 0.12
TRAIL_LENGTH = 80
TRAJECTORY_PREFILL_POINTS = 30

# Normalization references for the explainable 0..1 fan-strength formula.
STRENGTH_VELOCITY_REFERENCE = 700.0
STRENGTH_AMPLITUDE_REFERENCE = 180.0
STRENGTH_FREQUENCY_REFERENCE = 2.5
RECENT_SWEEP_WINDOW = 2.0

# Interference entities: mixed Latin/Cyrillic "voices" begin as one central
# cluster and fan strength pushes assigned halves toward opposite screen edges.
INTERFERENCE_ENTITY_COUNT = 28
INTERFERENCE_RANDOM_SEED = 2608
INTERFERENCE_CENTER_X = WINDOW_WIDTH / 2
INTERFERENCE_CENTER_Y = WINDOW_HEIGHT * 0.62
INTERFERENCE_CLUSTER_WIDTH = 260.0
INTERFERENCE_CLUSTER_HEIGHT = 170.0
INTERFERENCE_MIN_FONT_SIZE = 30
INTERFERENCE_MAX_FONT_SIZE = 48
LETTER_MASS_MIN = 0.8
LETTER_MASS_MAX = 1.2
LETTER_RADIUS_SCALE = 0.45
INTERFERENCE_DISPERSED_MARGIN = 45.0

# Pillow renders real Cyrillic glyphs; OpenCV Hershey fonts only cover ASCII.
UNICODE_FONT_CANDIDATES = (
    "C:/Windows/Fonts/segoeui.ttf",
    "C:/Windows/Fonts/arial.ttf",
    "C:/Windows/Fonts/calibri.ttf",
)

# MediaPipe.
NUM_HANDS = 1
MIN_HAND_DETECTION_CONFIDENCE = 0.45
MIN_HAND_PRESENCE_CONFIDENCE = 0.45
MIN_HAND_TRACKING_CONFIDENCE = 0.45

# Reproducible interactive test targets.
TARGET_POSITIVE_TRIALS = 20
TARGET_NEGATIVE_TRIALS = 20
