# HandInspect：封装修订与 Fast-forward 交付

## 1. 目标

将 `codex/qimiaoye-hand-inspect` 重写为 grounded 最新提交之上的**单一封装提交**。最终提交只交付可独立实例化、可独立测试的 HandInspect 模块，不提前修改主流程绑定；集成分支之后必须能够使用 `git merge --ff-only` 接收它。

目标拓扑：

```text
grounded 最新提交
└── HandInspect 单一实现提交（重放并 amend 后的新 SHA）
```

旧提交 `c6d38e7e3e04e0cf31b988469007e5ea21620500` 的父提交是 `c92bdad0beac9391c83b293bd2f708622a28c986`。它与 grounded 已经分叉，单独执行 `git commit --amend` 不会改变父提交，因此不能形成 fast-forward。必须先把实现提交重放到 grounded 最新 tip，再将所有修订压入该实现提交。

## 2. 当前提交审查结论

### 阻断项

1. `scripts/main.gd` 与 `scripts/story_data.gd` 被提前修改，模块封装和主流程拼接混在同一提交里。最终实现提交必须让这两个文件与其父提交完全一致。
2. 三个热点全部查看后，实际界面没有按钮、键盘输入或自动路径调用 `request_finish()`。当前测试直接调用内部方法，因此测试通过也会在真实玩法中卡死。

### 必修项

1. 增加明确的完成入口。采用可见的 `FinishButton`：查看未完成时禁用，三个热点全部查看后启用；按下后调用已有的单次完成保护并发射 `finished(result)`。
2. 增加可见的细节反馈区域。点击戒指、掌纹、伤疤后，必须显示对应标题和 `SPOT_DETAIL` 文本；当前这组常量存在但从未进入 UI。
3. 修正热点与手部绘制的几何关系。当前伤疤热点位于约 `x=0.66..0.80`，程序化手掌主体约位于 `x=0.40..0.60`，视觉标记漂在手外。热点位置和点击区域必须落在实际绘制部位上。
4. 测试必须覆盖真实 UI 路径：通过 `Hotspot_*` 节点的 `gui_input` 完成三次点击，再通过 `FinishButton.pressed` 完成模块；不能只直接调用 `inspect_spot()` 和 `request_finish()`。
5. 保留现有三分辨率布局、热点去重、未完成保护、完成信号仅一次和 payload 检查。

## 3. 最终提交边界

最终 `HEAD^..HEAD` 只允许包含以下 6 个新增文件：

```text
Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.gd
Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.gd.uid
Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.tscn
Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.gd
Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.gd.uid
Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.tscn
```

以下内容由后续集成提交负责，本提交保持与父提交一致：

```text
Qimiaoye_DarkForest_TextOnly_V0.1/scripts/main.gd
Qimiaoye_DarkForest_TextOnly_V0.1/scripts/story_data.gd
Qimiaoye_DarkForest_TextOnly_V0.1/scripts/story_source_lock.gd
Qimiaoye_DarkForest_TextOnly_V0.1/project.godot
```

模块继续提供稳定接口：

```gdscript
signal finished(result: Dictionary)

func setup(event: Dictionary) -> void:
    pass
```

完成 payload 至少保留：

```gdscript
{
    "result": "success",
    "inspected": ["ring", "palm_lines", "scar"],
    "source": 353,
    "spot_count": 3,
}
```

## 4. 重写与 amend 流程

在 `codex/qimiaoye-hand-inspect` 的独立、干净 worktree 中执行。不要在有未提交改动的 grounded worktree 中切换分支。

```powershell
git fetch origin
git status --short --branch

$groundedBase = git rev-parse origin/codex/20260828-gespielt-grounded
$oldBase = "c92bdad0beac9391c83b293bd2f708622a28c986"

git rebase --onto $groundedBase $oldBase codex/qimiaoye-hand-inspect
git rev-parse HEAD^
```

`git rev-parse HEAD^` 必须等于 `$groundedBase`。随后把提前拼接的两个底座文件恢复为新父提交版本：

```powershell
git restore --source=HEAD^ -- `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/main.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/story_data.gd
```

完成本文件第 2 节要求的代码和测试修订后，显式暂存模块文件、测试文件以及上面两个恢复文件，再 amend 当前实现提交。两个恢复文件必须进入暂存区，否则旧提交中的提前拼接仍会留在 amend 结果里。

```powershell
git add -- `
  Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.gd.uid `
  Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.tscn `
  Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.gd.uid `
  Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.tscn `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/main.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/story_data.gd

git commit --amend
```

提交说明必须删除“已替换 DOCX 353 的 `module_skip`”“已修改宿主绑定”等不再成立的描述，明确这是等待集成的独立模块。

## 5. 验证门槛

### 模块测试

运行 HandInspect 定向场景，日志保存到仓库的 `tmp/codex_logs`。测试至少证明：

- 三个真实热点节点都可通过 GUI 输入查看；
- 每次查看显示对应细节文本；
- `FinishButton` 在 0/3、1/3、2/3 时禁用，在 3/3 时启用；
- 从真实按钮路径完成后，`finished(result)` 恰好发射一次；
- 1280×720、1920×1080、2560×1440 下热点、点击区和绘制位置一致；
- payload 字段和值符合第 3 节契约。

### 底座完整性

```powershell
git diff --exit-code HEAD^ -- `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/main.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/story_data.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/scripts/story_source_lock.gd `
  Qimiaoye_DarkForest_TextOnly_V0.1/project.godot

git diff --check HEAD^..HEAD
git diff --name-status HEAD^..HEAD
```

`git diff --name-status HEAD^..HEAD` 必须只列出第 3 节的 6 个新增文件。

### Fast-forward 拓扑

```powershell
$groundedBase = git rev-parse origin/codex/20260828-gespielt-grounded
git merge-base --is-ancestor $groundedBase HEAD
git rev-parse HEAD^
git rev-list --left-right --count "$groundedBase...HEAD"
```

验收结果必须满足：

- `merge-base --is-ancestor` 退出码为 0；
- `HEAD^` 等于 grounded 最新 tip；
- ahead/behind 输出为 `0 1`；
- 最终集成人员在干净 grounded worktree 中执行 `git merge --ff-only codex/qimiaoye-hand-inspect` 可以成功。

## 6. 远端更新

rebase 与 amend 都会产生新 SHA。全部验证通过后，使用带租约的历史更新，避免覆盖别人刚推送的新提交：

```powershell
git push --force-with-lease origin codex/qimiaoye-hand-inspect
```

交付时报告：grounded 基线 SHA、旧实现 SHA `c6d38e7`、新实现 SHA、测试命令与日志路径，以及 `0 1` 的拓扑验证结果。
