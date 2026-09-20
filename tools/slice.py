"""MyPet asset pipeline - step 2: slice pet_full.png into rig layers.

Reads  mypet/assets/rig.json:
{
  "canvas": {"w": W, "h": H},
  "skinColor": [r, g, b],
  "eyePatches": [[x0,y0,x1,y1], ...],          # filled with skin before export
  "layers": [
    {"name": "tail",  "crop": [x0,y0,x1,y1], "patched": false},
    {"name": "body",  "crop": [x0,y0,x1,y1], "patched": true },
    {"name": "head",  "crop": [x0,y0,x1,y1], "patched": true },
    {"name": "eyeL",  "crop": [x0,y0,x1,y1], "patched": false},
    {"name": "eyeR",  "crop": [x0,y0,x1,y1], "patched": false}
  ]
}

"patched" layers get every eyePatches rect filled with a smooth per-row
horizontal gradient sampled from the patch border - that is what lets the
eye layers slide around without leaving a ghost eye underneath.

Outputs: mypet/assets/parts/<name>.png
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "mypet" / "assets"


def fill_patch(arr: np.ndarray, rect: list[int]) -> None:
    """Fill rect with a per-row horizontal gradient from border pixels."""
    x0, y0, x1, y1 = rect
    h, w = y1 - y0, x1 - x0
    if h <= 0 or w <= 0:
        return
    left = arr[y0:y1, max(x0 - 2, 0):x0, :3].mean(axis=1)   # (h, 3)
    right = arr[y0:y1, x1:min(x1 + 2, arr.shape[1]), :3].mean(axis=1)
    t = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :, None]  # (1,w,1)
    grad = left[:, None, :] * (1 - t) + right[:, None, :] * t
    region = arr[y0:y1, x0:x1]
    region[:, :, :3] = np.clip(grad, 0, 255).astype(np.uint8)
    region[:, :, 3] = 255


def erase_color_mask(piece: np.ndarray, rect: list[int], pred: str,
                     dilate_px: int, layer_origin: tuple[int, int]) -> None:
    """Zero alpha where pixels inside `rect` match a color predicate.

    Used to remove the static tail from the body layer so wagging the tail
    layer does not leave a ghost tail behind. Pink predicate matches the
    tail/hair pink but not the grey-blue dress or white socks.
    """
    lx0, ly0 = layer_origin
    x0, y0, x1, y1 = rect
    ix0, iy0 = max(x0, lx0), max(y0, ly0)
    ix1, iy1 = min(x1, lx0 + piece.shape[1]), min(y1, ly0 + piece.shape[0])
    if ix0 >= ix1 or iy0 >= iy1:
        return
    sub = piece[iy0 - ly0:iy1 - ly0, ix0 - lx0:ix1 - lx0]
    r = sub[:, :, 0].astype(np.int16)
    g = sub[:, :, 1].astype(np.int16)
    b = sub[:, :, 2].astype(np.int16)
    if pred == "pink":
        core = (r - g > 12) & (r - b > 6) & (r > 170) & (sub[:, :, 3] > 0)
    else:
        return
    if dilate_px > 0:  # catch anti-aliased fringe around the tail
        m = core.copy()
        for dy in range(-dilate_px, dilate_px + 1):
            for dx in range(-dilate_px, dilate_px + 1):
                m |= np.roll(np.roll(core, dy, axis=0), dx, axis=1)
    else:
        m = core
    # never bite into fully-opaque non-pink pixels (skirt / leg edges):
    # the 2px dilation may only remove pink cores or semi-transparent fringe
    mask = m & (core | (sub[:, :, 3] < 250))
    sub[:, :, 3][mask] = 0


def main() -> int:
    rig = json.loads((ASSETS / "rig.json").read_text(encoding="utf-8"))
    src = Image.open(ASSETS / "parts" / "pet_full.png").convert("RGBA")
    cw, ch = rig["canvas"]["w"], rig["canvas"]["h"]
    if src.size != (cw, ch):
        sys.exit(f"[slice] canvas mismatch: pet_full {src.size} != rig {cw}x{ch}")

    arr = np.array(src)
    patches = rig.get("eyePatches", [])
    out_dir = ASSETS / "parts"

    for layer in rig["layers"]:
        x0, y0, x1, y1 = layer["crop"]
        piece = arr[y0:y1, x0:x1].copy()
        if layer.get("patched"):
            for p in patches:
                px0, py0, px1, py1 = p
                # intersect patch with this layer's crop
                ix0, iy0, ix1, iy1 = max(px0, x0), max(py0, y0), min(px1, x1), min(py1, y1)
                if ix0 < ix1 and iy0 < iy1:
                    fill_patch(piece, [ix0 - x0, iy0 - y0, ix1 - x0, iy1 - y0])
        mask_cfg = layer.get("eraseColorMask")
        if mask_cfg:
            erase_color_mask(
                piece, mask_cfg["rect"], mask_cfg.get("pred", "pink"),
                int(mask_cfg.get("dilate", 2)), (x0, y0),
            )
        out = out_dir / f"{layer['name']}.png"
        Image.fromarray(piece, "RGBA").save(out)
        print(f"[slice] {out.name:<12} crop=({x0},{y0})-({x1},{y1}) {x1-x0}x{y1-y0}")
    print("[slice] done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
