# 奇妙夜：她所向之处

Godot 4.7.2 剧情游戏工程，包含婚礼前夜、奇妙夜、黑暗森林、章节三与结局流程，以及 ForestRun、TextInput、LakeJump、StarJar 等玩法模块。

## 获取内容

- Windows 测试版：`Gespielt-Latest.exe`（随测试包单独提供，不放入 Git 仓库）。
- 完整 Godot 工程：`Qimiaoye_DarkForest_TextOnly_V0.1/`。
- Windows Godot 4.7.2 引擎：`tools/godot/windows/Godot_v4.7.2-stable_win64.zip`。
- macOS 不使用 Windows EXE；请按下方说明用 macOS 版 Godot 4.7.2 打开源码。

## Windows：直接玩 EXE

1. 把 `Gespielt-Latest.exe` 复制到本地磁盘，预留至少 2 GB 空间。
2. 双击运行。第一次启动可能需要等待一段时间加载资源。
3. 如果 Windows SmartScreen 拦截，确认文件来源后选择“更多信息”→“仍要运行”。
4. 游戏存档和日志位于：

   ```text
   %APPDATA%\Qimiaoye_DarkForest_TextOnly_V0.1\
   ```

## Windows：从源码运行

仓库已经附带 Windows Godot 4.7.2：

1. 解压 `tools/godot/windows/Godot_v4.7.2-stable_win64.zip`。
2. 启动解压后的 `Godot_v4.7.2-stable_win64.exe`。
3. 点击 **Import**，选择：

   ```text
   Qimiaoye_DarkForest_TextOnly_V0.1\project.godot
   ```

4. 打开工程后点击右上角 **Run Project**，或按 `F6/F5`。

也可以在仓库根目录使用命令行：

```powershell
.\tools\godot\windows\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64.exe --path .\Qimiaoye_DarkForest_TextOnly_V0.1
```

> 上述命令假设 ZIP 解压到了同名目录；如果解压位置不同，请替换引擎路径。

## macOS：从源码运行

Windows EXE 不能在 macOS 上直接运行。macOS 用户需要使用官方 Godot 4.7.2：

1. 从 [Godot 官方下载页](https://godotengine.org/download/archive/4.7.2-stable/) 下载 macOS Standard 版 Godot 4.7.2（不需要 .NET 版）。
2. 解压并把 `Godot.app` 移入 `/Applications`。
3. 如果 macOS 阻止打开，在“系统设置”→“隐私与安全性”中允许；也可以在确认下载来源后执行：

   ```bash
   xattr -dr com.apple.quarantine /Applications/Godot.app
   ```

4. 启动 Godot，点击 **Import**，选择：

   ```text
   Qimiaoye_DarkForest_TextOnly_V0.1/project.godot
   ```

5. 导入完成后点击 **Run Project**。

命令行运行方式：

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /你的仓库路径/Qimiaoye_DarkForest_TextOnly_V0.1
```

macOS 首次导入会重新生成平台相关缓存，耗时取决于磁盘和机器性能。摄像头手势属于可选功能；未连接摄像头时仍可使用键盘和鼠标完成主要流程。

## 基本操作

- 推进旁白/对白：`Space`、`Enter` 或画面中的“继续”。
- 移动：`A / D` 或 `← / →`。
- ForestRun：`Space` 跳跃，`S / ↓` 下滑。
- 光源交互：鼠标悬停在光源区域。
- 跳水/触摸：点击剧情中的对应按钮。
- TextInput：键盘输入；没有摄像头时可按 `F` 使用 Fan 预览操作。
- LakeJump：按住鼠标左键、`Space` 或 `Enter` 蓄力，松开起跳；落水后返回剧情。
- StarJar：拖动五团星光进入瓶口。
- DOCX 开发回溯：`F4` 打开，输入来源行；`Esc` 或再次按 `F4` 关闭。
- 诊断面板：`F3`。正式界面默认隐藏全局 Blink 状态和跑酷状态调试覆盖层。

## 从源码导出 Windows 版本

需要先在 Godot 编辑器中安装对应版本的 Export Templates。随后可在仓库根目录执行：

```powershell
$godot = ".\tools\godot\windows\Godot_v4.7.2-stable_win64\Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless `
  --path ".\Qimiaoye_DarkForest_TextOnly_V0.1" `
  --export-release "Gespielt Windows" `
  ".\Gespielt.exe"
```

macOS 导出包需要在 macOS 版 Godot 中安装 Export Templates，并在 **Project → Export** 中新增 macOS preset；当前仓库固定提供的是 Windows export preset。

## 工程结构

```text
Qimiaoye_DarkForest_TextOnly_V0.1/
├─ project.godot              # Godot 工程入口
├─ main.tscn                  # 黑暗森林主流程入口
├─ scenes/                    # 开场、婚礼、奇妙夜、章节三和玩法场景
├─ scripts/                   # 剧情数据、UI、状态机和验证逻辑
├─ levels/                    # ForestRun、LakeJump、TextInput、StarJar 等模块
├─ assets/                    # 图像、序列帧、字体和音频
└─ export_presets.cfg         # Windows/Web 导出预设
```

## 日志与故障排查

Windows 日志目录：

```text
%APPDATA%\Qimiaoye_DarkForest_TextOnly_V0.1\logs\
```

macOS 日志目录通常位于：

```text
~/Library/Application Support/Qimiaoye_DarkForest_TextOnly_V0.1/logs/
```

关键文件：

- `godot.log`：Godot 和脚本错误。
- `runtime.log`：剧情事件、模块进入/返回、场景切换。
- `trace_steps.log`：DOCX 来源行和事件执行记录。
- `forest_amai_fixed_route.log`：ForestRun 阿麦路线状态。
- `forest_vine_echo_runtime.log`：跑酷藤蔓延迟模仿状态。

如果出现黑屏或资源缺失，请先用 Godot 4.7.2 打开工程并等待资源导入完成，再运行项目。不要删除源码目录中的 `.import` 描述文件；本地生成的 `.godot/` 缓存可以在关闭 Godot 后删除并重新导入。
