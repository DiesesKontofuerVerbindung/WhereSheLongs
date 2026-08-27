# Forest Parkour Prototype V2

Forest-owned continuous parkour prototype. It reuses `res://shared/player/player.tscn`; all three gameplay segments keep the same Player, ParkourMotor, EXTERNAL control session, and checkpoint state.

## Flow

```text
Segment 01 — supplied forest art
J1 → J2 → J3 → J3.5 → J4 → jump beyond the right edge
    ↓ eye-close transition
Segment 02 — VINE ECHO
Four indexed gates: each accepts UP or DOWN; Amai Echo executes the previous gate's Player action
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
- Vine echo prototype: `res://scenes/forest/parkour/vine_segment_prototype.tscn` (focused layout test)
- Vine echo smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/vine_echo_smoke_test.gd`
- Amai fixed-route 30-run validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_fixed_route_30_test.gd`

Controls:

- `A / D` or arrows: run
- `Space`: jump
- `S / ↓ / PgDn`: choose or perform the grounded DOWN slide
- `F1`: diagnostics
- `F2`: respawn at the current segment checkpoint
- `F3`: advance debug progress / jump to the next segment
- `F4`: collision and sensor overlay
- `F5`: route labels
- `F6`: clean/annotated Segment 01 background

Segment 02 and 03 are deliberately Greybox placeholders. Their gameplay scripts and collision are separate from visuals so future art replacement does not rewrite the mechanics.

## Segment 02 Vine Echo

The full `parkour_prototype.tscn` uses the four-gate delayed-action rule in Segment 02. Horizontal movement remains player-controlled. Amai Echo follows a fixed ground route with one spawn anchor, four wait anchors, and one exit anchor. She runs ahead independently, waits 90 px before each Gate, ignores the floating `UP PATH` platforms, and still uses real gravity/jump plus the shortened slide collider. At Gate N, Amai Echo executes the Player action stored from Gate N-1. Gate 01 gives Amai Echo `NONE` and bypasses her obstacle collision. Space locks `UP`; `S`/Down/PgDn locks `DOWN`; the first valid input per gate wins. The expanded decision zone only records the choice; a separate action line 100 px before the vine starts Player current/Amai previous actions in the same physics frame, so an early input cannot finish before the obstacle. A 0.35-second pre-input buffer and 0.32-second landing buffer prevent edge-frame input loss. The slide capsule is reduced to 56% height and 78% radius, preserving the standing block while giving the crouched route reliable clearance. The focused `vine_segment_prototype.tscn` is retained for mechanism-only inspection.
