# 星光入瓶

Godot 4.7 拖拽小游戏：将 low poly 星光拖入手中玻璃瓶，进瓶后自动复位。

## 运行

用 Godot 4.7 打开本项目，运行 `main.tscn`（F5）。

或命令行：

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "项目路径" "res://main.tscn"
```

## 玩法

- 鼠标 / 触屏拖拽上方 5 颗黄色星光
- 拖入瓶内后星光会自动回到原位
- 5 颗都进过一次后自动结束

## 响应式布局

- 窗口拉伸模式：`canvas_items` + `expand`
- 罐子按视口比例居中缩放
- 星光尺寸、间距、提示字号随窗口自适应
- 支持触屏拖拽
