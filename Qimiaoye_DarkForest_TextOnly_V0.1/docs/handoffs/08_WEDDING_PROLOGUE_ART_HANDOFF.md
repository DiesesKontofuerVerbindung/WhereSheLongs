# 交接｜婚礼前夜章节（接美术素材）

交接给外部协作方。这份文档假设你**没有**这个项目的任何背景，所以从"这是什么"开始写。

## 0. 开工前必做

**先把你手上的美术资源清点一遍，把它们的实际存放位置回报给我们，再动代码。**

原因：婚礼这一章目前**没有任何美术素材**，仓库里、素材盘里都翻过了，只有森林 / 湖边 / 河流 / 阿麦角色动画。所以现在整章跑的是纯文字舞台占位。你要插的图放在哪、叫什么、什么分辨率、有几套，我们这边完全不知道。不先对齐这个，你写的加载路径大概率跟实际素材对不上。

回报内容建议包含：素材根目录、四个场景各自对应哪个文件、分辨率、是否有前景/后景分层、是否有角色立绘。

---

## 1. 这是什么

一个 Godot 4.7 的叙事游戏。整体三章串联：

```
婚礼前夜  →  奇妙夜  →  森林（正片）
  你负责      开发中      已完成
```

**你负责的是第一章「婚礼前夜」。** 它是一段婚礼当天早晨到夜里的剧情：小凌在婚礼现场、车上、家里，最后闭眼，进入后面的章节。

- 事件 146 条，其中旁白 28 条、人物对白 96 条
- 4 个场景，2 个交互模块，1 个按钮交互
- 全部是文字 + 占位，**没有一张图**

## 2. 环境

| 项 | 值 |
|---|---|
| 引擎 | Godot 4.7.2 stable |
| 仓库 | https://github.com/DiesesKontofuerVerbindung/Peking26082026 |
| 分支 | `codex/20260829-lake-stone-route` |
| Godot 项目根 | `Qimiaoye_DarkForest_TextOnly_V0.1/` |

**注意仓库根目录很杂**：有大量未跟踪的源画、原型、文档、生成物，是有意保留的。不要为了"清理干净"跑 `git clean` 或 `git reset --hard`。

### 怎么跑婚礼这一章

`project.godot` 的主场景是**森林**，不是婚礼。所以直接点运行会进森林。要跑婚礼，显式指定场景：

```bash
Godot_v4.7.2-stable_win64.exe --path <项目路径> res://scenes/wedding/wedding_prologue.tscn
```

或者在编辑器里打开 `scenes/wedding/wedding_prologue.tscn` 按 F6 单独运行。

**不要**为了方便把 `run/main_scene` 改成婚礼再提交——森林的验证和打包都依赖它。本地临时改可以，提交前改回来。

## 3. 文件地图

| 文件 | 作用 |
|---|---|
| `scenes/wedding/wedding_prologue.tscn` | 章节场景，根节点挂 `wedding_prologue.gd` |
| `scripts/wedding_prologue.gd` | **章节外壳。你主要改这个。** UI 构建、事件循环、推进、F4 面板 |
| `scripts/wedding_data.gd` | 剧本事件表。纯数据，146 条 |
| `scripts/wedding_vow_solo.gd` + `scenes/wedding/modules/wedding_vow_solo.tscn` | 交互模块①：誓词卡 |
| `scripts/phone_notifications.gd` | 交互模块②：手机通知 |
| `scripts/narration_ui.gd` | 上方旁白 UI（**与森林正片共用，改它会影响森林**） |
| `scripts/dialogue_ui.gd` | 下方对话框 UI（同上，共用） |
| `scripts/dev_jump_panel.gd` | F4 开发者回溯面板（同上，共用） |

**共用文件要当心**：`narration_ui.gd` / `dialogue_ui.gd` / `dev_jump_panel.gd` 三个文件森林正片也在用。改它们之前先想清楚，改完两边都要验。婚礼专属的样式请加在 `wedding_prologue.gd` 里，不要改进共用 UI。

