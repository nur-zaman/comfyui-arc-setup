"""Benchmark the repo's workflows on a running local ComfyUI server.

Loads each workflow from workflows/ exactly as shipped, swaps in the case's prompt,
seed and (for edit / img2img) input image, then times the run and polls
/system_stats for peak VRAM. Standard library only.

Usage (start ComfyUI with run_comfyui.bat first):
    python benchmark\\bench.py
    python benchmark\\bench.py --server-log comfy.log   # also read the sampler's s/it from the console log

cases.json entries:
    {"name", "workflow", "prompt", "seed", "repeat_seed"?, "input_from"?}
"repeat_seed" re-runs the same prompt with seed + 1, so the text encoder is cached;
that is the time to iterate on seeds. "input_from" names an earlier case whose
output becomes the input image (for the Edit and Image-to-Image workflows).
"""
import argparse
import json
import re
import threading
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

HERE = Path(__file__).parent
WORKFLOWS = HERE.parent / "workflows"

parser = argparse.ArgumentParser()
parser.add_argument("--cases", default=str(HERE / "cases.json"))
parser.add_argument("--out", default=str(HERE / "results.json"))
parser.add_argument("--server", default="127.0.0.1:8188")
parser.add_argument("--server-log", help="ComfyUI console log, to read the sampler's s/it")
parser.add_argument("--clip", help="override the text encoder file in every workflow")
parser.add_argument("--only", help="comma-separated case names to run")
parser.add_argument("--append", action="store_true", help="keep existing runs in --out and replace only the re-run cases")
args = parser.parse_args()
base = f"http://{args.server}"


def get(path):
    return json.loads(urllib.request.urlopen(base + path, timeout=30).read())


object_info = get("/object_info")


def to_api(workflow):
    """Convert a UI-format workflow into the API prompt format."""
    links = {l[0]: (str(l[1]), l[2]) for l in workflow["links"]}
    prompt = {}
    for node in workflow["nodes"]:
        if node.get("mode", 0) != 0:
            continue
        spec = object_info[node["type"]]["input"]
        inputs = {}
        values = iter(node.get("widgets_values", []))
        for name, opts in {**spec.get("required", {}), **spec.get("optional", {})}.items():
            kind = opts[0]
            is_widget = isinstance(kind, list) or kind in ("INT", "FLOAT", "STRING", "BOOLEAN", "COMBO")
            if not is_widget:
                continue
            try:
                inputs[name] = next(values)
            except StopIteration:
                break
            if len(opts) > 1 and isinstance(opts[1], dict) and opts[1].get("control_after_generate"):
                next(values, None)  # the "randomize" / "fixed" widget has no API input
        for inp in node.get("inputs", []):
            if inp.get("link") is not None:
                inputs[inp["name"]] = list(links[inp["link"]])
        prompt[str(node["id"])] = {"class_type": node["type"], "inputs": inputs}
    return prompt


def set_input(prompt, class_type, name, value):
    for node in prompt.values():
        if node["class_type"] == class_type:
            node["inputs"][name] = value


