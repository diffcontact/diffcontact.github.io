#!/usr/bin/env python3
"""Crop every "Fig. N." of the paper PDF into assets/figures/figN.{png,jpg}.
The figure is the region above its caption (IEEE layout), across the caption's width, below the last body-text line
or caption above it; the render is then trimmed to its non-white content.
    usage: extract_figures.py <paper.pdf> <out_dir> [zoom]"""
import re
import sys

import fitz
from PIL import Image, ImageChops

BODY_PT = 9.5          # body text is 10 pt; captions 8 pt
HEADER_Y = 42          # running header + page number live above this


def body_blocks(page):
    """paragraph blocks of body text: long and set in the 10-pt body size (figure labels are short)"""
    out = []
    for b in page.get_text("dict")["blocks"]:
        spans = [s for l in b.get("lines", []) for s in l["spans"] if s["text"].strip()]
        if not spans:
            continue
        sizes = sorted(s["size"] for s in spans)
        if sum(len(s["text"]) for s in spans) >= 120 and sizes[len(sizes) // 2] >= BODY_PT:
            out.append(fitz.Rect(b["bbox"]))
    return out


def main():
    pdf, out = sys.argv[1], sys.argv[2]
    zoom = float(sys.argv[3]) if len(sys.argv) > 3 else 4.0
    doc = fitz.open(pdf)
    for page in doc:
        caps = []
        for b in page.get_text("blocks"):
            m = re.match(r"^(Fig\.|TABLE|Algorithm)\s*([0-9IVX]+)\.?\s", b[4].strip())
            if m and not re.match(r"^Fig\. \d+ (compares|shows)", b[4].strip()):
                caps.append((m.group(1), m.group(2), fitz.Rect(b[:4])))
        lines = body_blocks(page)
        for kind, num, cap in caps:
            if kind != "Fig.":
                continue
            x0, x1 = cap.x0 - 4, cap.x1 + 4
            top = HEADER_Y
            for r in lines + [c[2] for c in caps if c[2] != cap]:
                if r.y1 <= cap.y0 + 0.5 and min(r.x1, x1) - max(r.x0, x0) > 0.3 * r.width:
                    top = max(top, r.y1)
            for kind2, _, r in caps:                    # an algorithm box above: start below its bottom rule
                if kind2 == "Algorithm" and r.y1 <= cap.y0 and min(r.x1, x1) - max(r.x0, x0) > 0:
                    rules = [d["rect"].y1 for d in page.get_drawings() if d["rect"].height < 1.5
                             and d["rect"].width > 0.9 * (x1 - x0 - 8) and r.y1 < d["rect"].y0 < cap.y0]
                    top = max([top] + rules)
            clip = fitz.Rect(x0, top + 0.5, x1, cap.y0 - 0.5)
            pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), clip=clip, alpha=False)
            img = Image.frombytes("RGB", (pix.width, pix.height), pix.samples)
            bbox = ImageChops.difference(img, Image.new("RGB", img.size, "white")).convert("L").point(
                lambda v: 255 if v > 12 else 0).getbbox()
            pad = int(4 * zoom)
            if bbox:
                img = img.crop((max(bbox[0] - pad, 0), max(bbox[1] - pad, 0),
                                min(bbox[2] + pad, img.width), min(bbox[3] + pad, img.height)))
            photo = bool(page.get_image_info()) and any(fitz.Rect(i["bbox"]).intersects(clip)
                                                        and fitz.Rect(i["bbox"]).width > 40
                                                        for i in page.get_image_info())
            path = f"{out}/fig{num}.{'jpg' if photo else 'png'}"
            if photo:
                img.save(path, quality=90, optimize=True, progressive=True)
            else:
                img.save(path, optimize=True)
            print(f"Fig. {num}: page {page.number + 1}, clip y {clip.y0:.0f}-{clip.y1:.0f} x {clip.x0:.0f}-{clip.x1:.0f}"
                  f" -> {path.split('/')[-1]} {img.width}x{img.height}")


if __name__ == "__main__":
    main()
