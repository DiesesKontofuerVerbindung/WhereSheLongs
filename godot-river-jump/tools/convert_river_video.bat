@echo off
set FF=%LOCALAPPDATA%\Programs\Python\Python312\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe
if not exist "%FF%" set FF=ffmpeg
"%FF%" -y -i assets\backgrounds\river_bg.mp4 -c:v libtheora -q:v 3 -an assets\backgrounds\river_bg.ogv
echo Done. Re-open Godot project to import river_bg.ogv
