# Hand Checkbox Prototype v0.3

独立技术验证：`Webcam -> INDEX_FINGER_TIP -> ARMING/ARMED segmentation -> 在线 ✓ phase -> Trial -> CSV/JSON -> 可复现实验`。鼠标点击圆圈始终能完成 Checkbox，但不会混进手势指标。

## 启动

本项目使用目录外层的隔离环境：

```powershell
cd D:\PEKING26082026
.\.venv\Scripts\python.exe .\Prototyp_über_Hand\main.py
```

若 `.venv` 或模型不存在：

```powershell
py -3.13 -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r .\Prototyp_über_Hand\requirements.txt
.\.venv\Scripts\python.exe .\Prototyp_über_Hand\download_model.py
```

要按本次验证的依赖版本重建环境，可把安装命令替换为：

```powershell
.\.venv\Scripts\python.exe -m pip install -r .\Prototyp_über_Hand\requirements-lock.txt
```

支持 Windows 10/11、Python 3.10–3.13、普通 USB/内置摄像头。Windows 相机权限必须允许桌面应用；摄像头初始化失败时，窗口和鼠标 fallback 仍然可用。

## 交互与 Trial 标签

- `P`：下一次手势标记为 **positive**；画正确 `✓`。
- `N`：下一次手势标记为 **negative**；画 `V`、`/`、`\\`、横线、圈或随机挥动，理论上不应触发。
- `R`：开始下一次。若当前 Trial 尚未终结，记录为 `aborted`，不参与 TP/TN/FP/FN。
- 鼠标点击圆圈：完成 Checkbox；若中断正在画的手势，当前 Trial 记为 `aborted`。
- `Q` / `Esc`：退出并落盘当前 summary。

指尖进入圆圈只会进入 `ARMING`，稳定约 300 ms 后才 `ARMED`。只有随后检测到真实的向右下起笔 candidate，才自动建立 Trial。默认目标是 20 个 positive + 20 个 negative；目标数在 `config.py` 中配置。程序终端会打印实时 Trial 与混淆矩阵摘要。

v0.3 先解决 Gesture Segmentation。negative trial 的严格人工边界协议会在下一版本单独设计；当前不要把 hover、误入圆圈或 candidate reject 当成 negative/positive 样本。

## 在线状态机

运行状态：`IDLE -> TRACKING -> ARMING -> ARMED -> DRAWING -> CHECKED/FAILED`。

绘制 phase：

```text
STARTED -> DOWNSTROKE_OK -> TURN_OK -> UPSTROKE_OK -> SUCCESS
                                      \-> FAILED
```

进入圆圈不会立即记录 Trial。`ARMING` 期间要求手在 `ARM_RADIUS` 内低速稳定；`ARMED` 后保存一段 rolling candidate buffer，只有候选轨迹达到 `START_DOWN_DISTANCE + START_RIGHT_DISTANCE` 才进入正式 `DRAWING`。早期错误 candidate 会自动清空并回到 `ARMED`，不写 Trial CSV、不记 FN/TN；已进入后续 phase 的明显错误、超时、离开区域或手部丢失才会成为正式 `FAILED`。`FAILED` 在 0.5 秒后自动 re-arm，玩家不必按 R 才能再试。

## 当前 ✓ 判定

检测器使用屏幕坐标进行几何判断：

1. 从 Checkbox 附近开始；
2. 先有足够的向右下位移与趋势；
3. 最低点后必须出现有效上升，作为转折；
4. 再有足够的向右上位移、趋势、总路径长度与转折比例；
5. 满足整体条件才进入 `SUCCESS`。

它是可解释的启发式，不是神经网络手写识别。参数不靠“把门槛砍成地板”刷 20/20；FP 也会在 negative Trials 里暴露。

## 结果目录

每次启动会新建：

```text
results/run_YYYYMMDD_HHMMSS_xxxxxx/
├─ summary.json
├─ trials.csv
├─ config_snapshot.json
├─ environment.json
└─ trajectories/trial_001.csv
```

每条轨迹 CSV 保存 `timestamp, raw_x, raw_y, smoothed_x, smoothed_y, current_phase`；坐标以窗口归一化值 `[0, 1]` 保存。`trials.csv` 保存 expected label、结果、失败原因、时长、点数与 TP/TN/FP/FN 分类。`summary.json` 自动统计 Positive Success Rate、False Positive Rate、Precision、Recall、Accuracy；样本不足时写 `null`，不装懂。

`environment.json` 包含可获取的 OS、架构、Python、OpenCV、MediaPipe、NumPy、摄像头 resolution/FPS 和 Git commit/branch/dirty 状态。拿不到的硬件字段明确记录 `unknown`。人工场景信息填 [TEST_ENVIRONMENT.md](TEST_ENVIRONMENT.md)。

## 调参

所有判定阈值都在 `config.py`：

- `CHECK_RADIUS`、`START_ZONE_RADIUS`、`TRACKING_RADIUS`
- `MIN_PATH_LENGTH`、`MIN_DOWN_DISTANCE`、`MIN_UP_DISTANCE`
- `MIN_HORIZONTAL_DISTANCE`、`MAX_DRAW_TIME`
- `SMOOTHING_FACTOR`、`TURN_TOLERANCE`、`DIRECTION_TOLERANCE`
- `INVALID_DIRECTION_DISTANCE`、`MIN_TREND_RATIO`
- `ARM_RADIUS`、`ARM_HOLD_TIME`、`ARM_MAX_SPEED`
- `CANDIDATE_BUFFER_SECONDS`、`START_DOWN_DISTANCE`、`START_RIGHT_DISTANCE`
- `START_MIN_POINTS`、`CANDIDATE_REARM_DELAY`、`FAIL_AUTO_REARM_TIME`

调参顺序：先确认镜像方向和光点跟手，再看 `trajectories/` 里失败卡在哪个 phase；最后只改一个参数并运行同样的正/负 Trial 集。否则实验不可比，数据会像烂掉的 Kartoffelsalat。

## 接入 Godot 时建议的数据

正式接入只消费一个高层事件：

```json
{
  "event": "checkbox_completed",
  "checkbox_id": "example_id",
  "source": "gesture",
  "timestamp_ms": 0
}
```

调试时可额外读取 `phase`、`hand_detected`、`cursor_normalized` 和 `trial_id`。不要让游戏层依赖摄像头帧或 MediaPipe 的 landmark 索引。
