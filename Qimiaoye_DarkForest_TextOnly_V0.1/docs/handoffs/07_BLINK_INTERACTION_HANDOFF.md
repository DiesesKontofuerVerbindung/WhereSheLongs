# 机制 7 交接：BlinkInteraction（眨眼互动）

## 1. 固定起点

这是一项独立模块开发任务。开始编码前必须取得并核对下面的基线：

- 仓库：`https://github.com/DiesesKontofuerVerbindung/Peking26082026.git`
- 基线分支：`codex/qimiaoye-demo`
- 必须阅读的最新提交：`5fbf87e636d26fa80dfabb4090bfe51dc695af71`
- 当前效果参考：`C:\Users\27532\Desktop\Gespielt.exe`（版本 `1.2.0.0`，SHA-256 `72175B99FF7F3254BF2693543411C6E7FF4BBF30832AD6FF1159B4D233610AC6`）
- 建议工作分支：`codex/qimiaoye-blink-interaction`

建议命令：

```powershell
git fetch origin
git worktree add ..\qimiaoye-blink-interaction -b codex/qimiaoye-blink-interaction 5fbf87e636d26fa80dfabb4090bfe51dc695af71
git -C ..\qimiaoye-blink-interaction rev-parse HEAD
```

最后一条命令必须输出完整提交号 `5fbf87e636d26fa80dfabb4090bfe51dc695af71`。`Gespielt.exe` 只用于观察当前风格和运行效果，源码权威仍是该提交。不要直接在集成分支上开发，也不要把机制 6 或其他玩法混进本模块提交。

## 2. 编码前先看懂现有风格

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

## 3. 剧情位置与功能目标

当前提交的 `scripts/story_data.gd` 中：

- DOCX 第 354 行开始，小凌问“我们以前是不是见过？”，全局屏幕抖动从轻微逐步增强。
- DOCX 第 358 行：世界开始晃动，小凌与女孩的手松开。
- DOCX 第 359 行：场景切到“两只手松开的特写”。
- DOCX 第 360 行：现为 `BlinkInteraction` 的 `module_skip`，这里是模块的唯一插入点。
- 下一条实际剧情事件是 DOCX 第 362 行：小凌追问“什么时候？在哪儿见过？”。模块完成后必须回到这一行。

行号不是靠截图猜的。编码前先在 `story_data.gd` 中按 `id="BlinkInteraction"` 和前后对白重新定位，并检查 `story_source_lock.gd`；当前基线应解析为第 360 行。如果以后上游 source 映射发生变化，以模块 ID、前后剧情锚点和来源锁三者共同确认，并在交付说明中写出新的实际行号，不要自行重排其他事件。

玩法目标：玩家完成一次简短、明确的眨眼交互，体验梦境画面闭合、短暂失联、再次睁开的过程。推荐用按住表示闭眼、松开表示睁眼，或使用等价且可访问的单次交互；节奏要可理解，不要靠猜。

主题是“梦境崩塌与失去连接”。模块内部不要显示第 362 行的对白，主对白系统会在返回后负责显示。

## 4. 模块契约

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

## 5. 与全局晃动的边界

主剧情已从 DOCX 第 354 行开始控制渐强屏幕晃动，并持续到章节末尾。BlinkInteraction 可以做自身的闭眼遮罩和轻微局部运动，但不能创建第二套全局相机抖动，也不能在退出时把主流程的 shake 状态清零。否则两套 tween 会互殴，最后只剩玩家晕。

避免快速明暗闪烁。闭眼和睁眼建议分别使用约 `0.25–0.5` 秒的缓动，并设置低频、可预测的变化；不要使用高频白闪，以降低光敏风险。

## 6. 当前正在修的分辨率问题

旧版本把嵌入模块放进逻辑尺寸为 `1280×720` 的 `SubViewport`，随后将这张 720p 纹理放大到高分辨率窗口，导致 ForestRun 在 1080p、1440p 等环境中明显发糊。

最新提交已经把“逻辑坐标尺寸”和“实际渲染纹理尺寸”拆开：模块仍按 `1280×720` 的逻辑坐标设计，内部渲染目标跟随实际输出分辨率并保持 16:9；2560×1440 导出版已完整验证。BlinkInteraction 必须满足：

- 窗口尺寸变化时遮罩仍完整覆盖模块画面。
- 不硬编码 `2560×1440` 等单一分辨率，不自行修改全局 stretch 设置。
- 在 `1280×720`、`1920×1080`、`2560×1440` 下，闭眼边缘、提示文字和输入区域保持一致。
- 只使用逻辑视口坐标；渲染像素密度由宿主控制。

## 7. 验收与交付

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
