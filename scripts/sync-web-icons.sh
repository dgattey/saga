#!/usr/bin/env bash
# Regenerates or verifies `server/public/` web icons, favicons, OpenGraph card, and asset manifest
# from the canonical `AppIcon.icon` bundle (`Saga/Saga/AppIcon.icon` or `Sources/Saga/AppIcon.icon`).
#
# Usage:
#   ./scripts/sync-web-icons.sh           # Regenerate web icons + update server/web-assets-manifest.json
#   ./scripts/sync-web-icons.sh --check   # Verify AppIcon.icon and server/public/ match the manifest (CI-safe, stdlib only)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE="${1:---sync}"

if [[ "$MODE" != "--sync" && "$MODE" != "--check" ]]; then
  echo "Usage: $0 [--sync|--check]" >&2
  exit 2
fi

if [[ "$MODE" == "--check" ]]; then
  python3 - "$ROOT" <<'PY'
import hashlib
import json
import os
import struct
import sys

root = sys.argv[1]
manifest_path = os.path.join(root, "server", "web-assets-manifest.json")
if not os.path.isfile(manifest_path):
    sys.stderr.write(
        "error: server/web-assets-manifest.json is missing. Run ./scripts/sync-web-icons.sh to generate it.\n"
    )
    sys.exit(1)

with open(manifest_path, "r", encoding="utf-8") as f:
    manifest = json.load(f)

icon_dir = None
for candidate in ["Saga/Saga/AppIcon.icon", "Sources/Saga/AppIcon.icon"]:
    full = os.path.join(root, candidate)
    if os.path.isdir(full):
        icon_dir = full
        break

