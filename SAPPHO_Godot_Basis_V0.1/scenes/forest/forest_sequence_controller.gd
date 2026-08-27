extends Node
class_name ForestSequenceController

enum ForestState {
    ENTER_FOREST,
    LIGHT_GUIDE,
    MEET_AMAI,
    DECIDE_FOLLOW,
    FOLLOW_AMAI,
    FORK,
    PARKOUR,
    WATERFALL_INTRO,
    WATERFALL_JUMP,
    HEART_INTERACTION,
    STREAM_WALK,
    LAKE_INTRO,
    STONE_JUMP,
    DROWNING,
    GIRL_RESCUE,
    LAKE_DIALOGUE,
    WORLD_COLLAPSE,
    FOREST_END,
}

signal state_changed(previous_state: int, current_state: int)
signal trigger_consumed(trigger_id: StringName)

const STATE_NAMES := [
    "ENTER_FOREST",
    "LIGHT_GUIDE",
    "MEET_AMAI",
    "DECIDE_FOLLOW",
    "FOLLOW_AMAI",
    "FORK",
    "PARKOUR",
    "WATERFALL_INTRO",
    "WATERFALL_JUMP",
    "HEART_INTERACTION",
    "STREAM_WALK",
    "LAKE_INTRO",
    "STONE_JUMP",
    "DROWNING",
    "GIRL_RESCUE",
    "LAKE_DIALOGUE",
    "WORLD_COLLAPSE",
    "FOREST_END",
]

const LOCKED_STATES := [
    ForestState.MEET_AMAI,
    ForestState.DECIDE_FOLLOW,
    ForestState.WATERFALL_INTRO,
    ForestState.WATERFALL_JUMP,
    ForestState.HEART_INTERACTION,
    ForestState.LAKE_INTRO,
    ForestState.GIRL_RESCUE,
    ForestState.LAKE_DIALOGUE,
    ForestState.WORLD_COLLAPSE,
    ForestState.FOREST_END,
]

const EXTERNAL_STATES := [
    ForestState.PARKOUR,
    ForestState.STONE_JUMP,
    ForestState.DROWNING,
]

@export var player_path: NodePath = ^"../Player"

var current_state: int = ForestState.ENTER_FOREST
var current_trigger: StringName = &"sequence_start"
var _consumed_triggers: Dictionary = {}

@onready var player = get_node(player_path)


func _ready() -> void:
    _apply_player_control()


func advance() -> bool:
    if current_state == ForestState.FOREST_END:
        return false
    return transition_to(current_state + 1, &"debug_next")


func transition_to(next_state: int, source: StringName = &"sequence") -> bool:
    if next_state < 0 or next_state >= STATE_NAMES.size() or next_state == current_state:
        return false

    var previous_state := current_state
    current_state = next_state
    current_trigger = source
    _apply_player_control()
    state_changed.emit(previous_state, current_state)
    return true


func trigger_once(trigger_id: StringName, next_state: int) -> bool:
    if trigger_id == &"" or _consumed_triggers.has(trigger_id):
        return false
    if next_state < 0 or next_state >= STATE_NAMES.size():
        return false

    _consumed_triggers[trigger_id] = true
    trigger_consumed.emit(trigger_id)
    return transition_to(next_state, trigger_id)


func request_transition(trigger_id: StringName, expected_state: int, next_state: int) -> bool:
    if current_state != expected_state:
        return false
    return trigger_once(trigger_id, next_state)


func debug_jump(next_state: int) -> bool:
    return transition_to(next_state, &"debug_jump")


func restart_sequence() -> void:
    var previous_state := current_state
    _consumed_triggers.clear()
    current_state = ForestState.ENTER_FOREST
    current_trigger = &"debug_restart"
    _apply_player_control()
    state_changed.emit(previous_state, current_state)


func get_state_name(state: int = current_state) -> String:
    if state < 0 or state >= STATE_NAMES.size():
        return "UNKNOWN"
    return STATE_NAMES[state]


func get_state_count() -> int:
    return STATE_NAMES.size()


func is_trigger_consumed(trigger_id: StringName) -> bool:
    return _consumed_triggers.has(trigger_id)


func is_player_movement_enabled() -> bool:
    return current_state not in LOCKED_STATES


func _apply_player_control() -> void:
    if current_state in EXTERNAL_STATES:
        player.use_external_control()
        player.set_interaction_enabled(false)
    elif current_state in LOCKED_STATES:
        player.lock_control()
        player.set_interaction_enabled(false)
    else:
        player.use_normal_control()
        player.set_interaction_enabled(true)
