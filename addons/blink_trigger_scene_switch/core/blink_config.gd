class_name BlinkConfiguration
extends Resource

@export var close_ear: float = 0.19
@export var open_ear: float = 0.23
@export var min_blink_duration_ms: float = 80.0
@export var max_blink_duration_ms: float = 500.0
@export var cooldown_ms: float = 220.0
@export var confidence_threshold: float = 0.6
@export var transition: String = "Fade"
@export var fade_seconds: float = 0.28
@export var black_hold_seconds: float = 0.12
@export var debug_mode: bool = true
@export var detector_ws_url: String = "ws://127.0.0.1:8765"
@export var allow_debug_key_blink: bool = true
