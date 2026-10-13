@echo off
rem ---------------------------------------------------------------------------
rem VBAPL BricsCAD LISP - double-click this to INSTALL or UPDATE.
rem
rem   Empty folder     -> installs the latest release into it
rem   Existing install -> updates it to the latest release
rem
rem TO GIVE THIS TO SOMEONE: send them this file AND update.ps1, together. They
rem put the pair in the folder the LISP should live in - C:\VBAPL\Lisp, say -
rem and double-click this one. After installing, both files are inside the
rem install they just made, so double-clicking again is the update.
rem
rem All the work and all the safety checks are in update.ps1 beside it. This
rem file only gets past Windows opening a .ps1 in Notepad and refusing to run
rem an unsigned script.
rem
rem Everything after the powershell call stays on that ONE line: an update
rem rewrites this file while it is running, and cmd re-reads a .bat line by
rem line at a byte offset. A line it has already parsed is safe.
rem ---------------------------------------------------------------------------

title VBAPL LISP - install / update
cd /d "%~dp0"

if not exist "%~dp0update.ps1" (
  echo.
  echo   update.ps1 is missing from this folder.
  echo   Update.bat and update.ps1 travel together - copy both, not just this one.
  echo.
  pause
  exit /b 1
)

setlocal EnableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" %* & set "rc=!ERRORLEVEL!" & pause & exit /b !rc!
