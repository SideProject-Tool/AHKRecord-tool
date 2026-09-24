@echo off
rem Launch the AHK-Replay recorder with an explicit AutoHotkey v2 interpreter if found
set "AHK="
if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK if exist "%ProgramFiles%\AutoHotkey\v2\AutoHotkey32.exe" set "AHK=%ProgramFiles%\AutoHotkey\v2\AutoHotkey32.exe"
if not defined AHK if exist "%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey64.exe" set "AHK=%ProgramFiles(x86)%\AutoHotkey\v2\AutoHotkey64.exe"
if not defined AHK if exist "%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe" set "AHK=%LocalAppData%\Programs\AutoHotkey\v2\AutoHotkey64.exe"

if defined AHK (
    start "" "%AHK%" "%~dp0AHK-Replay.ahk"
    exit /b 0
)

echo [start.bat] AutoHotkey v2 not found. Please install AutoHotkey v2 first:
echo   https://www.autohotkey.com/
echo Expected location: %ProgramFiles%\AutoHotkey\v2\AutoHotkey64.exe
pause
exit /b 1
