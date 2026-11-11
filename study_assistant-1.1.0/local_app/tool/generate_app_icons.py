"""Generate legacy PNG and adaptive Android resources from the icon sources."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android" / "app" / "src" / "main" / "res"
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
PAPER = "#F7F5EC"
SHEET = "#FFFDF5"
INK = "#243E34"
SAGE = "#DFE8D8"
SAGE_DARK = "#8DAF91"


def _scaled(value: float, size: int) -> int:
    return round(value * size / 108)


def _line(draw: ImageDraw.ImageDraw, points, fill, width, size):
    draw.line(
        [(_scaled(x, size), _scaled(y, size)) for x, y in points],
        fill=fill,
        width=max(1, _scaled(width, size)),
        joint="curve",
    )


def _dot(draw: ImageDraw.ImageDraw, x, y, radius, fill, size):
    cx, cy, r = _scaled(x, size), _scaled(y, size), _scaled(radius, size)
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def _base(size: int, round_icon: bool) -> Image.Image:
    factor = 4
    canvas = size * factor
    image = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    inset = 2 * factor
    radius = round(28 * factor) if not round_icon else canvas
    draw.rounded_rectangle(
        (inset, inset, canvas - inset, canvas - inset),
        radius=radius,
        fill=PAPER,
    )
    return image


def _draw_a(draw: ImageDraw.ImageDraw, size: int):
    factor = size // 48 if size >= 48 else 1
    width = max(1, round(size / 48))
    outer = [(17, 36), (37, 30), (52, 37), (67, 30), (91, 36),
             (89, 82), (68, 73), (54, 84), (39, 73), (19, 82)]
    left = [(24, 41), (37, 37), (49, 43), (49, 75), (38, 69), (24, 73)]
    right = [(84, 41), (71, 37), (59, 43), (59, 75), (70, 69), (84, 73)]
    draw.polygon([(_scaled(x, size), _scaled(y, size)) for x, y in outer],
                 fill=SAGE_DARK)
    _line(draw, [*left, left[0]], INK, 4, size)
    draw.polygon([(_scaled(x, size), _scaled(y, size)) for x, y in left],
                 fill=SHEET)
    _line(draw, [*left, left[0]], INK, 4, size)
    draw.polygon([(_scaled(x, size), _scaled(y, size)) for x, y in right],
                 fill=SHEET)
    _line(draw, [*right, right[0]], INK, 4, size)
    _line(draw, [(54, 40), (54, 78)], INK, 4, size)
    _line(draw, [(62, 62), (68, 68), (80, 54)], INK, 6, size)
    _dot(draw, 62, 62, 3, INK, size)
    _dot(draw, 80, 54, 3, INK, size)


def _draw_b(draw: ImageDraw.ImageDraw, size: int):
    def box(x0, y0, x1, y1, radius, fill):
        draw.rounded_rectangle(
            (_scaled(x0, size), _scaled(y0, size),
             _scaled(x1, size), _scaled(y1, size)),
            radius=_scaled(radius, size),
            fill=fill,
        )

    box(23, 18, 85, 90, 10, INK)
    box(31, 26, 77, 82, 5, SHEET)
    box(27, 22, 36, 86, 4.5, SAGE)
    box(31, 67, 78, 82, 3, PAPER)
    draw.polygon(
        [(_scaled(62, size), _scaled(18, size)),
         (_scaled(77, size), _scaled(18, size)),
         (_scaled(77, size), _scaled(63, size)),
         (_scaled(69.5, size), _scaled(56, size)),
         (_scaled(62, size), _scaled(63, size))],
        fill=SAGE_DARK,
    )
    _line(draw, [(34, 72), (78, 72)], SHEET, 2, size)


def _render(candidate: str, size: int, round_icon: bool) -> Image.Image:
    factor = 4
    image = _base(size, round_icon)
    draw = ImageDraw.Draw(image)
    if candidate == "a":
        _draw_a(draw, size * factor)
    elif candidate == "b":
        _draw_b(draw, size * factor)
    else:
        raise ValueError(candidate)
    return image.resize((size, size), Image.Resampling.LANCZOS)


def _foreground(candidate: str) -> str:
    if candidate == "a":
        return """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="#8DAF91"
      android:pathData="M17,36 L37,30 L52,37 L67,30 L91,36 L89,82 L68,73 L54,84 L39,73 L19,82 Z"/>
  <path android:fillColor="#FFFDF5" android:strokeColor="#243E34"
      android:strokeWidth="4" android:strokeLineJoin="round"
      android:pathData="M24,41 L37,37 L49,43 L49,75 L38,69 L24,73 Z"/>
  <path android:fillColor="#FFFDF5" android:strokeColor="#243E34"
      android:strokeWidth="4" android:strokeLineJoin="round"
      android:pathData="M84,41 L71,37 L59,43 L59,75 L70,69 L84,73 Z"/>
  <path android:fillColor="@android:color/transparent" android:strokeColor="#243E34"
      android:strokeWidth="4" android:strokeLineCap="round"
      android:pathData="M54,40 L54,78"/>
  <path android:fillColor="@android:color/transparent" android:strokeColor="#243E34"
      android:strokeWidth="6" android:strokeLineCap="round" android:strokeLineJoin="round"
      android:pathData="M62,62 L68,68 L80,54"/>
