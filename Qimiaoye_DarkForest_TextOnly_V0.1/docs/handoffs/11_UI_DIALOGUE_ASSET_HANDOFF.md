# 交接｜全局 UI 与对话框素材接入

## 0. 目标

把共享素材目录中的对话框、姓名牌、输入框和按钮完整接入项目 UI，并保持当前已经修好的布局：

- 姓名文字在左上姓名牌中自动居中，不受“阿麦 / 女孩 / 玩家选择”等字数影响。
- 正文左对齐，水平右移 96 个逻辑像素、向下偏移 20 个逻辑像素。
- 两项选择必须同时可见，例如“走 / 不走”“想 / 不想”。
- 按钮仍居中。

本交接不写本机盘符。不同电脑只需找到同名共享目录 `Szene/ui/对话框` 和 `Szene/ui/其他`；这些目录及图片在各开发机上都有。

## 1. 必须使用的图片

### `Szene/ui/对话框`

| 图片名 | 用途 | 项目内建议名称 |
|---|---|---|
| `对话框.png` | 对话框底板、9-slice 原始素材 | `assets/ui/dialogue/dialogue_box.png` |
| `姓名显示处.png` | 独立姓名牌素材 | `assets/ui/dialogue/name_plate.png` |
| `姓名在左对话框.png` | 左侧姓名牌完整对话框；当前对白 UI 使用此图 | `assets/ui/dialogue/dialogue_left_reference.png` |
| `姓名在右对话框.png` | 右侧姓名牌完整对话框，保留供后续左右切换 | `assets/ui/dialogue/dialogue_right_reference.png` |

**不要导入：**`示意图1.png`、`示意图2.png`。

### `Szene/ui/其他`

| 图片名 | 用途 | 项目内建议名称 |
|---|---|---|
| `输入框.png` | TextInput 输入框 9-slice | `assets/ui/text_input/input_box.png` |
| `说出来按钮.png` | TextInput 确认按钮 | `assets/ui/text_input/speak_button.png` |
| `底图.png` | TextInput 界面底图 | `assets/ui/text_input/background.png` |
| `完整.png` | TextInput 完整构图参考 | `assets/ui/text_input/complete_reference.png` |

**不要导入：**`示意图.png`。

复制素材，不要移动、重命名或修改共享目录中的源文件。每次复制到 `res://` 后立刻运行一次 Godot `--import`。

## 2. 当前代码锚点

### 对话框：`scripts/dialogue_ui.gd`

当前实现使用：

- `PanelContainer + StyleBoxTexture + AtlasTexture`，没有新增 `TextureRect`。
- 底图：`dialogue_left_reference.png`。
- Atlas 区域：`Rect2(104, 416, 1072, 262)`。
- 9-slice 纹理边距：左 `76`、上 `96`、右 `76`、下 `62`。
- `content_margin_*` 必须显式为 `0`；否则内容会额外下移 96 px，第二个选择按钮会被挤出画面。
- 对话框范围：`offset_top = -328`、`offset_bottom = -28`。
- 姓名牌内容区：左边距 `64`、宽 `191`、姓名 `HORIZONTAL_ALIGNMENT_CENTER`。
- 正文：左边距 `96`、上边距 `20`、正文保持左对齐。

不要再用固定文字宽度手动“看起来居中”；姓名 Label 必须在姓名牌内容区内自动居中。

### TextInput：`levels/minigames/text_input.gd`

当前实现使用 `PanelContainer + StyleBoxTexture` 包住实际控件：

- 输入框 Atlas 区域：`Rect2(668, 304, 1232, 88)`。
- “说出来”按钮 Atlas 区域：`Rect2(1162, 482, 236, 98)`。
- `LineEdit` / `Button` 自身使用透明 `StyleBoxEmpty`，素材由外层 Panel 绘制。

### 图片白名单：`scripts/main.gd`

`ALLOWED_MODULE_IMAGE_ROOTS` 必须包含：

```gdscript
"res://assets/ui/",
```

否则完整流程会报“未授权图片资产”。

## 3. 禁止事项

`scripts/main.gd` 的 `_find_forbidden_visual_nodes()` 会扫描 main 整棵子树。`dialogue_ui` 是 main 的直接子节点，因此：

- **禁止**在 `dialogue_ui` / `narration_ui` 下增加 `TextureRect`、`Sprite2D`、`AnimatedSprite2D` 或 `CharacterBody2D`。
- 对话框与姓名牌必须继续使用 `Panel/PanelContainer + StyleBoxTexture` 9-slice。
- 不要把 `示意图*.png` 当成正式资产。
- 不要删除 SimSun 末端 fallback；天王星像素体仍缺“窸”“窣”。
- 不要修改森林跑酷模块来解决 UI 问题。

## 4. 验收标准

实际运行至少检查：

1. 普通对白：“阿麦”“女孩”等姓名位于白色姓名牌内并水平居中。
2. 长姓名：“玩家选择”等仍自动居中，不越出姓名牌。
3. 正文不再贴住左侧装饰，且位于叶片装饰下方。
4. DOCX 83：“走”“不走”两个按钮同时可见。
5. DOCX 181：“想”“不想”两个按钮同时可见。
6. 继续按钮保持居中。
7. 完整验证保留：`dialogue_left_aligned=true`、`dialogue_body_top=true`、`continue_button_centered=true`、`choices_centered=true`。

## 5. 当前基线与 Git 边界

当前远端基线：

```text
8d20824 fix(ui): lower dialogue body text further
```

该基线之前已包含：

- `07b27ae`：奇妙夜 2/5/10 视频覆盖 37–60、89–94、105–133。
- `601b4a9`：正文水平右移。
- `4260ae7`：姓名牌自动居中。
- `7b723c0`、`8d20824`：正文最终向下偏移 20。

提交时只暂存实际代码和正式 UI 素材：

- 不要 `git add .` / `git add -A`。
- 不要提交既有 `.import` 行尾噪声、`project.godot` 行尾变化、`tools/`、`tmp/` 或截图日志。
- 不要 amend、rebase、reset；新建 commit 后正常 push。
