class_name FanGestureDetector
extends RefCounted

## Godot port of Prototype_2_Fan's explainable Open-Palm Fan detector.
## Source contract: fan_update { strength, direction, sweep_count }.

const STATE_TRACKING := "TRACKING"
const STATE_PALM_ARMING := "PALM_ARMING"
const STATE_FAN_READY := "FAN_READY"
const STATE_FANNING := "FANNING"

const PALM_ARM_TIME := 0.12
const PALM_ARM_MAX_DRIFT := 55.0
const FAN_START_DISTANCE := 32.0
const MIN_HORIZONTAL_AMPLITUDE := 65.0
const MIN_DIRECTION_DISTANCE := 32.0
const MAX_VERTICAL_DRIFT := 105.0
const JITTER_DEADZONE := 7.0
const DIRECTION_HYSTERESIS := 14.0
const FAN_IDLE_TIMEOUT := 1.20
const OPEN_PALM_GRACE_TIME := 0.24
const MIN_SWEEPS_FOR_SUCCESS := 2
const SMOOTHING_FACTOR := 0.55
const VELOCITY_SMOOTHING_FACTOR := 0.55
const MAX_MISSING_HAND_TIME := 0.35

const STRENGTH_VELOCITY_REFERENCE := 700.0
const STRENGTH_AMPLITUDE_REFERENCE := 180.0
const STRENGTH_FREQUENCY_REFERENCE := 2.5
const RECENT_SWEEP_WINDOW := 2.0

var state := STATE_TRACKING
var direction := "center"
var sweep_count := 0
var horizontal_amplitude := 0.0
var horizontal_velocity := 0.0
var fan_strength := 0.0
var anchor_x := NAN
var anchor_y := NAN

var _last_point := Vector2.ZERO
var _has_last_point := false
var _last_seen_at := NAN
var _last_open_palm_at := NAN
var _last_point_at := NAN
var _arming_anchor := Vector2.ZERO
var _has_arming_anchor := false
var _arming_started_at := NAN
var _ready_at := NAN
var _last_significant_motion_at := NAN
var _segment_origin_x := NAN
var _direction_extreme_x := NAN
var _sweep_timestamps: Array[float] = []
var _completed_emitted := false


func reset() -> void:
	_clear_session()


func update(raw_point: Variant, open_palm: bool, now: float) -> Dictionary:
	if raw_point == null:
		if state != STATE_TRACKING and not is_nan(_last_seen_at) and now - _last_seen_at > MAX_MISSING_HAND_TIME:
			return _reset_event("hand_lost", state in [STATE_FAN_READY, STATE_FANNING])
		return _event()
	if not raw_point is Vector2:
		return _reset_event("invalid_point", state in [STATE_FAN_READY, STATE_FANNING])

	var point: Vector2 = raw_point
	var previous_point := _last_point
	var previous_time := _last_point_at
	var had_previous := _has_last_point
	_last_seen_at = now
	var smoothed := point if not had_previous else _last_point.lerp(point, SMOOTHING_FACTOR)
	_last_point = smoothed
	_has_last_point = true
	_last_point_at = now

	if had_previous and not is_nan(previous_time):
		var delta_time := maxf(0.000001, now - previous_time)
		var instantaneous_velocity := (smoothed.x - previous_point.x) / delta_time
		horizontal_velocity += VELOCITY_SMOOTHING_FACTOR * (instantaneous_velocity - horizontal_velocity)
		if absf(smoothed.x - previous_point.x) >= JITTER_DEADZONE:
			_last_significant_motion_at = now
	else:
		horizontal_velocity = 0.0

	if open_palm:
		_last_open_palm_at = now
	elif state != STATE_TRACKING and (is_nan(_last_open_palm_at) or now - _last_open_palm_at > OPEN_PALM_GRACE_TIME):
		return _reset_event("open_palm_lost", state in [STATE_FAN_READY, STATE_FANNING])
	elif state != STATE_TRACKING:
		return _event()

	if state == STATE_TRACKING:
		if not open_palm:
			return _event()
		state = STATE_PALM_ARMING
		_arming_anchor = smoothed
		_has_arming_anchor = true
		_arming_started_at = now
	elif state == STATE_PALM_ARMING:
		if not _has_arming_anchor or is_nan(_arming_started_at):
			_arming_anchor = smoothed
			_has_arming_anchor = true
			_arming_started_at = now
		elif smoothed.distance_to(_arming_anchor) > PALM_ARM_MAX_DRIFT:
			_arming_anchor = smoothed
			_arming_started_at = now
		elif now - _arming_started_at >= PALM_ARM_TIME:
			state = STATE_FAN_READY
			anchor_x = smoothed.x
			anchor_y = smoothed.y
			_segment_origin_x = smoothed.x
			_direction_extreme_x = smoothed.x
			_ready_at = now
			_last_significant_motion_at = now
	elif state == STATE_FAN_READY:
		if _vertical_drift(smoothed) > MAX_VERTICAL_DRIFT:
			return _reset_event("vertical_drift", true)
		if not is_nan(_ready_at) and now - _ready_at > FAN_IDLE_TIMEOUT:
			return _reset_event("no_horizontal_motion", true)
		var displacement := smoothed.x - anchor_x
		if absf(displacement) >= FAN_START_DISTANCE:
			state = STATE_FANNING
			direction = "right" if displacement > 0.0 else "left"
			_segment_origin_x = anchor_x
			_direction_extreme_x = smoothed.x
			horizontal_amplitude = absf(displacement)
			_last_significant_motion_at = now
	elif state == STATE_FANNING:
		if _vertical_drift(smoothed) > MAX_VERTICAL_DRIFT:
			return _reset_event("vertical_drift", true)
		if not is_nan(_last_significant_motion_at) and now - _last_significant_motion_at > FAN_IDLE_TIMEOUT:
			return _reset_event("no_horizontal_motion", true)
		_update_sweeps(smoothed, now)

	fan_strength = _calculate_strength(now)
	var completed := sweep_count >= MIN_SWEEPS_FOR_SUCCESS and not _completed_emitted
	if completed:
		_completed_emitted = true
	return _event(completed)


