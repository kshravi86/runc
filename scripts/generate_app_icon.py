import json
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except Exception as e:
    raise SystemExit("Pillow not installed. Run: pip install Pillow")

ASSET_DIR = Path('Run-C/Assets.xcassets/AppIcon.appiconset')
CONTENTS_PATH = ASSET_DIR / 'Contents.json'


def parse_size(size_str: str) -> tuple:
    w, h = size_str.lower().split('x')
    return float(w), float(h)


def gradient_bg(size: int, top_color=(10, 132, 255), bottom_color=(0, 96, 223)) -> Image.Image:
    img = Image.new('RGB', (size, size), top_color)
    draw = ImageDraw.Draw(img)
    tr, tg, tb = top_color
    br, bg, bb = bottom_color
    for y in range(size):
        t = y / (size - 1)
        r = int(tr + (br - tr) * t)
        g = int(tg + (bg - tg) * t)
        b = int(tb + (bb - tb) * t)
        draw.line([(0, y), (size, y)], fill=(r, g, b))
    return img


def draw_c_glyph(img: Image.Image, fg=(255, 255, 255)) -> None:
    draw = ImageDraw.Draw(img)
    W, H = img.size
    pad = int(0.18 * W)
    bbox = [pad, pad, W - pad, H - pad]
    thickness = int(0.14 * W)
    draw.ellipse(bbox, outline=fg, width=thickness)

    # Carve opening on right to form a "C"
    bg_sample = img.getpixel((W // 2, H - 1))
    open_w = int(0.33 * W)
    open_h = int(0.58 * H)
    rect = [W - pad - open_w, (H - open_h) // 2, W - pad + open_w, (H + open_h) // 2]
    draw.rectangle(rect, fill=bg_sample)

    # Round ends a bit
    end_r = int(thickness * 0.6)
    cx = W - pad - open_w
    cy1 = (H - open_h) // 2
    cy2 = (H + open_h) // 2
    draw.ellipse([cx - end_r, cy1 - end_r, cx + end_r, cy1 + end_r], fill=bg_sample)
    draw.ellipse([cx - end_r, cy2 - end_r, cx + end_r, cy2 + end_r], fill=bg_sample)


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
    draw_c_glyph(base)

    for entry in images:
        size = entry.get('size')
        scale = entry.get('scale')
        fname = entry.get('filename')
        if not size or not scale or not fname:
            continue
        w_pt, _ = parse_size(size)
        sc = int(scale.replace('x', ''))
        px = int(round(w_pt * sc))
        target = base if px == 1024 else base.resize((px, px), Image.LANCZOS)
        out_path = ASSET_DIR / fname
        target.save(out_path, format='PNG')

    CONTENTS_PATH.write_text(json.dumps(data, indent=2), encoding='utf-8')


def main():
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    generate_from_contents()
    print(f"App icons generated in {ASSET_DIR}")


if __name__ == '__main__':
    main()

