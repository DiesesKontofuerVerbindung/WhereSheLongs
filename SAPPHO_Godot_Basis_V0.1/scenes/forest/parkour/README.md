# Forest Parkour Prototype

Standalone Forest-owned prototype scenes. Both reuse `res://shared/player/player.tscn`; no second Player implementation exists.

## Run

- Mechanism test: `res://scenes/forest/parkour/parkour_mechanics_test.tscn`
- Fixed-art gameplay: `res://scenes/forest/parkour/parkour_prototype.tscn`
- Automated smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/parkour_smoke_test.gd`

Controls: `A/D` or arrows move, `Space` jumps. `F1` toggles diagnostics, `F2` respawns, `F3` teleports to the next platform, `F4` toggles collision/sensor overlays, `F5` toggles J labels, and `F6` switches between clean art and the annotated layout reference.

## Layer contract

- Art: the supplied image, fitted uniformly inside the 1920×1080 design canvas.
- Route: normalized anchors stored only in `parkour_route.gd`.
- Collision: scene-owned rectangles configured from the route data; no image-derived collision.

The main route is `J1 → J2 → J3 → J3.5 → J4`. The current fixed composition places J5 above the normal jump envelope, so it remains an optional advanced/checkpoint target and emits its own completion event when reached (including through the F3 inspection tool). A future playable connection should add J4.5 or a later dream mechanic instead of increasing global jump strength.
