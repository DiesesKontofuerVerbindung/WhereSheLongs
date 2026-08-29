class_name Chapter3NarrationUI
extends Control

signal advance_requested
signal narration_presented(token: int)
signal queue_idle
signal fade_finished

const MAX_RETAINED := 2
const MAX_ON_SCREEN_DURING_TRANSITION := 3
const ENTRY_HEIGHT := 64.0
const OLD_Y := -10.0
const CENTER_TOLERANCE := 0.75
const DIRECT_FADE_IN_DURATION := 0.36

var _entries: Array[Label] = []
var _pending: Array[Dictionary] = []
var _completed: Dictionary = {}
var _next_token := 1
var _processing := false
var _waiting_for_advance := false
var _continue_button: Button
var _max_observed_count := 0
var _fade_after_queue := false
var _fade_after_queue_instant := false
var _fade_active := false
var _fading_entries: Array[Label] = []
var _layout_sample_count := 0
var _layout_violation_count := 0
var _max_center_error := 0.0
var _max_width_overflow := 0.0


func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    clip_contents = false
    resized.connect(_reflow_widths)
    _continue_button = Button.new()
    _continue_button.name = "NarrationContinue"
    _continue_button.text = "继续"
    _continue_button.flat = true
    _continue_button.visible = false
    _continue_button.mouse_filter = Control.MOUSE_FILTER_STOP
    _continue_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
    _continue_button.offset_left = -70
    _continue_button.offset_right = 70
    _continue_button.offset_top = 8
    _continue_button.offset_bottom = 36
    _continue_button.add_theme_font_size_override("font_size", 14)
    _continue_button.add_theme_color_override("font_color", Color(0.78, 0.84, 0.92, 0.82))
    _continue_button.pressed.connect(request_advance)
    add_child(_continue_button)
    call_deferred("_reflow_widths")


func present(text: String, instant := false) -> void:
    var token := enqueue(text, instant)
    while not _completed.has(token):
        await narration_presented


func enqueue(text: String, instant := false) -> int:
    var token := _next_token
    _next_token += 1
    _pending.append({"token": token, "text": text, "instant": instant})
    if not _processing:
        _processing = true
        call_deferred("_drain_queue")
    return token


func wait_until_idle() -> void:
    while _processing or not _pending.is_empty():
        await queue_idle


func set_advance_waiting(enabled: bool) -> void:
    _waiting_for_advance = enabled
    _continue_button.visible = enabled


func request_advance() -> void:
    if not _waiting_for_advance:
        return
    _waiting_for_advance = false
    _continue_button.visible = false
    advance_requested.emit()


func begin_fade_for_dialogue(instant := false) -> void:
    set_advance_waiting(false)
    if _processing or not _pending.is_empty():
        _fade_after_queue = true
        _fade_after_queue_instant = instant
        return
    _start_fade_out(instant)


func clear_immediately() -> void:
    _pending.clear()
    for entry in _entries:
        if is_instance_valid(entry):
            entry.queue_free()
    _entries.clear()
    for entry in _fading_entries:
        if is_instance_valid(entry):
            entry.queue_free()
    _fading_entries.clear()
    _completed.clear()
    _processing = false
    _fade_active = false
    _fade_after_queue = false
    _layout_sample_count = 0
    _layout_violation_count = 0
    _max_center_error = 0.0
    _max_width_overflow = 0.0
    set_advance_waiting(false)


func get_visible_entry_count() -> int:
    return _entries.size()


func get_max_observed_count() -> int:
    return _max_observed_count


func get_latest_text() -> String:
    if _entries.is_empty():
        return ""
    return _entries.back().text


func is_queue_idle() -> bool:
    return not _processing and _pending.is_empty()


func get_layout_sample_count() -> int:
    return _layout_sample_count


func get_layout_violation_count() -> int:
    return _layout_violation_count


func get_max_center_error() -> float:
    return _max_center_error


func get_max_width_overflow() -> float:
    return _max_width_overflow


func is_horizontally_centered() -> bool:
    if not is_equal_approx(anchor_left + anchor_right, 1.0):
        return false
    if not is_equal_approx(offset_left + offset_right, 0.0):
        return false
    if _continue_button == null:
        return false
    if not is_equal_approx(_continue_button.anchor_left, 0.5) or not is_equal_approx(_continue_button.anchor_right, 0.5):
        return false
    if not is_equal_approx(_continue_button.offset_left + _continue_button.offset_right, 0.0):
        return false
    for entry in _entries:
        if entry.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER:
            return false
        if not is_equal_approx(entry.position.x, 0.0) or not is_equal_approx(entry.size.x, size.x):
            return false
    return true


func uses_direct_reveal() -> bool:
    return DIRECT_FADE_IN_DURATION > 0.0


