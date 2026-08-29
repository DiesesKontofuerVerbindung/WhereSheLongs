# 奇妙夜 H5

这是 `奇妙夜 · RPG Demo v0.4` 的移动端落地页，Godot Web 构建位于 `game/`。

本交付包只包含页面文件；请将这些文件复制到已有的 `qimiaoye-h5/` 目录，并保留其中现有的 `game/` 文件夹。

## 本地运行

浏览器安全策略要求 Godot Web 构建通过 HTTP(S) 加载，不能直接双击使用 `file://` 打开。

在本目录双击 `start-server.bat`，或在终端执行：

```bat
cd C:\Users\liuxi\Desktop\game\qimiaoye-h5
python -m http.server 8080
```

然后访问 <http://localhost:8080/>。首页“开始游戏”会直接打开 `game/index.html`；也可访问 <http://localhost:8080/play.html>，在带返回导航的响应式画框中游玩。

## 部署

将整个目录（包括 `game/` 下的 `.wasm`、`.pck`、`.js` 及资源文件）部署到任意静态 HTTP(S) 主机即可。确保服务器支持 `.wasm` MIME 类型（`application/wasm`），并保留 `game/index.html` 使用的相对路径。若部署在子目录，无需修改页面链接。

## 文件说明

- `index.html`：中文首页与开始按钮
- `play.html`：全屏/响应式 Godot 游戏页
- `style.css`：共享暗黑奇幻主题样式，无运行时 CDN 依赖
- `start-server.bat`：本地 HTTP 服务器启动脚本
