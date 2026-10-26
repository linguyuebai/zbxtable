@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0install-release.ps1" %*
if errorlevel 1 pause
endlocal
