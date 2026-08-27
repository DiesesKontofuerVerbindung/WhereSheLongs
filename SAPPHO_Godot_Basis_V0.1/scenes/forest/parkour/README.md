# Forest Parkour Prototype V2

Forest-owned continuous parkour prototype. It reuses `res://shared/player/player.tscn`; all three gameplay segments keep the same Player, ParkourMotor, EXTERNAL control session, and checkpoint state.

## Flow

```text
Segment 01 — supplied forest art
J1 → J2 → J3 → J3.5 → J4 → jump beyond the right edge
    ↓ eye-close transition
Segment 02 — ROOT ARCH ECHO
Five supplied root arches on continuous ground; the first four retain indexed UP/DOWN gates and Amai Echo executes the previous gate's Player action
    ↓ eye-close transition
Segment 03 — SUPPLIED PREDATOR-PLANT SCENE
Nine supplied floating platforms form a lower route and an upper flower-head route; all three flower heads are one-way landing surfaces
小凌先选路线并保持领先；阿麦以较慢速度沿同一路线做真实跳跃，最后从后方追到出口
    ↓ parkour_completed
WATERFALL INTRO PLACEHOLDER
```

小凌的 Forest 专用视觉位于 `characters/xiaoling_parkour_visual.tscn`：静止时循环播放 8 帧待机，开始水平移动时先完整播放 9 帧跑步启动，再进入 1–9 帧跑步循环；方向由实际水平速度翻转，Shared Player 保持不变。

J4 only completes the platform portion. It does not complete Parkour. J5 and the former advanced-route signal have been removed.

## Run and controls

- Gameplay: `res://scenes/forest/parkour/parkour_prototype.tscn`
- Mechanism test: `res://scenes/forest/parkour/parkour_mechanics_test.tscn`
- Smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/parkour_smoke_test.gd`
- Vine echo prototype: `res://scenes/forest/parkour/vine_segment_prototype.tscn` (focused layout test)
- Vine echo smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/vine_echo_smoke_test.gd`
- Segment 02 root-arch traversal: `godot --headless --path . --script res://scenes/forest/parkour/tests/segment02_root_arch_test.gd`
- Segment 03 dual-route/art/head traversal: `godot --headless --path . --script res://scenes/forest/parkour/tests/segment03_dual_route_test.gd`
- Amai fixed-route 30-run validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_fixed_route_30_test.gd`
- Amai Segment 03 trailing 30-run validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_segment03_follow_30_test.gd`
- Amai Segment 03 trailing/shared-exit validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_segment03_shared_exit_test.gd`

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

Segment 02 and 03 are deliberately Greybox placeholders. Segment 02 now uses a reusable `root_obstacle.tscn`: each instance draws an asymmetrical 3/4 root placeholder while keeping a simple upper rectangle collision and an open slide channel. Gameplay collision remains separate from final art.

## Segment 02 Vine Echo

The full `parkour_prototype.tscn` uses the four-gate delayed-action rule in Segment 02. Horizontal movement remains player-controlled. The supplied backdrop, five root arches, and foreground are fitted as a 1920×1080 layered scene. Roots 01–04 align with the existing four Gates, while Root 05 provides a free-action closing beat. Amai Echo follows a fixed ground route with one spawn anchor, four wait anchors, and one exit anchor. Root collisions use a Player-only layer so Amai can keep the proven fixed route while still performing delayed jump/slide commands. At Gate N, Amai Echo executes the Player action stored from Gate N-1. Gate 01 gives Amai Echo `NONE`. Space locks `UP`; `S`/Down/PgDn locks `DOWN`; the first valid input per gate wins. The decision zone records the choice and the separate action line starts Player current/Amai previous actions in the same physics frame. Pre-input and landing buffers remain unchanged. The focused `vine_segment_prototype.tscn` is retained for mechanism-only inspection.
