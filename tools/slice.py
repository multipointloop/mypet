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


def fill_patch(arr: np.ndarray, rect: list[int], feather: int = 6) -> None:
    """Fill rect with a smooth skin-toned gradient (v2).

    v2 changes vs the first version:
      * border colours are sampled with a MEDIAN over a wider band, so lashes /
        bangs at the patch edge no longer darken the fill;
      * the replacement RGB is feathered into the original border pixels, which
        removes the visible hard-edged rectangle that showed on light desktops.
    """
    x0, y0, x1, y1 = rect
    h, w = y1 - y0, x1 - x0
    if h <= 0 or w <= 0:
        return
    band = 4
    left = np.median(arr[y0:y1, max(x0 - band, 0):x0, :3], axis=1)
    right = np.median(arr[y0:y1, x1:min(x1 + band, arr.shape[1]), :3], axis=1)
    t = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :, None]
    grad = left[:, None, :] * (1 - t) + right[:, None, :] * t
    region = arr[y0:y1, x0:x1]
    original = region[:, :, :3].astype(np.float32).copy()
    filled = np.clip(grad, 0, 255).astype(np.float32)
    fx = np.minimum(np.arange(w), np.arange(w)[::-1]).astype(np.float32)
    fy = np.minimum(np.arange(h), np.arange(h)[::-1]).astype(np.float32)
    dist = np.minimum(fx[None, :], fy[:, None])
    ramp = np.clip(dist / float(feather), 0.0, 1.0)[:, :, None]
    region[:, :, :3] = (filled * ramp + original * (1.0 - ramp)).astype(np.uint8)
    region[:, :, 3] = 255


def feather_border(piece: np.ndarray, px: int = 4) -> None:
    """Ramp alpha down over the outermost px pixels (eye layers blend into the face)."""
    h, w = piece.shape[:2]
    a = piece[:, :, 3].astype(np.float32)
    ramp = np.ones((h, w), dtype=np.float32)
    for i in range(px):
        f = (i + 1) / float(px + 1)
        ramp[i, :] = np.minimum(ramp[i, :], f)
        ramp[h - 1 - i, :] = np.minimum(ramp[h - 1 - i, :], f)
        ramp[:, i] = np.minimum(ramp[:, i], f)
        ramp[:, w - 1 - i] = np.minimum(ramp[:, w - 1 - i], f)
    piece[:, :, 3] = np.clip(a * ramp, 0, 255).astype(np.uint8)


def feather_bottom(piece: np.ndarray, px: int = 14) -> None:
    """Fade the bottom edge so the head/body collar overlap shows no hard line."""
    h = piece.shape[0]
    a = piece[:, :, 3].astype(np.float32)
    ramp = np.ones(h, dtype=np.float32)
    for i in range(px):
        ramp[h - 1 - i] = (i + 1) / float(px + 1)
    piece[:, :, 3] = np.clip(a * ramp[:, None], 0, 255).astype(np.uint8)


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
    src = Image.open(ROOT / "source_assets" / "pet_full.png").convert("RGBA")
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
        if layer["name"] in ("eyeL", "eyeR"):
            feather_border(piece, 4)
        elif layer["name"] == "head":
            feather_bottom(piece, 14)
        out = out_dir / f"{layer['name']}.png"
        Image.fromarray(piece, "RGBA").save(out)
        print(f"[slice] {out.name:<12} crop=({x0},{y0})-({x1},{y1}) {x1-x0}x{y1-y0}")
    print("[slice] done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