if icon_dir is None:
    sys.stderr.write("error: Could not locate AppIcon.icon under Saga/Saga/ or Sources/Saga/.\n")
    sys.exit(1)

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def png_dimensions(path: str):
    with open(path, "rb") as fp:
        header = fp.read(24)
    if len(header) < 24 or header[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    w, h = struct.unpack(">II", header[16:24])
    return [int(w), int(h)]

errors = []

# 1. Verify canonical AppIcon.icon sources match manifest
icon_json_path = os.path.join(icon_dir, "icon.json")
if not os.path.isfile(icon_json_path):
    errors.append(f"Missing {icon_json_path}")
else:
    actual_hash = sha256_file(icon_json_path)
    expected_hash = manifest.get("source", {}).get("iconJsonSha256")
    if actual_hash != expected_hash:
        errors.append(
            "AppIcon.icon/icon.json changed since web icons were synced. "
            "Run ./scripts/sync-web-icons.sh and commit the updated server/ assets."
        )

    with open(icon_json_path, "r", encoding="utf-8") as f:
        icon_spec = json.load(f)

    expected_layers = manifest.get("source", {}).get("layers", {})
    seen_layers = []
    for group in icon_spec.get("groups", []):
        for layer in group.get("layers", []):
            img_name = layer.get("image-name")
            if img_name:
                seen_layers.append(img_name)
                layer_path = os.path.join(icon_dir, "Assets", img_name)
                if not os.path.isfile(layer_path):
                    errors.append(f"Missing AppIcon.icon layer: {layer_path}")
                else:
                    actual_layer_hash = sha256_file(layer_path)
                    if expected_layers.get(img_name) != actual_layer_hash:
                        errors.append(
                            f"AppIcon.icon layer '{img_name}' changed since web icons were synced. "
                            "Run ./scripts/sync-web-icons.sh and commit the updated server/ assets."
                        )

    if sorted(seen_layers) != sorted(expected_layers.keys()):
        errors.append(
            f"AppIcon.icon layer list ({seen_layers}) does not match manifest ({list(expected_layers.keys())}). "
            "Run ./scripts/sync-web-icons.sh."
        )

# 2. Verify generated web icons & preview screenshots in server/public/
public_dir = os.path.join(root, "server", "public")
for rel_name, meta in manifest.get("outputs", {}).items():
    out_path = os.path.join(public_dir, rel_name)
    if not os.path.isfile(out_path):
        errors.append(f"Missing server/public/{rel_name}. Run ./scripts/sync-web-icons.sh.")
        continue
    actual_out_hash = sha256_file(out_path)
    if actual_out_hash != meta.get("sha256"):
        errors.append(
            f"server/public/{rel_name} is out of sync with server/web-assets-manifest.json. "
            "Run ./scripts/sync-web-icons.sh."
        )
    expected_size = meta.get("dimensions")
    if expected_size and rel_name.endswith(".png"):
        actual_size = png_dimensions(out_path)
        if actual_size != expected_size:
            errors.append(
                f"server/public/{rel_name} dimensions {actual_size} != expected {expected_size}."
            )

# 3. Verify server/app/layout.tsx references the synced favicons and OpenGraph image
layout_path = os.path.join(root, "server", "app", "layout.tsx")
if os.path.isfile(layout_path):
    with open(layout_path, "r", encoding="utf-8") as f:
        layout_src = f.read()
    for token in ["/favicon.ico", "/favicon.svg", "/icon.png", "/apple-touch-icon.png", "/opengraph-image.png"]:
        if token not in layout_src:
            errors.append(f"server/app/layout.tsx is missing metadata reference to '{token}'.")

if errors:
    for err in errors:
        sys.stderr.write(f"error: {err}\n")
    sys.exit(1)

print("Web icons and UI preview assets in server/public/ are in sync with AppIcon.icon.")
PY
  exit 0
fi

python3 - "$ROOT" <<'PY'
import base64
import hashlib
import io
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

root = sys.argv[1]
icon_dir = None
icon_rel = None
for candidate in ["Saga/Saga/AppIcon.icon", "Sources/Saga/AppIcon.icon"]:
    full = os.path.join(root, candidate)
    if os.path.isdir(full):
        icon_dir = full
        icon_rel = candidate
        break

if icon_dir is None:
    sys.stderr.write("error: Could not locate AppIcon.icon under Saga/Saga/ or Sources/Saga/.\n")
    sys.exit(1)

icon_json_path = os.path.join(icon_dir, "icon.json")
with open(icon_json_path, "r", encoding="utf-8") as f:
    icon_spec = json.load(f)

# Composite layers back-to-front (icon.json lists groups front-to-back)
canvas_size = 1024
full_bleed = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
layer_hashes = {}

def sha256_file(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fp:
        for chunk in iter(lambda: fp.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

for group in reversed(icon_spec.get("groups", [])):
    for layer in group.get("layers", []):
        img_name = layer.get("image-name")
        if not img_name:
            continue
        layer_path = os.path.join(icon_dir, "Assets", img_name)
        layer_hashes[img_name] = sha256_file(layer_path)
        layer_img = Image.open(layer_path).convert("RGBA")
        if layer_img.size != (canvas_size, canvas_size):
            layer_img = layer_img.resize((canvas_size, canvas_size), Image.LANCZOS)
        full_bleed = Image.alpha_composite(full_bleed, layer_img)

# Build smooth anti-aliased squircle mask (4x supersampled rounded rectangle r=229 on 1024x1024)
ss = 4
mask_ss = Image.new("L", (canvas_size * ss, canvas_size * ss), 0)
ImageDraw.Draw(mask_ss).rounded_rectangle(
    (0, 0, canvas_size * ss - 1, canvas_size * ss - 1),
    radius=229 * ss,
    fill=255,
)
squircle_mask_1024 = mask_ss.resize((canvas_size, canvas_size), Image.LANCZOS)

squircle_1024 = full_bleed.copy()
squircle_1024.putalpha(squircle_mask_1024)

public_dir = os.path.join(root, "server", "public")
os.makedirs(public_dir, exist_ok=True)

# 1. Save RGBA squircle PNGs
squircle_sizes = {
    "app-icon.png": 1024,
    "icon.png": 1024,
    "icon-512.png": 512,
    "icon-192.png": 192,
    "favicon-64x64.png": 64,
    "favicon-32x32.png": 32,
    "favicon-16x16.png": 16,
}

for filename, px in squircle_sizes.items():
    out_img = squircle_1024 if px == 1024 else squircle_1024.resize((px, px), Image.LANCZOS)
    out_img.save(os.path.join(public_dir, filename), format="PNG", optimize=True)

# 2. Save opaque 180x180 apple-touch-icon.png (iOS applies its own home-screen squircle mask)
apple_touch = full_bleed.convert("RGB").resize((180, 180), Image.LANCZOS)
apple_touch.save(os.path.join(public_dir, "apple-touch-icon.png"), format="PNG", optimize=True)

# 3. Save multi-resolution favicon.ico (16x16, 32x32, 48x48)
ico_base = squircle_1024.resize((256, 256), Image.LANCZOS)
ico_base.save(
    os.path.join(public_dir, "favicon.ico"),
    format="ICO",
    sizes=[(16, 16), (32, 32), (48, 48)],
)

# 4. Save crisp favicon.svg embedding a 128x128 squircle PNG
buf_128 = io.BytesIO()
squircle_1024.resize((128, 128), Image.LANCZOS).save(buf_128, format="PNG", optimize=True)
b64_128 = base64.b64encode(buf_128.getvalue()).decode("ascii")
svg_content = (
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">\n'
    f'  <image width="128" height="128" href="data:image/png;base64,{b64_128}" />\n'
    "</svg>\n"
)
with open(os.path.join(public_dir, "favicon.svg"), "w", encoding="utf-8") as f:
    f.write(svg_content)

# 5. Save site.webmanifest
webmanifest = {
    "name": "Saga",
    "short_name": "Saga",
    "description": "Personal library & reading tracker for macOS and iOS — editorial reviews, private notes, ⌘K Spotlight search, and Contentful + Goodreads sync.",
    "start_url": "/",
    "display": "standalone",
    "background_color": "#0e1a15",
    "theme_color": "#264e3a",
    "icons": [
        {"src": "/icon-192.png", "sizes": "192x192", "type": "image/png"},
        {"src": "/icon-512.png", "sizes": "512x512", "type": "image/png"},
    ],
}
with open(os.path.join(public_dir, "site.webmanifest"), "w", encoding="utf-8") as f:
    json.dump(webmanifest, f, indent=2)
    f.write("\n")

# 6. Generate 1200x630 OpenGraph social image (opengraph-image.png)
og_w, og_h = 1200, 630
yy, xx = np.mgrid[0:og_h, 0:og_w].astype(np.float32)
# Deep botanical radial gradient background matching page.module.css
bg = np.zeros((og_h, og_w, 3), dtype=np.float32)
bg[..., 0] = 14.0
bg[..., 1] = 26.0
bg[..., 2] = 21.0
g1 = np.exp(-(((xx - 240.0) / 680.0) ** 2 + ((yy - 40.0) / 420.0) ** 2))
g2 = np.exp(-(((xx - 1080.0) / 560.0) ** 2 + ((yy - 560.0) / 380.0) ** 2))
bg[..., 0] += g1 * 24.0 + g2 * 16.0
bg[..., 1] += g1 * 42.0 + g2 * 30.0
bg[..., 2] += g1 * 32.0 + g2 * 22.0
og = Image.fromarray(np.clip(bg, 0, 255).astype(np.uint8), "RGB").convert("RGBA")

# Place subtle preview window on right side of OG card
preview_path = os.path.join(public_dir, "saga-preview.png")
if os.path.isfile(preview_path):
    prev_im = Image.open(preview_path).convert("RGBA")
    pw = 620
    ph = int(round(prev_im.height * (pw / prev_im.width)))
    prev_resized = prev_im.resize((pw, ph), Image.LANCZOS)
    px, py = 548, (og_h - ph) // 2 + 6
    shadow = Image.new("RGBA", (og_w, og_h), (0, 0, 0, 0))
    sh_alpha = prev_resized.split()[3].point(lambda a: int(a * 0.65))
    sh_box = Image.new("RGBA", (pw, ph), (0, 0, 0, 255))
    sh_box.putalpha(sh_alpha)
    shadow.paste(sh_box, (px, py + 14))
    shadow = shadow.filter(ImageFilter.GaussianBlur(radius=22))
    og = Image.alpha_composite(og, shadow)
    og.alpha_composite(prev_resized, (px, py))

# Left column branding on OG card
icon_og = squircle_1024.resize((92, 92), Image.LANCZOS)
icon_shadow = Image.new("RGBA", (og_w, og_h), (0, 0, 0, 0))
ish = Image.new("RGBA", (92, 92), (0, 0, 0, 180))
ish.putalpha(icon_og.split()[3].point(lambda a: int(a * 0.55)))
icon_shadow.paste(ish, (56, 86))
icon_shadow = icon_shadow.filter(ImageFilter.GaussianBlur(radius=12))
og = Image.alpha_composite(og, icon_shadow)
og.alpha_composite(icon_og, (56, 80))

draw = ImageDraw.Draw(og)
font_serif_Candidates = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
    "/System/Library/Fonts/Supplemental/Georgia Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSerif-Bold.ttf",
]
font_sans_bold_candidates = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/System/Library/Fonts/SFNS.ttf",
]
font_sans_candidates = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
    "/System/Library/Fonts/SFNS.ttf",
]

