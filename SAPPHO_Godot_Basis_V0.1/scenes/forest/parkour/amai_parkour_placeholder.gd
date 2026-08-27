extends CharacterBody2D
class_name AmaiParkourPlaceholder

enum AmaiState {
    RUNNING,
    JUMPING,
    WAITING,
}

signal waiting_started
signal fixed_jump_started(guide_name: StringName, from_index: int, to_index: int)
signal fixed_landing_reached(guide_name: StringName, anchor_index: int, position: Vector2)

@export var player_path: NodePath = ^"../Player"
@export var guide_root_path: NodePath = ^"../Gameplay/AmaiGuides"
@export var movement_speed := 300.0
@export var gravity := 1700.0
@export var jump_impulse := 920.0
@export var max_fall_speed := 1100.0
@export var arrival_tolerance := 12.0
@export var landing_anchor_tolerance := 48.0
@export var landing_vertical_tolerance := 18.0
@export var lead_gap_pattern := PackedFloat32Array([320.0, 620.0, 320.0, 620.0])
@export var recovery_release_distance := 160.0
@export var segment_one_fall_recovery_y := 1080.0
@export var segment_one_escort_lead := 260.0
@export var segment_one_exit_x := 1900.0
@export var segment_three_follow_distance := 150.0
@export var segment_three_follow_speed := 255.0
@export var segment_three_fall_recovery_y := 1080.0
@export var segment_three_escort_lead := 70.0
@export var segment_three_exit_x := 5735.0
@export var trace_enabled := true
@export var trace_path := "res://../tmp/codex_logs/amai_fixed_route_live.log"

var state: int = AmaiState.RUNNING
var last_mimicked_choice: StringName = &""
var active_guide: StringName = &"Segment01Guide"
var _guide_points: Array[Marker2D] = []
var _guide_index := 0
var _leg_active := false
var _leg_is_jump := false
var _jump_launched := false
var _airborne_seen := false
var _jump_landed := false
var _planned_horizontal_speed := 0.0
var _needs_floor_settle := true
var _jump_count := 0
var _landing_history: Array[Vector2] = []
var _last_recorded_guide: StringName = &""
var _last_recorded_anchor_index := -1
var _max_observed_lead := 0.0
var _max_observed_trail := 0.0
var _max_observed_horizontal_speed := 0.0
var _segment_three_route_locked := false
var _waiting_for_player_recovery := false
var _segment_one_exit_released := false
var _segment_three_exit_released := false
var _fall_recovery_count := 0
var _trace_file: FileAccess
var _trace_frame := 0

@onready var player: CharacterBody2D = get_node(player_path)
@onready var choice_label: Label = $ChoiceLabel
@onready var guide_root: Node2D = get_node(guide_root_path)


func _ready() -> void:
    add_collision_exception_with(player)
    _open_trace()
    reset_to_segment(1)


func _exit_tree() -> void:
    _trace_event("SESSION_END")
    if _trace_file != null:
        _trace_file.close()
        _trace_file = null


