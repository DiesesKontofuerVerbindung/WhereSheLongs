# 交接｜固定定位 UI 图层与通用模块面板

## 0. 结论

`Szene/ui` 交付的是整幅画布定位图层，不是九宫格素材。只裁 alpha 元素矩形并按 1280×720 设计坐标原尺寸摆放；不要设置 `texture_margin_*`，不要随文本或窗口自适应拉伸。

不同电脑只按共享目录名和图片名找素材，不依赖本机盘符。

## 1. 正式素材

### `Szene/ui/对话框`

| 源文件 | 项目路径 | 用途 |
|---|---|---|
| `对话框.png` | `assets/ui/dialogue/dialogue_box.png` | 固定对白底板 |
| `姓名显示处.png` | `assets/ui/dialogue/name_plate.png` | 可左右移动的姓名牌 |

不要导入：`姓名在左对话框.png`、`姓名在右对话框.png`、`示意图1.png`、`示意图2.png`。

### `Szene/ui/其他`

| 源文件 | 项目路径 | 用途 |
|---|---|---|
| `底图.png` | `assets/ui/panel/panel.png` | 通用玩家模块底板 |
| `输入框.png` | `assets/ui/panel/input_box.png` | 文本输入框图层 |
| `说出来按钮.png` | `assets/ui/panel/primary_button.png` | 通用主按钮图层 |

不要导入：`完整.png`、`示意图.png`。

每次向 `res://` 复制或移动素材后立即运行 Godot `--import`。共享目录中的源文件只能复制，不能移动或修改。

## 2. 固定矩形（1280×720 设计空间）

| 图层 | 目标矩形 | 源图 Atlas 区域 |
|---|---|---|
| 对话框 | `Rect2(110, 458, 1060, 218)` | 同目标矩形 |
| 左姓名牌 | `Rect2(198, 422, 166, 82)` | `Rect2(198, 422, 166, 82)` |
| 右姓名牌 | `Rect2(920, 422, 166, 82)` | 与左姓名牌使用同一 Atlas，只改目标 x |
| 通用面板 | `Rect2(302, 46, 676, 274)` | 同目标矩形 |
| 输入框 | `Rect2(334, 152, 616, 44)` | 原图为 2560×1440，裁 `Rect2(668, 304, 1232, 88)` |
| 主按钮 | `Rect2(581, 241, 118, 49)` | 原图为 2560×1440，裁 `Rect2(1162, 482, 236, 98)` |

统一几何与 Atlas 构造集中在 `scripts/ui_panel_skin.gd`。

## 3. 接入位置

- `scripts/dialogue_ui.gd`：正式对话框 + 独立姓名牌；姓名文字在姓名牌内自动居中。
- `scripts/story_stage.gd` + `scripts/main.gd`：根据当前说话人的演员 x 与舞台中线决定姓名牌 left/right；取不到演员位置时退化为 left，不能按名字硬编码。
- `scripts/main.gd::_build_interaction_panel()`：森林 DOCX 136 跳水、光源等玩家交互使用通用底板和主按钮。
- `levels/minigames/text_input.gd`：DOCX 157 使用通用底板、输入框、主按钮。
- `levels/river_jump.gd` / `river_jump.tscn`：DOCX 193 LakeJump HUD 使用通用底板和按钮。
- `levels/minigames/firefly_bottle.gd`：DOCX 238 StarJar 使用通用底板。

不要修改 `scripts/main.gd::_diagnostic_panel` 或 `scripts/dev_jump_panel.gd` 的 F4 开发者 UI。

## 4. TextInput 漂浮杂念视觉

- 所有漂浮文字强制 `#FFFFFF`，忽略 Python 帧传来的彩色值。
- 基础透明度只能来自 `0.16 / 0.25 / 0.34 / 0.46 / 0.58`；低档位占多数，最高档只占少量。
- 最终透明度继续乘现有物理帧 opacity，保留运动与消散；进入通用面板核心区时额外乘 `0.55`。
- 玩家输入文字为白色 alpha 1；placeholder 白色 alpha 0.55；核心引导 alpha 0.9–1。
- 不加彩色描边、霓虹、发光、渐变或黑幕。面板和杂念层只做自身 alpha 的柔和淡入淡出。

## 5. 硬约束

- main 子树禁止新增 `TextureRect` / `Sprite2D` / `AnimatedSprite2D` / `CharacterBody2D`。玩家 UI 底板用 `Panel` / `PanelContainer + StyleBoxTexture`。
- `scripts/main.gd` 的图片白名单必须保留 `res://assets/ui/`。
- 不改摄像头、输入、提交、跳跃、拖拽、事件表或验证语义。
- 不要 `git add .` / `git add -A`；不要提交既有 `.import` 行尾噪声、`project.godot`、`tools/`、`tmp/`。

## 6. 最小验证

```powershell
& $g --headless --path $p --import
& $g --headless --path $p --resolution 1280x720 res://scenes/wedding/wedding_prologue.tscn -- --verify
& $g --headless --path $p --resolution 1280x720 res://main.tscn -- --verify
```

必须出现 `WEDDING_PROLOGUE_PASS` 和 `FULL_FLOW_PASS`，并保留：

`dialogue_left_aligned=true` `dialogue_body_top=true` `continue_button_centered=true` `choices_centered=true` `narration_centered=true`。