def load_font(candidates, size):
    for c in candidates:
        if os.path.isfile(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()

f_title = load_font(font_serif_Candidates, 52)
f_sub = load_font(font_sans_candidates, 22)
f_pill = load_font(font_sans_bold_candidates, 16)

draw.text((56, 198), "Saga", font=f_title, fill=(243, 247, 244, 255))
draw.text((56, 268), "Personal reading log for macOS & iOS.", font=f_sub, fill=(210, 228, 218, 255))
draw.text((56, 300), "Editorial reviews, Private Notes, ⌘K Spotlight", font=f_sub, fill=(176, 204, 189, 255))
draw.text((56, 332), "search, and Contentful + Goodreads sync.", font=f_sub, fill=(176, 204, 189, 255))

pills = [
    "Books & Shelves",
    "Reviews & Private Notes",
    "⌘K Search",
    "Goodreads Sync",
]
px_cursor, py_cursor = 56, 404
for pill in pills:
    bbox = draw.textbbox((0, 0), pill, font=f_pill)
    tw = bbox[2] - bbox[0]
    pw_pill = tw + 28
    ph_pill = 36
    if px_cursor + pw_pill > 520:
        px_cursor = 56
        py_cursor += 46
    draw.rounded_rectangle(
        (px_cursor, py_cursor, px_cursor + pw_pill, py_cursor + ph_pill),
        radius=18,
        fill=(74, 126, 101, 52),
        outline=(126, 182, 152, 96),
        width=1,
    )
    draw.text((px_cursor + 14, py_cursor + 9), pill, font=f_pill, fill=(182, 226, 202, 255))
    px_cursor += pw_pill + 10

og.convert("RGB").save(os.path.join(public_dir, "opengraph-image.png"), format="PNG", optimize=True)

# 7. Export canonical icon sizes & latest preview to Project store media/ if mounted
store_media = "/cursor/stores/bc-150e5be2-2d2a-4a16-9354-3a146dd3a429/media"
if os.path.isdir(store_media):
    for px, name in [
        (512, "saga-latest-app-icon-512.png"),
        (192, "saga-latest-app-icon-192.png"),
        (64, "saga-latest-app-icon-64.png"),
        (32, "saga-latest-app-icon-32.png"),
    ]:
        squircle_1024.resize((px, px), Image.LANCZOS).save(
            os.path.join(store_media, name), format="PNG", optimize=True
        )
    if os.path.isfile(preview_path):
        shutil.copy2(preview_path, os.path.join(store_media, "saga-latest-preview.png"))

# 8. Write deterministic manifest in server/web-assets-manifest.json
tracked_outputs = [
    "app-icon.png",
    "icon.png",
    "icon-512.png",
    "icon-192.png",
    "apple-touch-icon.png",
    "favicon-64x64.png",
    "favicon-32x32.png",
    "favicon-16x16.png",
    "favicon.ico",
    "favicon.svg",
    "opengraph-image.png",
    "site.webmanifest",
    "saga-preview.png",
]

outputs_manifest = {}
for rel_name in tracked_outputs:
    p = os.path.join(public_dir, rel_name)
    if not os.path.isfile(p):
        continue
    entry = {"sha256": sha256_file(p)}
    if rel_name.endswith(".png"):
        im = Image.open(p)
        entry["dimensions"] = [im.width, im.height]
    outputs_manifest[rel_name] = entry

manifest = {
    "source": {
        "iconBundle": icon_rel,
        "iconJsonSha256": sha256_file(icon_json_path),
        "layers": layer_hashes,
    },
    "outputs": outputs_manifest,
}

manifest_path = os.path.join(root, "server", "web-assets-manifest.json")
with open(manifest_path, "w", encoding="utf-8") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")

print(f"Synced {len(outputs_manifest)} web assets into server/public/ and updated server/web-assets-manifest.json.")
PY
