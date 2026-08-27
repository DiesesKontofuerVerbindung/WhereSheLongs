extends Node
class_name VineEchoCoordinator

enum RunnerAction {
    NONE,
    UP,
    DOWN,
}

signal gate_action_locked(gate_index: int, player_action: int, xiaomai_action: int)

@export var player_path: NodePath = ^"../Player"
@export var xiaomai_path: NodePath = ^"../Xiaomai"
@export var player_runner_path: NodePath = ^"../Player/RunnerActionController"
@export var xiaomai_runner_path: NodePath = ^"../Xiaomai/RunnerActionController"
@export var debug_label_path: NodePath = ^"../DebugLayer/Panel/DebugText"
@export var start_on_ready := true
@export var automatic_forward := false
@export var echo_start_offset := Vector2(-18.0, 0.0)
@export var echo_waits_at_gates := false
@export var echo_wait_offset := 90.0
@export var echo_fixed_route := PackedVector2Array()
@export var echo_anchor_tolerance := 4.0
@export var echo_ground_snap_tolerance := 20.0
@export var decision_input_buffer_duration := 0.35
@export var runtime_trace_enabled := true
@export_range(1, 60, 1) var runtime_trace_every_physics_frames := 1
@export var runtime_trace_path := "res://../tmp/codex_logs/vine_echo_runtime_live.log"

var previous_player_action = RunnerAction.NONE
var current_gate_index = 0
var action_locked := false

var _awaiting_action := false
var _action_pending := false
var _pending_action = RunnerAction.NONE
var _buffered_action = RunnerAction.NONE
var _buffered_action_remaining := 0.0
var _locked_player_action = RunnerAction.NONE
var _running := false
var _echo_crossing_gate := false
var _player_in_action_zone := false
var _player_crossed_pass_zone := false
var _action_executed := false
var _locked_retry_pending = RunnerAction.NONE
var _gates: Array[Node2D] = []
var _player_history: Array[int] = []
var _xiaomai_history: Array[int] = []
var _last_echo_anchor_index := -1
var _echo_anchor_hits: Array[Vector2] = []
var _trace_file: FileAccess
var _trace_frame := 0

@onready var player: CharacterBody2D = get_node(player_path)
@onready var xiaomai: CharacterBody2D = get_node(xiaomai_path)
@onready var player_runner: Node = get_node(player_runner_path)
@onready var xiaomai_runner: Node = get_node(xiaomai_runner_path)
@onready var debug_label: Label = get_node_or_null(debug_label_path)


func _ready() -> void:
    process_physics_priority = -10
    _open_runtime_trace()
    _gates = _get_sorted_gates()
    for gate in _gates:
        gate.decision_requested.connect(_on_gate_decision_requested)
        gate.action_execution_requested.connect(_on_gate_action_execution_requested)
        gate.gate_passed.connect(_on_gate_passed)
        if not echo_fixed_route.is_empty():
            gate.allow_fixed_ground_route(xiaomai)
    if not _gates.is_empty():
        _gates[0].allow_first_round_echo_bypass(xiaomai)
    player.add_collision_exception_with(xiaomai)
    xiaomai.add_collision_exception_with(player)
    if start_on_ready:
        call_deferred("begin_run")


func _exit_tree() -> void:
    _trace_event("SESSION_END")
    if _trace_file != null:
        _trace_file.close()
        _trace_file = null


func _input(event: InputEvent) -> void:
    if not _running:
        return
    var event_action := _get_event_action(event)
    if event_action == RunnerAction.NONE:
        return
    _trace_event("INPUT", "action=%s key=%s locked=%s executed=%s floor=%s" % [
        action_name(event_action),
        _event_key_text(event),
        str(action_locked),
        str(_action_executed),
        str(player.is_on_floor()),
    ])
    if _handle_player_action_input(event_action):
        get_viewport().set_input_as_handled()
    else:
        _trace_event("INPUT_REJECTED", "reason=gate_state requested=%s locked=%s" % [
            action_name(event_action),
            action_name(_locked_player_action),
        ])


