#!/usr/bin/env python
"""
fix_gguf_arch.py <path-to-qwen-image.gguf>

The KasugaiSakura Qwen-Image-2.1 GGUFs ship WITHOUT a `general.architecture`
metadata field, so ComfyUI-GGUF can't identify them ("Unknown model architecture!").
This injects `general.architecture = qwen_image` (lossless: tensors are copied
byte-for-byte via the gguf library's own round-trip helper) and replaces the file
in place. Idempotent — running it again is a no-op.
"""
import sys, os, gguf
from gguf.scripts.gguf_new_metadata import copy_with_new_metadata

def main(path):
    r = gguf.GGUFReader(path)
    cur = r.fields.get("general.architecture")
    if cur is not None and cur.contents() == "qwen_image":
        print(f"[fix_gguf_arch] already tagged qwen_image: {path}")
        return
    tmp = path + ".archfixed"
    w = gguf.GGUFWriter(tmp, arch="qwen_image", endianess=r.endianess)
    copy_with_new_metadata(r, w, new_metadata={}, remove_metadata=[])
    # verify
    r2 = gguf.GGUFReader(tmp)
    assert r2.fields["general.architecture"].contents() == "qwen_image"
    assert len(r2.tensors) == len(r.tensors), "tensor count mismatch!"
    del r, r2
    os.replace(tmp, path)
    print(f"[fix_gguf_arch] tagged qwen_image: {path}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(1)
    main(sys.argv[1])
