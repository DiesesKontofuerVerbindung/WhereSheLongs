# 奇妙夜：她所向之处

本仓库包含完整 Godot 4.7.2 游戏源码。主工程位于 [`Qimiaoye_DarkForest_TextOnly_V0.1/`](Qimiaoye_DarkForest_TextOnly_V0.1/)，详细操作、导出、日志与故障排查请阅读[工程 README](Qimiaoye_DarkForest_TextOnly_V0.1/README.md)。

## Windows

### 直接运行测试版

使用 `releases/windows/Gespielt-Submission.exe`，双击即可启动。该大文件通过 Git LFS 管理，克隆源码时请确保已安装 Git LFS。Windows SmartScreen 首次提示时，请在确认文件来源后选择“更多信息”→“仍要运行”。

### 从源码运行

仓库附带 Windows Godot 4.7.2 引擎压缩包：

```text
tools/godot/windows/Godot_v4.7.2-stable_win64.zip
```

1. 解压 ZIP。
2. 启动 `Godot_v4.7.2-stable_win64.exe`。
3. 点击 **Import**，选择 `Qimiaoye_DarkForest_TextOnly_V0.1/project.godot`。
4. 等待资源导入完成，点击 **Run Project**。

## macOS

Windows EXE 不能在 macOS 上运行。请安装 [Godot 4.7.2 macOS Standard 版](https://godotengine.org/download/archive/4.7.2-stable/)，然后：

1. 启动 `Godot.app`。
2. 点击 **Import**，选择 `Qimiaoye_DarkForest_TextOnly_V0.1/project.godot`。
3. 等待资源导入完成，点击 **Run Project**。

命令行方式：

```bash
/Applications/Godot.app/Contents/MacOS/Godot \
  --path /你的仓库路径/Qimiaoye_DarkForest_TextOnly_V0.1
```

如果 macOS 阻止打开 Godot，请在“系统设置”→“隐私与安全性”中允许；确认下载来源后，也可运行：

```bash
xattr -dr com.apple.quarantine /Applications/Godot.app
```

## 基本操作

- 推进对白：`Space` / `Enter`
- 移动：`A / D` 或 `← / →`
- 跑酷：`Space` 跳跃，`S / ↓` 下滑
- LakeJump：按住鼠标左键、`Space` 或 `Enter` 蓄力，松开起跳
- StarJar：把五团星光拖入瓶口
- 提交版已关闭开发者快捷键。`F3/F4` 仅在 Godot 编辑器运行源码时可用。

## 日志

Windows：

```text
%APPDATA%\Qimiaoye_DarkForest_TextOnly_V0.1\logs\
```

macOS：

```text
~/Library/Application Support/Qimiaoye_DarkForest_TextOnly_V0.1/logs/
```
