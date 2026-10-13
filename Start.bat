@echo off
rem ---------------------------------------------------------------------------
rem VBAPL BricsCAD LISP - start. Double-click once a day; leave the window open.
rem
rem  1. Unlocks the office LISP (vbapl-lisp.exe unlock). This is one "start":
rem     in the office it resets the allowance to 7 days / 100 starts; off-site
rem     it uses one start. When the allowance is gone it stays locked until
rem     this PC is next on the office network.
rem  2. Opens the office page (app\index.html: Commands, Getting started).
rem  3. Keeps this PC on the office list and the LISP available (presence.ps1).
rem     AutoCAD / BricsCAD load the LISP (vbapl.lsp) only while this runs.
rem
rem Everything after the powershell call stays on that ONE line: an update can
rem rewrite this file while it runs, and cmd re-reads a .bat by byte offset.
rem ---------------------------------------------------------------------------

title VBAPL LISP
cd /d "%~dp0"

if not exist "%~dp0presence.ps1" goto :broken
if not exist "%~dp0vbapl-lisp.exe" goto :broken

echo.
echo   VBAPL office LISP
echo.
"%~dp0vbapl-lisp.exe" unlock > "%TEMP%\vbapl-unlock.txt"
set "UNLOCK=%ERRORLEVEL%"
type "%TEMP%\vbapl-unlock.txt"
del "%TEMP%\vbapl-unlock.txt" >nul 2>&1
echo.
if not "%UNLOCK%"=="0" echo   AutoCAD / BricsCAD will not load the office LISP until this PC is unlocked.

if exist "%~dp0app\index.html" start "" "%~dp0app\index.html"

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0presence.ps1" %* & exit /b

:broken
echo.
echo   This build folder is incomplete - presence.ps1 or vbapl-lisp.exe is missing.
echo   Copy the whole release folder again.
echo.
pause
exit /b 1
