import json
from pathlib import Path

try:
    from PIL import Image, ImageDraw, ImageFilter
except Exception as e:
    raise SystemExit("Pillow not installed. Run: pip install Pillow")

ASSET_DIR = Path('Run-C/Assets.xcassets/AppIcon.appiconset')
CONTENTS_PATH = ASSET_DIR / 'Contents.json'


def parse_size(size_str: str) -> tuple:
    w, h = size_str.lower().split('x')
    return float(w), float(h)


def gradient_bg(size: int,
                top_color=(99, 102, 241),    # indigo-500
                bottom_color=(147, 51, 234)  # purple-600
                ) -> Image.Image:
    """Create a smooth vertical gradient background.

    Uses a modern indigo→purple palette to make the icon feel fresh.
    """
    img = Image.new('RGB', (size, size), top_color)
    draw = ImageDraw.Draw(img)
    tr, tg, tb = top_color
    br, bg, bb = bottom_color
    for y in range(size):
        t = y / max(1, size - 1)
        r = int(tr + (br - tr) * t)
        g = int(tg + (bg - tg) * t)
        b = int(tb + (bb - tb) * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b))

    # Soft top-left gloss highlight
    overlay = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ov_draw = ImageDraw.Draw(overlay)
    gloss_r = int(size * 0.9)
    oval = [-int(gloss_r * 0.4), -int(gloss_r * 0.4), gloss_r, gloss_r]
    ov_draw.ellipse(oval, fill=(255, 255, 255, 38))  # subtle
    overlay = overlay.filter(ImageFilter.GaussianBlur(int(size * 0.06)))
    img = Image.alpha_composite(img.convert('RGBA'), overlay).convert('RGB')
    return img


def draw_c_glyph_layer(size: int, base_bg: Image.Image, fg=(255, 255, 255)) -> Image.Image:
    """Draw a refined "C" glyph with a tiny play-cutout and soft shadow.

    Returns an RGBA image containing only the glyph (with transparency).
    """
    glyph = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glyph)
    W = H = size
    pad = int(0.2 * W)
    bbox = [pad, pad, W - pad, H - pad]
    thickness = int(0.13 * W)

    # Main ring
    draw.ellipse(bbox, outline=fg, width=thickness)

    # Carve opening on right to form a "C" (simulate cutout using background sample)
    bg_sample = base_bg.getpixel((W // 2, H - 1))
    open_w = int(0.34 * W)
    open_h = int(0.56 * H)
    rect = [W - pad - open_w, (H - open_h) // 2, W - pad + open_w, (H + open_h) // 2]
    draw.rectangle(rect, fill=bg_sample)

    # Round ends a bit to avoid harsh edges
    end_r = int(thickness * 0.6)
    cx = W - pad - open_w
    cy1 = (H - open_h) // 2
    cy2 = (H + open_h) // 2
    draw.ellipse([cx - end_r, cy1 - end_r, cx + end_r, cy1 + end_r], fill=bg_sample)
    draw.ellipse([cx - end_r, cy2 - end_r, cx + end_r, cy2 + end_r], fill=bg_sample)

    # Subtle "Run" cue: a small play triangle cutout inside
    tri_w = int(0.18 * W)
    tri_h = int(0.18 * H)
    tri_cx = int(W * 0.52)
    tri_cy = H // 2
    p1 = (tri_cx - tri_w // 2, tri_cy - tri_h // 2)
    p2 = (tri_cx - tri_w // 2, tri_cy + tri_h // 2)
    p3 = (tri_cx + tri_w // 2, tri_cy)
    draw.polygon([p1, p2, p3], fill=bg_sample)

    return glyph


def ensure_filenames(images):
    for entry in images:
        size = entry.get('size')
        scale = entry.get('scale')
        idiom = entry.get('idiom')
        if not size or not scale:
            continue
        w, _ = parse_size(size)
        sc = int(scale.replace('x', ''))
        if idiom == 'ios-marketing':
            name = 'Icon-AppStore-1024.png'
        else:
            name = f'Icon-{int(w)}@{sc}x.png'
        entry['filename'] = name


def generate_from_contents():
    if not CONTENTS_PATH.exists():
        raise SystemExit(f"Missing Contents.json at {CONTENTS_PATH}")
    data = json.loads(CONTENTS_PATH.read_text(encoding='utf-8'))
    images = data.get('images', [])
    ensure_filenames(images)

    base = gradient_bg(1024)
    # Build glyph and soft shadow
    glyph = draw_c_glyph_layer(1024, base)

    # Shadow from glyph alpha
    alpha = glyph.split()[3]
    shadow_mask = alpha.filter(ImageFilter.GaussianBlur(18))
    shadow = Image.new('RGBA', (1024, 1024), (0, 0, 0, 95))
    shadow_layer = Image.new('RGBA', (1024, 1024), (0, 0, 0, 0))
    # Slight downward offset
    shadow_layer.paste(shadow, (0, 10), mask=shadow_mask)

    composed = Image.alpha_composite(base.convert('RGBA'), shadow_layer)
    composed = Image.alpha_composite(composed, glyph)

    for entry in images:
        size = entry.get('size')
        scale = entry.get('scale')
        fname = entry.get('filename')
        if not size or not scale or not fname:
            continue
        w_pt, _ = parse_size(size)
        sc = int(scale.replace('x', ''))
        px = int(round(w_pt * sc))
        if px == 1024:
            target = composed
        else:
            target = composed.resize((px, px), Image.LANCZOS)
        out_path = ASSET_DIR / fname
        target.save(out_path, format='PNG')

    CONTENTS_PATH.write_text(json.dumps(data, indent=2), encoding='utf-8')


def main():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    generate_from_contents()
    print(f"App icons generated in {ASSET_DIR}")


if __name__ == '__main__':
    main()
