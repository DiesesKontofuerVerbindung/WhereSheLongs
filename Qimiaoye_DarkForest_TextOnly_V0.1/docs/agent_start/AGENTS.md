# 机制 6 / 7 开工说明

本文件是 HandInspect 与 BlinkInteraction 两项独立模块任务的开工入口。两项任务共享同一基线，但必须使用两个独立分支或 worktree；不要把两个模块混进同一次实现提交。

## 待办

- [x] **6｜手部查看 `HandInspect`** — 模块已交付，待集成
  - Hook：抓住女孩的手 → 查看戒指、掌纹、伤疤三个细节点 → “我们以前是不是见过？”
  - 主题：通过身体细节触发身份记忆。
  - 模块本体与测试已合入 grounded（`5ec354d`）；**DOCX 353 行仍是 `module_skip`，玩家暂玩不到**。
  - 待办与接线方式见 `docs/handoffs/06_HAND_INSPECT_INTEGRATION_STATUS.md`。
- [x] **7｜眨眼互动 `BlinkInteraction`** — 已合入 grounded（`b915fb5` / `183b28c`）
  - Hook：世界震动、双手松开 → 眨眼互动 → 小凌急问“什么时候？在哪儿见过？”
  - 主题：梦境崩塌与失去连接。

## 权威基线

- 仓库：`https://github.com/DiesesKontofuerVerbindung/Peking26082026.git`
- 基线分支：`codex/20260828-gespielt-grounded`
- 开工 commit：`c92bdad0beac9391c83b293bd2f708622a28c986`
- Godot 工程：`Qimiaoye_DarkForest_TextOnly_V0.1`
- 桌面参考构建：`C:\Users\27532\Desktop\Gespielt.exe`
- 参考版本：`1.3.8.0`
- 参考 SHA-256：`F10756C26F36B81AB36D0059E4CAC3E36D16FA3754347F7005FC52A2A9ADC963`
- 本地验证日志目录：`D:\PEKING26082026\tmp\codex_logs`

开始工作前必须完整阅读对应交接文档：

- `docs/handoffs/06_HAND_INSPECT_HANDOFF.md`
- `docs/handoffs/07_BLINK_INTERACTION_HANDOFF.md`

## 开工检查

先运行并保存结果：

```powershell
git status --short --branch
git diff --stat
git rev-parse HEAD
git branch --show-current
```

`git rev-parse HEAD` 必须输出 `c92bdad0beac9391c83b293bd2f708622a28c986`。如果工作树已有修改，先辨认归属；不要 reset、clean、覆盖或顺手提交其他人的文件。

建议分别建立：

- `codex/qimiaoye-hand-inspect`
- `codex/qimiaoye-blink-interaction`

## 当前项目状态

- 336 个剧情事件可完整运行到第 366 行章节终点。
- F4 开发者模式可以按 DOCX source 行定位；定位时必须同时核对 `scripts/story_data.gd` 与 `scripts/story_source_lock.gd`。
- 已实装：ForestRun（122）、TextInput（157）、LakeJump（193）、StarJar（238）、
  BlinkInteraction（360，已接线）。
- HandInspect（353）：模块与测试已交付并合入 grounded，但**尚未接线**，当前仍为 `module_skip`。
  接线缺口与步骤见 `docs/handoffs/06_HAND_INSPECT_INTEGRATION_STATUS.md`。
- HandInspect 完成后回到第 354 行，由主对白显示“我们以前是不是见过？”。
- BlinkInteraction 完成后回到第 362 行，由主对白显示“什么时候？在哪儿见过？”。
- 模块宿主使用 `1280×720` 逻辑坐标和随输出分辨率变化的高清渲染纹理；不得修改全局 stretch 或硬编码桌面分辨率。
- 主流程已负责第 354–366 行的渐强世界震动；BlinkInteraction 不得创建或复位第二套全局 shake。

## 实现边界

- 每个模块使用独立场景、脚本、资源目录和测试文件。
- 根节点优先使用全屏 `Control`，布局采用 anchors、容器和视口相对坐标。
- 对外保留 `setup(event: Dictionary)` 与单次 `finished(result: Dictionary)` 契约。
- 模块完成 payload 只返回必要状态，不放入玩家原始输入、敏感内容或大型资源对象。
- 不改 ForestRun、TextInput、LakeJump、StarJar、持续森林舞台或前后剧情文本。
- 不按旧截图硬编码行号；按模块 ID、前后剧情锚点和 source lock 三重确认。

## 完成标准

完成全部实现后再统一测试。至少包含模块定向测试、三种 16:9 分辨率布局检查、主流程跳入/返回检查和完整 `--verify`。日志写入 `tmp/codex_logs`，最后运行 `git diff --check` 并审阅范围。

交付必须列出：分支、commit SHA、变更文件、真实测试命令、日志路径、未验证风险，以及集成时需要替换的 `module_skip` 和新增资源白名单路径。
