@echo off
REM ComfyUI launcher for Intel Arc B580 (native PyTorch XPU)
cd /d "%~dp0"

set "CACHE=%~dp0..\comfy-cache"

set "PYTORCH_ENABLE_XPU_FALLBACK=1"
set "SYCL_CACHE_PERSISTENT=1"
set "SYCL_CACHE_DIR=%CACHE%\sycl"
set "HF_HOME=%CACHE%\huggingface"
set "PIP_CACHE_DIR=%CACHE%\pip"
set "TMP=%CACHE%\tmp"
set "TEMP=%CACHE%\tmp"

REM --reserve-vram keeps VRAM free for the desktop. The B580 also drives the
REM display, and without this heavy sampling can crash the driver (BSOD 0x7E).
"%~dp0venv\Scripts\python.exe" main.py --use-pytorch-cross-attention --reserve-vram 2.0 --auto-launch %*

pause
