# 机制 7 交接：BlinkInteraction（眨眼互动）

## 1. 固定起点

这是一项独立模块开发任务。开始编码前必须取得并核对下面的基线：

- 仓库：`https://github.com/DiesesKontofuerVerbindung/Peking26082026.git`
- 基线分支：`codex/20260828-gespielt-grounded`
- 必须阅读的最新提交：`c92bdad0beac9391c83b293bd2f708622a28c986`
- 当前效果参考：`C:\Users\27532\Desktop\Gespielt.exe`（版本 `1.3.8.0`，SHA-256 `F10756C26F36B81AB36D0059E4CAC3E36D16FA3754347F7005FC52A2A9ADC963`）
- 建议工作分支：`codex/qimiaoye-blink-interaction`

建议命令：

```powershell
git fetch origin
git worktree add ..\qimiaoye-blink-interaction -b codex/qimiaoye-blink-interaction c92bdad0beac9391c83b293bd2f708622a28c986
git -C ..\qimiaoye-blink-interaction rev-parse HEAD
```

最后一条命令必须输出完整提交号 `c92bdad0beac9391c83b293bd2f708622a28c986`。`Gespielt.exe` 只用于观察当前风格和运行效果，源码权威仍是该提交。不要直接在集成分支上开发，也不要把机制 6 或其他玩法混进本模块提交。

## 2. 当前项目进度

基线已经完成 336 个剧情事件全流程、DOCX 行号开发者跳转、持续森林到瀑布舞台、ForestRun、TextInput、LakeJump、StarJar，以及独立模块高清 `SubViewport` 宿主。主流程的渐强世界震动范围仍为 DOCX 第 354–366 行，当前全流程验证会检查起点、峰值和复位。

`BlinkInteraction` 目前仍是 `module_skip`，因此当前任务只需要替换这个钩子并补齐绑定。不得另建第二套全局震动，也不要改写已验证的震动范围。开始前必须运行 `git status --short --branch`、`git diff --stat`、`git rev-parse HEAD`，确认基线和工作树状态。

## 3. 编码前先看懂现有风格

先运行 `Qimiaoye_DarkForest_TextOnly_V0.1`，用 F4 开发者跳转定位到 DOCX 第 360 行附近，完整看一遍世界晃动开始、双手松开、眨眼和随后追问之间的节奏。随后阅读：

- `README.md`
- `scripts/main.gd`
- `scripts/story_data.gd`
- `scripts/story_source_lock.gd`
- `scripts/narration_ui.gd`
- `scripts/dialogue_ui.gd`
- `scripts/text_reveal_profile.gd`

还要查看 ForestRun、LakeJump、StarJar 的现有嵌入方式，理解主流程如何加载独立场景、调用 `setup(event)`、等待完成信号并恢复剧情。

当前奇妙夜使用安静、克制、偏暗的视觉语言。全局字体优先 `Times New Roman`，中文回退 `SimSun / 宋体`；顶部旁白和底部对白完全分区。眨眼应当像梦境连接正在断裂的一瞬间，别做成白色闪光灯压力测试。

## 4. 剧情位置与功能目标

当前提交的 `scripts/story_data.gd` 中：

- DOCX 第 354 行开始，小凌问“我们以前是不是见过？”，全局屏幕抖动从轻微逐步增强。
- DOCX 第 358 行：世界开始晃动，小凌与女孩的手松开。
- DOCX 第 359 行：场景切到“两只手松开的特写”。
- DOCX 第 360 行：现为 `BlinkInteraction` 的 `module_skip`，这里是模块的唯一插入点。
- 下一条实际剧情事件是 DOCX 第 362 行：小凌追问“什么时候？在哪儿见过？”。模块完成后必须回到这一行。

行号不是靠截图猜的。编码前先在 `story_data.gd` 中按 `id="BlinkInteraction"` 和前后对白重新定位，并检查 `story_source_lock.gd`；当前基线应解析为第 360 行。如果以后上游 source 映射发生变化，以模块 ID、前后剧情锚点和来源锁三者共同确认，并在交付说明中写出新的实际行号，不要自行重排其他事件。

玩法目标：玩家完成一次简短、明确的眨眼交互，体验梦境画面闭合、短暂失联、再次睁开的过程。推荐用按住表示闭眼、松开表示睁眼，或使用等价且可访问的单次交互；节奏要可理解，不要靠猜。

主题是“梦境崩塌与失去连接”。模块内部不要显示第 362 行的对白，主对白系统会在返回后负责显示。

## 5. 模块契约

建议文件范围：

- `modules/blink_interaction/blink_interaction.tscn`
- `modules/blink_interaction/blink_interaction.gd`
- 必要的局部资源与独立测试文件