func _physics_process(delta: float) -> void:
    _trace_frame += 1
    if _running:
        var player_horizontal_input := 1.0 if automatic_forward else Input.get_axis("move_left", "move_right")
        player_runner.set_horizontal_input(player_horizontal_input)
        _settle_echo_on_fixed_route()
        xiaomai_runner.set_horizontal_input(_get_echo_horizontal_input(player_horizontal_input))
        _consume_locked_retry_on_landing()
    _tick_decision_input_buffer(delta)
    _capture_held_decision_input()
    if _action_pending:
        _commit_pending_action()
    _update_debug_label()
    _trace_physics_state()


func begin_run() -> void:
    reset_rounds()
    _running = true
    player.use_external_control()
    player.set_interaction_enabled(false)
    player_runner.stop_run()
    xiaomai_runner.stop_run()
    xiaomai.global_position = _get_echo_route_anchor(0, player.global_position + echo_start_offset)
    xiaomai.velocity = Vector2.ZERO
    xiaomai.visible = true
    var initial_input := 1.0 if automatic_forward else 0.0
    player_runner.start_run(initial_input)
    xiaomai_runner.start_run(initial_input)
    _trace_event("RUN_BEGIN", "player=(%.1f, %.1f) amai=(%.1f, %.1f)" % [
        player.global_position.x,
        player.global_position.y,
        xiaomai.global_position.x,
        xiaomai.global_position.y,
    ])
    _update_debug_label()


func stop_run(restore_player_control: bool = true) -> void:
    _trace_event("RUN_STOP", "restore_player_control=%s" % str(restore_player_control))
    _running = false
    player_runner.stop_run()
    xiaomai_runner.stop_run()
    xiaomai.visible = false
    player.stop_external_movement()
    if restore_player_control:
        player.use_normal_control()
        player.set_interaction_enabled(true)


func is_active() -> bool:
    return _running


func debug_set_player_slide(enabled: bool) -> void:
    player_runner.debug_set_slide(enabled)


func reset_rounds() -> void:
    previous_player_action = RunnerAction.NONE
    current_gate_index = 0
    action_locked = false
    _awaiting_action = false
    _action_pending = false
    _pending_action = RunnerAction.NONE
    _buffered_action = RunnerAction.NONE
    _buffered_action_remaining = 0.0
    _locked_player_action = RunnerAction.NONE
    _echo_crossing_gate = false
    _player_in_action_zone = false
    _player_crossed_pass_zone = false
    _action_executed = false
    _locked_retry_pending = RunnerAction.NONE
    _player_history.clear()
    _xiaomai_history.clear()
    _last_echo_anchor_index = -1
    _echo_anchor_hits.clear()
    _update_debug_label()


func submit_action(action: int) -> bool:
    if not _awaiting_action or action_locked or _action_pending:
        return false
    if action != RunnerAction.UP and action != RunnerAction.DOWN:
        return false
    _pending_action = action
    _action_pending = true
    return true


func buffer_action(action: int) -> bool:
    if not _running or action_locked or _action_pending:
        return false
    if action != RunnerAction.UP and action != RunnerAction.DOWN:
        return false
    if _awaiting_action:
        return submit_action(action)
    if _buffered_action != RunnerAction.NONE:
        return false
    _buffered_action = action
    _buffered_action_remaining = decision_input_buffer_duration
    _update_debug_label()
    return true


func debug_buffer_action(action: int) -> bool:
    return buffer_action(action)


func retry_locked_player_action(action: int) -> bool:
    if not _running or not action_locked or not _action_executed:
        return false
    if action != _locked_player_action:
        return false
    if player.is_on_floor():
        player_runner.perform_action(action)
        _locked_retry_pending = RunnerAction.NONE
        _trace_event("RETRY_EXECUTED", "gate=%d action=%s" % [current_gate_index + 1, action_name(action)])
    else:
        _locked_retry_pending = action
        _trace_event("RETRY_LATCHED", "gate=%d action=%s reason=airborne" % [current_gate_index + 1, action_name(action)])
    _update_debug_label()
    return true


func debug_retry_locked_player_action(action: int) -> bool:
    return retry_locked_player_action(action)


func get_locked_retry_pending() -> int:
    return _locked_retry_pending


func debug_input_action(action: int) -> bool:
    return _handle_player_action_input(action)


