# 交接｜婚礼前夜章节·美术底图接入

本文档给下一个 Agent 说明：**本次提交在婚礼前夜章节做了什么、边界是什么、还差什么**。避免重复实现，也避免误以为整章美术已完成。

## 0. 一句话现状

婚礼前夜章节的 **4 张场景底图已接入并验证通过**（`assets/backgrounds/wedding/`），其余美术（誓词卡/手机模块 UI、角色立绘、多余备选图）**未做**，属于可选项/后续。

## 1. 本次提交做了什么

- 在 `scripts/wedding_prologue.gd` 的舞台层 `WeddingStage` 下、两个占位 Label 之下新增 `WeddingSceneTexture`（TextureRect）。
  - 全屏 + 外扩 `SCENE_TEXTURE_OVERSCAN = 64px` 过扫描：剧情震动最大 26px，不会露出边缘。
  - `EXPAND_IGNORE_SIZE` + `STRETCH_KEEP_ASPECT_COVERED`：3:2 源图适配 16:9 视口（上下裁 ~11%），无黑边、不变形。
  - `mouse_filter = IGNORE`，不拦截点击。
- 重写 `_set_scene(scene_name)`：按场景名查 `_scene_texture_paths` 字典 → `ResourceLoader.exists()` + `load()` 双重判断。
  - 有图：切底图、清空占位 Label。
  - 没图 / 加载失败（含导入缓存损坏）：**保留文字占位回退，不黑屏**。
  - 字典键直接引用 `WeddingDataScript` 的场景常量（单一数据源），改场景名不脱同步。

### 4 张场景底图映射

| 场景常量 | 文件（`assets/backgrounds/wedding/`） | 源图 | 剧情位置 |
|---|---|---|---|
| `SCENE_WEDDING_1` 婚礼背景图1 | `wedding_1.png` | 婚礼宴会厅.png | DOCX 2，开场 |
| `SCENE_WEDDING_2` 婚礼背景图2 | `wedding_2.jpg` | 婚礼场景·全部勾选的清单.jpg | DOCX 18，后半 |
| `SCENE_CAR` 车上背景图 | `car.png` | 车里看城市外景.png | DOCX 47 |
| `SCENE_HOME` 家里场景 | `home.png` | 晚上在家里的客厅.png | DOCX 105 |

源图来自压缩包 `森林前.zip`，解压在 `D:\gamejamshe\森林前_解压\`。

## 2. 验证结果（文档 08 §7 两条，全图状态，均 exit 0）

```
WEDDING_PROLOGUE_PASS events=146 scenes=4 sources=140 modules=2 interactions=1 endpoint=true
  narration_lines=28 dialogue_lines=96 advance_gated=true dev_docx_jump=true
  dev_jump_chapters=wedding_mystic_night_forest wedding_source_bounds=(2, 145)
WEDDING_ADVANCE_GATE_PASS narration_and_dialogue_gated=true enter_advances=true hint_follows_gate=true
```

日志在 `tmp/codex_logs/`。回退路径（无图）与有图路径均验证过。

## 3. 提交与分支

- 分支：`codex/20260829-lake-stone-route`（worktree `worktrees/qimiaoye-wedding-art`）
- 基础：`8f7cc96`（贡献者补推的奇妙夜章节，修复了 5d1c0e1 缺 `mystic_night_data.gd` 跑不起来的问题）
- 本次产出：1 个新提交（含 `wedding_prologue.gd` + 4 素材及 `.import` + 本文档）

## 4. 边界 —— 明确没做 / 留给下一位的

**本次只做了文档 08 明确要求的"接美术"最小闭环：4 张场景底图。** 以下均未做，按需接：

1. **誓词卡模块美术**（`WeddingVowSolo`，DOCX 21）：文档说"可以接卡片美术"。候选源图 `小道具白色a4纸.jpg`。
2. **手机通知模块 UI**（`PhoneNotifications`，DOCX 32）：文档说"可以接手机 UI 美术"。候选源图 `小道具婚戒.jpg`。
3. **角色立绘**：**当前 `dialogue_ui.gd` 只有说话人名字 Label，没有立绘位**。要做立绘必须改共用 UI（`dialogue_ui.gd`），会影响森林正片，改完两边都要跑验证。**建议下一轮再评估**。候选源图 `婚礼司仪.jpg`。
4. **未使用的备选图**：`婚礼场景 上面有个最后1项没勾选的清单.jpg`、`婚礼场景 上面有个最后2项没勾选的清单.jpg`（清单递进态，若做誓词卡逐句勾选进度可用）。
5. **3:2→16:9 裁切视觉效果**：本次用 `KEEP_ASPECT_COVERED`，上下各裁 ~11%。**实测手感需人工确认**（接入方本地无视觉能力，未做像素级校验）。若某张裁掉关键内容，改 `STRETCH_KEEP_ASPECT`（留边）或按场景单独偏移。

## 5. 下一位 Agent 建议开工前先读

- `docs/handoffs/08_WEDDING_PROLOGUE_ART_HANDOFF.md`（本次工作的母文档，环境/文件地图/红线都在里面）
- `scripts/wedding_prologue.gd`（`_scene_texture_paths` 字典 + `_set_scene()` + `_build_ui()` 舞台段）
- `scripts/wedding_data.gd`（场景常量，改前注意别动剧本 `text`）
- `scenes/wedding/wedding_prologue.tscn`

## 6. 红线（继承文档 08 §9）

- 不要 `git reset --hard` / `git clean` / 广义 `git checkout --` / `git add .` / `git add -A`。仓库根有大量无关未跟踪素材，必须保留。
- 不要改 `project.godot` 的 `run/main_scene`（森林验证与打包依赖它）。
- 不要把婚礼事件混进 `scripts/story_data.gd`（森林硬断言 `events=336` / `source_bounds=(29,366)` / `docx_source_lock`）。
- `narration_ui.gd` / `dialogue_ui.gd` / `dev_jump_panel.gd` 是森林共用文件，改前想清楚、改完两边都验；婚礼专属样式加在 `wedding_prologue.gd`。
- 大量 `.import` 会显示 modified 但 diff 为 0，是行尾符噪声，**不要提交它们**（提交用显式 `git add <path>`，禁用 `git add -A`）。
- 剧本文字（`wedding_data.gd` 的 `text`）不要改写、润色、补写。有问题先问。
