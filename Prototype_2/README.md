# Prototype 2 — Swipe-up Checklist Interaction v0.1

独立技术验证：

```text
Webcam -> MediaPipe Hand Tracking -> 1/2 finger cursor
       -> hover/arm -> upward Swipe -> visual block removed
       -> block-to-checklist mapping -> reproducible Trial logs
```

Prototype 2 只新增 `Prototype_2/`，不依赖 Prototype 1 的运行时模块，也不改变 Prototype 1 的行为。

## 启动

```powershell
cd D:\PEKING26082026
.\.venv\Scripts\python.exe .\Prototype_2\main.py
```

若模型还不存在：

```powershell
.\.venv\Scripts\python.exe .\Prototype_2\download_model.py
```

依赖安装：

```powershell
.\.venv\Scripts\python.exe -m pip install -r .\Prototype_2\requirements.txt
```

摄像头或模型不可用时，窗口仍然启动，鼠标 fallback 仍可用。Windows 相机权限必须允许桌面应用访问摄像头。

## 操作

- `1`：ONE_FINGER，要求食指伸出，使用 `INDEX_FINGER_TIP`。
- `2`：TWO_FINGER，要求食指和中指都伸出，使用两根指尖的中点。
- `P`：下一次正式 Trial 期望为 Positive。
- `N`：下一次正式 Trial 期望为 Negative。
- `R`：重置当前交互和未完成方块；已完成 Checklist 项保留。
- `T`：重置全部五个方块和全部 Checklist 项，开始新一轮。
- `Q` / `Esc`：退出并落盘。
- 鼠标按住方块向上拖过 `REMOVE_THRESHOLD_Y`：永久可用的 fallback。

## 防误触状态机

```text
TRACKING
  -> BLOCK_HOVER       指尖进入一个方块 Hitbox
  -> BLOCK_ARMED       在 Hitbox 内稳定 BLOCK_ARM_TIME
  -> SWIPING           向上位移达到 MIN_SWIPE_START_DISTANCE
  -> BLOCK_REMOVED     方块中心越过 REMOVE_THRESHOLD_Y，成功一次
```

Hitbox、稳定等待和 Swipe 启动是三个独立门槛。进入方块不会移动方块，也不会建立 Trial。候选阶段明显向下或横向移动会 `Candidate Reject`，回到 `TRACKING`；它不会写 Trial，也不会增加 FN/TN。只有进入 `SWIPING` 后，超时、丢手或横向漂移才会形成正式失败 Trial。

Swipe 只跟随 Y 方向，X 方向保持方块原位。每个 block 有独立 `block_id` 和 `completed`，`complete_block(block_id, source)` 是手势和鼠标共用的唯一成功入口，因此一个方块不能重复计数。

## 两层 Checklist 映射

`block_manager.py` 只管理视觉位置和完成标记；`checklist_mapper.py` 管理逻辑项目：

```python
{
    "block_1": "item_1",
    "block_2": "item_2",
    "block_3": "item_3",
    "block_4": "item_4",
    "block_5": "item_5",
}
```

因此视觉方块可以以后替换，正式 Checklist 文案和数据结构不会被摄像头逻辑绑死。

## Trial 与日志

默认目标是 20 个 Positive + 20 个 Negative。P/N 只设置下一次 Trial 标签；Trial 在手势真正从 `BLOCK_ARMED` 进入 `SWIPING` 时开始，或者鼠标按下方块时开始。每次正式 Trial 包含：

```text
trial_id, expected_type, finger_mode, target_block, result, classification,
fail_reason, duration, path_points, start/end x/y, vertical/horizontal distance,
timestamp, source
```

Positive 成功是 TP，Positive 失败是 FN；Negative 成功是 FP，Negative 失败是 TN。Candidate Reject 不算 Trial，避免把“只是路过”伪装成数据。

每次运行保存：

```text
results/run_YYYYMMDD_HHMMSS_xxxxxx/
├─ summary.json
├─ trials.csv
├─ environment.json
├─ config_snapshot.json
└─ trajectories/trial_XXX.csv
```

轨迹 CSV 保存时间、raw/smoothed 坐标、finger mode、state、target block、block x/y。`summary.json` 保存 TP/TN/FP/FN、precision、recall、accuracy、false positive rate、blocks completed、one/two finger trials。

## 参数

所有交互阈值在 `config.py`：窗口六等分、方块尺寸/间距、`INTERACTION_BOTTOM_RATIO`、`BLOCK_ARM_TIME`、`BLOCK_HITBOX_MARGIN`、`MIN_SWIPE_START_DISTANCE`、`MIN_SWIPE_UP_DISTANCE`、`MAX_HORIZONTAL_DRIFT`、`MAX_SWIPE_TIME`、`REMOVE_THRESHOLD_Y`、`SMOOTHING_FACTOR`、`MAX_MISSING_HAND_TIME` 等。不要把门槛写回 `main.py`，否则调参会变成考古。

如果光点实际只能下到屏幕中部，调整 `CURSOR_Y_INPUT_MAX`。默认把 MediaPipe 的 `y=0.00–0.62` 拉伸到整个窗口高度，因此玩家无需把手伸到摄像头画面最下方也能触及第五区方块。界面同时显示 Raw 与 Mapped 坐标、手是否暂时 HOLD、以及 index/middle 是否伸出：这能区分相机丢帧、坐标映射和两指模式门槛。

## 验收顺序

自动测试覆盖状态机、候选拒绝、两指 extension 判断、一次性完成、Checklist 映射和日志字段。真实摄像头还需要人工验证：

1. 一指稳定进入、上划成功。
2. 两指均伸出并用中点上划成功；折叠中指不应触发 TWO_FINGER。
3. 路过、轻触、向下、左右动作不移除方块。
4. 正式失败后不按 R 也能重新尝试。
5. 已完成方块不重复计数，五块完成显示 `5 / 5`。
6. 摄像头不可用时鼠标拖拽仍成功。

更详细的人工记录模板见 `TEST_ENVIRONMENT.md`。