func _handle_player_action_input(action: int) -> bool:
    if action_locked:
        return retry_locked_player_action(action)
    if _action_pending:
        return false
    if _awaiting_action:
        return buffer_action(action)

    var buffered_for_gate := buffer_action(action)
    player_runner.perform_action(action)
    _trace_event("FREE_ACTION_EXECUTED", "action=%s buffered_for_gate=%s" % [
        action_name(action),
        str(buffered_for_gate),
    ])
    return true


func debug_enter_gate(gate_index: int) -> void:
    if not _running and not start_on_ready:
        return
    if gate_index != current_gate_index:
        return
    if _awaiting_action:
        return
    _awaiting_action = true
    action_locked = false
    _action_pending = false
    _pending_action = RunnerAction.NONE
    _locked_player_action = RunnerAction.NONE
    _player_in_action_zone = false
    _player_crossed_pass_zone = false
    _action_executed = false
    _locked_retry_pending = RunnerAction.NONE
    _trace_event("GATE_ENTER", "gate=%d" % (gate_index + 1))
    _consume_buffered_action()
    _update_debug_label()


func debug_submit_action(action: int) -> bool:
    if not submit_action(action):
        return false
    _commit_pending_action()
    return true


func debug_execute_gate(gate_index: int) -> void:
    if gate_index != current_gate_index:
        return
    _player_in_action_zone = true
    _execute_or_repeat_locked_action()


func debug_pass_gate(gate_index: int) -> void:
    if gate_index != current_gate_index or not action_locked or not _action_executed:
        return
    _finish_gate()


func debug_run_sequence(actions: Array) -> void:
    reset_rounds()
    for gate_index in actions.size():
        debug_enter_gate(gate_index)
        debug_submit_action(int(actions[gate_index]))
        debug_execute_gate(gate_index)
        debug_pass_gate(gate_index)


func get_player_history() -> Array[int]:
    return _player_history.duplicate()


func get_xiaomai_history() -> Array[int]:
    return _xiaomai_history.duplicate()


func get_buffered_action() -> int:
    return _buffered_action


func get_echo_fixed_route() -> PackedVector2Array:
    return echo_fixed_route.duplicate()


func get_echo_anchor_hits() -> Array[Vector2]:
    return _echo_anchor_hits.duplicate()


func action_name(action: int) -> String:
    match action:
        RunnerAction.UP:
            return "UP"
        RunnerAction.DOWN:
            return "DOWN"
        _:
            return "NONE"


func _on_gate_decision_requested(gate_index: int, body: Node2D) -> void:
    if not _running or body != player:
        return
    debug_enter_gate(gate_index)


func _on_gate_action_execution_requested(gate_index: int, body: Node2D) -> void:
    if not _running or body != player or gate_index != current_gate_index:
        return
    _player_in_action_zone = true
    _trace_event("ACTION_ZONE_ENTER", "gate=%d" % (gate_index + 1))
    _execute_or_repeat_locked_action()


func _on_gate_passed(gate_index: int, body: Node2D) -> void:
    if not _running or body != player:
        return
    if gate_index != current_gate_index:
        _trace_event("PASS_ZONE_IGNORED", "gate=%d current=%d" % [gate_index + 1, current_gate_index + 1])
        return
    _player_crossed_pass_zone = true
    _trace_event("PASS_ZONE_ENTER", "gate=%d" % (gate_index + 1))
    if not action_locked or not _action_executed:
        _trace_event("PASS_WAITING_FOR_ACTION", "gate=%d locked=%s executed=%s" % [
            gate_index + 1,
            str(action_locked),
            str(_action_executed),
        ])
        return
    _finish_gate()


func _commit_pending_action() -> void:
    if not _action_pending or not _awaiting_action or action_locked:
        return
    var current_action: int = _pending_action
    _action_pending = false
    _pending_action = RunnerAction.NONE
    _locked_player_action = current_action
    action_locked = true
    _trace_event("ACTION_LOCKED", "gate=%d action=%s" % [current_gate_index + 1, action_name(current_action)])
    if _player_in_action_zone:
        _execute_or_repeat_locked_action()
    _update_debug_label()


