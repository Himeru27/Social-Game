@echo off
REM Local development server. Usage: tools\run_server.bat "C:\path\to\Godot.exe"
set GODOT=%~1
if "%GODOT%"=="" set GODOT=godot
"%GODOT%" --headless --path "%~dp0.." res://scenes/server/dedicated_server.tscn -- --port=7777
