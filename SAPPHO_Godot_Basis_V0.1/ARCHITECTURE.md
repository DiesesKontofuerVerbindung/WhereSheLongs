# Basis V0.1 Architecture

## Goal

Forest and Wedding are parallel scene modules. Neither is the “base” of the other.

```text
                 shared/
        ┌──────────┼──────────┐
        │          │          │
      Player    GameState   Dialogue
        │          │          │
        ├──────────┴──────────┤
        │                     │
  scenes/forest/       scenes/wedding/
      (owner A)             (owner B)
```

## Why this exists

The narrative already implies several systems that may appear across scenes: player movement, observation/interaction, dialogue, persistent choices/state, and scene transitions. Those are shared.

Forest-specific sequences such as running/parkour, the scripted surreal waterfall transition, stone jumping, drowning/oxygen, firefly guidance, heart-light effects, and dream collapse remain local until reuse is proven.

## Shared public surface

### Player

`res://shared/player/player.tscn`

- normal 2D movement
- facing direction
- interaction detector
- `interact` / `look` dispatch
- scene hand-off through `ControlMode`

Control modes:

```text
NORMAL   shared Player reads normal movement/interact input
LOCKED   Player is frozen for dialogue/cutscene/sequence gates
EXTERNAL scene-owned controller supplies movement during local gameplay
```

Public hand-off methods:

```gdscript
player.use_normal_control()
player.lock_control()
player.use_external_control()
player.set_external_velocity(desired_velocity)
player.stop_external_movement()
player.set_interaction_enabled(true_or_false)
```

`jump` is a global InputMap action, but jump physics/gameplay are **not** implemented by Shared Player. Forest owns its parkour/stone-jump interpretation of that action.

### SharedInteractable

`res://shared/interaction/interactable.gd`

- `interact(actor)`
- `look(actor)`

### GameState

Autoload name: `GameState`

- `set_flag(key, value)`
- `get_flag(key, default_value)`
- `has_flag(key)`
- `erase_flag(key)`
- `clear_flags()`

### SceneManager

Autoload name: `SceneManager`

- `change_scene(scene_path)`

### Dialogue

Autoload name: `Dialogue`

- `show_line(speaker, text)`
- `show_choices(speaker, text, choices)`
- signal `choice_selected(index, value)`

## Integration rule

A scene may depend on Shared.
Shared must not depend on Forest or Wedding.
Forest must not depend on Wedding internals.
Wedding must not depend on Forest internals.

Root `tests/**` validates shared contracts and is protected. Scene-owned regression tests should be placed under `scenes/forest/tests/**` or `scenes/wedding/tests/**`.
