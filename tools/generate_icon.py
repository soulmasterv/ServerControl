"""Rebuild the original Server Control icon (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw
import json

ROOT = Path(__file__).resolve().parents[1]
SIZE = 2048
image = Image.new('RGB', (SIZE, SIZE))
pixels = image.load()
for y in range(SIZE):
    for x in range(SIZE):
        blend = (x * 0.55 + y * 0.45) / SIZE
        glow = max(0, 1 - ((x / SIZE - .84)**2 + (y / SIZE - .15)**2)**.5 / .85)
        pixels[x, y] = (int(24 + 27 * blend + 7 * glow), int(30 + 19 * blend + 19 * glow), int(77 + 56 * blend + 19 * glow))
draw = ImageDraw.Draw(image)
# A compact rack silhouette, with a continuous teal status rail.
draw.rounded_rectangle((407, 329, 1667, 1743), radius=162, fill=(12, 18, 53))
draw.rounded_rectangle((356, 278, 1616, 1692), radius=152, fill=(229, 235, 255))
draw.rounded_rectangle((412, 334, 1560, 1636), radius=112, fill=(37, 43, 96))
for top in [424, 806, 1188]:
    draw.rounded_rectangle((500, top, 1472, top + 276), radius=62, fill=(245, 248, 255))
    for slot in range(3):
        xx = 583 + slot * 100
        draw.rounded_rectangle((xx, top + 90, xx + 38, top + 186), radius=19, fill=(73, 80, 154))
    draw.ellipse((1272, top + 85, 1378, top + 191), fill=(18, 175, 164))
draw.rounded_rectangle((1639, 497, 1719, 1533), radius=40, fill=(30, 210, 193))
draw.ellipse((1613, 424, 1745, 556), fill=(126, 255, 225))
catalog = ROOT / 'ServerControl/Assets.xcassets'
icons = catalog / 'AppIcon.appiconset'
icons.mkdir(parents=True, exist_ok=True)
image.resize((1024, 1024), Image.Resampling.LANCZOS).save(icons / 'AppIcon.png')
(catalog / 'Contents.json').write_text(json.dumps({'info': {'author': 'xcode', 'version': 1}}, indent=2))
(icons / 'Contents.json').write_text(json.dumps({
    'images': [{'filename': 'AppIcon.png', 'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024'}],
    'info': {'author': 'xcode', 'version': 1}
}, indent=2))
print('Created opaque 1024x1024 AppIcon.png')