func _execute_or_repeat_locked_action() -> void:
    if not action_locked or _locked_player_action == RunnerAction.NONE:
        return
    if _action_executed:
        player_runner.perform_action(_locked_player_action)
        _update_debug_label()
        return
    _execute_locked_action()


func _execute_locked_action() -> void:
    if not action_locked or _action_executed or _locked_player_action == RunnerAction.NONE:
        return
    var current_action: int = _locked_player_action
    var xiaomai_action: int = previous_player_action
    player_runner.perform_action(current_action)
    _echo_crossing_gate = true
    if xiaomai_action != RunnerAction.NONE:
        xiaomai_runner.perform_action(xiaomai_action)
    _player_history.append(current_action)
    _xiaomai_history.append(xiaomai_action)
    previous_player_action = current_action
    _action_executed = true
    _trace_event("ACTION_EXECUTED", "gate=%d player=%s amai=%s history=%s/%s" % [
        current_gate_index + 1,
        action_name(current_action),
        action_name(xiaomai_action),
        str(_player_history),
        str(_xiaomai_history),
    ])
    gate_action_locked.emit(current_gate_index, current_action, xiaomai_action)
    _update_debug_label()
    if _player_crossed_pass_zone:
        _trace_event("PASS_RECOVERED_AFTER_ACTION", "gate=%d" % (current_gate_index + 1))
        _finish_gate()


func _finish_gate() -> void:
    _trace_event("GATE_FINISH", "gate=%d" % (current_gate_index + 1))
    _awaiting_action = false
    action_locked = false
    current_gate_index += 1
    _echo_crossing_gate = false
    _locked_player_action = RunnerAction.NONE
    _player_in_action_zone = false
    _player_crossed_pass_zone = false
    _action_executed = false
    _locked_retry_pending = RunnerAction.NONE
    _update_debug_label()


func _consume_locked_retry_on_landing() -> void:
    if _locked_retry_pending == RunnerAction.NONE:
        return
    if not action_locked or not _action_executed:
        _trace_event("RETRY_CANCELLED", "reason=gate_state_changed action=%s" % action_name(_locked_retry_pending))
        _locked_retry_pending = RunnerAction.NONE
        return
    if not player.is_on_floor():
        return
    var retry_action: int = _locked_retry_pending
    _locked_retry_pending = RunnerAction.NONE
    player_runner.perform_action(retry_action)
    _trace_event("RETRY_EXECUTED", "gate=%d action=%s source=landing_latch" % [
        current_gate_index + 1,
        action_name(retry_action),
    ])


func _capture_held_decision_input() -> void:
    if not _awaiting_action or action_locked or _action_pending:
        return
    if Input.is_action_just_pressed(&"jump"):
        submit_action(RunnerAction.UP)
    elif Input.is_action_just_pressed(&"move_down") or Input.is_key_pressed(KEY_PAGEDOWN):
        submit_action(RunnerAction.DOWN)


func _tick_decision_input_buffer(delta: float) -> void:
    if _buffered_action == RunnerAction.NONE:
        return
    _buffered_action_remaining = maxf(0.0, _buffered_action_remaining - delta)
    if is_zero_approx(_buffered_action_remaining):
        _buffered_action = RunnerAction.NONE
        _update_debug_label()
        return
    if _awaiting_action:
        _consume_buffered_action()


func _consume_buffered_action() -> void:
    if _buffered_action == RunnerAction.NONE or not _awaiting_action:
        return
    var action: int = _buffered_action
    _buffered_action = RunnerAction.NONE
    _buffered_action_remaining = 0.0
    submit_action(action)


func _get_echo_horizontal_input(player_horizontal_input: float) -> float:
    if automatic_forward:
        return 1.0
    if not echo_waits_at_gates:
        return player_horizontal_input
    if current_gate_index >= _gates.size() and echo_fixed_route.is_empty():
        return 0.0
    var target := _get_current_echo_target()
    if xiaomai.global_position.x < target.x - echo_anchor_tolerance:
        return 1.0
    if xiaomai.global_position.x > target.x + echo_anchor_tolerance:
        return -1.0
    return 0.0


