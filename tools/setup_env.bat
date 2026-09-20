@echo off
setlocal
rem ============================================================
rem  MyPet asset pipeline environment bootstrap (idempotent)
rem  1. extract Python 3.11 embeddable -> dev\py311
rem  2. enable site-packages in python311._pth
rem  3. bootstrap pip (Tsinghua mirror)
rem  4. install tools\requirements.txt
rem  5. pre-download u2net.onnx -> dev\models (E: drive)
rem ============================================================
call "%~dp0..\dev\env.bat"

set "PY=%MYPET_DEV%\py311\python.exe"
set "DL=%MYPET_DEV%\downloads"
set "MIRROR_PYPI=https://pypi.tuna.tsinghua.edu.cn/simple"

if not exist "%PY%" (
  if not exist "%DL%\py311-embed.zip" (
    echo [setup] ERROR: %DL%\py311-embed.zip not found. Download it first.
    exit /b 1
  )
  echo [setup] extracting Python 3.11 embeddable ...
  powershell -NoProfile -Command "Expand-Archive -Force '%DL%\py311-embed.zip' '%MYPET_DEV%\py311'"
)

echo [setup] enabling site-packages in python311._pth ...
powershell -NoProfile -Command "$p='%MYPET_DEV%\py311\python311._pth'; if (Test-Path $p) { (Get-Content $p) -replace '^#\s*import site','import site' | Set-Content $p -Encoding ASCII }"

if not exist "%DL%\get-pip.py" (
  echo [setup] fetching get-pip.py ...
  curl -sS -L --fail -o "%DL%\get-pip.py" "https://bootstrap.pypa.io/get-pip.py"
)
"%PY%" -m pip --version >nul 2>&1
if errorlevel 1 (
  echo [setup] bootstrapping pip ...
  "%PY%" "%DL%\get-pip.py" --no-warn-script-location -i %MIRROR_PYPI%
)

echo [setup] installing python requirements ...
"%PY%" -m pip install -r "%MYPET_ROOT%\tools\requirements.txt" -i %MIRROR_PYPI% --no-warn-script-location --retries 3

if not exist "%MYPET_DEV%\models\u2net.onnx" (
  if not exist "%MYPET_DEV%\models" mkdir "%MYPET_DEV%\models"
  echo [setup] pre-downloading u2net.onnx ~170MB ...
  curl -L --fail --retry 2 -sS -o "%MYPET_DEV%\models\u2net.onnx" "https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
  if errorlevel 1 (
    echo [setup] github direct failed, trying ghproxy mirror ...
    curl -L --fail --retry 2 -sS -o "%MYPET_DEV%\models\u2net.onnx" "https://ghproxy.net/https://github.com/danielgatis/rembg/releases/download/v0.0.0/u2net.onnx"
  )
)

echo [setup] verifying ...
"%PY%" -c "import onnxruntime, PIL, rembg; print('[setup] OK - rembg ready, onnxruntime', onnxruntime.__version__)"
if errorlevel 1 ( echo [setup] FAILED & exit /b 1 )
echo [setup] all done.