func _drain_queue() -> void:
    if _fade_active:
        await fade_finished
    while not _pending.is_empty():
        var request: Dictionary = _pending.pop_front()
        await _animate_new_entry(str(request.get("text", "")), bool(request.get("instant", false)))
        var token := int(request.get("token", 0))
        _completed[token] = true
        narration_presented.emit(token)
    _processing = false
    queue_idle.emit()
    if _fade_after_queue:
        var instant := _fade_after_queue_instant
        _fade_after_queue = false
        _fade_after_queue_instant = false
        _start_fade_out(instant)


func _animate_new_entry(text: String, instant: bool) -> void:
    var new_entry := _make_entry(text)
    var latest_y := maxf(54.0, size.y - ENTRY_HEIGHT - 10.0)
    add_child(new_entry)
    new_entry.position = Vector2(0, size.y + 8.0)
    new_entry.size = Vector2(maxf(size.x, 1.0), ENTRY_HEIGHT)
    new_entry.visible_ratio = 1.0
    new_entry.modulate.a = 0.0
    move_child(_continue_button, -1)

    var transient_count := _entries.size() + _fading_entries.size() + 1
    _max_observed_count = maxi(_max_observed_count, transient_count)
    var old_duration := 0.001 if instant else 0.82
    var position_duration := 0.001 if instant else 0.42
    var reveal_duration := 0.001 if instant else DIRECT_FADE_IN_DURATION
    var tween := create_tween()
    tween.set_parallel(true)
    for i in range(_entries.size()):
        var entry := _entries[i]
        var is_oldest_leaving := _entries.size() >= MAX_RETAINED and i == 0
        var target_y := -ENTRY_HEIGHT if is_oldest_leaving else OLD_Y
        var target_alpha := 0.0 if is_oldest_leaving else 0.50
        tween.tween_property(entry, "position:y", target_y, old_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.tween_property(entry, "modulate:a", target_alpha, old_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(new_entry, "position:y", latest_y, position_duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.tween_property(new_entry, "modulate:a", 1.0, reveal_duration).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
    await tween.finished
    new_entry.visible_ratio = 1.0
    new_entry.modulate.a = 1.0
    _record_entry_layout(new_entry)

    _entries.append(new_entry)
    while _entries.size() > MAX_RETAINED:
        var oldest: Label = _entries.pop_front()
        if is_instance_valid(oldest):
            oldest.queue_free()


func _make_entry(text: String) -> Label:
    var label := Label.new()
    label.name = "NarrationEntry"
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
    label.clip_text = true
    label.custom_minimum_size = Vector2.ZERO
    label.add_theme_font_size_override("font_size", 20)
    label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0, 1.0))
    label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.72))
    label.add_theme_constant_override("shadow_offset_x", 1)
    label.add_theme_constant_override("shadow_offset_y", 2)
    label.add_theme_constant_override("shadow_outline_size", 2)
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.text = text
    label.size = Vector2(maxf(size.x, 1.0), ENTRY_HEIGHT)
    return label


func _reflow_widths() -> void:
    var centered_width := maxf(size.x, 1.0)
    for entry in _entries:
        if is_instance_valid(entry):
            entry.position.x = 0.0
            entry.size = Vector2(centered_width, ENTRY_HEIGHT)
    for entry in _fading_entries:
        if is_instance_valid(entry):
            entry.position.x = 0.0
            entry.size = Vector2(centered_width, ENTRY_HEIGHT)


func _record_entry_layout(entry: Label) -> void:
    _layout_sample_count += 1
    var entry_rect := entry.get_global_rect()
    var ui_rect := get_global_rect()
    var viewport_center := ui_rect.position.x + ui_rect.size.x * 0.5
    var entry_center := entry_rect.position.x + entry_rect.size.x * 0.5
    var center_error := absf(entry_center - viewport_center)
    var width_overflow := maxf(0.0, entry.size.x - size.x)
    _max_center_error = maxf(_max_center_error, center_error)
    _max_width_overflow = maxf(_max_width_overflow, width_overflow)
    if entry.horizontal_alignment != HORIZONTAL_ALIGNMENT_CENTER or center_error > CENTER_TOLERANCE or width_overflow > CENTER_TOLERANCE:
        _layout_violation_count += 1


func _start_fade_out(instant: bool) -> void:
    if _entries.is_empty() or _fade_active:
        return
    var snapshot: Array[Label] = _entries.duplicate()
    _entries.clear()
    _fading_entries = snapshot
    _fade_active = true
    var duration := 0.001 if instant else 0.78
    var tween := create_tween()
    tween.set_parallel(true)
    for entry in snapshot:
        if not is_instance_valid(entry):
            continue
        tween.tween_property(entry, "position:y", entry.position.y - 42.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
        tween.tween_property(entry, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
    tween.finished.connect(func() -> void:
        for entry in snapshot:
            if is_instance_valid(entry):
                entry.queue_free()
        _fading_entries.clear()
        _fade_active = false
        fade_finished.emit()
    )
