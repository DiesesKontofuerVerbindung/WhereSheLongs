# Forest Parkour Prototype V2

Forest-owned continuous parkour prototype. It reuses `res://shared/player/player.tscn`; all three gameplay segments keep the same Player, ParkourMotor, EXTERNAL control session, and checkpoint state.

## Flow

```text
Segment 01 — supplied forest art
J1 → J2 → J3 → J3.5 → J4 → jump beyond the right edge
    ↓ eye-close transition
Segment 02 — VINE PLACEHOLDER
Jump over or slide under
    ↓ eye-close transition
Segment 03 — MOVING PLANT PLACEHOLDER
Wait for CLOSED or take the upper risk route
    ↓ parkour_completed
WATERFALL INTRO PLACEHOLDER
```

J4 only completes the platform portion. It does not complete Parkour. J5 and the former advanced-route signal have been removed.

## Run and controls

- Gameplay: `res://scenes/forest/parkour/parkour_prototype.tscn`
- Mechanism test: `res://scenes/forest/parkour/parkour_mechanics_test.tscn`
- Smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/parkour_smoke_test.gd`

Controls:

- `A / D` or arrows: run
- `Space`: jump
- `S / ↓`: slide while grounded
- `F1`: diagnostics
- `F2`: respawn at the current segment checkpoint
- `F3`: advance debug progress / jump to the next segment
- `F4`: collision and sensor overlay
- `F5`: route labels
- `F6`: clean/annotated Segment 01 background

Segment 02 and 03 are deliberately Greybox placeholders. Their gameplay scripts and collision are separate from visuals so future art replacement does not rewrite the mechanics.
