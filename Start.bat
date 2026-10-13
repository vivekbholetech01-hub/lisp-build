@echo off
rem ---------------------------------------------------------------------------
rem VBAPL BricsCAD LISP - start. Double-click once a day; leave the window open.
rem
rem All the work is in presence.ps1, which runs in this window:
rem  - only one at a time: if it is already running, this says so, brings that
rem    window forward and closes - without using up a start. Once that window
rem    is closed, Start.bat works again;
rem  - unlocks the office LISP (vbapl-lisp.exe unlock): one "start" - in the
rem    office the allowance resets to 7 days / 100 starts, off-site it uses one;
rem  - opens the office page (app\index.html);
rem  - keeps this PC on the office list and the LISP available. AutoCAD and
rem    BricsCAD load the LISP (vbapl.lsp) only while this window is open.
rem
rem Everything after the powershell call stays on that ONE line: an update can
rem rewrite this file while it runs, and cmd re-reads a .bat by byte offset.
rem ---------------------------------------------------------------------------

title VBAPL LISP
cd /d "%~dp0"

if not exist "%~dp0presence.ps1" goto :broken
if not exist "%~dp0vbapl-lisp.exe" goto :broken

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0presence.ps1" %* & exit /b

:broken
echo.
echo   This build folder is incomplete - presence.ps1 or vbapl-lisp.exe is missing.
echo   Copy the whole release folder again, or run Update.bat.
echo.
pause
exit /b 1
