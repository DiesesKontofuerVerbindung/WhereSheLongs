# SAPPHO — Godot Basis V0.1

A minimal shared foundation for two programmers building separate scenes in the same Godot repository.

## Target

- Godot: **4.7.x** (prepared against 4.7.2 stable)
- Renderer: GL Compatibility
- Main scene: `scenes/test_room/test_room.tscn`

## What is already shared

- `shared/player/` — one shared Player implementation with NORMAL / LOCKED / EXTERNAL control hand-off
- `shared/interaction/` — common `interact()` / `look()` contract
- `shared/dialogue/` — minimal global dialogue layer
- `shared/game_state/` — cross-scene flags
- `shared/scene_manager/` — scene transitions
- `project.godot` — common InputMap + Autoload configuration

## Ownership

- Forest programmer: `scenes/forest/**`, `assets/forest/**`
- Wedding programmer: `scenes/wedding/**`, `assets/wedding/**`
- Shared/protected: `shared/**`, `project.godot`, `AGENTS.md`, `skills.md`, `ARCHITECTURE.md`, root `tests/**`

Scene-owned tests belong under each scene directory, e.g. `scenes/forest/tests/**`.

Do **not** create a second Player, GameState, SceneManager, Dialogue system, or competing InputMap inside a scene.

## Controls

- Move: `WASD` or arrow keys
- Interact: `E`
- Look / inspect: `F`
- Jump action: `Space` (scene-owned gameplay decides its behavior)
- Pause hook: `Esc`

## First run

1. Import this folder (or the ZIP) in Godot Project Manager.
2. Open with Godot 4.7.x.
3. Run the project (`F6/F5` as appropriate).
4. In TestRoom, walk near the center object and use `E` / `F`.
5. Use the Forest/Wedding portals to verify both scenes can reuse the shared Player.

## Smoke test

If the Godot executable is available on `PATH`:

```bash
godot --headless --path . --script res://tests/smoke_test.gd
```

V0.1 smoke testing adds scenes to the SceneTree for at least one frame before freeing them, so `_ready()` / `@onready` integration is exercised instead of testing only `instantiate()`.

On Windows, use the actual Godot executable path if `godot` is not registered on `PATH`.
