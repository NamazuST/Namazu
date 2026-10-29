@echo off
setlocal
set "RIG_PYTHON=%USERPROFILE%\.platformio\penv\Scripts\python.exe"
if not exist "%RIG_PYTHON%" (
    echo PlatformIO Python was not found. Open or install PlatformIO in VS Code first.
    pause
    exit /b 2
)
"%RIG_PYTHON%" "%~dp0tools\run_latest_sensors.py" --sensors 5 %*
set "RIG_EXIT=%ERRORLEVEL%"
echo.
pause
exit /b %RIG_EXIT%
