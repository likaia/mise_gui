#!/usr/bin/env python3
"""Render transparent app icons from the SVG logo.

The SVG is rendered by Chrome headless into a transparent 1024x1024 PNG. Pillow
then creates the platform icon sizes from that source image.
"""

from __future__ import annotations

import base64
import io
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SVG_PATH = ROOT / "assets/branding/mise_gui_logo.svg"
BASE_PNG_PATH = ROOT / "assets/branding/mise_gui_logo_1024.png"
LINUX_ICON_PATH = ROOT / "linux/runner/resources/app_icon.png"
WINDOWS_ICO_PATH = ROOT / "windows/runner/resources/app_icon.ico"
MACOS_APP_ICONSET = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
MACOS_VOLUME_ICONSET = ROOT / "packaging/macos/volume-icon.iconset"
MACOS_VOLUME_ICNS = ROOT / "packaging/macos/volume-icon.icns"

CHROME_CANDIDATES = [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    shutil.which("google-chrome"),
    shutil.which("chromium"),
    shutil.which("chromium-browser"),
]

MACOS_APP_SIZES = {
    "app_icon_16.png": 16,
    "app_icon_32.png": 32,
    "app_icon_64.png": 64,
    "app_icon_128.png": 128,
    "app_icon_256.png": 256,
    "app_icon_512.png": 512,
    "app_icon_1024.png": 1024,
}

MACOS_VOLUME_SIZES = {
    "icon_16x16.png": 16,
    "icon_16x16@2x.png": 32,
    "icon_32x32.png": 32,
    "icon_32x32@2x.png": 64,
    "icon_128x128.png": 128,
    "icon_128x128@2x.png": 256,
    "icon_256x256.png": 256,
    "icon_256x256@2x.png": 512,
    "icon_512x512.png": 512,
    "icon_512x512@2x.png": 1024,
}

WINDOWS_ICO_SIZES = [16, 24, 32, 48, 64, 128, 256]


def main() -> int:
    chrome_path = next(
        (Path(path) for path in CHROME_CANDIDATES if path and Path(path).exists()),
        None,
    )
    if chrome_path is None:
        print("Chrome/Chromium was not found; cannot render SVG via browser canvas.")
        return 1

    base_image = render_svg_with_chrome(chrome_path)
    ensure_transparent_corners(base_image)

    save_png(base_image, BASE_PNG_PATH)
    save_png(resize(base_image, 512), LINUX_ICON_PATH)
    write_iconset(base_image, MACOS_APP_ICONSET, MACOS_APP_SIZES)
    write_iconset(base_image, MACOS_VOLUME_ICONSET, MACOS_VOLUME_SIZES)
    write_icns()
    write_ico(base_image, WINDOWS_ICO_PATH)

    print("Rendered transparent icons from", SVG_PATH)
    return 0


def render_svg_with_chrome(chrome_path: Path) -> Image.Image:
    svg_data = base64.b64encode(SVG_PATH.read_bytes()).decode("ascii")
    html = f"""<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    html, body {{
      margin: 0;
      width: 1024px;
      height: 1024px;
      overflow: hidden;
      background: transparent;
    }}
    canvas {{
      display: block;
      width: 1024px;
      height: 1024px;
    }}
  </style>
</head>
<body>
  <canvas id="icon" width="1024" height="1024"></canvas>
  <script>
    const canvas = document.getElementById('icon');
    const context = canvas.getContext('2d');
    const image = new Image();
    image.onload = () => context.drawImage(image, 0, 0, 1024, 1024);
    image.src = 'data:image/svg+xml;base64,{svg_data}';
  </script>
</body>
</html>
"""

    with tempfile.TemporaryDirectory(prefix="mise-gui-icons-") as tmp:
        tmp_path = Path(tmp)
        html_path = tmp_path / "render.html"
        screenshot_path = tmp_path / "icon.png"
        profile_path = tmp_path / "chrome-profile"
        html_path.write_text(html, encoding="utf-8")

        command = [
            str(chrome_path),
            "--headless=new",
            "--disable-gpu",
            "--hide-scrollbars",
            "--no-first-run",
            f"--user-data-dir={profile_path}",
            "--force-device-scale-factor=1",
            "--window-size=1024,1024",
            "--default-background-color=00000000",
            "--virtual-time-budget=1000",
            f"--screenshot={screenshot_path}",
            html_path.as_uri(),
        ]
        try:
            subprocess.run(
                command,
                check=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=20,
            )
        except subprocess.TimeoutExpired:
            if not screenshot_path.exists():
                raise

        return Image.open(screenshot_path).convert("RGBA")


def ensure_transparent_corners(image: Image.Image) -> None:
    if image.size != (1024, 1024):
        raise RuntimeError(f"Expected 1024x1024 render, got {image.size}")

    corners = [
        image.getpixel((0, 0))[3],
        image.getpixel((1023, 0))[3],
        image.getpixel((0, 1023))[3],
        image.getpixel((1023, 1023))[3],
    ]
    if any(alpha != 0 for alpha in corners):
        raise RuntimeError(f"Rendered icon corners are not transparent: {corners}")


def resize(image: Image.Image, size: int) -> Image.Image:
    return image.resize((size, size), Image.Resampling.LANCZOS)


def save_png(image: Image.Image, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    image.save(path, format="PNG", optimize=True, compress_level=9)


def write_iconset(
    base_image: Image.Image,
    iconset_path: Path,
    sizes_by_name: dict[str, int],
) -> None:
    iconset_path.mkdir(parents=True, exist_ok=True)
    for filename, size in sizes_by_name.items():
        save_png(resize(base_image, size), iconset_path / filename)


def write_icns() -> None:
    iconutil = shutil.which("iconutil")
    if iconutil is None:
        print("iconutil not found; skipped macOS volume-icon.icns")
        return

    subprocess.run(
        [
            iconutil,
            "-c",
            "icns",
            str(MACOS_VOLUME_ICONSET),
            "-o",
            str(MACOS_VOLUME_ICNS),
        ],
        check=True,
    )


def write_ico(base_image: Image.Image, path: Path) -> None:
    png_payloads: list[tuple[int, bytes]] = []
    for size in WINDOWS_ICO_SIZES:
        buffer = io.BytesIO()
        resize(base_image, size).save(
            buffer,
            format="PNG",
            optimize=True,
            compress_level=9,
        )
        png_payloads.append((size, buffer.getvalue()))

    header_size = 6 + 16 * len(png_payloads)
    offset = header_size
    directory_entries = []
    for size, payload in png_payloads:
        directory_entries.append(
            struct.pack(
                "<BBBBHHII",
                0 if size == 256 else size,
                0 if size == 256 else size,
                0,
                0,
                1,
                32,
                len(payload),
                offset,
            )
        )
        offset += len(payload)

    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as output:
        output.write(struct.pack("<HHH", 0, 1, len(png_payloads)))
        output.write(b"".join(directory_entries))
        for _, payload in png_payloads:
            output.write(payload)


if __name__ == "__main__":
    sys.exit(main())
