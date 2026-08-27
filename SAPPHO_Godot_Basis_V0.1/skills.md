# SAPPHO Godot Basis — Codex Working Contract

## 0. Mandatory first step

Read this file before implementation. Then inspect only the files relevant to the requested scene/task.

Target engine: **Godot 4.7.x**. The basis was prepared for Godot **4.7.2 stable**.

## 1. Repository ownership boundary

### Forest-owned

- `scenes/forest/**`
- `assets/forest/**`
- Forest regression tests should live under `scenes/forest/tests/**`

### Wedding-owned

- `scenes/wedding/**`
- `assets/wedding/**`
- Wedding regression tests should live under `scenes/wedding/tests/**`

### Shared / protected

Do not modify these unless the user explicitly requests a shared change:

- `shared/**`
- `project.godot`
- `AGENTS.md`
- `skills.md`
- `ARCHITECTURE.md`
- root `tests/**`
- `scenes/test_room/**`

Root `tests/**` means the shared integration/smoke suite. It does **not** forbid scene-owned tests under `scenes/forest/tests/**` or `scenes/wedding/tests/**`.

If a scene task appears to require changing a protected file, **stop that modification** and report:

1. which shared file would need to change;
2. why the current public interface is insufficient;
3. the smallest proposed interface change;
4. which Forest/Wedding files could be affected.

Do not silently “fix” shared architecture from inside a scene task.

## 2. One shared Player only

The canonical Player is:

`res://shared/player/player.tscn`

Rules:

- Reuse/instantiate this Player in Forest and Wedding scenes.
- Do not copy `player.gd` into a scene folder.
- Do not create `ForestPlayer`, `WeddingPlayer`, `Player2`, or another movement controller to bypass the shared Player.
- Scene-specific behavior should normally live in the scene or in a scene-owned component, not by rewriting Player.

Current Player public behavior:

- 2D movement through InputMap actions in `ControlMode.NORMAL`.
- `interact` searches the nearest compatible Area2D in the detector range.
- `look` calls the same target's `look(actor)` method.
- `facing_changed(direction)` is available for future animation/art integration.
- Dialogue temporarily blocks normal movement and scene interaction.
- `interaction_enabled` can disable shared interact/look dispatch without disabling normal movement.

### Player control hand-off

Use the shared control modes instead of creating another Player:

```text
NORMAL   shared Player owns normal movement and shared interaction input
LOCKED   Player is frozen for cutscenes/dialogue/sequence gates
EXTERNAL scene-owned gameplay controller supplies movement
```

Public interface:

```gdscript
player.use_normal_control()
player.lock_control()
player.use_external_control()
player.set_interaction_enabled(false)
player.set_external_velocity(desired_velocity)
player.stop_external_movement()
```

When a Forest/Wedding controller enters `EXTERNAL`, it may drive movement through `set_external_velocity(...)`. Call `use_normal_control()` when the local gameplay sequence ends.

Do not directly replace the Player's `_physics_process()` logic from a scene script.

## 3. InputMap is global and protected

Existing actions:

- `move_left`
- `move_right`
- `move_up`
- `move_down`
- `interact`
- `look`
- `jump`
- `pause`

`jump` is reserved globally (Space) so scene-owned gameplay can use a common action. Shared Player does **not** implement jump physics; Forest/Wedding decide what `jump` means inside their own gameplay states.

Do not hardcode alternative movement/interact/jump keys inside a scene script.
Do not add a second set such as `forest_interact` / `wedding_interact` without explicit approval.
If a new global action is genuinely necessary, report it as a shared change first.

## 4. Interaction contract

Canonical base:

`res://shared/interaction/interactable.gd`

A normal world object should expose:

- `interact(actor)` for active interaction;
- `look(actor)` for inspection/observation.

Prefer extending the shared interactable or implementing compatible methods.
Do not make Player know concrete scene node paths.

Bad:

```gdscript
$"../Wedding/Bride/AnimationPlayer".play("cry")
```

Good:

```gdscript
some_interactable.interact(player)
```

or scene-local signals/state changes.

## 5. Cross-scene state

Canonical global state:

`GameState`

Public interface:

```gdscript
GameState.set_flag("forest_finished", true)
var done = GameState.get_flag("forest_finished", false)
```

Rules:

- Use flags only for state that must survive a scene change.
- Do not store direct Node references in GameState.
- Do not make Forest directly fetch nodes inside Wedding or vice versa.

## 6. Scene changes

Canonical scene transition service:

`SceneManager`

Use:

```gdscript
SceneManager.change_scene("res://scenes/wedding/wedding.tscn")
```

Do not duplicate scene-transition managers inside Forest/Wedding.
Do not hard-wire cross-scene NodePaths.

## 7. Dialogue

Canonical global dialogue layer:

`Dialogue`

Minimum API:

```gdscript
Dialogue.show_line("Speaker", "Text")
Dialogue.show_choices("Speaker", "Question", ["A", "B"])
```

Dialogue is intentionally minimal. Narrative tooling/data import is **not** part of Basis V0.1 yet.
Do not replace this system during scene implementation just because a scene needs more dialogue features; propose the smallest shared extension first.

## 8. Scene-local systems stay scene-local

The following planned Forest mechanics are NOT shared infrastructure in V0.1:

- parkour/running sequence;
- **scripted surreal waterfall jump/transition** (not a standalone waterfall-descent minigame);
- stepping/jumping across stones;
- drowning/oxygen value and narrative Game Over;
- firefly navigation;
- heart-light visual interaction;
- dream-world collapse;
- forest-specific camera effects or shaders.

Current Forest gameplay split:

```text
Parkour              = gameplay system
Waterfall            = short scripted surreal interaction / worldbuilding
Stone jumping        = gameplay system
Drowning             = narrative transition, not a level reload
```

Implement them under Forest ownership unless a real second-scene reuse case appears.

Likewise, Wedding-specific rehearsal/ceremony systems stay under Wedding ownership.

## 9. Resource/path discipline

- Shared assets: `assets/shared/**`
- Forest assets: `assets/forest/**`
- Wedding assets: `assets/wedding/**`
- Do not move/rename shared files casually after they are referenced by scenes.
- Prefer `res://...` paths.
- Keep filenames `snake_case`.
- Keep scene root names descriptive and stable.

## 10. Git / merge safety

The goal is to reduce overlapping writes, not to “be clever” during merge conflict resolution.

Before finishing a task:

- Confirm no unrelated protected file changed.
- Confirm no second implementation of shared services was added.
- Confirm no scene-owned asset was moved into another owner's folder.
- Do not resolve an ambiguous conflict by choosing “ours” or “theirs” blindly.
- If `project.godot` has an unexpected diff, treat it as a shared-infrastructure change and inspect it explicitly.

## 11. Required validation

When a Godot executable is available, run:

```bash
godot --headless --path . --script res://tests/smoke_test.gd
```

Then, for a scene task, also open/run the modified scene or project if the environment supports it.

Minimum acceptance criteria:

- project parses;
- required InputMap actions exist;
- shared Player scene enters the SceneTree and exposes the documented public hand-off methods;
- TestRoom, Forest placeholder, and Wedding placeholder enter the SceneTree;
- no missing resource dependency;
- no new parser errors.

If Godot is unavailable in the environment, say validation was limited to static inspection. Do not claim the runtime test passed.

## 12. Definition of done for a scene task

A task is done only if:

1. the requested behavior works inside the owned scene;
2. shared APIs were reused instead of duplicated;
3. protected files were not changed without explicit authorization;
4. the scene remains loadable independently;
5. scene-owned regression tests are added when a bug/behavior warrants them;
6. the validation result is reported clearly.
