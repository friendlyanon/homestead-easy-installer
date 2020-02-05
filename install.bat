@echo off

net session >nul 2>&1
if %errorLevel% == 0 (
    powershell -ExecutionPolicy Bypass -NoLogo -NoProfile -File "%~dp0%homestead.ps1"
) else (
    echo Ezt a fajlt adminisztratorkent kell futtatni!
)

pause
