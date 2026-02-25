#!/usr/bin/env python3
"""Draw bounding boxes from a Zero-Clean JSON onto the matching image.
Use this to verify that normalized coordinates match the image (e.g. after
opening the image elsewhere).

Usage:
  python draw_annotations.py <folder>
  python draw_annotations.py .

Finds <folder>/<name>.json and <folder>/<name>.<ext> (jpg/png/etc.),
draws each annotation's bbox and full_label, saves <folder>/<name>_annotated.<ext>.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Install Pillow: pip install Pillow")
    sys.exit(1)


def find_image_for_json(json_path: Path) -> Path | None:
    """Return path to an image with same stem as json_path, or None."""
    stem = json_path.stem
    for ext in (".jpg", ".jpeg", ".png", ".webp", ".bmp"):
        candidate = json_path.parent / f"{stem}{ext}"
        if candidate.exists():
            return candidate
    return None


def normalized_to_pixels(bbox: list[float], img_w: int, img_h: int) -> tuple[int, int, int, int]:
    """Convert [x, y, w, h] normalized 0-1 to pixel (left, top, right, bottom)."""
    x, y, w, h = bbox[0], bbox[1], bbox[2], bbox[3]
    left = int(x * img_w)
    top = int(y * img_h)
    right = int((x + w) * img_w)
    bottom = int((y + h) * img_h)
    return (left, top, right, bottom)


def main() -> None:
    if len(sys.argv) < 2:
        folder = Path(".")
    else:
        folder = Path(sys.argv[1])

    if not folder.is_dir():
        print(f"Not a directory: {folder}")
        sys.exit(1)

    # Find first .json in folder
    json_files = list(folder.glob("*.json"))
    if not json_files:
        print(f"No .json file found in {folder}")
        sys.exit(1)

    json_path = json_files[0]
    image_path = find_image_for_json(json_path)
    if not image_path:
        print(f"No image found for {json_path.name} (expected same name with .jpg/.png etc.)")
        sys.exit(1)

    with open(json_path, encoding="utf-8") as f:
        data = json.load(f)

    annotations = data.get("annotations", [])
    if not annotations:
        print(f"No annotations in {json_path.name}")
        sys.exit(0)

    img = Image.open(image_path).convert("RGB")
    img_w, img_h = img.size
    draw = ImageDraw.Draw(img)

    # Try a slightly larger font if available
    try:
        font = ImageFont.truetype("arial.ttf", size=max(14, min(img_w, img_h) // 40))
    except OSError:
        try:
            font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", size=14)
        except OSError:
            font = ImageFont.load_default()

    for ann in annotations:
        bbox_norm = ann.get("bbox")
        if not bbox_norm or len(bbox_norm) != 4:
            continue
        label = ann.get("full_label", "?")
        left, top, right, bottom = normalized_to_pixels(bbox_norm, img_w, img_h)

        # Draw rectangle (green, width 3)
        draw.rectangle([left, top, right, bottom], outline=(0, 255, 0), width=3)
        # Draw label background and text
        if hasattr(draw, "textbbox"):
            text_bbox = draw.textbbox((0, 0), label, font=font)
            tw, th = text_bbox[2] - text_bbox[0], text_bbox[3] - text_bbox[1]
        else:
            tw, th = draw.textsize(label, font=font)
        draw.rectangle([left, top - th - 4, left + tw + 4, top], fill=(0, 255, 0))
        draw.text((left + 2, top - th - 2), label, fill=(0, 0, 0), font=font)

    out_name = f"{image_path.stem}_annotated{image_path.suffix}"
    out_path = folder / out_name
    img.save(out_path)
    print(f"Saved: {out_path}")


if __name__ == "__main__":
    main()