func _physics_process(delta: float) -> void:
    _trace_frame += 1
    if _guide_points.is_empty():
        velocity = Vector2.ZERO
        _trace_state()
        return

    _max_observed_lead = maxf(_max_observed_lead, global_position.x - player.global_position.x)
    if _is_segment_three_guide():
        _max_observed_trail = maxf(_max_observed_trail, player.global_position.x - global_position.x)

    if (
        (active_guide == &"Segment01Guide" and global_position.y >= segment_one_fall_recovery_y)
        or (_is_segment_three_guide() and global_position.y >= segment_three_fall_recovery_y)
    ):
        _recover_active_guide_fall()
        _trace_state()
        return

    if _needs_floor_settle:
        velocity.x = 0.0
        _apply_gravity(delta)
        move_and_slide()
        if is_on_floor():
            _needs_floor_settle = false
            _record_landing(_guide_index)
        _trace_state()
        return

    if _waiting_for_player_recovery and not _leg_active and is_on_floor():
        if global_position.x - player.global_position.x > recovery_release_distance:
            velocity = Vector2.ZERO
            _set_state(AmaiState.WAITING)
            _trace_state()
            return
        _waiting_for_player_recovery = false
        _trace_event("RECOVERY_RELEASE", "player_x=%.1f amai_x=%.1f" % [
            player.global_position.x,
            global_position.x,
        ])

    if _is_segment_three_guide() and not _segment_three_route_locked:
        velocity.x = 0.0
        _apply_gravity(delta)
        move_and_slide()
        _set_state(AmaiState.WAITING)
        _trace_state()
        return

    if _guide_index >= _guide_points.size() - 1:
        if active_guide == &"Segment01Guide" and _segment_one_exit_released:
            _step_segment_one_escort(delta)
            _trace_state()
            return
        if active_guide in [&"Segment03SafeGuide", &"Segment03RiskGuide"] and _segment_three_exit_released:
            _step_segment_three_escort(delta)
            _trace_state()
            return
        velocity.x = 0.0
        _apply_gravity(delta)
        move_and_slide()
        _set_state(AmaiState.WAITING)
        _trace_state()
        return

    if not _leg_active:
        if _is_segment_three_guide() and player.global_position.x - global_position.x < segment_three_follow_distance:
            velocity.x = 0.0
            _apply_gravity(delta)
            move_and_slide()
            _set_state(AmaiState.WAITING)
            _trace_state()
            return
        if not _is_segment_three_guide():
            var allowed_gap := _get_allowed_lead_gap(_guide_index)
            if global_position.x - player.global_position.x > allowed_gap:
                velocity.x = 0.0
                _apply_gravity(delta)
                move_and_slide()
                _set_state(AmaiState.WAITING)
                _trace_state()
                return
        _begin_leg()

    _step_active_leg(delta)
    _trace_state()


func has_guide(guide_name: StringName) -> bool:
    return guide_root.get_node_or_null(NodePath(str(guide_name))) is Node2D


func record_choice(choice: StringName) -> void:
    last_mimicked_choice = choice
    choice_label.text = "阿麦模仿：%s" % str(choice).replace("_", " ")
    match choice:
        &"JUMP":
            _set_guide(&"Segment02JumpGuide")
        &"SLIDE":
            _set_guide(&"Segment02SlideGuide")
        &"WAIT":
            if _segment_three_route_locked:
                return
            _segment_three_route_locked = true
            choice_label.text = "阿麦跟随：下层路线"
            collision_mask = 1
            _set_guide(&"Segment03SafeGuide")
        &"RISK_ROUTE":
            if _segment_three_route_locked:
                return
            _segment_three_route_locked = true
            choice_label.text = "阿麦跟随：花头路线"
            collision_mask = 9
            _set_guide(&"Segment03RiskGuide")


func reset_to_segment(segment_index: int) -> void:
    var guide_name: StringName = &"Segment01Guide"
    if segment_index == 2:
        guide_name = &"Segment02MainGuide"
    elif segment_index == 3:
        guide_name = &"Segment03SafeGuide"
    _jump_count = 0
    _landing_history.clear()
    _max_observed_lead = 0.0
    _max_observed_trail = 0.0
    _max_observed_horizontal_speed = 0.0
    _segment_three_route_locked = false
    _waiting_for_player_recovery = false
    _segment_one_exit_released = false
    _segment_three_exit_released = false
    _fall_recovery_count = 0
    collision_mask = 1
    _set_guide(guide_name, true)


func hold_for_player_recovery() -> void:
    if active_guide != &"Segment01Guide" and not _is_segment_three_guide():
        return
    _waiting_for_player_recovery = true
    if not _guide_points.is_empty() and (_leg_active or not is_on_floor()):
        var recovery_index := clampi(_guide_index, 0, _guide_points.size() - 1)
        var interrupted_position := global_position
        global_position = _guide_points[recovery_index].global_position
        velocity = Vector2.ZERO
        _reset_leg()
        _needs_floor_settle = true
        _set_state(AmaiState.WAITING)
        _trace_event("RECOVERY_RESTORE", "index=%d from=(%.1f,%.1f) to=(%.1f,%.1f)" % [
            recovery_index,
            interrupted_position.x,
            interrupted_position.y,
            global_position.x,
            global_position.y,
        ])
    _trace_event("RECOVERY_HOLD", "index=%d p=(%.1f,%.1f) player_x=%.1f" % [
        _guide_index,
        global_position.x,
        global_position.y,
        player.global_position.x,
    ])