</vector>
"""
    return """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
  <path android:fillColor="#243E34"
      android:pathData="M32,18 H76 A10,10 0 0 1 86,28 V90 H23 V28 A10,10 0 0 1 32,18 Z"/>
  <path android:fillColor="#FFFDF5"
      android:pathData="M36,26 H72 A5,5 0 0 1 77,31 V82 H31 V31 A5,5 0 0 1 36,26 Z"/>
  <path android:fillColor="#DFE8D8"
      android:pathData="M27,22 H36 V86 H27 Z"/>
  <path android:fillColor="#F7F5EC"
      android:pathData="M31,67 H78 V82 H34 A3,3 0 0 1 31,79 Z"/>
  <path android:fillColor="#8DAF91"
      android:pathData="M62,18 H77 V63 L69.5,56 L62,63 Z"/>
</vector>
"""


def _monochrome(candidate: str) -> str:
    if candidate == "a":
        path = """  <path android:fillColor="@android:color/transparent"
      android:strokeColor="#000000" android:strokeWidth="6"
      android:strokeLineJoin="round"
      android:pathData="M24,41 L37,37 L49,43 L49,75 L38,69 L24,73 Z"/>
  <path android:fillColor="@android:color/transparent"
      android:strokeColor="#000000" android:strokeWidth="6"
      android:strokeLineJoin="round"
      android:pathData="M84,41 L71,37 L59,43 L59,75 L70,69 L84,73 Z"/>
  <path android:fillColor="@android:color/transparent"
      android:strokeColor="#000000" android:strokeWidth="5"
      android:strokeLineCap="round" android:pathData="M54,40 L54,78"/>
  <path android:fillColor="@android:color/transparent"
      android:strokeColor="#000000" android:strokeWidth="7"
      android:strokeLineCap="round" android:strokeLineJoin="round"
      android:pathData="M62,62 L68,68 L80,54"/>
"""
    else:
        path = """  <path android:fillColor="@android:color/transparent"
      android:strokeColor="#000000" android:strokeWidth="6"
      android:strokeLineJoin="round"
      android:pathData="M32,18 H76 A10,10 0 0 1 86,28 V90 H23 V28 A10,10 0 0 1 32,18 Z"/>
  <path android:fillColor="#000000"
      android:pathData="M62,18 H77 V63 L69.5,56 L62,63 Z"/>
  <path android:fillColor="@android:color/transparent"
      android:strokeColor="#000000" android:strokeWidth="4"
      android:strokeLineCap="round" android:pathData="M34,74 L78,74"/>
"""
    return f"""<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
{path}</vector>
"""


def _write(path: Path, content: str):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def install(candidate: str):
    for density, size in DENSITIES.items():
        folder = RES / f"mipmap-{density}"
        _render(candidate, size, False).save(folder / "ic_launcher.png")
        _render(candidate, size, True).save(folder / "ic_launcher_round.png")
    _write(RES / "drawable" / "ic_launcher_foreground.xml", _foreground(candidate))
    _write(RES / "drawable" / "ic_launcher_monochrome.xml", _monochrome(candidate))
    background = SAGE if candidate == "a" else PAPER
    _write(
        RES / "values" / "ic_launcher_background.xml",
        '<resources>\n'
        f'  <color name="ic_launcher_background">{background}</color>\n'
        "</resources>\n",
    )
    adaptive = """<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
"""
    _write(RES / "mipmap-anydpi-v26" / "ic_launcher.xml", adaptive)
    _write(RES / "mipmap-anydpi-v26" / "ic_launcher_round.xml", adaptive)
    themed = """<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
  <background android:drawable="@color/ic_launcher_background"/>
  <foreground android:drawable="@drawable/ic_launcher_foreground"/>
  <monochrome android:drawable="@drawable/ic_launcher_monochrome"/>
</adaptive-icon>
"""
    _write(RES / "mipmap-anydpi-v33" / "ic_launcher.xml", themed)
    _write(RES / "mipmap-anydpi-v33" / "ic_launcher_round.xml", themed)


def preview(candidate: str, output: Path):
    output.mkdir(parents=True, exist_ok=True)
    _render(candidate, 192, False).save(output / f"candidate-{candidate}-192.png")
    _render(candidate, 48, False).save(output / f"candidate-{candidate}-48.png")
    _render(candidate, 192, True).save(output / f"candidate-{candidate}-round.png")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", choices=("a", "b"))
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--preview-root", type=Path)
    args = parser.parse_args()
    if args.install:
        if args.candidate is None:
            parser.error("--install requires --candidate")
        install(args.candidate)
    if args.preview_root is not None:
        if args.candidate is None:
            parser.error("--preview-root requires --candidate")
        preview(args.candidate, args.preview_root)
    if not args.install and args.preview_root is None:
        parser.error("choose --install and/or --preview-root")


if __name__ == "__main__":
    main()
