<#
.SYNOPSIS
  Installs ComfyUI + Qwen-Image-2.1 (GGUF) for Intel Arc B580 using native PyTorch XPU.

.EXAMPLE
  ./install.ps1
  ./install.ps1 -ComfyRoot D:\ComfyUI -Quant Q8_0
#>
[CmdletBinding()]
param(
    [string]$ComfyRoot = (Join-Path (Split-Path $PSScriptRoot -Qualifier) "ComfyUI"),
    [string]$CacheRoot = (Join-Path (Split-Path $ComfyRoot -Parent) "comfy-cache"),
    [ValidateSet("Q3_K_M","Q4_K_M","Q5_K_M","Q6_K","Q8_0")]
    [string]$Quant     = "Q6_K",
    [string]$HfToken   = $env:HF_TOKEN
)
$ErrorActionPreference = "Stop"
$gguf  = "https://huggingface.co/unsloth/Qwen-Image-2.1-GGUF/resolve/main"
$comfy = "https://huggingface.co/Comfy-Org/Qwen-Image-2.1/resolve/main"
$py    = "$ComfyRoot\venv\Scripts\python.exe"

function Step($msg) { Write-Host "`n>> $msg" -ForegroundColor Cyan }

Write-Host "ComfyUI Arc setup   root=$ComfyRoot   cache=$CacheRoot   quant=$Quant" -ForegroundColor Green

# Keep pip/temp caches next to the install instead of on C:
New-Item -ItemType Directory -Force -Path "$CacheRoot\pip","$CacheRoot\tmp","$CacheRoot\sycl","$CacheRoot\huggingface" | Out-Null
$env:PIP_CACHE_DIR = "$CacheRoot\pip"; $env:TMP = "$CacheRoot\tmp"; $env:TEMP = "$CacheRoot\tmp"

Step "ComfyUI"
if (-not (Test-Path "$ComfyRoot\main.py")) {
    git clone https://github.com/comfyanonymous/ComfyUI.git $ComfyRoot
} else { Write-Host "Already present, skipping clone." }

Step "Python venv + PyTorch XPU"
if (-not (Test-Path $py)) {
    py -3.13 -m venv "$ComfyRoot\venv"
    & $py -m pip install --upgrade pip
}
& $py -m pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/xpu
& $py -m pip install -r "$ComfyRoot\requirements.txt" --extra-index-url https://download.pytorch.org/whl/xpu

Step "Custom nodes"
New-Item -ItemType Directory -Force -Path "$ComfyRoot\custom_nodes" | Out-Null
foreach ($n in @(
    @{u="https://github.com/city96/ComfyUI-GGUF.git";     d="ComfyUI-GGUF"},
    @{u="https://github.com/ltdrdata/ComfyUI-Manager.git"; d="ComfyUI-Manager"})) {
    $dst = "$ComfyRoot\custom_nodes\$($n.d)"
    if (-not (Test-Path $dst)) { git clone --depth 1 $n.u $dst }
    if (Test-Path "$dst\requirements.txt") { & $py -m pip install -r "$dst\requirements.txt" }
}

Step "Models (~16 GB)"
New-Item -ItemType Directory -Force -Path "$ComfyRoot\models\diffusion_models","$ComfyRoot\models\text_encoders","$ComfyRoot\models\vae" | Out-Null
$auth = if ($HfToken) { @("-H", "Authorization: Bearer $HfToken") } else { @() }
$dls = @(
    @{ url="$gguf/qwen-image-2.1-$Quant.gguf";                         dest="$ComfyRoot\models\diffusion_models\qwen-image-2.1-$Quant.gguf" },
    @{ url="$comfy/text_encoders/qwen3vl_8b_int8_convrot.safetensors"; dest="$ComfyRoot\models\text_encoders\qwen3vl_8b_int8_convrot.safetensors" },
    @{ url="$comfy/vae/qwen_image_2.1_vae_bf16.safetensors";           dest="$ComfyRoot\models\vae\qwen_image_2.1_vae_bf16.safetensors" }
)
foreach ($d in $dls) {
    if (Test-Path $d.dest) { Write-Host "Have $(Split-Path $d.dest -Leaf)"; continue }
    Write-Host "Downloading $(Split-Path $d.dest -Leaf)..."
    curl.exe -L --fail --retry 5 --retry-delay 5 -C - @auth -o $d.dest $d.url
    if ($LASTEXITCODE -ne 0) { throw "Download failed: $($d.url)" }
}

Step "Tagging GGUF architecture"
& $py "$PSScriptRoot\fix_gguf_arch.py" "$ComfyRoot\models\diffusion_models\qwen-image-2.1-$Quant.gguf"

Step "Launcher + workflows"
(Get-Content "$PSScriptRoot\run_comfyui.bat") -replace '^set "CACHE=.*"$', "set `"CACHE=$CacheRoot`"" |
    Set-Content "$ComfyRoot\run_comfyui.bat" -Encoding ascii
$wfDir = "$ComfyRoot\user\default\workflows"
New-Item -ItemType Directory -Force -Path $wfDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding $false
foreach ($wf in Get-ChildItem "$PSScriptRoot\workflows\*.json") {
    $json = [IO.File]::ReadAllText($wf.FullName) -replace 'qwen-image-2\.1-Q6_K\.gguf', "qwen-image-2.1-$Quant.gguf"
    [IO.File]::WriteAllText((Join-Path $wfDir $wf.Name), $json, $utf8)
}

Write-Host "`nDone. Launch with:  $ComfyRoot\run_comfyui.bat" -ForegroundColor Green
