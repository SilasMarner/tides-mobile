"""Generate the OpenTides app/Play-Store icon at high resolution.

Reproduces the current OpenTides launcher art (night-sky gradient, crescent
moon, stars, the ~ wave mark, "OpenTides / free · open · forever", cyan water
band) crisply, by rendering at 4x supersampling and downscaling with LANCZOS.

Master is 1024x1024 full-bleed square (no rounded corners — Play and the
launcher apply their own masking).
"""
import math
from PIL import Image, ImageDraw, ImageFont

REPO = "/root/git/tides-android"
ROBOTO_BOLD = f"{REPO}/tides_flutter/assets/Roboto-Bold.ttf"
ROBOTO_REG = f"{REPO}/tides_flutter/assets/Roboto-Regular.ttf"

SS = 4                      # supersample factor
S = 1024 * SS              # internal canvas
W = H = S


def px(v):
    return int(round(v * SS))


img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

# ── sky gradient (top → horizon) ────────────────────────────────────────────
horizon = int(H * 0.72)
bg = Image.new("RGBA", (S, S))
bd = ImageDraw.Draw(bg)
for y in range(H):
    if y < horizon:
        t = y / horizon
        r = int(4 + (8 - 4) * t)
        g = int(20 + (40 - 20) * t)
        b = int(54 + (88 - 54) * t)
    else:
        r, g, b = 8, 40, 88        # filled, water drawn on top
    bd.line([(0, y), (W, y)], fill=(r, g, b, 255))
img = Image.alpha_composite(img, bg)

# ── moon (waxing crescent, top-right) ───────────────────────────────────────
moon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
md = ImageDraw.Draw(moon)
cx, cy, rr = px(728), px(250), px(140)
md.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=(255, 240, 180, 255))
# carve the upper-right to leave a crescent lit on the lower-left
ox, oy, orr = px(820), px(212), px(138)
md.ellipse([ox - orr, oy - orr, ox + orr, oy + orr], fill=(0, 0, 0, 0))
img = Image.alpha_composite(img, moon)
draw = ImageDraw.Draw(img)

# ── stars (upper-left field) ────────────────────────────────────────────────
stars = [(110, 92, 6), (232, 70, 5), (322, 150, 4.5), (180, 205, 5),
         (92, 250, 4), (300, 232, 4), (150, 140, 3.5), (420, 112, 4.5),
         (60, 160, 3.5), (250, 120, 3)]
for sx, sy, sr in stars:
    r = px(sr)
    draw.ellipse([px(sx) - r, px(sy) - r, px(sx) + r, px(sy) + r],
                 fill=(255, 255, 255, 235))

# ── water band (wavy horizon + gradient + crest highlights) ─────────────────
def wave_pts(yc, amp, wl, ph, n=600):
    pts = [(i * W / n, px(yc) + px(amp) * math.sin(2 * math.pi * (i * W / n) / px(wl) + ph))
           for i in range(n + 1)]
    pts += [(W, H), (0, H)]
    return pts

# fill the whole water area bottom-up with a vertical cyan gradient
water = Image.new("RGBA", (S, S), (0, 0, 0, 0))
wd = ImageDraw.Draw(water)
wtop = int(H * 0.70)
for y in range(wtop, H):
    t = (y - wtop) / (H - wtop)
    r = int(20 + (60 - 20) * t)
    g = int(120 + (180 - 120) * t)
    b = int(185 + (228 - 185) * t)
    wd.line([(0, y), (W, y)], fill=(r, g, b, 255))
# carve a wavy top edge by clearing above the front wave line
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon(wave_pts(740 / 5.333, 14, 360, 0.6), fill=255)
# wave_pts expects 1024-space values; convert: pass directly in 1024 units
mask = Image.new("L", (S, S), 0)
ImageDraw.Draw(mask).polygon(wave_pts(740, 12, 360, 0.6), fill=255)
water.putalpha(mask)
img = Image.alpha_composite(img, water)
draw = ImageDraw.Draw(img)

# subtle back-wave for depth, just above the main water
back = Image.new("RGBA", (S, S), (0, 0, 0, 0))
ImageDraw.Draw(back).polygon(wave_pts(726, 10, 300, 2.1), fill=(22, 120, 188, 150))
img = Image.alpha_composite(img, back)
draw = ImageDraw.Draw(img)

# ── "~" wave mark (cyan, above the wordmark) — smooth filled ribbon ─────────
tx, ty = px(512), px(452)
tw, tamp, half = px(72), px(16), px(8)
N = 200
center = []
for i in range(N + 1):
    u = i / N
    x = tx - tw + 2 * tw * u
    y = ty + tamp * math.sin(2 * math.pi * u)
    center.append((x, y))
top, bot = [], []
for i, (x, y) in enumerate(center):
    a = center[max(0, i - 1)]
    b = center[min(N, i + 1)]
    dx, dy = b[0] - a[0], b[1] - a[1]
    dl = math.hypot(dx, dy) or 1
    nx, ny = -dy / dl, dx / dl          # unit normal
    top.append((x + nx * half, y + ny * half))
    bot.append((x - nx * half, y - ny * half))
draw.polygon(top + bot[::-1], fill=(40, 182, 212, 255))
# round the ends
for end in (center[0], center[-1]):
    draw.ellipse([end[0] - half, end[1] - half, end[0] + half, end[1] + half],
                 fill=(40, 182, 212, 255))

# ── wordmark + subtitle ─────────────────────────────────────────────────────
def fit_font(path, text, target_w):
    size = 100
    f = ImageFont.truetype(path, size)
    w = draw.textlength(text, font=f)
    size = int(size * target_w / w)
    return ImageFont.truetype(path, size)

word = "OpenTides"
fbig = fit_font(ROBOTO_BOLD, word, px(880))
draw.text((px(512), px(600)), word, font=fbig, fill=(255, 255, 255, 255),
          anchor="mm")

sub = "free · open · forever"
fsub = fit_font(ROBOTO_REG, sub, px(700))
draw.text((px(512), px(742)), sub, font=fsub, fill=(200, 236, 250, 255),
          anchor="mm")

# ── downscale to 1024 master, then emit every deliverable ───────────────────
master = img.resize((1024, 1024), Image.LANCZOS)        # RGBA
master.save("/tmp/opentides_master_1024.png")

import os
WRITE = os.environ.get("WRITE_REPO") == "1"
if WRITE:
    # canonical high-res source (so we never lack an OpenTides source again)
    master.convert("RGB").save(f"{REPO}/docs/icon-1024.png")
    # Play Store hi-res icon — 512x512 (match existing RGB format)
    master.convert("RGB").resize((512, 512), Image.LANCZOS).save(
        f"{REPO}/docs/icon-512.png")
    # Android launcher mipmaps (RGBA, per density)
    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144,
                 "xxxhdpi": 192}
    for name, size in densities.items():
        out = (f"{REPO}/tides_flutter/android/app/src/main/res/"
               f"mipmap-{name}/ic_launcher.png")
        master.resize((size, size), Image.LANCZOS).save(out)
    print("wrote docs/icon-1024.png, docs/icon-512.png, and 5 mipmaps")
else:
    print("wrote /tmp/opentides_master_1024.png (set WRITE_REPO=1 to emit repo files)")