func _get_current_echo_target_index() -> int:
    if echo_fixed_route.is_empty():
        return -1
    var target_index: int = current_gate_index + 1
    if _echo_crossing_gate:
        target_index += 1
    return clampi(target_index, 0, echo_fixed_route.size() - 1)


func _get_current_echo_target() -> Vector2:
    var fixed_index := _get_current_echo_target_index()
    if fixed_index >= 0:
        return echo_fixed_route[fixed_index]
    if current_gate_index >= _gates.size():
        return xiaomai.global_position
    return Vector2(_gates[current_gate_index].global_position.x - echo_wait_offset, xiaomai.global_position.y)


func _get_echo_route_anchor(index: int, fallback: Vector2) -> Vector2:
    if index >= 0 and index < echo_fixed_route.size():
        return echo_fixed_route[index]
    return fallback


func _settle_echo_on_fixed_route() -> void:
    var target_index := _get_current_echo_target_index()
    if target_index < 0:
        return
    var target := echo_fixed_route[target_index]
    if absf(xiaomai.global_position.x - target.x) <= echo_anchor_tolerance:
        xiaomai.global_position.x = target.x
    if not xiaomai.is_on_floor():
        return
    if absf(xiaomai.global_position.y - target.y) <= echo_ground_snap_tolerance:
        xiaomai.global_position.y = target.y
    if xiaomai.global_position.distance_to(target) <= echo_ground_snap_tolerance and _last_echo_anchor_index != target_index:
        _last_echo_anchor_index = target_index
        _echo_anchor_hits.append(xiaomai.global_position)


func _is_page_down(event: InputEvent) -> bool:
    var key_event := event as InputEventKey
    return key_event != null and key_event.pressed and key_event.keycode == KEY_PAGEDOWN


func _get_event_action(event: InputEvent) -> int:
    var key_event := event as InputEventKey
    if key_event != null and key_event.echo:
        return RunnerAction.NONE
    if event.is_action_pressed(&"jump"):
        return RunnerAction.UP
    if event.is_action_pressed(&"move_down") or _is_page_down(event):
        return RunnerAction.DOWN
    return RunnerAction.NONE


func _event_key_text(event: InputEvent) -> String:
    var key_event := event as InputEventKey
    if key_event == null:
        return event.as_text()
    return OS.get_keycode_string(key_event.keycode)


func _open_runtime_trace() -> void:
    if not runtime_trace_enabled:
        return
    var absolute_path := ProjectSettings.globalize_path(runtime_trace_path)
    DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
    if FileAccess.file_exists(absolute_path):
        _trace_file = FileAccess.open(absolute_path, FileAccess.READ_WRITE)
        if _trace_file != null:
            _trace_file.seek_end()
    else:
        _trace_file = FileAccess.open(absolute_path, FileAccess.WRITE_READ)
    if _trace_file == null:
        push_error("[VINE TRACE] failed to open %s error=%s" % [absolute_path, error_string(FileAccess.get_open_error())])
        return
    _trace_event("SESSION_START", "path=%s" % absolute_path)


func _trace_event(kind: String, details: String = "") -> void:
    if not runtime_trace_enabled:
        return
    var line := "[VINE TRACE] ms=%d frame=%d event=%s %s" % [Time.get_ticks_msec(), _trace_frame, kind, details]
    print(line)
    _write_trace_line(line)


