@echo off
cd /d "%~dp0SAPPHO_Godot_Basis_V0.1"
set HAND_CHECKBOX_AUTO=
start "" "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --path "%cd%" --rendering-driver opengl3 "res://scenes/hand_checkbox/hand_checkbox_demo.tscn"