def upload(image_ref):
    """Copy an output image into ComfyUI's input folder via the HTTP API."""
    subfolder, filename = image_ref.rsplit("/", 1)
    query = urllib.parse.urlencode({"filename": filename, "subfolder": subfolder, "type": "output"})
    data = urllib.request.urlopen(f"{base}/view?{query}").read()
    boundary = uuid.uuid4().hex
    body = (f"--{boundary}\r\nContent-Disposition: form-data; name=\"image\"; filename=\"bench_{filename}\"\r\n"
            f"Content-Type: image/png\r\n\r\n").encode() + data + f"\r\n--{boundary}--\r\n".encode()
    req = urllib.request.Request(f"{base}/upload/image", data=body,
                                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    return json.loads(urllib.request.urlopen(req).read())["name"]


class VramPoller(threading.Thread):
    def __init__(self):
        super().__init__(daemon=True)
        self.min_free, self.total, self.min_ram, self.stop = None, None, None, False

    def run(self):
        while not self.stop:
            try:
                stats = get("/system_stats")
                dev = stats["devices"][0]
                ram = stats["system"]["ram_free"]
                self.min_ram = ram if self.min_ram is None else min(self.min_ram, ram)
                self.total = dev["vram_total"]
                self.min_free = dev["vram_free"] if self.min_free is None else min(self.min_free, dev["vram_free"])
            except Exception:
                pass
            time.sleep(0.25)


def sampler_rate(log_offset):
    """Last tqdm rate printed to the server log since log_offset, in s/it."""
    if not args.server_log:
        return None, log_offset
    data = Path(args.server_log).read_bytes()
    rates = re.findall(r"(\d+(?:\.\d+)?)(s/it|it/s)\]", data[log_offset:].decode("utf-8", "replace"))
    if not rates:
        return None, len(data)
    value, unit = float(rates[-1][0]), rates[-1][1]
    return (value if unit == "s/it" else 1 / value), len(data)


def run(prompt, log_offset):
    poller = VramPoller()
    poller.start()
    start = time.time()
    req = urllib.request.Request(base + "/prompt", data=json.dumps({"prompt": prompt}).encode(),
                                 headers={"Content-Type": "application/json"})
    prompt_id = json.loads(urllib.request.urlopen(req).read())["prompt_id"]
    while prompt_id not in (history := get(f"/history/{prompt_id}")):
        time.sleep(0.25)
    wall = time.time() - start
    poller.stop = True
    poller.join()

    entry = history[prompt_id]
    if entry["status"]["status_str"] != "success":
        raise SystemExit(f"failed: {json.dumps(entry['status']['messages'], indent=2)}")
    stamps = {m[0]: m[1]["timestamp"] for m in entry["status"]["messages"]}
    s_per_it, log_offset = sampler_rate(log_offset)
    image = next(o["images"][0] for o in entry["outputs"].values() if "images" in o)
    return {
        "wall_s": round(wall, 1),
        "exec_s": round((stamps["execution_success"] - stamps["execution_start"]) / 1000, 1),
        "s_per_it": round(s_per_it, 2) if s_per_it else None,
        "peak_vram_gb": round((poller.total - poller.min_free) / 1e9, 2) if poller.min_free is not None else None,
        "min_free_ram_gb": round(poller.min_ram / 1e9, 1) if poller.min_ram is not None else None,
        "image": f"{image['subfolder']}/{image['filename']}",
    }, log_offset


cases = json.loads(Path(args.cases).read_text(encoding="utf-8"))
if args.only:
    cases = [c for c in cases if c["name"] in args.only.split(",")]

stats = get("/system_stats")
dev = stats["devices"][0]
results = {"system": {"gpu": dev["name"], "vram_total_gb": round(dev["vram_total"] / 1e9, 1),
                      "ram_total_gb": round(stats["system"]["ram_total"] / 1e9, 1),
                      "pytorch": stats["system"]["pytorch_version"], "comfyui": stats["system"]["comfyui_version"]},
           "runs": []}
log_offset = Path(args.server_log).stat().st_size if args.server_log else 0
outputs = {}
if args.append and Path(args.out).exists():
    previous = json.loads(Path(args.out).read_text(encoding="utf-8"))["runs"]
    rerun = {c["name"] for c in cases}
    results["runs"] = [r for r in previous if r["name"] not in rerun]
    for r in previous:
        outputs.setdefault(r["name"], r["image"])

for case in cases:
    workflow = json.loads((WORKFLOWS / f"{case['workflow']}.json").read_text(encoding="utf-8"))
    prompt = to_api(workflow)
    set_input(prompt, "TextEncodeQwenImage21", "prompt", case["prompt"])
    set_input(prompt, "SaveImage", "filename_prefix", f"bench/{case['name']}")
    if args.clip:
        set_input(prompt, "CLIPLoader", "clip_name", args.clip)
    if "input_from" in case:
        set_input(prompt, "LoadImage", "image", upload(outputs[case["input_from"]]))
    ksampler = next(n for n in prompt.values() if n["class_type"] == "KSampler")["inputs"]

    seeds = [case["seed"]] + ([case["seed"] + 1] if case.get("repeat_seed") else [])
    for i, seed in enumerate(seeds):
        ksampler["seed"] = seed
        r, log_offset = run(prompt, log_offset)
        outputs.setdefault(case["name"], r["image"])
        latent = next((n["inputs"] for n in prompt.values() if n["class_type"] == "EmptyLatentImage"), None)
        r = {"name": case["name"], "workflow": case["workflow"], "kind": "same prompt, new seed" if i else "new prompt",
             "size": f"{latent['width']}x{latent['height']}" if latent else "from input",
             "steps": ksampler["steps"], "denoise": ksampler["denoise"], "seed": seed, "prompt": case["prompt"], **r}
        results["runs"].append(r)
        print(f"{r['name']:<16} {r['kind']:<22} {r['size']:>10} {r['steps']:>2} steps  "
              f"wall {r['wall_s']:>6.1f}s  {r['s_per_it'] or '-':>5} s/it  peak {r['peak_vram_gb']} GB  min free RAM {r['min_free_ram_gb']} GB", flush=True)
        Path(args.out).write_text(json.dumps(results, indent=2), encoding="utf-8")
