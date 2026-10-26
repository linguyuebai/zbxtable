@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0package-release.ps1"
if errorlevel 1 pause
endlocal