推荐根节点使用全屏 `Control`，并提供：

```gdscript
signal finished(result: Dictionary)

func setup(event: Dictionary) -> void:
    pass
```

完成结果建议为：

```gdscript
finished.emit({
    "result": "success",
    "blinks": 1
})
```

模块必须只发射一次完成信号。交互层使用 anchors、容器或视口相对布局；输入区域不能依赖固定桌面像素坐标。鼠标、Enter/Space 至少提供一种清楚的等价操作，避免只有某个外设才能继续。

## 6. 与全局晃动的边界

主剧情已从 DOCX 第 354 行开始控制渐强屏幕晃动，并持续到章节末尾。BlinkInteraction 可以做自身的闭眼遮罩和轻微局部运动，但不能创建第二套全局相机抖动，也不能在退出时把主流程的 shake 状态清零。否则两套 tween 会互殴，最后只剩玩家晕。

避免快速明暗闪烁。闭眼和睁眼建议分别使用约 `0.25–0.5` 秒的缓动，并设置低频、可预测的变化；不要使用高频白闪，以降低光敏风险。

## 7. 高清模块宿主边界

旧版本把嵌入模块放进逻辑尺寸为 `1280×720` 的 `SubViewport`，随后将这张 720p 纹理放大到高分辨率窗口，导致 ForestRun 在 1080p、1440p 等环境中明显发糊。

最新提交已经把“逻辑坐标尺寸”和“实际渲染纹理尺寸”拆开：模块仍按 `1280×720` 的逻辑坐标设计，内部渲染目标跟随实际输出分辨率并保持 16:9；2560×1440 导出版已完整验证。BlinkInteraction 必须满足：

- 窗口尺寸变化时遮罩仍完整覆盖模块画面。
- 不硬编码 `2560×1440` 等单一分辨率，不自行修改全局 stretch 设置。
- 在 `1280×720`、`1920×1080`、`2560×1440` 下，闭眼边缘、提示文字和输入区域保持一致。
- 只使用逻辑视口坐标；渲染像素密度由宿主控制。

## 8. 验收与交付

至少完成以下检查，并把命令输出保存到项目日志目录：

1. 从 DOCX 第 360 行进入，交互完成后由宿主继续到第 362 行。
2. 完成信号只发射一次，快速重复输入不会跳两次剧情。
3. 退出模块后，主流程的渐强晃动仍保持连续，没有被模块复位或叠加成双倍。
4. 三种 16:9 分辨率下遮罩无缝、文字不裁切、点击区域不漂移。
5. 没有高频闪烁；闭眼、停顿、睁眼的动画节奏可读。
6. 模块不改写前后剧情文本，也不改 ForestRun、LakeJump、StarJar 的逻辑。

交付时提供：

- 你的分支名与最终 commit SHA。
- 变更文件清单。
- 实际运行过的验证命令和日志路径。
- 尚未验证的风险。
- 给集成人员的一句明确说明：用哪个完成信号、返回什么 payload、是否需要新增资源白名单路径。

## 9. 实施状态与交付记录（2026-08-28 已实装）

本节记录本次推送的实际情况，供主程 agent 快速了解现状。**机制 6（HandInspect）不在本节范围内，本次未触碰其任何代码。**

### 9.1 落点

| 项 | 值 |
|---|---|
| 目标分支 | `codex/20260828-gespielt-grounded` |
| 集成分支 HEAD | `183b28c8763ddcef64b953658678ac770a219b6e`（merge commit） |
| 模块提交 | `b915fb5`，原建于 `codex/qimiaoye-blink-interaction`（基线 `c92bdad`） |
| 合并方式 | `--no-ff`；目标分支当时仅有 docs 提交，无代码冲突 |
| 推送状态 | **未推送**，待授权 |

### 9.2 变更文件清单（9 个文件，+900 行）

| 文件 | 说明 |
|---|---|
| `modules/blink_interaction/blink_interaction.gd` | 新增，模块本体（全屏 `Control`，1280×720 逻辑坐标） |
| `modules/blink_interaction/blink_interaction.tscn` | 新增，模块场景 |
| `modules/blink_interaction/blink_interaction.gd.uid` | 新增，编辑器生成 |
| `tests/blink_interaction_module_test.gd` | 新增，模块定向测试 |
| `tests/blink_interaction_module_test.tscn` | 新增，测试场景 |
| `tests/blink_interaction_module_test.gd.uid` | 新增，编辑器生成 |
| `scripts/story_data.gd` | 第 360 行 `module_skip` → `module` |
| `scripts/main.gd` | `EXPECTED_MODULE_BINDINGS` 注册 + 根节点/契约守卫（+5 行） |
| `README.md` | 绑定清单、操作说明、待实装模块列表 |

