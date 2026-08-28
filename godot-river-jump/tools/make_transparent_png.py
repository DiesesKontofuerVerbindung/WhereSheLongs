"""Convert character JPEGs to cropped transparent PNGs."""
from __future__ import annotations

from collections import deque
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "assets" / "characters"

JOBS = [
    ("player.jpg", "player.png", "flood", 4),
    ("reflection.jpg", "reflection.png", "flood", 2),
]


def lum(r: int, g: int, b: int) -> float:
    return 0.299 * r + 0.587 * g + 0.114 * b


def flood_background(im: Image.Image, edge_cutoff: int) -> Image.Image:
    rgb = im.convert("RGB")
    w, h = rgb.size
    px = rgb.load()
    bg = [[False] * w for _ in range(h)]

    def dark(x: int, y: int) -> bool:
        r, g, b = px[x, y]
        return lum(r, g, b) <= edge_cutoff

    q: deque[tuple[int, int]] = deque()
    for x in range(w):
        for y in (0, h - 1):
            if dark(x, y):
                q.append((x, y))
                bg[y][x] = True
    for y in range(h):
        for x in (0, w - 1):
            if not bg[y][x] and dark(x, y):
                q.append((x, y))
                bg[y][x] = True

    while q:
        x, y = q.popleft()
        for nx, ny in ((x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)):
            if 0 <= nx < w and 0 <= ny < h and not bg[ny][nx] and dark(nx, ny):
                bg[ny][nx] = True
                q.append((nx, ny))

    out = Image.new("RGBA", (w, h))
    opx = out.load()
    for y in range(h):
        for x in range(w):
            r, g, b = px[x, y]
            a = 0 if bg[y][x] else 255
            opx[x, y] = (r, g, b, a)
    return out


def cutoff_background(im: Image.Image, cutoff: int) -> Image.Image:
    out = im.convert("RGBA")
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            r, g, b, _a = px[x, y]
            if lum(r, g, b) <= cutoff:
                px[x, y] = (r, g, b, 0)
    return out


def crop_content(im: Image.Image) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    pad = 4
    w, h = im.size
    l = max(0, bbox[0] - pad)
    t = max(0, bbox[1] - pad)
    r = min(w, bbox[2] + pad)
    b = min(h, bbox[3] + pad)
    return im.crop((l, t, r, b))


def convert(src: Path, dst: Path, mode: str, param: int) -> None:
    im = Image.open(src)
    if mode == "flood":
        out = flood_background(im, param)
    else:
        out = cutoff_background(im, param)
    out = crop_content(out)
    out.save(dst, "PNG")
    alpha = out.split()[-1]
    opaque = sum(1 for p in alpha.get_flattened_data() if p > 0)
    print(f"{src.name} -> {dst.name}  {out.size}  opaque={opaque}")


def make_reflection_from_player(player_png: Path, dst: Path) -> None:
    """13_6 source is fully black; derive reflection from player silhouette."""
    im = Image.open(player_png).convert("RGBA")
    px = im.load()
    w, h = im.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            px[x, y] = (max(0, r // 4), max(0, g // 4), max(0, b // 4), int(a * 0.55))
    im.save(dst, "PNG")
    print(f"derived reflection -> {dst.name}  {im.size}")


def main() -> None:
    for src_name, dst_name, mode, param in JOBS:
        src = ROOT / src_name
        dst = ROOT / dst_name
        if not src.exists():
            print(f"skip missing {src}")
            continue
        convert(src, dst, mode, param)

    player_png = ROOT / "player.png"
    reflection_png = ROOT / "reflection.png"
    if player_png.exists():
        alpha = Image.open(reflection_png).split()[-1]
        if sum(1 for p in alpha.get_flattened_data() if p > 0) < 100:
            make_reflection_from_player(player_png, reflection_png)


if __name__ == "__main__":
    main()