## 4. 美术要插在哪

### 4.1 当前的占位长什么样

`wedding_prologue.gd` 的 `_build_ui()` 里建了一棵这样的树：

```
WeddingPrologue (Control, 全屏)
├── WeddingBackdrop      ColorRect，纯色底 (0.055, 0.05, 0.07)
├── WeddingStage         Control，全屏 ← 【美术插这里】
│   ├── _scene_label     Label，居中大字，显示场景名，例如"婚礼背景图1"
│   └── _scene_subtitle  Label，居中小字，"婚礼前段 · 美术未到位，纯文字舞台占位"
├── NARRATION_UI         上方旁白
├── DIALOGUE_UI          下方对话框
├── WeddingInteraction   按钮面板（默认隐藏）
├── WeddingModuleHost    交互模块宿主（默认隐藏）
├── _advance_hint        左上角"按 Enter / Space 继续"
└── DeveloperDocxJumpOverlay  F4 面板（默认隐藏）
```

`WeddingStage`（代码里的 `_stage_root`）就是舞台层。**把底图 `TextureRect` 加进这个节点，放在两个 Label 之前**（即让 Label 画在图上面），然后按场景切换纹理。

选 `_stage_root` 而不是根节点，是因为剧情里的震动效果只晃 `_stage_root`，不晃对话框——文字必须始终可读。你把图挂进去就自动获得同样的震动行为。

### 4.2 四个场景

场景由 `{"type": "scene", ...}` 事件驱动，切换走 `_set_scene(scene_name)`：

| DOCX 行 | 场景名（`wedding_data.gd` 里的常量） | 剧情位置 |
|---|---|---|
| 2 | `婚礼背景图1` (`SCENE_WEDDING_1`) | 婚礼现场，开场 |
| 18 | `婚礼背景图2` (`SCENE_WEDDING_2`) | 婚礼现场，后半 |
| 47 | `车上背景图` (`SCENE_CAR`) | 车上 |
| 105 | `家里场景` (`SCENE_HOME`) | 家里，直到结尾 |

接美术时改 `_set_scene()`：现在它只设两个 Label 的文字，你在里面按 `scene_name` 换底图。素材没到位的场景请保留文字占位回退，不要让缺图变成黑屏。

### 4.3 两个交互模块

| 模块 | DOCX 行 | 现状 |
|---|---|---|
| 誓词卡 `WeddingVowSolo` | 21 | 三句誓词，玩家逐句按 Enter 念完。纯文字卡片，可以接卡片美术 |
| 手机通知 `PhoneNotifications` | 32 | 消息逐条弹出（定时，不需要按键）。可以接手机 UI 美术 |

模块通过 `_run_module()` 实例化，挂在 `WeddingModuleHost` 下，跑完 `queue_free`。模块必须实现 `run(verify_mode) -> void` 协程——用协程而不是信号，因为验证模式下模块可能在 `_ready` 里就跑完了，那时再 await 信号会永久挂起。

另外还有 1 个按钮交互（DOCX 59），走 `_run_interaction()`。

## 5. 开发者模式（F4）—— 这是给你省时间的

**游戏里任何时候按 F4**，弹出一个开发者回溯面板：

```
┌─────────────────────────────────────────┐
│      开发者功能 · DOCX 行回溯            │
│   [ 婚礼前夜回溯 ]  [ 森林回溯 ]         │  ← 两页 tab
│                                          │
│   当前 DOCX 行：47 | 可跳转范围：2–145   │
│   [ 118        ]  [ 从此行开始 ]         │
│   精确落点：DOCX 第 118 行 · line / …    │
│              [ 取消 · Esc / F4 ]         │
└─────────────────────────────────────────┘
```

**怎么用**：输入剧本 DOCX 的行号，点「从此行开始」，游戏立刻重载并从那一行开始播。如果那一行没有事件，会自动落到下一条有事件的行，面板下方会提示实际落点。

**这对你意味着什么**：

