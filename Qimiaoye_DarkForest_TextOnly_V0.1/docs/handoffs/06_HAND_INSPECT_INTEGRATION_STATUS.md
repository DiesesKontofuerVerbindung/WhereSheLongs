# HandInspect：已交付内容与待集成缺口

本文件给后续 agent 说明：**机制 6 已经交付了什么、还差什么、怎么接上**。
避免重复实现，也避免误以为主线里已经能玩到这个模块。

## 0. 一句话现状

模块本体与测试**已合入 `codex/20260828-gespielt-grounded`**，但 **尚未挂到主线剧情上**：
DOCX 第 353 行仍是 `module_skip`，玩家现在**玩不到**这个模块。

## 1. 已交付内容

- 分支：`codex/20260828-gespielt-grounded`
- 提交：`5ec354de3d41a5409e825083b39e53ea73df021e`
- 提交标题：`feat(qimiaoye): 交付可独立测试的 HandInspect 模块（等待集成）`
- 变更：6 个新增文件，692 行

```text
Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.gd        (+345)
Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.gd.uid
Qimiaoye_DarkForest_TextOnly_V0.1/levels/minigames/hand_inspect.tscn
Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.gd       (+327)
Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.gd.uid
Qimiaoye_DarkForest_TextOnly_V0.1/tests/hand_inspect_module_test.tscn
```

### 模块能力（已实装并通过测试）

- 根节点：全屏 `Control`
- 契约：`setup(event: Dictionary)` + 单次 `finished(result: Dictionary)`
- 三个热点：`ring` 戒指、`palm_lines` 掌纹、`scar` 伤疤，去重计数
- 完成入口：`FinishButton`，0/3、1/3、2/3 禁用，3/3 启用，按下走单次完成保护
- 细节反馈：`DetailLabel`，查看后显示【标题】+ 细节文本
- 布局：归一化坐标 × `size`，响应 `resized`，1280×720 / 1920×1080 / 2560×1440 一致
- 资源：程序化绘制手与标记，**不新增任何图片资源**

### 关键节点名（集成与测试依赖）

| 节点名 | 类型 | 作用 |
|---|---|---|
| `Hotspot_ring` | Control | 戒指点击区 |
| `Hotspot_palm_lines` | Control | 掌纹点击区 |
| `Hotspot_scar` | Control | 伤疤点击区 |
| `FinishButton` | Button | 完成入口，未按完三处时 disabled |
| `DetailLabel` | Label | 细节文本反馈 |

### 对外接口

```gdscript
signal finished(result: Dictionary)
const VIEW_SIZE := Vector2(1280.0, 720.0)
const HOTSPOT_IDS: Array[String] = ["ring", "palm_lines", "scar"]

func setup(event: Dictionary) -> void
func verify_contract() -> bool
func inspect_spot(spot_id: String) -> bool      # 仅新建时 true
func get_inspected_ids() -> PackedStringArray
func get_inspect_count() -> int
func is_complete() -> bool
func can_finish() -> bool
func request_finish() -> bool                    # 单一发射保护
func get_hotspot_rects() -> Dictionary
func get_source() -> int
func get_emit_count() -> int
```

### 完成 payload

```gdscript
{
    "result": "success",
    "inspected": ["ring", "palm_lines", "scar"],
    "source": 353,
    "spot_count": 3,
}
```

### 测试命令

```powershell
& "D:\gamejamshe\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe" `
  --headless --path "D:\gamejamshe\Peking26082026\worktrees\godot-dev\Qimiaoye_DarkForest_TextOnly_V0.1" `
  res://tests/hand_inspect_module_test.tscn
```

通过时输出：`HAND_INSPECT_PASS source=353 spots=3 finish_once=true layout_stable=true`，退出码 0。

## 2. 还缺什么（集成缺口）

### 缺口 1：第 353 行仍是 `module_skip`

`scripts/story_data.gd:340` 当前：

```gdscript
{"type": "module_skip", "source": 353, "id": "HandInspect", "result": "continue"},
```

需改为：

```gdscript
{"type": "module", "source": 353, "id": "HandInspect", "scene": "res://levels/minigames/hand_inspect.tscn", "completion_signal": "finished", "result": "success"},
```

### 缺口 2：`main.gd` 未登记绑定

`scripts/main.gd` 的 `EXPECTED_MODULE_BINDINGS`（第 37 行起）当前含
ForestRun / TextInput / LakeJump / StarJar / BlinkInteraction 五项，需追加第六项：

```gdscript
"HandInspect": {"source": 353, "type": "module", "scene": "res://levels/minigames/hand_inspect.tscn", "signal": "finished"},
```

### 缺口 3：宿主契约校验（可选但建议）

在 `_run_embedded_module()` 内现有的各模块校验之后追加：

```gdscript
if module_id == "HandInspect":
    if not module_instance is Control:
        _record_module_failure(module_id, source, "HandInspect 根节点必须是 Control")
    elif not module_instance.has_method("verify_contract") or not bool(module_instance.call("verify_contract")):
        _record_module_failure(module_id, source, "HandInspect 戒指、掌纹、伤疤三处细节查看契约不完整")
```

## 3. 集成时的注意事项

- **不需要新增资源白名单**：模块不使用任何图片，`ALLOWED_MODULE_IMAGE_ROOTS` 保持原样。
- **不要改剧情文本**：第 354 行「我们以前是不是见过？」由主对白系统显示，模块内部**故意不显示**这句，避免重复。
- **source lock 不受影响**：`story_source_lock.gd` 只锁 351 与 355，未锁 353，改类型不会破坏校验。
- **三重锚点**：351 `hand_inspect_prepare` → 352 剧情图-手 → **353 模块** → 354 对白。改之前先按这三点确认。
- 集成后必须跑完整 `--verify`，确认 `FULL_FLOW_PASS` 且 `modules=7`。

## 4. 历史（避免走回头路）

- `c6d38e7`：第一版实现，**把模块和主流程绑定混在同一提交**，且**没有 UI 调用 `request_finish()`**
  （真实玩法会卡死）。已被 `af39f53` 的返工文档判定为阻断，该提交已废弃。
- `5ec354d`：当前版本。修掉了上述两个阻断项，补了 `FinishButton` 与 `DetailLabel`，
  校正了热点几何，测试改为走真实 `gui_input` + 按钮路径，并以单一提交落在 grounded tip 上。
- 返工要求见 `docs/handoffs/06_HAND_INSPECT_FAST_FORWARD_REWORK.md`。

## 5. 未验证风险

- **真实鼠标点击未测**：测试是程序化派发 `gui_input`，不是 OS 级点击；`SubViewport`
  指针映射链路建议人工在 1080p / 1440p 实点一遍。
- **手的绘制是程序化占位**：低多边形色块，非美术交付。若要替换为真实美术图，
  放在 `res://assets/scene/` 下即可沿用现有白名单，无需改配置。