func release_segment_one_exit() -> void:
    if active_guide != &"Segment01Guide" or _segment_one_exit_released:
        return
    _segment_one_exit_released = true
    _waiting_for_player_recovery = false
    _trace_event("SEGMENT01_EXIT_RELEASE", "index=%d p=(%.1f,%.1f) player_x=%.1f" % [
        _guide_index,
        global_position.x,
        global_position.y,
        player.global_position.x,
    ])


func join_waterfall_intro(target_position: Vector2) -> void:
    global_position = target_position
    velocity = Vector2.ZERO
    _reset_leg()
    _waiting_for_player_recovery = false
    _segment_one_exit_released = false
    _segment_three_exit_released = false
    _needs_floor_settle = true
    collision_mask = 1
    visible = true
    set_physics_process(true)
    _set_state(AmaiState.WAITING)
    _trace_event("WATERFALL_JOIN", "p=(%.1f,%.1f) player=(%.1f,%.1f)" % [
        global_position.x,
        global_position.y,
        player.global_position.x,
        player.global_position.y,
    ])


func is_waiting_for_player_recovery() -> bool:
    return _waiting_for_player_recovery


func is_segment_one_exit_released() -> bool:
    return _segment_one_exit_released


func release_segment_three_exit() -> void:
    if active_guide not in [&"Segment03SafeGuide", &"Segment03RiskGuide"] or _segment_three_exit_released:
        return
    if not is_route_complete():
        return
    _segment_three_exit_released = true
    _trace_event("SEGMENT03_EXIT_RELEASE", "guide=%s p=(%.1f,%.1f) player=(%.1f,%.1f)" % [
        str(active_guide),
        global_position.x,
        global_position.y,
        player.global_position.x,
        player.global_position.y,
    ])


func is_segment_three_exit_released() -> bool:
    return _segment_three_exit_released


func is_segment_three_route_locked() -> bool:
    return _segment_three_route_locked


func is_segment_three_exit_ready() -> bool:
    return _segment_three_exit_released and global_position.x >= segment_three_exit_x - arrival_tolerance


func get_guide_index() -> int:
    return _guide_index


func get_jump_count() -> int:
    return _jump_count


func get_landing_history() -> Array[Vector2]:
    return _landing_history.duplicate()


func get_max_observed_lead() -> float:
    return _max_observed_lead


func get_max_observed_trail() -> float:
    return _max_observed_trail


func get_max_observed_horizontal_speed() -> float:
    return _max_observed_horizontal_speed


func get_fall_recovery_count() -> int:
    return _fall_recovery_count


func is_route_complete() -> bool:
    return not _guide_points.is_empty() and _guide_index >= _guide_points.size() - 1 and is_on_floor()


func get_debug_state_text() -> String:
    return "%s i=%d/%d p=(%.1f,%.1f) v=(%.1f,%.1f) floor=%s lead=%.1f trail=%.1f jumps=%d recovery=%s route_locked=%s s1_exit=%s s3_exit=%s" % [
        str(active_guide),
        _guide_index,
        maxi(0, _guide_points.size() - 1),
        global_position.x,
        global_position.y,
        velocity.x,
        velocity.y,
        str(is_on_floor()),
        global_position.x - player.global_position.x,
        player.global_position.x - global_position.x,
        _jump_count,
        str(_waiting_for_player_recovery),
        str(_segment_three_route_locked),
        str(_segment_one_exit_released),
        str(_segment_three_exit_released),
    ]


