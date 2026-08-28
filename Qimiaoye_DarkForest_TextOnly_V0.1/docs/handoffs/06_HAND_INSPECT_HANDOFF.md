# 机制 6 交接：HandInspect（手部查看）

## 1. 固定起点

这是一项独立模块开发任务。开始编码前必须取得并核对下面的基线：

- 仓库：`https://github.com/DiesesKontofuerVerbindung/Peking26082026.git`
- 基线分支：`codex/qimiaoye-demo`
- 必须阅读的最新提交：`5fbf87e636d26fa80dfabb4090bfe51dc695af71`
- 当前效果参考：`C:\Users\27532\Desktop\Gespielt.exe`（版本 `1.2.0.0`，SHA-256 `72175B99FF7F3254BF2693543411C6E7FF4BBF30832AD6FF1159B4D233610AC6`）
- 建议工作分支：`codex/qimiaoye-hand-inspect`

建议命令：

```powershell
git fetch origin
git worktree add ..\qimiaoye-hand-inspect -b codex/qimiaoye-hand-inspect 5fbf87e636d26fa80dfabb4090bfe51dc695af71
git -C ..\qimiaoye-hand-inspect rev-parse HEAD
```

最后一条命令必须输出完整提交号 `5fbf87e636d26fa80dfabb4090bfe51dc695af71`。`Gespielt.exe` 只用于观察当前风格和运行效果，源码权威仍是该提交。不要直接在集成分支上开发，也不要把其他机制顺手塞进同一次提交。

## 2. 编码前先看懂现有风格

先运行 `Qimiaoye_DarkForest_TextOnly_V0.1`，用 F4 开发者跳转定位到 DOCX 第 353 行附近，完整看一遍模块前后的剧情节奏。随后阅读：

- `README.md`
- `scripts/main.gd`
- `scripts/story_data.gd`
- `scripts/story_source_lock.gd`
- `scripts/narration_ui.gd`
- `scripts/dialogue_ui.gd`
- `scripts/text_reveal_profile.gd`

还要查看 ForestRun、LakeJump、StarJar 的现有嵌入方式，理解主流程如何加载独立场景、调用 `setup(event)`、等待完成信号并回到下一条剧情。

当前奇妙夜的基调是安静、克制、偏暗的文字叙事。全局字体优先 `Times New Roman`，中文回退 `SimSun / 宋体`；旁白在顶部独立区域，对白和心理文字在底部对白区域。新模块应像这个世界里原本就存在的一段交互，别突然长成手游签到页。

## 3. 剧情位置与功能目标

当前提交的 `scripts/story_data.gd` 中：

- DOCX 第 351 行：小凌抓住女孩的手，查看手上的细节点位。
- DOCX 第 352 行：场景切到“剧情图-手”。
- DOCX 第 353 行：现为 `HandInspect` 的 `module_skip`，这里是模块的唯一插入点。
- DOCX 第 354 行：小凌说“我们以前是不是见过？”。模块完成后必须回到这一行，由主对白系统显示。

行号不是靠截图猜的。编码前先在 `story_data.gd` 中按 `id="HandInspect"` 和前后对白重新定位，并检查 `story_source_lock.gd`；当前基线应解析为第 353 行。如果以后上游 source 映射发生变化，以模块 ID、前后剧情锚点和来源锁三者共同确认，并在交付说明中写出新的实际行号，不要自行重排其他事件。

玩法要求：

1. 玩家查看女孩手上的三个细节点：戒指、掌纹、伤疤。
2. 每个点被查看后给出克制、清楚的状态反馈。
3. 三个点全部查看后允许完成交互。
4. 完成信号只发射一次，随后由集成层继续 DOCX 第 354 行。

主题是“身体细节触发身份记忆”。模块内部不要抢先显示“我们以前是不是见过？”这句对白，否则合并后会重复。

## 4. 模块契约

建议文件范围：

- `modules/hand_inspect/hand_inspect.tscn`
- `modules/hand_inspect/hand_inspect.gd`
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
    "inspected": ["ring", "palm_lines", "scar"]
})
```

热点布局必须基于 anchors、容器或视口相对位置；不要依赖某一台电脑上的绝对屏幕坐标。模块所需图片应只放入自己的目录，交接时列出资源根目录。若集成层需要更新图片白名单，由集成人员做精确增补，别把允许范围一把扩到整个项目。

## 5. 当前正在修的分辨率问题

旧版本把嵌入模块放进逻辑尺寸为 `1280×720` 的 `SubViewport`，再由外层画布放大到高分辨率窗口。这样会把已经以 720p 渲染好的纹理二次放大，ForestRun 在 1080p、1440p 等高分辨率下明显发糊。

最新提交已经把“逻辑坐标尺寸”和“实际渲染纹理尺寸”拆开：模块仍按 `1280×720` 的逻辑坐标设计，内部渲染目标会跟随实际输出分辨率并保持 16:9；2560×1440 导出版已完整验证。HandInspect 必须遵守以下兼容要求：

- 能在运行中收到窗口尺寸变化后重新布局。
- 不硬编码某个显示器分辨率，也不自行修改全局 stretch 设置。
- 不用 nearest filtering 假装解决清晰度问题。
- 在 `1280×720`、`1920×1080`、`2560×1440` 下热点位置、文字和点击区域一致可用。
- 只依赖逻辑视口坐标；渲染像素密度由宿主负责。

## 6. 验收与交付

至少完成以下检查，并把命令输出保存到项目日志目录：

1. 三个热点均可单独查看，重复点击不会重复计数。
2. 未查看全部热点时不能误完成。
3. 全部查看后只发射一次 `finished(result)`。
4. 三种 16:9 分辨率下布局不漂移、不裁切，点击区域与画面一致。
5. 从 DOCX 第 353 行进入，完成后可由宿主继续到第 354 行。
6. 模块不改写前后剧情文本，也不改 ForestRun、LakeJump、StarJar 的逻辑。

交付时提供：

- 你的分支名与最终 commit SHA。
- 变更文件清单。
- 实际运行过的验证命令和日志路径。
- 尚未验证的风险。
- 给集成人员的一句明确说明：用哪个完成信号、返回什么 payload、需要新增哪些资源白名单路径。
