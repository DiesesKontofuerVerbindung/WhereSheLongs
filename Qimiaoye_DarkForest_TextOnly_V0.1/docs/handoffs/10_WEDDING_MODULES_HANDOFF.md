# 交接｜婚礼前夜·Checklist / 客厅查看模块

## 0. 一句话现状

在 `codex/20260829-lake-stone-route` 美术底图之上，接入了 **手势 checklist×2**、**客厅物品查看**，并把 **司仪图** 用作婚礼背景图1（DOCX 3–21）；誓词+清单①之后再切婚礼背景图2。

## 1. 本次做了什么

| 模块 | 位置 | 说明 |
|---|---|---|
| `WeddingChecklist1` | DOCX 21（誓词后） | `hand_checkbox_gesture`：p1→空中打勾→p2；鼠标/Enter 回退 |
| `WeddingChecklist2` | DOCX 46（上车前） | 同上，variant `2` |
| `WeddingLivingroomInspect` | DOCX 107（108 前） | 客厅底图 + 三件道具查看（自带对白层） |
| 场景切图 | `SCENE_WEDDING_1` → `candidates/officiant.jpg` | 3–21 司仪；`scene@22` 再切 `wedding_2` |
| 输入防穿透 | `_drain_advance_input()` | 模块结束 / 台词启用推进前吞掉残留 Enter/点击 |

## 2. 关键文件

- `addons/hand_checkbox_gesture/`（`SHOW_CAMERA_PREVIEW=False`，`WEDDING_LOOSE_MODE=True`）
- `scripts/wedding_checklist.gd` + `scenes/wedding/modules/wedding_checklist.tscn`
- `scripts/wedding_livingroom_inspect.gd` + `scenes/wedding/modules/wedding_livingroom_inspect.tscn`
- `assets/wedding/livingroom_base.jpg` + `assets/wedding/props/*`
- `scripts/wedding_data.gd` / `scripts/wedding_prologue.gd`（事件表 + 模块 setup + drain）

## 3. 未做

- 角色立绘（共用 `dialogue_ui.gd`，影响森林）
- 誓词卡 / 手机模块美术
- 人工确认 3:2→16:9 裁切手感

## 4. 红线（继承 08/09）

- 不要 `git add -A` / `git clean` / `reset --hard`
- 不要改 `project.godot` 的 `main_scene`
- 不要改 `story_data.gd` / 剧本 `text`
- 不要提交 `.import` 行尾噪声、`__pycache__`、检测日志
