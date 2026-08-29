# 奇妙夜 · 章节三 · 典礼上的选择

Godot 4.7.2 视觉小说章节，按 `0829全剧本V2_美术音效需求新.docx` 第 916–1168 行接入。

## 打开方式

用同目录引擎 `03_Godot_4.7.2_引擎/Godot_v4.7.2-stable_win64.exe` 打开本文件夹。
首次打开或用脚本替换图片后，需要执行一次资源导入：

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --editor --quit --path .
```

这会在工程目录生成 `.godot/imported/`，运行时才能加载 PNG/JPG 背景。

## 场景美术

| 行号范围 | 内容 | 资源 |
| --- | --- | --- |
| 916–923 | 卧室/客厅（妈妈叫醒小凌） | 视频 `assets/videos/opening_video.ogv`（4.48s），播放中按 Enter/Space/Esc 可跳过 |
| 923–933 | 场景转换后的妈妈 | `assets/backgrounds/场景转换后的妈妈.png`（视频播完即切到这里并停住） |
| 934–943 | 正式婚礼现场 | `assets/backgrounds/正式婚礼现场.png` |
| 943–962 | 婚礼会场外静谧走廊 | `assets/backgrounds/静谧走廊.png` |
| 962–1074 | 小凌思羽窗边谈话 | `assets/backgrounds/小凌思羽窗边谈话.png` |
| 1078–1097 | 结局 A：小凌思羽窗边谈话-1 | `assets/backgrounds/小凌思羽窗边谈话-1.png` |
| 1100–1106 | 结局 A：带头纱的婚礼现场 | `assets/backgrounds/结局A带头纱的婚礼现场.jpg` |
| 1107 | 结局 A：不带头纱结婚照 | `assets/backgrounds/结局A不带头纱结婚照.jpg` |
| 1112–1122 | 结局 B：小凌思羽窗边谈话 | `assets/backgrounds/小凌思羽窗边谈话.png` |
| 1123–1130 | 结局 B：光腿在地毯上奔跑 | `assets/backgrounds/结局B 光腿在地毯上奔跑.png` |
| 1131 | 结局 B：阳光下奔跑 | `assets/backgrounds/结局BC阳光下奔跑.png` |
| 1135–1163 | 结局 C：小凌思羽窗边谈话-2 | `assets/backgrounds/小凌思羽窗边谈话-2.png` |
| 1164–1167 | 结局 C：光腿在地毯上奔跑-1 | `assets/backgrounds/结局B 光腿在地毯上奔跑-1.png` |
| 1168 | 结局 C：女主离开，思羽看着她 | `assets/backgrounds/结局C女主离开，思羽看着她.png` |

## 人物立绘

由于新背景图已自带人物，这些立绘当前未显示：
- 小凌婚纱：`assets/characters/xiaoling_bride.png`
- 思雨：`assets/characters/siyu.png`
- 妈妈：`assets/characters/mom.png`

## 界面布局

- **顶部居中**：旁白（环境描写、动作描述、结局标题）
- **底部**：对白框（说话人 + 台词）
- **屏幕中间**：只有背景画面，没有任何占位文字

原本显示在屏幕中间的场景标签、副标题、动作描述已全部移除。
动作描写（如「妈妈的一只戴着戒指的手伸过来…」）改为顶部旁白呈现，
因此数据里已不存在 `action` 类型事件，全部是 `line`。

## 操作

- Enter / Space：推进对话（自动推给当前等待推进的那条通道）；播放视频时按它可跳过
- Esc：跳过视频 / 关闭回溯面板
- F4：开发者 DOCX 行回溯面板

## 视频播放说明

Theora（`.ogv`）在 Godot 4.7 上实测 `finished` 信号不触发、`is_playing()` 播完也不回落，
所以结束判定走已知时长 + 真实时钟，不依赖播放器状态，也不会出现「定格后卡住」。
新增视频时把时长写进 `chapter3_stage.gd` 的 `VIDEO_OPENING_SECONDS` 附近常量即可。

## 三分支结局

- A：走进婚礼
- B：取消婚礼
- C：暂缓婚礼

## 验证

无头验证（默认走 A）：

```bash
Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --verify
```

验证指定分支：

```bash
-- --verify --choice=A
-- --verify --choice=B
-- --verify --choice=C
```

调试开关（可叠加）：

- `--trace`：打印事件流水、每 2 秒一次看门狗、视频起止耗时
- `--auto`：自动推进对话、自动选第一个分支，无人值守跑完整章

```bash
-- --trace --auto --choice=A
```
