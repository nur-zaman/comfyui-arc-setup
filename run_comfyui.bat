@echo off
REM ============================================================
REM  ComfyUI launcher optimized for Intel Arc B580 (Battlemage)
REM  Uses native PyTorch XPU backend (no IPEX needed).
REM ============================================================
cd /d "%~dp0"

REM --- Intel Arc / XPU tuning --------------------------------
REM Fall back to CPU for any op not yet implemented on XPU (stability):
set "PYTORCH_ENABLE_XPU_FALLBACK=1"
REM Persist compiled SYCL kernels between runs -> faster warm starts:
set "SYCL_CACHE_PERSISTENT=1"
set "SYCL_CACHE_DIR=E:\comfy-cache\sycl"
REM Keep HF / pip caches off the C: drive:
set "HF_HOME=E:\comfy-cache\huggingface"
set "PIP_CACHE_DIR=E:\comfy-cache\pip"
set "TMP=E:\comfy-cache\tmp"
set "TEMP=E:\comfy-cache\tmp"

REM --- Launch -------------------------------------------------
REM  --use-pytorch-cross-attention : Arc has no flash-attn/xformers
REM  --reserve-vram 2.0 : CRITICAL on this PC. The B580 also drives the
REM      display, so we keep 2 GB free for the Windows desktop/compositor.
REM      Without this, heavy sampling starves the display driver -> BSOD (0x7E).
REM  --auto-launch : open the ComfyUI page in your browser automatically
"E:\ComfyUI\venv\Scripts\python.exe" main.py --use-pytorch-cross-attention --reserve-vram 2.0 --auto-launch %*

pause