func _set_guide(guide_name: StringName, warp_to_start: bool = false) -> void:
    var guide := guide_root.get_node_or_null(NodePath(str(guide_name))) as Node2D
    if guide == null:
        return
    if active_guide == guide_name and not _guide_points.is_empty() and not warp_to_start:
        return
    if active_guide != guide_name:
        _landing_history.clear()
    active_guide = guide_name
    _last_recorded_guide = guide_name
    _last_recorded_anchor_index = -1
    _guide_points.clear()
    for child in guide.get_children():
        if child is Marker2D:
            _guide_points.append(child as Marker2D)
    _guide_index = 0
    _reset_leg()
    if _guide_points.is_empty():
        return
    if warp_to_start:
        global_position = _guide_points[0].global_position
        velocity = Vector2.ZERO
        _needs_floor_settle = true
    else:
        _advance_to_nearest_guide_point()
        _needs_floor_settle = not is_on_floor()
    # The selected route starts at this anchor. Recording it immediately keeps
    # route telemetry complete even when the controller switches from SAFE to
    # RISK in the same physics frame.
    _record_landing(_guide_index)
    _trace_event("GUIDE_SET", "guide=%s warp=%s index=%d p=(%.1f,%.1f)" % [
        str(active_guide),
        str(warp_to_start),
        _guide_index,
        global_position.x,
        global_position.y,
    ])


func _advance_to_nearest_guide_point() -> void:
    var nearest_index := 0
    var nearest_distance := INF
    for index in _guide_points.size():
        var candidate_distance := global_position.distance_squared_to(_guide_points[index].global_position)
        if candidate_distance < nearest_distance:
            nearest_distance = candidate_distance
            nearest_index = index
    _guide_index = nearest_index


func _begin_leg() -> void:
    _leg_active = true
    _leg_is_jump = _is_fixed_jump_leg(_guide_index)
    _jump_launched = false
    _airborne_seen = false
    _jump_landed = false
    var target := _guide_points[_guide_index + 1].global_position
    _planned_horizontal_speed = _calculate_ballistic_horizontal_speed(target) if _leg_is_jump else _current_movement_speed()
    _set_state(AmaiState.JUMPING if _leg_is_jump else AmaiState.RUNNING)
    _trace_event("LEG_BEGIN", "guide=%s from=%d to=%d kind=%s target=(%.1f,%.1f) speed=%.1f lead_limit=%.1f" % [
        str(active_guide),
        _guide_index,
        _guide_index + 1,
        "JUMP" if _leg_is_jump else "RUN",
        target.x,
        target.y,
        _planned_horizontal_speed,
        _get_allowed_lead_gap(_guide_index),
    ])


func _step_active_leg(delta: float) -> void:
    var target := _guide_points[_guide_index + 1].global_position
    if _leg_is_jump:
        _step_jump_leg(delta, target)
    else:
        _step_run_leg(delta, target)
    _max_observed_horizontal_speed = maxf(_max_observed_horizontal_speed, absf(velocity.x))
    move_and_slide()
    _after_move(target)


func _step_jump_leg(delta: float, target: Vector2) -> void:
    if not _jump_launched:
        if not is_on_floor():
            velocity.x = 0.0
            _apply_gravity(delta)
            return
        velocity.y = -jump_impulse
        _jump_launched = true
        _jump_count += 1
        fixed_jump_started.emit(active_guide, _guide_index, _guide_index + 1)
        _trace_event("JUMP_START", "guide=%s from=%d to=%d p=(%.1f,%.1f) v=(%.1f,%.1f)" % [
            str(active_guide),
            _guide_index,
            _guide_index + 1,
            global_position.x,
            global_position.y,
            _planned_horizontal_speed,
            velocity.y,
        ])

    if _jump_landed:
        velocity.x = _ground_approach_velocity(target.x)
        _apply_gravity(delta)
        return

    var direction := signf(target.x - global_position.x)
    velocity.x = direction * _planned_horizontal_speed
    if direction == 0.0 or direction * (target.x - global_position.x) <= arrival_tolerance:
        velocity.x = 0.0
    velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _step_run_leg(delta: float, target: Vector2) -> void:
    velocity.x = _ground_approach_velocity(target.x)
    _apply_gravity(delta)


func _step_segment_one_escort(delta: float) -> void:
    var lead := global_position.x - player.global_position.x
    if global_position.x >= segment_one_exit_x or lead >= segment_one_escort_lead:
        velocity.x = 0.0
        _set_state(AmaiState.WAITING)
    else:
        velocity.x = movement_speed
        _set_state(AmaiState.RUNNING)
    _max_observed_horizontal_speed = maxf(_max_observed_horizontal_speed, absf(velocity.x))
    _apply_gravity(delta)
    move_and_slide()


