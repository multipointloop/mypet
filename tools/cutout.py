"""MyPet asset pipeline - step 1: cut the character out of 1.jpg.

Input : ../1.jpg                (original photo-background artwork)
Output: ../source_assets/pet_full.png        (transparent RGBA, SAME canvas
        size as the source so every rig.json coordinate equals a source pixel)

Keep-canvas rule: we intentionally do NOT trim the empty border - rig.json
coordinates must stay valid against both 1.jpg (coord_picker.html) and the
cutout. A QA preview with checkerboard is written next to the output.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent


def main() -> int:
    src = ROOT / "source_assets" / "1.jpg"
    out_dir = ROOT / "source_assets"
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / "pet_full.png"

    img = Image.open(src).convert("RGB")
    print(f"[cutout] source {src.name} {img.size[0]}x{img.size[1]}")

    from rembg import new_session, remove

    session = new_session("u2net")
    cut = remove(img, session=session)  # RGBA PIL image
    if cut.size != img.size:
        cut = cut.resize(img.size, Image.LANCZOS)

    # clean faint halo noise: hard-zero very low alpha, keep soft edges above
    arr = np.array(cut)
    alpha = arr[:, :, 3]
    alpha[alpha < 10] = 0
    arr[:, :, 3] = alpha
    cut = Image.fromarray(arr, "RGBA")

    cut.save(out)
    coverage = float((arr[:, :, 3] > 0).mean())
    print(f"[cutout] wrote {out.relative_to(ROOT)}  alpha-coverage={coverage:.1%}")

    # checkerboard QA preview
    h, w = arr.shape[:2]
    yy, xx = np.mgrid[0:h:16, 0:w:16]
    board = (16 * ((xx // 1) + (yy // 1))) % 32
    checker = np.where(board[:, :, None] % 32 == 0, 200, 240).astype(np.uint8)
    checker = np.repeat(np.repeat(checker, 16, axis=0), 16, axis=1)[:h, :w]
    a = arr[:, :, 3:4].astype(np.float32) / 255.0
    comp = (arr[:, :, :3] * a + checker * (1 - a)).astype(np.uint8)
    Image.fromarray(comp, "RGB").save(out.with_name("pet_preview.jpg"), quality=90)
    print(f"[cutout] QA preview: {out.with_name('pet_preview.jpg').relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
