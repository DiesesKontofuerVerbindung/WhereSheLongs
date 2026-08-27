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

var previous_player_action = RunnerAction.NONE
var current_gate_index = 0
var action_locked := false

var _awaiting_action := false
var _action_pending := false
var _pending_action = RunnerAction.NONE
var _running := false
var _echo_crossing_gate := false
var _gates: Array[Node2D] = []
var _player_history: Array[int] = []
var _xiaomai_history: Array[int] = []
var _last_echo_anchor_index := -1
var _echo_anchor_hits: Array[Vector2] = []

@onready var player: CharacterBody2D = get_node(player_path)
@onready var xiaomai: CharacterBody2D = get_node(xiaomai_path)
@onready var player_runner: Node = get_node(player_runner_path)
@onready var xiaomai_runner: Node = get_node(xiaomai_runner_path)
@onready var debug_label: Label = get_node_or_null(debug_label_path)


func _ready() -> void:
    process_physics_priority = -10
    _gates = _get_sorted_gates()
    for gate in _gates:
        gate.decision_requested.connect(_on_gate_decision_requested)
        gate.gate_passed.connect(_on_gate_passed)
        if not echo_fixed_route.is_empty():
            gate.allow_fixed_ground_route(xiaomai)
    if not _gates.is_empty():
        _gates[0].allow_first_round_echo_bypass(xiaomai)
    player.add_collision_exception_with(xiaomai)
    xiaomai.add_collision_exception_with(player)
    if start_on_ready:
        call_deferred("begin_run")


func _input(event: InputEvent) -> void:
    if not _awaiting_action or action_locked or _action_pending:
        return
    if event.is_action_pressed(&"jump"):
        submit_action(RunnerAction.UP)
        get_viewport().set_input_as_handled()
    elif event.is_action_pressed(&"move_down") or _is_page_down(event):
        submit_action(RunnerAction.DOWN)
        get_viewport().set_input_as_handled()


func _physics_process(_delta: float) -> void:
    if _running:
        var player_horizontal_input := 1.0 if automatic_forward else Input.get_axis("move_left", "move_right")
        player_runner.set_horizontal_input(player_horizontal_input)
        _settle_echo_on_fixed_route()
        xiaomai_runner.set_horizontal_input(_get_echo_horizontal_input(player_horizontal_input))
    _capture_held_decision_input()
    if _action_pending:
        _commit_pending_action()


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
    _update_debug_label()


func stop_run(restore_player_control: bool = true) -> void:
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
    _echo_crossing_gate = false
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


func debug_enter_gate(gate_index: int) -> void:
    if not _running and not start_on_ready:
        return
    if gate_index != current_gate_index:
        return
    _awaiting_action = true
    action_locked = false
    _action_pending = false
    _pending_action = RunnerAction.NONE
    _update_debug_label()


func debug_submit_action(action: int) -> bool:
    if not submit_action(action):
        return false
    _commit_pending_action()
    return true


func debug_pass_gate(gate_index: int) -> void:
    if gate_index != current_gate_index or not action_locked:
        return
    _finish_gate()


func debug_run_sequence(actions: Array) -> void:
    reset_rounds()
    for gate_index in actions.size():
        debug_enter_gate(gate_index)
        debug_submit_action(int(actions[gate_index]))
        debug_pass_gate(gate_index)


func get_player_history() -> Array[int]:
    return _player_history.duplicate()


func get_xiaomai_history() -> Array[int]:
    return _xiaomai_history.duplicate()


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


func _on_gate_passed(gate_index: int, body: Node2D) -> void:
    if not _running or body != player or gate_index != current_gate_index or not action_locked:
        return
    _finish_gate()


func _commit_pending_action() -> void:
    if not _action_pending or not _awaiting_action or action_locked:
        return
    var current_action: int = _pending_action
    var xiaomai_action: int = previous_player_action
    _action_pending = false
    _pending_action = RunnerAction.NONE

    player_runner.perform_action(current_action)
    _echo_crossing_gate = true
    if xiaomai_action != RunnerAction.NONE:
        xiaomai_runner.perform_action(xiaomai_action)

    _player_history.append(current_action)
    _xiaomai_history.append(xiaomai_action)
    previous_player_action = current_action
    action_locked = true
    gate_action_locked.emit(current_gate_index, current_action, xiaomai_action)
    _update_debug_label()


func _finish_gate() -> void:
    _awaiting_action = false
    action_locked = false
    current_gate_index += 1
    _echo_crossing_gate = false
    _update_debug_label()


func _capture_held_decision_input() -> void:
    if not _awaiting_action or action_locked or _action_pending:
        return
    if Input.is_action_just_pressed(&"jump"):
        submit_action(RunnerAction.UP)
    elif Input.is_action_just_pressed(&"move_down") or Input.is_key_pressed(KEY_PAGEDOWN):
        submit_action(RunnerAction.DOWN)


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
    var player_current: int = RunnerAction.NONE
    var xiaomai_echo: int = previous_player_action
    if not _player_history.is_empty():
        player_current = _player_history[-1]
        xiaomai_echo = _xiaomai_history[-1]
    var decision_text := "READY · Space=UP / S↓PgDn=DOWN" if _awaiting_action and not action_locked else "Move right to the next Gate"
    var echo_text := "CROSSING" if _echo_crossing_gate else "WAITING AT GATE"
    debug_label.text = "Gate: %d\nDecision: %s\nPlayer Current: %s\nAmai Echo: %s (%s)\nPrevious Player: %s\nLocked: %s" % [
        current_gate_index + 1,
        decision_text,
        action_name(player_current),
        action_name(xiaomai_echo),
        echo_text,
        action_name(previous_player_action),
        str(action_locked),
    ]