func _step_segment_three_escort(delta: float) -> void:
    var lead := global_position.x - player.global_position.x
    if global_position.x >= segment_three_exit_x:
        velocity.x = 0.0
        _set_state(AmaiState.WAITING)
    elif lead > segment_three_escort_lead + arrival_tolerance:
        velocity.x = 0.0
        _set_state(AmaiState.WAITING)
    else:
        velocity.x = segment_three_follow_speed
        _set_state(AmaiState.RUNNING)
    _max_observed_horizontal_speed = maxf(_max_observed_horizontal_speed, absf(velocity.x))
    _apply_gravity(delta)
    move_and_slide()


func _after_move(target: Vector2) -> void:
    if _leg_is_jump and _jump_launched:
        if not is_on_floor():
            _airborne_seen = true
        elif _airborne_seen and not _jump_landed:
            _jump_landed = true
            velocity.y = 0.0
            _record_landing(_guide_index + 1)

    # A physical landing is the authority for a jump. Requiring the body to
    # crawl to the marker's exact X after landing can pin it against the next
    # platform edge even though the jump itself succeeded.
    var target_tolerance := landing_anchor_tolerance if _leg_is_jump and _jump_landed else arrival_tolerance
    var arrived_x := absf(global_position.x - target.x) <= target_tolerance
    var arrived_y := absf(global_position.y - target.y) <= landing_vertical_tolerance
    var arrived := arrived_x and is_on_floor() and (not _leg_is_jump or (_jump_landed and arrived_y))
    if not arrived:
        return
    if not _leg_is_jump:
        global_position.x = target.x
    velocity.x = 0.0
    if not _leg_is_jump:
        _record_landing(_guide_index + 1)
    _guide_index += 1
    _trace_event("ANCHOR_COMPLETE", "guide=%s index=%d p=(%.1f,%.1f)" % [
        str(active_guide),
        _guide_index,
        global_position.x,
        global_position.y,
    ])
    _reset_leg()


func _record_landing(anchor_index: int) -> void:
    # Log one landing for every route anchor, including adjacent anchors that
    # legitimately resolve to nearly the same physical point.
    if _last_recorded_guide == active_guide and _last_recorded_anchor_index == anchor_index:
        return
    _last_recorded_guide = active_guide
    _last_recorded_anchor_index = anchor_index
    _landing_history.append(global_position)
    fixed_landing_reached.emit(active_guide, anchor_index, global_position)
    _trace_event("LANDING", "guide=%s index=%d p=(%.1f,%.1f)" % [
        str(active_guide),
        anchor_index,
        global_position.x,
        global_position.y,
    ])


func _reset_leg() -> void:
    _leg_active = false
    _leg_is_jump = false
    _jump_launched = false
    _airborne_seen = false
    _jump_landed = false
    _planned_horizontal_speed = 0.0


func _recover_active_guide_fall() -> void:
    if _guide_points.is_empty():
        return
    var fall_position := global_position
    var recovery_index := clampi(_guide_index, 0, _guide_points.size() - 1)
    global_position = _guide_points[recovery_index].global_position
    velocity = Vector2.ZERO
    _reset_leg()
    _needs_floor_settle = true
    _fall_recovery_count += 1
    _set_state(AmaiState.WAITING)
    _trace_event("FALL_RECOVER", "index=%d from=(%.1f,%.1f) to=(%.1f,%.1f) count=%d" % [
        recovery_index,
        fall_position.x,
        fall_position.y,
        global_position.x,
        global_position.y,
        _fall_recovery_count,
    ])


func _ground_approach_velocity(target_x: float) -> float:
    var delta_x := target_x - global_position.x
    if absf(delta_x) <= arrival_tolerance:
        return 0.0
    return signf(delta_x) * _current_movement_speed()


func _apply_gravity(delta: float) -> void:
    if is_on_floor():
        if velocity.y > 0.0:
            velocity.y = 0.0
        return
    velocity.y = minf(velocity.y + gravity * delta, max_fall_speed)


