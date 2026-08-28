# Forest Parkour Prototype V2

Forest-owned continuous parkour prototype. It reuses `res://shared/player/player.tscn`; all three gameplay segments keep the same Player, ParkourMotor, EXTERNAL control session, and checkpoint state.

## Flow

```text
Segment 01 — supplied forest art
J1 → J2 → J3 → J3.5 → J4 → jump beyond the right edge
    ↓ eye-close transition
Segment 02 — ROOT ARCH ECHO
Four supplied root arches on continuous ground; every root retains an indexed UP/DOWN gate and Amai Echo executes the previous gate's Player action
    ↓ eye-close transition
Segment 03 — SUPPLIED PREDATOR-PLANT SCENE
Nine supplied floating platforms form a lower route and an upper flower-head route; all three flower heads are one-way landing surfaces
小凌先选路线并保持领先；阿麦以较慢速度沿同一路线做真实跳跃，最后从后方追到出口
    ↓ parkour_completed
WATERFALL INTRO PLACEHOLDER
```

小凌的 Forest 专用视觉位于 `characters/xiaoling_parkour_visual.tscn`：静止时循环播放 8 帧待机，开始水平移动时先完整播放 9 帧跑步启动，再进入 1–9 帧跑步循环；离地时播放 22 帧非循环跳跃，落地后按实际水平速度回到跑步或待机。跳跃帧已移除源 MOV 的画面内纵向漂移，由真实物理轨迹负责升降；方向由实际水平速度翻转，Shared Player 保持不变。

阿麦的 Forest 专用视觉位于 `characters/amai_parkour_visual.tscn`，由同一组件供 `AmaiPlaceholder` 与 `AmaiEcho` 使用：静止时循环待机，开始水平移动时完整播放启动段，再进入奔跑循环；方向由各自 CharacterBody2D 的实际水平速度翻转。原始 MOV 仅作为交付源，工程使用保留透明通道的 `720×1280` PNG 帧。

J4 only completes the platform portion. It does not complete Parkour. J5 and the former advanced-route signal have been removed.

## Run and controls

- Gameplay: `res://scenes/forest/parkour/parkour_prototype.tscn`
- Mechanism test: `res://scenes/forest/parkour/parkour_mechanics_test.tscn`
- Smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/parkour_smoke_test.gd`
- Xiaoling animation/integration validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/xiaoling_parkour_animation_test.gd`
- Vine echo prototype: `res://scenes/forest/parkour/vine_segment_prototype.tscn` (focused layout test)
- Vine echo smoke: `godot --headless --path . --script res://scenes/forest/parkour/tests/vine_echo_smoke_test.gd`
- Segment 02 root-arch traversal: `godot --headless --path . --script res://scenes/forest/parkour/tests/segment02_root_arch_test.gd`
- Segment 03 dual-route/art/head traversal: `godot --headless --path . --script res://scenes/forest/parkour/tests/segment03_dual_route_test.gd`
- Amai fixed-route 30-run validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_fixed_route_30_test.gd`
- Amai Segment 03 trailing 30-run validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_segment03_follow_30_test.gd`
- Amai Segment 03 trailing/shared-exit validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_segment03_shared_exit_test.gd`
- Amai animation/integration validation: `godot --headless --path . --script res://scenes/forest/parkour/tests/amai_parkour_animation_test.gd`

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

Segment 02 and 03 keep reusable gameplay geometry separate from supplied art. Segment 02 uses `root_obstacle.tscn` for four independently aligned upper collisions and open slide channels; the development root drawing stays disabled beneath the final layered image.

## Segment 02 Vine Echo

The full `parkour_prototype.tscn` uses the four-gate delayed-action rule in Segment 02. Horizontal movement remains player-controlled. The supplied 2560×1440 backdrop, four split-layer root arches, and foreground are fitted as a 1920×1080 scene; rear root faces stay behind the characters, while front faces and ground foliage occlude them in the supplied order. Roots 01–04 and their collision openings align with Gates 01–04, and every root accepts either a physical jump or the existing shortened slide collider. Amai Echo follows a fixed ground route with one spawn anchor, four wait anchors, and one exit anchor. Root collisions use a Player-only layer so Amai can keep the proven fixed route while still performing delayed jump/slide commands. At Gate N, Amai Echo executes the Player action stored from Gate N-1. Gate 01 gives Amai Echo `NONE`. Space locks `UP`; `S`/Down/PgDn locks `DOWN`; the first valid input per gate wins. The decision zone records the choice and the separate action line starts Player current/Amai previous actions in the same physics frame. Pre-input and landing buffers remain unchanged. The focused `vine_segment_prototype.tscn` is retained for mechanism-only inspection.