- **调美术不用从头看剧情。** 想看「家里场景」的底图对不对，按 F4 输 105，直接跳过去。不用一路 Enter 点 100 多条对白。
- **卡住了可以跳过去。** 遇到阻塞性 bug（某个模块卡死、某条事件不推进），按 F4 跳到它后面的行，继续验证后面的内容，不用等 bug 修好。**但请把卡住的行号记下来报告，别默默跳过。**
- **两个 tab 可以跨章节跳。** 切到「森林回溯」tab 输入森林的行号，会直接切到森林场景。婚礼行号范围 2–145，森林是 29–366，两套 DOCX 各自独立编号，别混。

Esc 或再按一次 F4 关闭。面板打开时 Enter 属于输入框，不会推进剧情。

## 6. 剧情推进机制

每条台词都**停下来等玩家按 Enter / Space**，不会自动播。左上角的「按 Enter / Space 继续」提示只在真的在等玩家时才亮。

这一点刚修过（原先是 146 条全自动流过去，按 Enter 没反应），有回归测试守着：`tests/wedding_advance_gate_test.tscn`。如果你改动了 `_show_line()` 或输入处理，跑一下这个测试。

非台词事件（`wait` / `effect` / `scene` / `action`）是定时推进的，不等玩家——这是设计如此，不是 bug。

## 7. 验证

改完跑这两条，日志写到 `tmp/codex_logs/`：

```bash
# 婚礼全流程验证（跑完整章，检查事件数、场景数、终点、面板契约）
Godot_v4.7.2-stable_win64_console.exe --headless --path <项目> res://scenes/wedding/wedding_prologue.tscn -- --verify

# 推进门控回归测试（确认 Enter 仍然有效、不会退回自动播放）
Godot_v4.7.2-stable_win64_console.exe --headless --path <项目> res://tests/wedding_advance_gate_test.tscn
```

通过的样子：

```
WEDDING_PROLOGUE_PASS events=146 scenes=4 sources=140 modules=2 interactions=1
  endpoint=true narration_lines=28 dialogue_lines=96 advance_gated=true
  dev_docx_jump=true dev_jump_chapters=wedding_forest wedding_source_bounds=(2, 145)

WEDDING_ADVANCE_GATE_PASS narration_and_dialogue_gated=true enter_advances=true
  hint_follows_gate=true
```

两条都是 exit 0。**只有你动了 `narration_ui.gd` / `dialogue_ui.gd` / `dev_jump_panel.gd` 这三个共用文件时，才需要额外跑森林的全流程验证**（`--headless --path <项目> -- --verify`），否则不用。

### 环境提醒

- 开发机内存 7.8 GB。**游戏窗口和 headless 测试不能同时跑**，否则会报 `alloc_static` null 或 `CreateProcess failed, error 1455`——看起来像代码错了，其实是内存。跑测试前先确认没有 Godot 进程在跑。
- 内存不足时被打断的资源导入会写坏 `.godot/imported/` 里的贴图缓存（症状：`Failed decoding WebP image`）。修法是删掉对应的 `.ctex`/`.md5` 再 `--import`。`.godot/` 已被 gitignore，删了安全。

## 8. 报 bug 的时候请带上

- **DOCX 行号**（F4 面板上一直显示当前行，直接抄）
- 是美术问题还是阻塞问题
- 复现路径：F4 跳到第几行能重现

带行号的 bug 我们这边能直接跳过去看，比截图快得多。

## 9. 红线

- 不要 `git reset --hard`、`git clean`、广义 `git checkout --`、`git add .` / `git add -A`。仓库根有大量无关未跟踪素材，必须保留。
- 不要把婚礼的事件混进 `scripts/story_data.gd`——森林正片的 `events=336`、`source_bounds=(29,366)`、`docx_source_lock` 都是硬断言，混进去会全部打掉。
- 不要改 `project.godot` 的 `run/main_scene`。
- 大量 `.import` 文件会显示 modified 但内容 diff 为 0，是行尾符噪声，不要提交它们。
- 剧本文字（`wedding_data.gd` 里的 `text`）不要改写、润色或补写。有问题先问。
