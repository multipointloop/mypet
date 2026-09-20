"""MyPet asset pipeline - step 4: app icons from the artwork head crop.

Generates:
  mypet/assets/icon/icon.png   512x512 (flutter_launcher_icons source)
  mypet/assets/icon/tray.ico   multi-size .ico for the Windows tray
"""
from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "mypet" / "assets" / "parts" / "pet_full.png"
OUT = ROOT / "mypet" / "assets" / "icon"
# head bounding box in canvas coords (see rig.json layers/head)
HEAD_CROP = (385, 322, 692, 648)


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    im = Image.open(SRC).convert("RGBA")
    head = im.crop(HEAD_CROP)

    # fit head into a square canvas with a small margin, bottom-aligned
    side = 512
    scale = (side * 0.92) / max(head.size)
    w = int(head.width * scale)
    h = int(head.height * scale)
    head_r = head.resize((w, h), Image.LANCZOS)

    canvas = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    canvas.paste(head_r, ((side - w) // 2, side - h - 12), head_r)

    # soft pink circular backdrop so the icon reads at small sizes
    bg = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    d = ImageDraw.Draw(bg)
    d.ellipse([16, 16, side - 16, side - 16], fill=(255, 214, 228, 255))
    icon = Image.alpha_composite(bg, canvas)

    icon.save(OUT / "icon.png")
    icon.resize((256, 256), Image.LANCZOS).save(
        OUT / "tray.ico",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"[icon] wrote {OUT / 'icon.png'} and tray.ico")
    return 0


if __name__ == "__main__":
    main()
