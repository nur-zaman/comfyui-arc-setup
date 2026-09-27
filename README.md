<div align="center">

<img src="https://github.com/intel.png?size=120" height="72" alt="Intel" />
&nbsp;&nbsp;&nbsp;
<img src="https://github.com/Comfy-Org.png?size=120" height="72" alt="ComfyUI" />
&nbsp;&nbsp;&nbsp;
<img src="https://github.com/QwenLM.png?size=120" height="72" alt="Qwen" />

# Qwen-Image-2.1 on Intel Arc B580

**Local text-to-image and image editing in ComfyUI on a 12 GB Intel Arc card, installed with one script.**

[![Intel Arc B580](https://img.shields.io/badge/Intel_Arc-B580_12GB-0071C5?style=for-the-badge&logo=intel&logoColor=white)](https://www.intel.com/content/www/us/en/products/sku/241598/intel-arc-b580-graphics/specifications.html)
[![PyTorch XPU](https://img.shields.io/badge/PyTorch-XPU-EE4C2C?style=for-the-badge&logo=pytorch&logoColor=white)](https://pytorch.org/docs/stable/notes/get_start_xpu.html)
[![ComfyUI](https://img.shields.io/badge/ComfyUI-GGUF-172117?style=for-the-badge)](https://github.com/comfyanonymous/ComfyUI)
[![Qwen-Image-2.1](https://img.shields.io/badge/Qwen--Image-2.1-615CED?style=for-the-badge&logo=huggingface&logoColor=white)](https://huggingface.co/Qwen/Qwen-Image-2.1)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge)](#-requirements)

</div>

---

This guide sets up **Qwen-Image-2.1** with native **PyTorch XPU**. You don't need IPEX, CUDA or WSL. The diffusion model is a GGUF quantization, so it fits in the B580's 12 GB of VRAM alongside your desktop.

- **Text-to-image** at square, portrait and landscape sizes
- **Instruction-based editing**: describe the change you want in plain words
- **Image-to-image** restyling
- **Arc-tuned launcher** that avoids the VRAM-starvation BSOD

## Requirements

| | |
|---|---|
| **GPU** | Intel Arc B580. Other Arc cards should work but are untested. |
| **Driver** | Latest [Intel Arc graphics driver](https://www.intel.com/content/www/us/en/download/785597/intel-arc-iris-xe-graphics-windows.html) |
| **Software** | [Git](https://git-scm.com/download/win) and [Python 3.13](https://www.python.org/downloads/) (`py -3.13 --version` must work) |
| **Disk** | About 35 GB free (16 GB of models, plus PyTorch and caches) |

## Quick start

```powershell
git clone https://github.com/<you>/comfyui-arc-setup.git
cd comfyui-arc-setup
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

Then launch:

```powershell
<drive>:\ComfyUI\run_comfyui.bat
```

ComfyUI opens at <http://127.0.0.1:8188>. Open the **Workflows** sidebar, pick one, and press **Run**.

> [!NOTE]
> The first image is slow because the GPU kernels are compiling. They're cached on disk, so later runs and restarts are much faster.

<details>
<summary><b>⚙️ Installer options</b></summary>

<br>

| Option | Default | Description |
|---|---|---|
| `-ComfyRoot` | `<repo drive>:\ComfyUI` | Where ComfyUI, the venv and the models go |
| `-CacheRoot` | `comfy-cache`, next to `ComfyRoot` | pip, temp and compiled-kernel caches (kept off `C:`) |
| `-Quant` | `Q6_K` | `Q3_K_M` · `Q4_K_M` · `Q5_K_M` · `Q6_K` · `Q8_0`. Larger quants give better quality and use more VRAM |
| `-HfToken` | `$env:HF_TOKEN` | Optional Hugging Face token, if you hit download rate limits |

```powershell
.\install.ps1 -ComfyRoot D:\ComfyUI -Quant Q8_0
```

You can re-run the script safely. It skips anything that's already installed or downloaded.

</details>

## What gets installed

1. [**ComfyUI**](https://github.com/comfyanonymous/ComfyUI) in a Python 3.13 venv
2. **PyTorch** from the official XPU wheel index
3. The custom nodes [**ComfyUI-GGUF**](https://github.com/city96/ComfyUI-GGUF) and [**ComfyUI-Manager**](https://github.com/ltdrdata/ComfyUI-Manager)
4. The models:

   | Component | File | Size | Source |
   |---|---|---|---|
   | Diffusion model | `qwen-image-2.1-Q6_K.gguf` | 6.3 GB | [unsloth/Qwen-Image-2.1-GGUF](https://huggingface.co/unsloth/Qwen-Image-2.1-GGUF) |
   | Text encoder | `qwen3vl_8b_int8_convrot.safetensors` | 9.4 GB | [Comfy-Org/Qwen-Image-2.1](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) |
   | VAE | `qwen_image_2.1_vae_bf16.safetensors` | 0.7 GB | [Comfy-Org/Qwen-Image-2.1](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) |

5. A small patch that adds the GGUF's missing architecture tag (`fix_gguf_arch.py`)
6. The Arc launcher and the ready-made workflows

## Workflows

| Workflow | Use it for |
|---|---|
| **Qwen T2I - Square 1024** | Standard 1024×1024 text-to-image. ⭐ Start here. |
| **Qwen T2I - Portrait 896x1152** | Tall images |
| **Qwen T2I - Landscape 1152x896** | Wide images |
| **Qwen T2I - Fast Draft 768** | Quick low-step previews for iterating on a prompt |
| **Qwen Image Edit** | Load an image and describe the change you want |
| **Qwen Image-to-Image** | Restyle an existing image |

> [!TIP]
> - **Leave CFG at 1.** That's the model's intended setting. Raise it only if you add a negative prompt.
> - **Steps:** 20–25 is a good default. Go up to 40–50 for maximum quality.
> - **Resolution:** around 1 megapixel (1024×1024) is the safe maximum on 12 GB.
> - **Editing:** keep denoise at `1.0` and write the prompt as an instruction, for example *"change the background to a snowy forest, keep the subject unchanged"*.
> - **Img2img:** denoise controls how much changes. `0.4–0.7` keeps most of the original.

## Why the launcher matters

> [!WARNING]
> The B580 renders your Windows desktop and runs ComfyUI at the same time. If ComfyUI takes all 12 GB during sampling, the display driver runs out of memory and Windows can crash with **BSOD `0x7E`**.

`run_comfyui.bat` prevents that and tunes ComfyUI for Arc:

| Setting | Purpose |
|---|---|
| `--reserve-vram 2.0` | Keeps 2 GB of VRAM free for the desktop |
| `--use-pytorch-cross-attention` | Arc doesn't support flash-attn or xformers |
| `SYCL_CACHE_PERSISTENT=1` | Caches compiled GPU kernels so later starts are faster |
| `PYTORCH_ENABLE_XPU_FALLBACK=1` | Runs ops that don't have an XPU kernel yet on the CPU instead of crashing |

Any extra arguments go to ComfyUI, for example `run_comfyui.bat --lowvram`.

## Troubleshooting

| Problem | Fix |
|---|---|
| BSOD or display freeze while generating | Raise `--reserve-vram` to `3.0` in `run_comfyui.bat`, or launch with `--lowvram` |
| Out of memory at high resolution | Launch with `--lowvram`, or reinstall with a smaller quant (`-Quant Q4_K_M`) |
| `Unknown model architecture!` | Run `venv\Scripts\python.exe fix_gguf_arch.py <path-to.gguf>` on the model |
| `py -3.13` not found | Install Python 3.13 from python.org with the **py launcher** option ticked |
| Script blocked by execution policy | Run it with `powershell -ExecutionPolicy Bypass -File .\install.ps1` |
| Workflow shows a missing model | Pick your installed `.gguf` in the **Unet Loader (GGUF)** node |


This repo only contains the setup. ComfyUI, the venv and the model weights are downloaded by the installer and never committed.

## Credits

- [Qwen-Image](https://huggingface.co/Qwen/Qwen-Image-2.1) by the Qwen team at Alibaba
- [ComfyUI](https://github.com/comfyanonymous/ComfyUI) and the [Comfy-Org](https://huggingface.co/Comfy-Org/Qwen-Image-2.1) model repackages
- [ComfyUI-GGUF](https://github.com/city96/ComfyUI-GGUF) by city96
- GGUF quantizations by [Unsloth](https://huggingface.co/unsloth/Qwen-Image-2.1-GGUF)

<sub>This is a community project. It isn't affiliated with or endorsed by Intel, Alibaba, Comfy Org or Unsloth. All logos and trademarks belong to their owners.</sub>
