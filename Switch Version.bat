@echo off
rem ---------------------------------------------------------------------------
rem VBAPL BricsCAD LISP - go back to (or forward to) a particular release.
rem
rem Lists the published releases, newest first, and moves this install to the
rem one you pick. Update.bat always brings it back to the latest.
rem
rem Same one-line rule as Update.bat: the switch rewrites this file while it
rem runs, so nothing may follow the powershell call on a later line.
rem ---------------------------------------------------------------------------

title VBAPL LISP - switch version
cd /d "%~dp0"

if not exist "%~dp0update.ps1" (
  echo.
  echo   update.ps1 is missing from this folder - it does the switching.
  echo.
  pause
  exit /b 1
)

setlocal EnableDelayedExpansion
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0update.ps1" -Choose %* & set "rc=!ERRORLEVEL!" & pause & exit /b !rc!
