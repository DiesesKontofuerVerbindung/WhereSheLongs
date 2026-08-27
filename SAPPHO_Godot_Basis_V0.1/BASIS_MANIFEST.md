# Basis V0.1 Manifest

Protected shared foundation:

- `project.godot`
- `shared/player/player.tscn`
- `shared/player/player.gd`
- `shared/interaction/interactable.gd`
- `shared/interaction/scene_portal.gd`
- `shared/dialogue/dialogue_ui.tscn`
- `shared/dialogue/dialogue_ui.gd`
- `shared/game_state/game_state.gd`
- `shared/scene_manager/scene_manager.gd`
- `tests/smoke_test.gd`

Parallel owner entry points:

- Forest: `scenes/forest/forest.tscn`
- Wedding: `scenes/wedding/wedding.tscn`

Scene-owned tests:

- Forest: `scenes/forest/tests/**`
- Wedding: `scenes/wedding/tests/**`

Integration playground:

- `scenes/test_room/test_room.tscn`

V0.1 shared interface additions:

- Player `ControlMode`: `NORMAL`, `LOCKED`, `EXTERNAL`
- Player external movement hand-off methods
- Player interaction enable/disable method
- global InputMap action `jump` (Space; physics remains scene-owned)
- stronger smoke test: scenes enter SceneTree before validation/free
