# EXE\_bash

### Ausführen mit Icon&#x20;

```text
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
```

### Voraussetzung falls noch kein pyinstaller etc&#x20;

```text
# On Windows (Command Prompt as Admin)
cd C:\Users\IRZ\Desktop\Namazu\Python
python -m venv venv
venv\Scripts\activate
pip install pyinstaller matplotlib numpy pyserial tqdm
pyinstaller --onedir --collect-all matplotlib --collect-all numpy ui_main.py
# Output: dist\ui_main\ui_main.exe
```


​

​

### Old version&#x20;

python -m venv venv

echo Step 2: Activating virtual environment...

call venv\\\Scripts\\\activate.bat

echo Step 3: Installing dependencies...

pip install --upgrade pip

pip install pyinstaller matplotlib numpy pyserial tqdm

echo Step 4: Copying custom modules if needed...

if exist Classes\\\\\*.py (

&#x20;   echo Copying from Classes folder...

&#x20;   copy Classes\\\\\*.py .

)

echo Step 5: Building executable...

pyinstaller --onedir ^

&#x20; \--collect-all matplotlib ^

&#x20; \--collect-all numpy ^

&#x20; \--hidden-import=matplotlib.backends.backend\_tkagg ^

&#x20; \--name=NamazuApp ^

&#x20; ui\_main.py
