@echo off
setlocal
set "RIG_PYTHON=%USERPROFILE%\.platformio\penv\Scripts\python.exe"
if not exist "%RIG_PYTHON%" (
    echo PlatformIO Python was not found at "%RIG_PYTHON%".
    echo Install or open PlatformIO in VS Code, then run this launcher again.
    pause
    exit /b 2
)
"%RIG_PYTHON%" "%~dp0tools\run_two_sensors.py" %*
set "RIG_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %RIG_EXIT%