func _calculate_ballistic_horizontal_speed(target: Vector2) -> float:
    var delta_y := target.y - global_position.y
    var discriminant := jump_impulse * jump_impulse + 2.0 * gravity * delta_y
    if discriminant <= 0.0:
        return _current_movement_speed()
    var flight_time := (jump_impulse + sqrt(discriminant)) / gravity
    if flight_time <= 0.01:
        return _current_movement_speed()
    return clampf(absf(target.x - global_position.x) / flight_time, 90.0, _current_movement_speed())


func _is_fixed_jump_leg(leg_index: int) -> bool:
    match active_guide:
        &"Segment01Guide":
            return leg_index in [0, 1, 2, 3]
        &"Segment03SafeGuide":
            # The middle descent is a running drop. The closing lower jump lands
            # left of the narrowed upper-exit collider, preserving both routes.
            return leg_index in [1, 3, 7]
        &"Segment03RiskGuide":
            return leg_index in [1, 3, 5, 7, 9, 11, 13]
        _:
            return false


func _get_allowed_lead_gap(leg_index: int) -> float:
    if lead_gap_pattern.is_empty():
        return 320.0
    return lead_gap_pattern[leg_index % lead_gap_pattern.size()]


func _current_movement_speed() -> float:
    return segment_three_follow_speed if _is_segment_three_guide() else movement_speed


func _is_segment_three_guide() -> bool:
    return active_guide in [&"Segment03SafeGuide", &"Segment03RiskGuide"]


func _set_state(next_state: int) -> void:
    if state == next_state:
        return
    state = next_state
    if state == AmaiState.WAITING:
        waiting_started.emit()
    _trace_event("STATE", "value=%s" % _state_name())


func _state_name() -> String:
    match state:
        AmaiState.RUNNING:
            return "RUNNING"
        AmaiState.JUMPING:
            return "JUMPING"
        _:
            return "WAITING"


func _open_trace() -> void:
    if not trace_enabled:
        return
    var absolute_path := ProjectSettings.globalize_path(trace_path)
    DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
    if FileAccess.file_exists(absolute_path):
        _trace_file = FileAccess.open(absolute_path, FileAccess.READ_WRITE)
        if _trace_file != null:
            _trace_file.seek_end()
    else:
        _trace_file = FileAccess.open(absolute_path, FileAccess.WRITE_READ)
    if _trace_file == null:
        push_error("[AMAI TRACE] failed to open %s error=%s" % [absolute_path, error_string(FileAccess.get_open_error())])
        return
    _trace_event("SESSION_START", "path=%s" % absolute_path)


func _trace_event(kind: String, details: String = "") -> void:
    if not trace_enabled:
        return
    var line := "[AMAI TRACE] ms=%d frame=%d event=%s %s" % [Time.get_ticks_msec(), _trace_frame, kind, details]
    print(line)
    _write_trace_line(line)


func _trace_state() -> void:
    if not trace_enabled:
        return
    var target := Vector2.ZERO
    if not _guide_points.is_empty() and _guide_index < _guide_points.size() - 1:
        target = _guide_points[_guide_index + 1].global_position
    var collision_text := "none"
    if get_slide_collision_count() > 0:
        var collision := get_slide_collision(0)
        if collision != null and collision.get_collider() is Node:
            collision_text = str((collision.get_collider() as Node).get_path())
    var line := "[AMAI STATE] ms=%d frame=%d guide=%s state=%s index=%d/%d leg=%s p=(%.2f,%.2f) v=(%.2f,%.2f) floor=%s hit=%s target=(%.2f,%.2f) player_x=%.2f lead=%.2f lead_limit=%.2f jumps=%d landings=%d" % [
        Time.get_ticks_msec(),
        _trace_frame,
        str(active_guide),
        _state_name(),
        _guide_index,
        maxi(0, _guide_points.size() - 1),
        "JUMP" if _leg_is_jump else ("RUN" if _leg_active else "IDLE"),
        global_position.x,
        global_position.y,
        velocity.x,
        velocity.y,
        str(is_on_floor()),
        collision_text,
        target.x,
        target.y,
        player.global_position.x,
        global_position.x - player.global_position.x,
        _get_allowed_lead_gap(_guide_index),
        _jump_count,
        _landing_history.size(),
    ]
    _write_trace_line(line)


func _write_trace_line(line: String) -> void:
    if _trace_file == null:
        return
    _trace_file.store_line(line)
    _trace_file.flush()
