"""The Roku channel's images, drawn in the Late Show palette from the app icon and the bundled fonts:
the channel poster (540x405 FHD, 290x218 HD), the splash screens (1920x1080, 1280x720) and the white 9-patch rounded
rectangles the app tints with a Poster's blendColor (SceneGraph rectangles have no corner radius).
usage: python3 roku/tools/images.py   (writes roku/images/; needs Pillow)"""
import math, os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROKU = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.dirname(ROKU)
OUT = os.path.join(ROKU, 'images')
ICON = os.path.join(REPO, 'App/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png')
BRICOLAGE = os.path.join(REPO, 'App/Fonts/BricolageGrotesque-Bold.ttf')
HANKEN = os.path.join(REPO, 'App/Fonts/HankenGrotesk-SemiBold.ttf')
BG, INK, ACCENT = (0x14, 0x11, 0x0f), (0xf3, 0xeb, 0xe0), (0xf0, 0xa3, 0x3a)


def backdrop(w, h):
    """The Late Show background with the accent glow from the top left (the store art's radial gradient)."""
    img = Image.new('RGB', (w, h), BG)
    glow = Image.new('L', (w, h), 0)
    d = ImageDraw.Draw(glow)
    rx, ry, cx = w * 0.9, h * 1.1, w * 0.22
    for i in range(60, 0, -1):   # concentric ellipses fading out to 70% of the radii
        f = i / 60
        a = int(0.22 * 255 * max(0, 1 - f / 0.7) if f <= 0.7 else 0)
        d.ellipse([cx - rx * f, -ry * f, cx + rx * f, ry * f], fill=a)
    glow = glow.filter(ImageFilter.GaussianBlur(w / 40))
    return Image.composite(Image.new('RGB', (w, h), ACCENT), img, glow)


def rounded_icon(size):
    icon = Image.open(ICON).convert('RGBA').resize((size, size), Image.LANCZOS)
    mask = Image.new('L', (size * 4, size * 4), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size * 4 - 1, size * 4 - 1], radius=int(size * 4 * 0.22), fill=255)
    icon.putalpha(mask.resize((size, size), Image.LANCZOS))
    return icon


def lockup(w, h, icon_size, title_size, tag_size, gap):
    """Icon left, "Rerun / Guide" and "TONIGHT'S LINEUP" right, centered (the TV banner's layout)."""
    img = backdrop(w, h).convert('RGBA')
    d = ImageDraw.Draw(img)
    title = ImageFont.truetype(BRICOLAGE, title_size)
    tag = ImageFont.truetype(HANKEN, tag_size)
    lines = ['Rerun', 'Guide']
    tw = max(d.textlength(s, font=title) for s in lines)
    tracking = tag_size * 0.14
    tag_text = 'TONIGHT’S LINEUP'
    tagw = sum(d.textlength(c, font=tag) for c in tag_text) + tracking * (len(tag_text) - 1)
    block_w = icon_size + gap + max(tw, tagw)
    x0 = (w - block_w) / 2
    shadow = Image.new('RGBA', img.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([x0, (h - icon_size) / 2 + icon_size * 0.06, x0 + icon_size, (h + icon_size) / 2 + icon_size * 0.06],
                                             radius=icon_size * 0.22, fill=(0, 0, 0, 140))
    img = Image.alpha_composite(img, shadow.filter(ImageFilter.GaussianBlur(icon_size * 0.08)))
    img.alpha_composite(rounded_icon(icon_size), (int(x0), int((h - icon_size) / 2)))
    d = ImageDraw.Draw(img)
    tx = x0 + icon_size + gap
    line_h = title_size * 0.98
    text_h = line_h * 2 + tag_size * 1.6
    ty = (h - text_h) / 2 - title_size * 0.12
    for i, s in enumerate(lines):
        d.text((tx, ty + i * line_h), s, font=title, fill=INK)
    cx, cy = tx, ty + line_h * 2 + tag_size * 0.55
    for c in tag_text:
        d.text((cx, cy), c, font=tag, fill=ACCENT)
        cx += d.textlength(c, font=tag) + tracking
    return img.convert('RGB')


def nine_patch(radius, name):
    """A white rounded rectangle as a Roku 9-patch: a 1 px border whose black pixels mark the stretchable middle."""
    inner = radius * 2 + 2
    scale = 4
    big = Image.new('L', (inner * scale, inner * scale), 0)
    ImageDraw.Draw(big).rounded_rectangle([0, 0, inner * scale - 1, inner * scale - 1], radius=radius * scale, fill=255)
    alpha = big.resize((inner, inner), Image.LANCZOS)
    img = Image.new('RGBA', (inner + 2, inner + 2), (0, 0, 0, 0))
    body = Image.new('RGBA', (inner, inner), (255, 255, 255, 255))
    body.putalpha(alpha)
    img.paste(body, (1, 1))
    px = img.load()
    for i in range(1 + radius, 1 + radius + 2):
        px[i, 0] = (0, 0, 0, 255)   # top: stretchable columns
        px[0, i] = (0, 0, 0, 255)   # left: stretchable rows
    img.save(os.path.join(OUT, name), optimize=True)


def save(img, name):
    img.save(os.path.join(OUT, name), optimize=True)


def rounded_mask(w, h, r, scale=4):
    m = Image.new('L', (w * scale, h * scale), 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, w * scale - 1, h * scale - 1], radius=r * scale, fill=255)
    return m.resize((w, h), Image.LANCZOS)