func _update_sweeps(point: Vector2, now: float) -> void:
	if direction == "right":
		_direction_extreme_x = maxf(_direction_extreme_x, point.x)
		var segment_amplitude := _direction_extreme_x - _segment_origin_x
		var opposite_distance := _direction_extreme_x - point.x
		horizontal_amplitude = maxf(0.0, segment_amplitude)
		if segment_amplitude >= MIN_HORIZONTAL_AMPLITUDE and opposite_distance >= maxf(DIRECTION_HYSTERESIS, MIN_DIRECTION_DISTANCE):
			_accept_reversal("left", _direction_extreme_x, point.x, segment_amplitude, now)
	elif direction == "left":
		_direction_extreme_x = minf(_direction_extreme_x, point.x)
		var segment_amplitude := _segment_origin_x - _direction_extreme_x
		var opposite_distance := point.x - _direction_extreme_x
		horizontal_amplitude = maxf(0.0, segment_amplitude)
		if segment_amplitude >= MIN_HORIZONTAL_AMPLITUDE and opposite_distance >= maxf(DIRECTION_HYSTERESIS, MIN_DIRECTION_DISTANCE):
			_accept_reversal("right", _direction_extreme_x, point.x, segment_amplitude, now)


func _accept_reversal(next_direction: String, old_extreme: float, current_x: float, amplitude: float, now: float) -> void:
	sweep_count += 1
	_sweep_timestamps.append(now)
	direction = next_direction
	_segment_origin_x = old_extreme
	_direction_extreme_x = current_x
	horizontal_amplitude = maxf(amplitude, absf(current_x - old_extreme))
	_last_significant_motion_at = now


func _calculate_strength(now: float) -> float:
	var recent: Array[float] = []
	for timestamp in _sweep_timestamps:
		if timestamp >= now - RECENT_SWEEP_WINDOW:
			recent.append(timestamp)
	_sweep_timestamps = recent
	var frequency := float(recent.size()) / RECENT_SWEEP_WINDOW
	var velocity_component := minf(1.0, absf(horizontal_velocity) / STRENGTH_VELOCITY_REFERENCE)
	var amplitude_component := minf(1.0, horizontal_amplitude / STRENGTH_AMPLITUDE_REFERENCE)
	var frequency_component := minf(1.0, frequency / STRENGTH_FREQUENCY_REFERENCE)
	return snappedf(0.50 * velocity_component + 0.30 * amplitude_component + 0.20 * frequency_component, 0.0001)


func _vertical_drift(point: Vector2) -> float:
	return 0.0 if is_nan(anchor_y) else absf(point.y - anchor_y)


func _event(completed := false) -> Dictionary:
	return {
		"event": "fan_update",
		"state": state,
		"strength": fan_strength,
		"direction": direction,
		"sweep_count": sweep_count,
		"horizontal_amplitude": horizontal_amplitude,
		"horizontal_velocity": horizontal_velocity,
		"completed": completed,
		"reset": false,
		"fail_reason": "",
	}


func _reset_event(reason: String, terminal: bool) -> Dictionary:
	var event := _event(false)
	event["reset"] = true
	event["terminal"] = terminal
	event["fail_reason"] = reason
	_clear_session()
	return event


func _clear_session() -> void:
	state = STATE_TRACKING
	direction = "center"
	sweep_count = 0
	horizontal_amplitude = 0.0
	horizontal_velocity = 0.0
	fan_strength = 0.0
	anchor_x = NAN
	anchor_y = NAN
	_last_point = Vector2.ZERO
	_has_last_point = false
	_last_seen_at = NAN
	_last_open_palm_at = NAN
	_last_point_at = NAN
	_arming_anchor = Vector2.ZERO
	_has_arming_anchor = false
	_arming_started_at = NAN
	_ready_at = NAN
	_last_significant_motion_at = NAN
	_segment_origin_x = NAN
	_direction_extreme_x = NAN
	_sweep_timestamps.clear()
	_completed_emitted = false
