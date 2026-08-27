# Changes in Basis V0.1

This is a minimal stabilization pass over Basis V0. No scene gameplay was implemented.

## Shared Player hand-off

Added three control modes without creating scene-specific Players:

- `NORMAL` — normal shared movement/interact input
- `LOCKED` — frozen for cutscenes/dialogue gates
- `EXTERNAL` — scene-owned gameplay supplies movement through `set_external_velocity(...)`

Preferred public helpers:

```gdscript
player.use_normal_control()
player.lock_control()
player.use_external_control()
player.set_external_velocity(desired_velocity)
player.stop_external_movement()
player.set_interaction_enabled(false)
```

## InputMap

Added global `jump` action on Space. Shared Player does not implement jump physics; scene-owned gameplay decides what the action means.

## Forest contract correction

Removed the outdated plan for a standalone waterfall-descent minigame.

Current split:

- Parkour = gameplay
- Waterfall = short scripted surreal/worldbuilding transition
- Stone jumping = gameplay
- Drowning = narrative transition, not level reload

## Tests

Root smoke test now adds each scene to the SceneTree and waits a frame before freeing it, instead of stopping at `instantiate()`.

Scene regression tests are explicitly allowed under:

- `scenes/forest/tests/**`
- `scenes/wedding/tests/**`

Root `tests/**` remains protected shared infrastructure.
