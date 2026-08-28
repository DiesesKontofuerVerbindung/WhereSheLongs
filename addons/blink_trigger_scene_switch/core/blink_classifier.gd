class_name BlinkClassifier
extends RefCounted

## OPEN -> CLOSED -> OPEN within duration window = one blink.

var config: BlinkConfiguration

var phase: String = "need_open"
var closed_started_at: float = 0.0
var closed_frames: int = 0
var open_frames: int = 0
var last_blink_at: float = -10000.0
var left_eye: String = "unknown"
var right_eye: String = "unknown"


func _init(p_config: BlinkConfiguration = null) -> void:
	config = p_config if p_config else BlinkConfiguration.new()


func reset() -> void:
	phase = "need_open"
	closed_started_at = 0.0
	closed_frames = 0
	open_frames = 0
	left_eye = "unknown"
	right_eye = "unknown"


func update(face_detected: bool, left: String, right: String, now_ms: float) -> Dictionary:
	left_eye = left
	right_eye = right
	if not face_detected:
		reset()
		return _result(false, now_ms, 0.0)

	var closed_score := (0.5 if left == "closed" else 0.0) + (0.5 if right == "closed" else 0.0)
	var open_score := (0.5 if left == "open" else 0.0) + (0.5 if right == "open" else 0.0)
	var confidence := maxf(closed_score, open_score)
	var threshold := config.confidence_threshold
	var min_closed_frames := 1

	if closed_score >= threshold and left != "unknown" and right != "unknown":
		closed_frames += 1
		open_frames = 0
		if closed_frames >= min_closed_frames:
			if phase == "open":
				phase = "closed"
				closed_started_at = now_ms
			elif phase == "need_open":
				phase = "closed_before_open"
		return _result(false, now_ms, confidence)

	if open_score >= threshold:
		open_frames += 1
		closed_frames = 0
		if open_frames < 1:
			return _result(false, now_ms, confidence)
		if phase == "closed":
			var duration := now_ms - closed_started_at
			phase = "open"
			var in_window := (
				duration >= config.min_blink_duration_ms
				and duration <= config.max_blink_duration_ms
			)
			var cooled := now_ms - last_blink_at >= config.cooldown_ms
			if in_window and cooled:
				last_blink_at = now_ms
				return _result(true, now_ms, confidence, duration)
			return _result(false, now_ms, confidence, duration)
		if phase == "closed_before_open" or phase == "need_open":
			phase = "open"
		return _result(false, now_ms, confidence)

	return _result(false, now_ms, confidence)


func _result(blink: bool, now_ms: float, confidence: float, duration_ms: float = 0.0) -> Dictionary:
	return {
		"blink": blink,
		"leftEye": left_eye,
		"rightEye": right_eye,
		"phase": phase,
		"confidence": confidence,
		"durationMs": duration_ms,
		"now": now_ms,
	}
