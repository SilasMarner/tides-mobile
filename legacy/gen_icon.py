"""Generate tides_icon.png — 512x512 app icon."""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W = H = 512
img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# ── background: deep ocean gradient ─────────────────────────────────────────
bg = Image.new("RGBA", (W, H))
bg_draw = ImageDraw.Draw(bg)
for y in range(H):
    t = y / H
    r = int(4  + (10 - 4)  * t)
    g = int(20 + (45 - 20) * t)
    b = int(55 + (90 - 55) * t)
    bg_draw.line([(0, y), (W, y)], fill=(r, g, b, 255))
img = Image.alpha_composite(img, bg)
draw = ImageDraw.Draw(img)

# ── rounded-rect mask ────────────────────────────────────────────────────────
mask = Image.new("L", (W, H), 0)
mask_draw = ImageDraw.Draw(mask)
radius = 110
mask_draw.rounded_rectangle([0, 0, W - 1, H - 1], radius=radius, fill=255)
img.putalpha(mask)
draw = ImageDraw.Draw(img)

# ── moon (crescent) ──────────────────────────────────────────────────────────
moon_cx, moon_cy, moon_r = 370, 115, 58
# full disc
moon_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
md = ImageDraw.Draw(moon_layer)
md.ellipse([moon_cx - moon_r, moon_cy - moon_r,
            moon_cx + moon_r, moon_cy + moon_r],
           fill=(255, 240, 180, 230))
# carve crescent shadow
offset = 34
md.ellipse([moon_cx - moon_r + offset, moon_cy - moon_r - 6,
            moon_cx + moon_r + offset, moon_cy + moon_r - 6],
           fill=(0, 0, 0, 0))
img = Image.alpha_composite(img, moon_layer)
draw = ImageDraw.Draw(img)

# ── stars ─────────────────────────────────────────────────────────────────────
stars = [(60, 55, 2), (130, 30, 1.5), (200, 70, 1.5), (290, 45, 2),
         (310, 90, 1), (420, 165, 1.5), (450, 60, 2), (480, 130, 1)]
for sx, sy, sr in stars:
    draw.ellipse([sx - sr, sy - sr, sx + sr, sy + sr],
                 fill=(255, 255, 255, 180))

# ── helper: filled wave polygon ───────────────────────────────────────────────
def wave_poly(y_center, amplitude, wavelength, phase, n=300, thickness=0):
    pts = []
    for i in range(n + 1):
        x = i * W / n
        y = y_center + amplitude * math.sin(2 * math.pi * x / wavelength + phase)
        pts.append((x, y))
    # close bottom
    pts.append((W, H))
    pts.append((0, H))
    return pts

# ── wave layers (back → front) ────────────────────────────────────────────────
wave_specs = [
    # y_center  amp  wl    phase   color               alpha
    (340,        28,  320, 0.0,   (10,  80,  160),     160),
    (365,        22,  270, 1.1,   (15,  100, 190),     180),
    (390,        18,  230, 2.3,   (20,  130, 210),     200),
    (415,        14,  190, 0.7,   (30,  155, 220),     210),
    (440,        10,  160, 1.8,   (50,  175, 230),     220),
]
for yc, amp, wl, ph, col, alpha in wave_specs:
    wlayer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    wd = ImageDraw.Draw(wlayer)
    poly = wave_poly(yc, amp, wl, ph)
    wd.polygon(poly, fill=(*col, alpha))
    img = Image.alpha_composite(img, wlayer)

draw = ImageDraw.Draw(img)

# ── wave crest highlights ─────────────────────────────────────────────────────
for yc, amp, wl, ph, _, _ in wave_specs[2:]:
    for i in range(150):
        x = i * W / 150
        y = yc + amp * math.sin(2 * math.pi * x / wl + ph)
        # only draw near crest tops
        dy = amp * math.sin(2 * math.pi * x / wl + ph)
        if dy < -amp * 0.6:
            draw.ellipse([x - 1.5, y - 1, x + 1.5, y + 1],
                         fill=(200, 240, 255, 130))

# ── "TIDES" text ──────────────────────────────────────────────────────────────
try:
    font_big = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 86)
    font_small = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 28)
except Exception:
    font_big = ImageFont.load_default()
    font_small = font_big

text = "TIDES"
# shadow
draw.text((W // 2 + 3, 213), text, font=font_big, fill=(0, 0, 0, 120), anchor="mm")
# white text
draw.text((W // 2, 210), text, font=font_big, fill=(255, 255, 255, 245), anchor="mm")

# subtitle
sub = "live tide data"
draw.text((W // 2 + 1, 268), sub, font=font_small, fill=(0, 0, 0, 80), anchor="mm")
draw.text((W // 2, 266), sub, font=font_small, fill=(180, 225, 255, 200), anchor="mm")

# ── re-apply rounded mask to composite ───────────────────────────────────────
mask2 = Image.new("L", (W, H), 0)
ImageDraw.Draw(mask2).rounded_rectangle([0, 0, W - 1, H - 1], radius=radius, fill=255)
img.putalpha(mask2)

# ── subtle vignette ───────────────────────────────────────────────────────────
vignette = Image.new("RGBA", (W, H), (0, 0, 0, 0))
for step in range(60):
    alpha = int(step * 1.8)
    r = step * 4
    ImageDraw.Draw(vignette).rounded_rectangle(
        [r, r, W - r, H - r], radius=max(0, radius - r), outline=(0, 0, 0, alpha), width=1
    )
img = Image.alpha_composite(img, vignette)

out = "/root/git/tides-android/tides_icon.png"
img.save(out, "PNG")
print(f"Saved {out}")
