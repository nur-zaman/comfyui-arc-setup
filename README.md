# ComfyUI — Intel Arc B580 + Qwen-Image-2.1 (GGUF)

A reproducible setup for running **Qwen-Image-2.1** (text-to-image, image-edit and
img2img) on an **Intel Arc B580** (Battlemage, 12 GB) via **native PyTorch XPU** —
no IPEX, no CUDA. Everything is quantized GGUF so it fits in 12 GB.

## What's in this repo

| File | Purpose |
|------|---------|
| `install.ps1` | One-shot installer — clones ComfyUI, venv, torch-xpu, nodes, downloads models, fixes the GGUF, drops in launcher + workflows |
| `run_comfyui.bat` | Arc-tuned launcher (reserves VRAM, opens the browser) |
| `fix_gguf_arch.py` | Injects the `qwen_image` architecture tag the GGUF is missing |
| `workflows/*.json` | Ready-to-use ComfyUI workflows |

## Fresh install (new machine / after a wipe)

Requirements: **git** and **Python 3.13** (`py -3.13` must work).

```powershell
git clone <this-repo> comfyui-arc-setup
cd comfyui-arc-setup
$env:HF_TOKEN = "hf_xxxxxxxx"      # your Hugging Face token — never commit it
./install.ps1                       # defaults: installs to E:\ComfyUI, Q6_K quant
```

Options: `./install.ps1 -ComfyRoot D:\ComfyUI -Quant Q8_0`
(quants: `Q4_0 Q4_K_M Q5_K_M Q6_K Q8_0` — bigger = better quality, more VRAM).

When it finishes, launch with `E:\ComfyUI\run_comfyui.bat`.

## Starting ComfyUI

Double-click **`run_comfyui.bat`**. It:
- reserves 2 GB VRAM for the Windows desktop (the B580 also drives your display),
- uses PyTorch cross-attention (Arc has no flash-attn/xformers),
- persists compiled GPU kernels for fast warm starts,
- opens <http://127.0.0.1:8188> in your browser automatically.

## Why the Arc-specific flags matter

The B580 renders your **desktop** *and* runs the **compute**. If ComfyUI grabs all
12 GB VRAM during sampling it starves the display driver → **BSOD (`0x7E`)**. The
launcher's `--reserve-vram 2.0` prevents that. If you ever push very large images and
see instability, raise it to `3.0` and/or add `--lowvram` in `run_comfyui.bat`.

## Models (installed by the script)

| Component | File | Folder |
|-----------|------|--------|
| Diffusion (GGUF) | `qwen-image-2.1-Q6_K.gguf` (5.88 GB) | `models/diffusion_models` |
| Text encoder | `qwen3vl_8b_int8_convrot.safetensors` (9.35 GB) | `models/text_encoders` |
| VAE | `qwen_image_2.1_vae_bf16.safetensors` (0.68 GB) | `models/vae` |

Source: <https://huggingface.co/KasugaiSakura/Qwen-Image-2.1-Uncensored-GGUF>

## Workflows

Loadable from the **Workflows** sidebar in ComfyUI:

- **Qwen T2I – Square 1024** — the standard 1 MP text-to-image (validated stable).
- **Qwen T2I – Portrait 896×1152** / **Landscape 1152×896** — aspect-ratio variants.
- **Qwen T2I – Fast Draft 768** — low steps, quick previews.
- **Qwen Image Edit** — instruction-based editing: load an image, describe the change.
- **Qwen Image-to-Image** — restyle an input image (denoise strength controls how much).

### Key settings
- **cfg = 1** is the official Qwen-Image-2.1 path. Only raise it if you use a negative prompt.
- **steps**: 25 is a good default; the official pipeline uses up to ~40–50 for max quality.
- **1024×1024 is the safe resolution.** For 2K, enable `--lowvram` first.
- For editing, keep denoise = 1 and phrase the prompt as an instruction
  (e.g. *"change the background to a snowy forest, keep the subject unchanged"*).
- For img2img, lower **denoise** (0.4–0.7) keeps more of the original.

## Reproducibility notes

This repo intentionally does **not** contain ComfyUI, the venv, or the multi-GB model
weights (see `.gitignore`) — `install.ps1` fetches them. Your Hugging Face token is read
from `$env:HF_TOKEN`, never stored, so this repo is safe to push.
