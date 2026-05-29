@echo off
echo ========================================
echo Building simple_ui.exe WITH ICON
echo ========================================

cd /d C:\Users\IRZ\Desktop\Namazu\Python

call .venv\Scripts\activate.bat

rmdir /s /q build dist 2>nul

pyinstaller --onedir ^
  --icon=Namazu_Icon.ico ^
  --add-data="Classes;Classes" ^
  --collect-all matplotlib ^
  --collect-all numpy ^
  --name="NamazuApp" ^
  simple_ui.py
echo ========================================
pause


