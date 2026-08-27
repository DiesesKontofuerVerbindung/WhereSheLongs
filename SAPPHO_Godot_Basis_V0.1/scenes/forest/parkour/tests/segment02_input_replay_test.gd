extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const MAX_REPLAY_FRAMES := 1200
const MIDDLE_GATE_INDEX := 2
const AD_PHASE_FRAMES := 6
const AD_PHASE_COUNT := 8

var failures: Array[String] = []
var replay_log: Array[String] = []
var _last_history_size := 0
var _minimum_velocity_after_action: Dictionary = {}


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    var packed := load(PARKOUR_SCENE) as PackedScene
    _check(packed != null, "Parkour Prototype failed to load")
    if packed == null:
        quit(1)
        return

    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await physics_frame
    await scene.debug_jump_to_segment(2)
    await physics_frame

    var player: CharacterBody2D = scene.get_node("Player")
    var coordinator = scene.get_node("VineEchoCoordinator")
    var runner = scene.get_node("Player/RunnerActionController")
    var gates: Array[Node2D] = []
    for index in 4:
        gates.append(scene.get_node("Gameplay/Segment02_Vines/Gate%02d" % (index + 1)))

    replay_log.append("START p=(%.1f, %.1f) floor=%s" % [player.global_position.x, player.global_position.y, player.is_on_floor()])
    Input.action_press(&"move_right")

    var submitted_gate := -1
    var middle_probe_done := false
    var completed := false
    for frame in MAX_REPLAY_FRAMES:
        var gate_index: int = coordinator.current_gate_index
        if gate_index >= gates.size():
            completed = true
            break

        var gate := gates[gate_index]
        if gate_index == MIDDLE_GATE_INDEX and not middle_probe_done and player.global_position.x >= gate.global_position.x - 250.0:
            Input.action_release(&"move_right")
            await _run_middle_ad_space_probe(player, coordinator, frame)
            Input.action_press(&"move_right")
            middle_probe_done = true
            submitted_gate = gate_index

        if gate_index != submitted_gate and player.global_position.x >= gate.global_position.x - 250.0:
            await _press_space_one_frame()
            var accepted: bool = coordinator.action_locked or coordinator.get_buffered_action() == 1
            replay_log.append("SPACE gate=%d frame=%d p=(%.1f, %.1f) floor=%s accepted=%s" % [
                gate_index + 1,
                frame,
                player.global_position.x,
                player.global_position.y,
                player.is_on_floor(),
                accepted,
            ])
            _check(accepted, "Gate %d did not lock the injected Space input" % (gate_index + 1))
            submitted_gate = gate_index

        await physics_frame
        _record_action_response(player, coordinator)
        if frame % 60 == 0:
            _record_frame_sample(frame, player, coordinator)

    Input.action_release(&"move_left")
    Input.action_release(&"move_right")
    Input.action_release(&"jump")

    _check(middle_probe_done, "Replay never reached the Gate 3 middle probe")
    _check(completed, "Replay did not pass all four Vine gates")
    _check(coordinator.get_player_history() == [1, 1, 1, 1], "Player action history is not four accepted Space/UP actions")
    for gate_index in 4:
        var minimum_velocity: float = float(_minimum_velocity_after_action.get(gate_index, 0.0))
        _check(minimum_velocity < -100.0, "Gate %d accepted Space but produced no upward velocity" % (gate_index + 1))

    for line in replay_log:
        print("[S2 INPUT REPLAY] %s" % line)

    scene.queue_free()
    await process_frame
    if failures.is_empty():
        print("[S2 INPUT REPLAY PASS] ADADADAD + Space was detected at Gate 3 and all four Space inputs produced physical jumps.")
        quit(0)
        return
    for failure in failures:
        push_error("[S2 INPUT REPLAY FAIL] %s" % failure)
    quit(1)


func _run_middle_ad_space_probe(player: CharacterBody2D, coordinator: Node, start_frame: int) -> void:
    var start_x := player.global_position.x
    var history_before: int = coordinator.get_player_history().size()
    var space_detected := false
    for phase in AD_PHASE_COUNT:
        var moving_right := phase % 2 == 0
        Input.action_release(&"move_left" if moving_right else &"move_right")
        Input.action_press(&"move_right" if moving_right else &"move_left")
        await _press_space_one_frame()
        space_detected = space_detected or coordinator.action_locked or coordinator.get_buffered_action() == 1
        replay_log.append("MIDDLE %s+SPACE frame=%d p=(%.1f, %.1f) vy=%.1f floor=%s locked=%s" % [
            "D" if moving_right else "A",
            start_frame + phase * AD_PHASE_FRAMES,
            player.global_position.x,
            player.global_position.y,
            player.velocity.y,
            player.is_on_floor(),
            coordinator.action_locked,
        ])
        for _subframe in range(AD_PHASE_FRAMES - 1):
            await physics_frame
            _record_action_response(player, coordinator)
    Input.action_release(&"move_left")
    Input.action_release(&"move_right")
    _check(space_detected, "Gate 3 ADADADAD probe sent Space but the coordinator never detected it")
    _check(absf(player.global_position.x - start_x) < 80.0, "ADADADAD probe drifted out of the Gate 3 decision area")
    _check(coordinator.get_player_history().size() >= history_before, "Gate 3 probe corrupted action history")


func _record_frame_sample(frame: int, player: CharacterBody2D, coordinator: Node) -> void:
    var collision_text := "none"
    if player.get_slide_collision_count() > 0:
        var collision := player.get_slide_collision(0)
        if collision != null and collision.get_collider() is Node:
            collision_text = str((collision.get_collider() as Node).get_path())
    replay_log.append("SAMPLE frame=%d gate=%d p=(%.1f, %.1f) v=(%.1f, %.1f) floor=%s locked=%s hit=%s" % [
        frame,
        coordinator.current_gate_index + 1,
        player.global_position.x,
        player.global_position.y,
        player.velocity.x,
        player.velocity.y,
        player.is_on_floor(),
        coordinator.action_locked,
        collision_text,
    ])


func _press_space_one_frame() -> void:
    var pressed_event := InputEventKey.new()
    pressed_event.physical_keycode = KEY_SPACE
    pressed_event.keycode = KEY_SPACE
    pressed_event.unicode = 32
    pressed_event.pressed = true
    Input.parse_input_event(pressed_event)
    await physics_frame
    await process_frame
    var released_event := pressed_event.duplicate() as InputEventKey
    released_event.pressed = false
    Input.parse_input_event(released_event)


func _record_action_response(player: CharacterBody2D, coordinator: Node) -> void:
    var history_size: int = coordinator.get_player_history().size()
    if history_size > _last_history_size:
        var gate_index := history_size - 1
        _minimum_velocity_after_action[gate_index] = player.velocity.y
        replay_log.append("ACTION gate=%d p=(%.1f, %.1f) vy=%.1f floor=%s" % [
            gate_index + 1,
            player.global_position.x,
            player.global_position.y,
            player.velocity.y,
            player.is_on_floor(),
        ])
        _last_history_size = history_size
    elif history_size > 0:
        var active_gate := history_size - 1
        var previous_minimum: float = float(_minimum_velocity_after_action.get(active_gate, player.velocity.y))
        _minimum_velocity_after_action[active_gate] = minf(previous_minimum, player.velocity.y)


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