func _trace_physics_state() -> void:
    if not runtime_trace_enabled or _trace_frame % runtime_trace_every_physics_frames != 0:
        return
    var collision_text := "none"
    if player.get_slide_collision_count() > 0:
        var collision := player.get_slide_collision(0)
        if collision != null and collision.get_collider() is Node:
            collision_text = str((collision.get_collider() as Node).get_path())
    var line := "[VINE STATE] ms=%d frame=%d gate=%d p=(%.2f,%.2f) v=(%.2f,%.2f) floor=%s hit=%s input(L=%s R=%s U=%s D=%s) awaiting=%s locked=%s executed=%s in_action=%s crossed_pass=%s pending=%s locked_action=%s retry_pending=%s buffer=%s/%.3f runner_queue=%s sliding=%s history=%s/%s" % [
        Time.get_ticks_msec(),
        _trace_frame,
        current_gate_index + 1,
        player.global_position.x,
        player.global_position.y,
        player.velocity.x,
        player.velocity.y,
        str(player.is_on_floor()),
        collision_text,
        str(Input.is_action_pressed(&"move_left")),
        str(Input.is_action_pressed(&"move_right")),
        str(Input.is_action_pressed(&"jump")),
        str(Input.is_action_pressed(&"move_down")),
        str(_awaiting_action),
        str(action_locked),
        str(_action_executed),
        str(_player_in_action_zone),
        str(_player_crossed_pass_zone),
        action_name(_pending_action),
        action_name(_locked_player_action),
        action_name(_locked_retry_pending),
        action_name(_buffered_action),
        _buffered_action_remaining,
        action_name(player_runner.get_queued_ground_action()),
        str(player_runner.is_sliding),
        str(_player_history),
        str(_xiaomai_history),
    ]
    _write_trace_line(line)


func _write_trace_line(line: String) -> void:
    if _trace_file == null:
        return
    _trace_file.store_line(line)
    _trace_file.flush()


func _get_sorted_gates() -> Array[Node2D]:
    var result: Array[Node2D] = []
    for candidate in get_tree().get_nodes_in_group("vine_decision_gate"):
        if candidate is Node2D:
            result.append(candidate as Node2D)
    result.sort_custom(func(left: Node2D, right: Node2D) -> bool: return left.get("gate_index") < right.get("gate_index"))
    return result


func _update_debug_label() -> void:
    if debug_label == null:
        return
    var player_current: int = _locked_player_action
    var xiaomai_echo: int = previous_player_action
    if _action_executed and not _player_history.is_empty():
        player_current = _player_history[-1]
        xiaomai_echo = _xiaomai_history[-1]
    elif player_current == RunnerAction.NONE and not _player_history.is_empty():
        player_current = _player_history[-1]
        xiaomai_echo = _xiaomai_history[-1]
    var decision_text := "READY · Space=UP / S↓PgDn=DOWN" if _awaiting_action and not action_locked else "Move right to the next Gate"
    if _buffered_action != RunnerAction.NONE:
        decision_text = "BUFFERED %s · %.2fs" % [action_name(_buffered_action), _buffered_action_remaining]
    elif action_locked and not _action_executed:
        decision_text = "LOCKED %s · Move to action line" % action_name(_locked_player_action)
    elif action_locked:
        decision_text = "LOCKED %s · Same key retries / move right" % action_name(_locked_player_action)
    var echo_text := "CROSSING" if _echo_crossing_gate else "WAITING AT GATE"
    var collision_text := "none"
    if player.get_slide_collision_count() > 0:
        var collision := player.get_slide_collision(0)
        if collision != null and collision.get_collider() is Node:
            collision_text = str((collision.get_collider() as Node).name)
    debug_label.text = "Gate: %d\nDecision: %s\nPlayer Current: %s\nAmai Echo: %s (%s)\nPrevious Player: %s\nLocked: %s\nP: (%.1f, %.1f) V: (%.1f, %.1f)\nFloor: %s  Hit: %s\nAwait/Exec/InAction/Passed: %s/%s/%s/%s\nRetry Pending: %s  Runner Queue: %s\nInput L/R/U/D: %s/%s/%s/%s\nTrace: %s" % [
        current_gate_index + 1,
        decision_text,
        action_name(player_current),
        action_name(xiaomai_echo),
        echo_text,
        action_name(previous_player_action),
        str(action_locked),
        player.global_position.x,
        player.global_position.y,
        player.velocity.x,
        player.velocity.y,
        str(player.is_on_floor()),
        collision_text,
        str(_awaiting_action),
        str(_action_executed),
        str(_player_in_action_zone),
        str(_player_crossed_pass_zone),
        action_name(_locked_retry_pending),
        action_name(player_runner.get_queued_ground_action()),
        str(Input.is_action_pressed(&"move_left")),
        str(Input.is_action_pressed(&"move_right")),
        str(Input.is_action_pressed(&"jump")),
        str(Input.is_action_pressed(&"move_down")),
        runtime_trace_path,
    ]