### 9.3 交互与时序

- 按住 `Space` / `Enter` / 鼠标左键 = 闭眼，松开 = 睁眼。单独单击也会完整走完一次闭眼—睁眼，保证键盘、鼠标、触控都能继续。
- 入场 0.45s（从两手紧握的暖光特写开始）→ 闭眼 0.40s → 最短停顿 0.16s → 睁眼 0.45s → 收尾 0.32s。
- 闭眼与睁眼均落在交接文档要求的 0.25–0.5 秒区间，无高频白闪。
- 局部漂移幅度 ≤ 4 逻辑像素，低频可预测；**不创建第二套全局相机抖动，不复位主流程 shake**。
- 25 秒无输入会走一次自动眨眼兜底，payload 中以 `auto_blink:true` 区分。

### 9.4 验证命令与结果

```powershell
$godot = "D:\gamejamshe\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe"
$proj  = "D:\gamejamshe\Peking26082026\worktrees\godot-dev\Qimiaoye_DarkForest_TextOnly_V0.1"

# 模块定向测试
& $godot --headless --path $proj res://tests/blink_interaction_module_test.tscn

# 全流程验证（三种 16:9 分辨率）
& $godot --headless --path $proj --resolution 1280x720  -- --verify
& $godot --headless --path $proj --resolution 1920x1080 -- --verify
& $godot --headless --path $proj --resolution 2560x1440 -- --verify
```

结果：

| 检查 | 结果 |
|---|---|
| 模块定向测试 | `BLINK_INTERACTION_MODULE_PASS source=360 finished_once=true blinks=1 resolution_cases=3 logical_viewport=1280x720 layout_relative=true flicker_safe=true` |
| 全流程 `--verify` | 1280×720 / 1920×1080 / 2560×1440 均 `FULL_FLOW_PASS` |
| 真实交互 360→362 | `BLINK_HOST_SMOKE_PASS module_complete=1 blinks=1 shake_start=1 shake_stop=0 real_interaction=true` |
| `git diff --check` | 干净 |

日志目录：`%APPDATA%\Qimiaoye_DarkForest_TextOnly_V0.1\logs\`（`runtime.log` / `trace_steps.log`）。

**注意**：`--verify` 模式下模块是**模拟完成**的（日志里会出现 `verification":"simulated_after_ready"`），无法证明真实交互链路。因此另写了临时脚手架，在不传 `--verify` 的情况下用 F4 跳到 360 行并真实按键驱动一次，确认：

```
MODULE_COMPLETE id=BlinkInteraction source=360 kind=playable
  result={"auto_blink":false,"blinks":1,"module":"BlinkInteraction","result":"success","source":360}
SHAKE_LEVEL source=362 progress=0.727 target_strength=13.01
LINE channel=DIALOGUE source=362 speaker=小凌（很着急地）text=什么时候？在哪儿见过？
```

`auto_blink:false` 证明是玩家真实输入完成，而非超时兜底；震动 9.79 → 13.01 持续增强，未被模块复位。该脚手架为临时文件，验证后已删除，不在提交内。

### 9.5 尚未验证的风险

1. **手部造型未经人眼确认。** 已用像素探针验证渲染正确（闭眼时 `warm_px=0`，四角遮罩取样值一致 `0.02,0.02,0.04`，无漏光），但"两只手看起来像不像手"属于视觉判断，本次无法给出结论。建议实机确认：`F4` → 输入 `360` → 从此行开始。
2. **闭眼期间世界仍在低频漂移。** 这是刻意保留的效果；若与主流程 shake 叠加后观感不适，把 `_current_drift()` 返回值改为 `Vector2.ZERO` 即可关闭。
3. **触控路径未实机验证**，仅走通了 `_gui_input` 中的 `InputEventScreenTouch` 分支。
4. 三种分辨率均在 headless 下验证，未覆盖导出包的实机窗口缩放行为。

### 9.6 给集成人员的一句话

完成信号用 `finished(result: Dictionary)`，宿主以 `CONNECT_ONE_SHOT` 接收，payload 为
`{"result":"success","blinks":1,"source":360,"auto_blink":false}`（宿主会补一个 `module` 字段）；
**无需新增资源白名单路径**——手部与遮罩全部由 `_draw()` 程序化绘制，模块目录内没有任何图片资源，因此 `ALLOWED_MODULE_IMAGE_ROOTS` 保持原样即可。

### 9.7 遗留项

`docs/agent_start/AGENTS.md` 中机制 6 与机制 7 的复选框（`- [ ]`）尚未勾选。机制 6 的提交未更新该文档，机制 7 本次也未改动它，以免在功能提交里夹带 docs 变更。需要时可单独补一个 docs 提交把两格一起勾掉。
