<#
  install.ps1 — Reproducible ComfyUI setup for Intel Arc (Battlemage) + Qwen-Image-2.1 GGUF
  ---------------------------------------------------------------------------------------
  Reinstalls the whole stack on a fresh machine:
    - clones ComfyUI + venv (Python 3.13)
    - PyTorch XPU (native Intel Arc, no IPEX)
    - ComfyUI-GGUF + ComfyUI-Manager custom nodes
    - downloads the Qwen-Image-2.1 GGUF diffusion model, text encoder, VAE
    - injects the 'qwen_image' architecture tag the GGUF is missing
    - drops in the Arc launcher + workflows

  Usage (PowerShell):
    $env:HF_TOKEN = "hf_xxx"            # your Hugging Face token (do NOT commit it)
    ./install.ps1                       # installs to E:\ComfyUI by default
    ./install.ps1 -ComfyRoot D:\ComfyUI -Quant Q6_K

  Notes:
    - Requires: git, and Python 3.13 available as `py -3.13`.
    - Everything (models, venv, caches) stays under -ComfyRoot / -CacheRoot to spare C:.
#>
[CmdletBinding()]
param(
    [string]$ComfyRoot = "E:\ComfyUI",
    [string]$CacheRoot = "E:\comfy-cache",
    [ValidateSet("Q4_0","Q4_K_M","Q5_K_M","Q6_K","Q8_0")]
    [string]$Quant     = "Q6_K",
    [string]$HfToken   = $env:HF_TOKEN
)
$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = "https://huggingface.co/KasugaiSakura/Qwen-Image-2.1-Uncensored-GGUF/resolve/main"
$py   = "$ComfyRoot\venv\Scripts\python.exe"

Write-Host "== ComfyUI Arc setup ==  root=$ComfyRoot  quant=$Quant" -ForegroundColor Cyan

# --- caches on the big drive ---
New-Item -ItemType Directory -Force -Path "$CacheRoot\pip","$CacheRoot\tmp","$CacheRoot\sycl","$CacheRoot\huggingface" | Out-Null
$env:PIP_CACHE_DIR = "$CacheRoot\pip"; $env:TMP = "$CacheRoot\tmp"; $env:TEMP = "$CacheRoot\tmp"

# --- 1. ComfyUI ---
if (-not (Test-Path "$ComfyRoot\main.py")) {
    Write-Host "Cloning ComfyUI..." -ForegroundColor Yellow
    git clone https://github.com/comfyanonymous/ComfyUI.git $ComfyRoot
} else { Write-Host "ComfyUI already present, skipping clone." }

# --- 2. venv + PyTorch XPU ---
if (-not (Test-Path $py)) {
    Write-Host "Creating venv (Python 3.13)..." -ForegroundColor Yellow
    py -3.13 -m venv "$ComfyRoot\venv"
    & $py -m pip install --upgrade pip
}
Write-Host "Installing PyTorch XPU (Intel Arc)..." -ForegroundColor Yellow
& $py -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/xpu
Write-Host "Installing ComfyUI requirements..." -ForegroundColor Yellow
& $py -m pip install -r "$ComfyRoot\requirements.txt" --extra-index-url https://download.pytorch.org/whl/xpu

# --- 3. custom nodes ---
New-Item -ItemType Directory -Force -Path "$ComfyRoot\custom_nodes" | Out-Null
foreach ($n in @(
    @{u="https://github.com/city96/ComfyUI-GGUF.git";       d="ComfyUI-GGUF"},
    @{u="https://github.com/ltdrdata/ComfyUI-Manager.git";   d="ComfyUI-Manager"})) {
    $dst = "$ComfyRoot\custom_nodes\$($n.d)"
    if (-not (Test-Path $dst)) { git clone --depth 1 $n.u $dst }
    if (Test-Path "$dst\requirements.txt") { & $py -m pip install -r "$dst\requirements.txt" }
}

# --- 4. models ---
if (-not $HfToken) { throw "No Hugging Face token. Set `$env:HF_TOKEN or pass -HfToken." }
New-Item -ItemType Directory -Force -Path "$ComfyRoot\models\diffusion_models","$ComfyRoot\models\text_encoders","$ComfyRoot\models\vae" | Out-Null
$dls = @(
    @{ url="$repo/qwen-image-2.1-$Quant.gguf";                              dest="$ComfyRoot\models\diffusion_models\qwen-image-2.1-$Quant.gguf" },
    @{ url="$repo/text_encoders/qwen3vl_8b_int8_convrot.safetensors";       dest="$ComfyRoot\models\text_encoders\qwen3vl_8b_int8_convrot.safetensors" },
    @{ url="$repo/vae/qwen_image_2.1_vae_bf16.safetensors";                 dest="$ComfyRoot\models\vae\qwen_image_2.1_vae_bf16.safetensors" }
)
foreach ($d in $dls) {
    if (Test-Path $d.dest) { Write-Host "have $($d.dest)"; continue }
    Write-Host "Downloading $($d.dest)..." -ForegroundColor Yellow
    curl.exe -L --fail --retry 5 --retry-delay 5 -C - -H "Authorization: Bearer $HfToken" -o $d.dest $d.url
    if ($LASTEXITCODE -ne 0) { throw "download failed: $($d.url)" }
}

# --- 5. inject the missing 'qwen_image' arch tag into the GGUF ---
$gguf = "$ComfyRoot\models\diffusion_models\qwen-image-2.1-$Quant.gguf"
& $py "$scriptDir\fix_gguf_arch.py" $gguf

# --- 6. launcher + workflows ---
Copy-Item "$scriptDir\run_comfyui.bat" "$ComfyRoot\run_comfyui.bat" -Force
New-Item -ItemType Directory -Force -Path "$ComfyRoot\user\default\workflows" | Out-Null
Copy-Item "$scriptDir\workflows\*.json" "$ComfyRoot\user\default\workflows\" -Force

Write-Host "`nDONE. Launch with:  $ComfyRoot\run_comfyui.bat" -ForegroundColor Green