def white(alpha):
    img = Image.new('RGBA', alpha.size, (255, 255, 255, 0))
    img.putalpha(alpha)
    return img


def stage_images():
    """The guide's and the player's drawn parts that SceneGraph can't do: gradients, scanlines, glyphs."""
    # The Late Show glow behind the guide: radial-gradient(1000px 640px at 380px 300px, rgba(240,163,58,.10), transparent 70%).
    w, h = 1080, 748
    a = Image.new('L', (w, h))
    px = a.load()
    for y in range(h):
        for x in range(w):
            d = math.hypot((x - 380) / 1000, (y - 300) / 640) / 0.7
            px[x, y] = int(255 * 0.10 * max(0.0, 1 - d))
    glow = Image.new('RGBA', (w, h), ACCENT + (0,))
    glow.putalpha(a)
    save(glow, 'glow.png')
    # The tube's picture before art or video: radial-gradient(at 25% 15%) as luminance, tinted with the channel's hue.
    for (w, h, r, name) in ((600, 450, 44, 'tube.png'), (520, 390, 24, 'sheet-art.png'), (640, 360, 0, 'picture.png')):
        lum = Image.new('L', (w, h))
        px = lum.load()
        for y in range(h):
            for x in range(w):
                d = min(1.0, math.hypot((x - 0.25 * w) / w, (y - 0.15 * h) / h) / 1.0)
                v = 1.0 - (1 - 0.48) * (d / 0.55) if d < 0.55 else 0.48 - (0.48 - 0.26) * ((d - 0.55) / 0.45)
                px[x, y] = int(255 * max(0.0, v))
        mask = rounded_mask(w, h, r) if r > 0 else Image.new('L', (w, h), 255)
        img = Image.merge('RGBA', (lum, lum, lum, mask))
        save(img, name)
    # Over real art and video: transparent to 60% black at the bottom, rounded.
    w, h = 600, 450
    scrim = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    am = Image.new('L', (w, h))
    d = ImageDraw.Draw(am)
    for y in range(h):
        f = max(0.0, (y / h - 0.45) / 0.55)
        d.line([(0, y), (w, y)], fill=int(255 * 0.6 * f))
    am = Image.composite(am, Image.new('L', (w, h), 0), rounded_mask(w, h, 44))
    scrim.putalpha(am)
    save(scrim, 'scrim.png')
    # CRT lines over the tube: 2 px on (16% black), 2 px off, under a vignette (55% to 50% black at the edge).
    crt = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    am = Image.new('L', (w, h))
    px = am.load()
    for y in range(h):
        line = 0.16 if y % 4 < 2 else 0.0
        for x in range(w):
            d = math.hypot((x - w / 2) / (w * 0.71), (y - h / 2) / (h * 0.71))
            v = 0.5 * max(0.0, min(1.0, (d - 0.55) / 0.45)) if d > 0.55 else 0.0
            px[x, y] = int(255 * (1 - (1 - line) * (1 - v)))
    am = Image.composite(am, Image.new('L', (w, h), 0), rounded_mask(w, h, 44))
    crt.putalpha(am)
    save(crt, 'crt.png')
    # The tube's corners outside its 44 radius in the background's color: video ignores clips, so they're painted over it.
    corners = Image.new('RGBA', (w, h), BG + (255,))
    inside = rounded_mask(w, h, 44)
    corners.putalpha(Image.eval(inside, lambda v: 255 - v))
    save(corners, 'corners.png')
    # Fades: the grid's bottom fifth into the background (a column stretched to the grid's width), the now line.
    fade = Image.new('RGBA', (4, 424), BG + (0,))
    am = Image.new('L', (4, 424))
    for y in range(424):
        f = max(0.0, (y / 424 - 0.78) / 0.22)
        ImageDraw.Draw(am).line([(0, y), (3, y)], fill=int(255 * f))
    fade.putalpha(am)
    save(fade, 'fade.png')
    now = Image.new('L', (2, 428))
    for y in range(428):
        ImageDraw.Draw(now).line([(0, y), (1, y)], fill=int(255 * (1 - y / 428)))
    save(white(now), 'nowline.png')
    # Remote-key glyphs (white, tinted): OK (ring and its button), Play/Pause, Back, the D-pad's left. 1.5:1, as the web's.
    S = 4
    for name, draw in (('glyph-ok.png', 'ok'), ('glyph-play.png', 'play'), ('glyph-back.png', 'back'), ('glyph-left.png', 'left')):
        gw, gh = 36, 24
        g = Image.new('L', (gw * S, gh * S), 0)
        d = ImageDraw.Draw(g)
        u = gh * S   # the unit square, centered horizontally
        ox = (gw * S - u) / 2
        P = lambda x, y: (ox + x * u, y * u)
        if draw == 'ok':
            d.ellipse([P(0.05, 0.05), P(0.95, 0.95)], outline=255, width=int(0.12 * u))
            d.ellipse([P(0.19, 0.19), P(0.81, 0.81)], fill=255)
        elif draw == 'play':
            d.polygon([P(-0.24, 0.12), P(-0.24, 0.88), P(0.43, 0.5)], fill=255)
            d.rounded_rectangle([P(0.58, 0.09), P(0.87, 0.91)], radius=int(0.05 * u), fill=255)
            d.rounded_rectangle([P(1.0, 0.09), P(1.29, 0.91)], radius=int(0.05 * u), fill=255)
        elif draw == 'back':
            d.line([P(0.61, 0.16), P(0.25, 0.51), P(0.61, 0.86)], fill=255, width=int(0.16 * u), joint='curve')
        else:
            for cx, cy, rr in ((0.55, 0.1, 0.175), (0.9, 0.48, 0.175), (0.55, 0.875, 0.175)):
                d.ellipse([P(cx - rr, cy - rr), P(cx + rr, cy + rr)], outline=255, width=int(0.1 * u))
            d.ellipse([P(0.2 - 0.225, 0.5 - 0.225), P(0.2 + 0.225, 0.5 + 0.225)], fill=255)
        save(white(g.resize((gw, gh), Image.LANCZOS)), name)
    # A circle for round things bigger than the 9-patches' 44 radius (the Profiles avatars).
    c = Image.new('L', (256 * S, 256 * S), 0)
    ImageDraw.Draw(c).ellipse([0, 0, 256 * S - 1, 256 * S - 1], fill=255)
    save(white(c.resize((256, 256), Image.LANCZOS)), 'circle.png')
    # The favorite star and the cells' clipped-edge triangles.
    st = Image.new('L', (22 * S, 22 * S), 0)
    pts = [(.5, 0), (.618, .338), (.976, .345), (.69, .562), (.794, .905), (.5, .7), (.206, .905), (.31, .562), (.024, .345), (.382, .338)]
    ImageDraw.Draw(st).polygon([(x * 22 * S, y * 22 * S) for x, y in pts], fill=255)
    save(white(st.resize((22, 22), Image.LANCZOS)), 'star.png')
    for name, pts in (('tri-left.png', [(12, 0), (0, 9), (12, 18)]), ('tri-right.png', [(0, 0), (12, 9), (0, 18)])):
        t = Image.new('L', (12 * S, 18 * S), 0)
        ImageDraw.Draw(t).polygon([(x * S, y * S) for x, y in pts], fill=255)
        save(white(t.resize((12, 18), Image.LANCZOS)), name)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    stage_images()
    # Channel poster: the home screen tile (FHD 540x405, HD 290x218).
    lockup(540, 405, 150, 66, 16, 26).save(os.path.join(OUT, 'icon-fhd.png'), optimize=True)
    lockup(290, 218, 80, 36, 9, 14).save(os.path.join(OUT, 'icon-hd.png'), optimize=True)
    # Splash screens, shown while the channel loads.
    lockup(1920, 1080, 300, 120, 30, 56).save(os.path.join(OUT, 'splash-fhd.png'), optimize=True)
    lockup(1280, 720, 200, 80, 20, 38).save(os.path.join(OUT, 'splash-hd.png'), optimize=True)
    lockup(720, 480, 140, 56, 14, 26).save(os.path.join(OUT, 'splash-sd.png'), optimize=True)
    # Rounded corners for the stage: cells 16, panels 24, the preview tube 44, pills and chips by height.
    for r in (4, 8, 12, 16, 20, 24, 30, 44):
        nine_patch(r, f'r{r}.9.png')
    print('wrote', sorted(os.listdir(OUT)))
