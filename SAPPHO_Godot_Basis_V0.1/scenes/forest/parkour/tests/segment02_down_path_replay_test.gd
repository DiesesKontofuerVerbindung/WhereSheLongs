extends SceneTree

const PARKOUR_SCENE := "res://scenes/forest/parkour/parkour_prototype.tscn"
const MAX_REPLAY_FRAMES := 1200
const REENTRY_GATE_INDEX := 2

var failures: Array[String] = []
var replay_log: Array[String] = []
var _last_history_size := 0
var _slide_seen: Array[bool] = [false, false, false, false]


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

    replay_log.append("START p=(%.1f, %.1f)" % [player.global_position.x, player.global_position.y])
    Input.action_press(&"move_right")
    var submitted_gate := -1
    var reentry_phase := 0
    var reentry_history_size := 0
    var completed := false

    for frame in MAX_REPLAY_FRAMES:
        var gate_index: int = coordinator.current_gate_index
        if gate_index >= gates.size():
            completed = true
            break
        var gate := gates[gate_index]

        if gate_index != submitted_gate and player.global_position.x >= gate.global_position.x - 250.0:
            await _press_down_one_frame()
            var accepted: bool = coordinator.action_locked or coordinator.get_buffered_action() == 2
            replay_log.append("DOWN gate=%d frame=%d p=(%.1f, %.1f) accepted=%s" % [
                gate_index + 1,
                frame,
                player.global_position.x,
                player.global_position.y,
                accepted,
            ])
            _check(accepted, "Gate %d did not detect the injected DOWN input" % (gate_index + 1))
            submitted_gate = gate_index

        _record_action_and_slide(player, coordinator, runner)

        if gate_index == REENTRY_GATE_INDEX and coordinator.get_player_history().size() == 3:
            if reentry_phase == 0:
                reentry_phase = 1
                reentry_history_size = coordinator.get_player_history().size()
                Input.action_release(&"move_right")
                Input.action_press(&"move_left")
                replay_log.append("REENTRY begin p=(%.1f, %.1f)" % [player.global_position.x, player.global_position.y])
            elif reentry_phase == 1 and player.global_position.x <= gate.global_position.x - 305.0:
                reentry_phase = 2
                Input.action_release(&"move_left")
                Input.action_press(&"move_right")
                replay_log.append("REENTRY reversed p=(%.1f, %.1f) locked=%s" % [player.global_position.x, player.global_position.y, coordinator.action_locked])
                _check(coordinator.action_locked, "Leaving Gate 3 DecisionZone cleared the locked DOWN action")
                _check(coordinator.get_player_history().size() == reentry_history_size, "Gate 3 re-entry duplicated action history")
            elif reentry_phase == 2 and player.global_position.x >= gate.global_position.x - 105.0:
                reentry_phase = 3
                replay_log.append("REENTRY action-line p=(%.1f, %.1f) sliding=%s" % [player.global_position.x, player.global_position.y, runner.is_sliding])
                _check(runner.is_sliding, "Gate 3 did not repeat DOWN after ActionZone re-entry")
                _check(coordinator.get_player_history().size() == reentry_history_size, "Repeated Gate 3 DOWN duplicated action history")

        if frame % 60 == 0:
            _record_sample(frame, player, coordinator, runner)
        await physics_frame

    Input.action_release(&"move_left")
    Input.action_release(&"move_right")
    Input.action_release(&"move_down")

    _check(reentry_phase == 3, "Replay did not complete the Gate 3 backward/forward re-entry")
    _check(completed, "DOWN replay did not pass all four Vine gates")
    _check(coordinator.get_player_history() == [2, 2, 2, 2], "Player history is not four DOWN actions")
    for gate_index in 4:
        _check(_slide_seen[gate_index], "Gate %d accepted DOWN but no physical slide was observed" % (gate_index + 1))

    for line in replay_log:
        print("[S2 DOWN REPLAY] %s" % line)
    scene.queue_free()
    await process_frame
    if failures.is_empty():
        print("[S2 DOWN REPLAY PASS] Four DOWN paths passed; Gate 3 re-entry preserved and repeated the locked slide without duplicating history.")
        quit(0)
        return
    for failure in failures:
        push_error("[S2 DOWN REPLAY FAIL] %s" % failure)
    quit(1)


func _press_down_one_frame() -> void:
    var pressed_event := InputEventKey.new()
    pressed_event.physical_keycode = KEY_S
    pressed_event.keycode = KEY_S
    pressed_event.unicode = 115
    pressed_event.pressed = true
    Input.parse_input_event(pressed_event)
    await physics_frame
    await process_frame
    var released_event := pressed_event.duplicate() as InputEventKey
    released_event.pressed = false
    Input.parse_input_event(released_event)


func _record_action_and_slide(player: CharacterBody2D, coordinator: Node, runner: Node) -> void:
    var history_size: int = coordinator.get_player_history().size()
    if history_size > _last_history_size:
        var gate_index := history_size - 1
        replay_log.append("ACTION gate=%d p=(%.1f, %.1f) sliding=%s floor=%s" % [
            gate_index + 1,
            player.global_position.x,
            player.global_position.y,
            runner.is_sliding,
            player.is_on_floor(),
        ])
        _last_history_size = history_size
    if history_size > 0 and history_size <= _slide_seen.size() and runner.is_sliding:
        _slide_seen[history_size - 1] = true


func _record_sample(frame: int, player: CharacterBody2D, coordinator: Node, runner: Node) -> void:
    var collision_text := "none"
    if player.get_slide_collision_count() > 0:
        var collision := player.get_slide_collision(0)
        if collision != null and collision.get_collider() is Node:
            collision_text = str((collision.get_collider() as Node).get_path())
    replay_log.append("SAMPLE frame=%d gate=%d p=(%.1f, %.1f) v=(%.1f, %.1f) locked=%s sliding=%s hit=%s" % [
        frame,
        coordinator.current_gate_index + 1,
        player.global_position.x,
        player.global_position.y,
        player.velocity.x,
        player.velocity.y,
        coordinator.action_locked,
        runner.is_sliding,
        collision_text,
    ])


func _check(condition: bool, message: String) -> void:
    if not condition:
        failures.append(message)
