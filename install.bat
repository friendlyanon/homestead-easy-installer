@echo off

net session >nul 2>&1
if %errorLevel% == 0 (
    powershell -ExecutionPolicy Bypass -NoLogo -NoProfile -NoExit -file homestead.ps1
) else (
    echo Ezt a fájlt adminisztrátorként kell futtatni!
)

pause >nul
