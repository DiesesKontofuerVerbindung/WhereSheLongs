extends Node

## Lightweight signal hub. Maps, minigames, and UI emit here; systems listen.

signal trigger_fired(trigger_id: String, payload: Dictionary)
signal cg_requested(cg_id: String, payload: Dictionary)
signal cg_finished(cg_id: String)
signal minigame_requested(minigame_id: String, payload: Dictionary)
signal minigame_finished(minigame_id: String, result: Dictionary)
signal game_over(reason: String, payload: Dictionary)
signal game_over_retry
signal player_input_requested(prompt: String, callback_key: String)
signal player_input_received(text: String, callback_key: String)
signal map_event(event_id: String, payload: Dictionary)
signal affection_changed(value: int)
