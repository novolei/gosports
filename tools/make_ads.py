"""Renders the advertising-board atlas (assets/env/ads.png): 16 fictional sponsor panels, 4 x 4 cells of 640 x 256 px.
All brands are made up for this game. Flat, bold, readable from the broadcast camera. Run: python tools/make_ads.py"""
import math
from PIL import Image, ImageDraw, ImageFont

CW, CH = 640, 256
COLS, ROWS = 4, 4
SS = 2                                   # supersampling for smooth edges
FONT_LATIN = "assets/fonts/latin_display.ttf"      # Kanit ExtraBold Italic (SIL OFL)
FONT_CJK = "art_src/fonts/build/cjk_display.ttf"    # Noto Sans SC Black (SIL OFL)


def font(size, text=""):
    return ImageFont.truetype(FONT_CJK if any(ord(ch) > 0x2000 for ch in text) else FONT_LATIN, int(size * SS))


def hexc(h, a=255):
    h = h.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), a)


def darker(c, k=0.6):
    return (int(c[0] * k), int(c[1] * k), int(c[2] * k), 255)


class Cell:
    def __init__(self, bg):
        self.im = Image.new("RGBA", (CW * SS, CH * SS), hexc(bg) if isinstance(bg, str) else bg)
        self.d = ImageDraw.Draw(self.im)

    def s(self, v):
        return v * SS

    def rect(self, x0, y0, x1, y1, fill, r=0):
        if r:
            self.d.rounded_rectangle([self.s(x0), self.s(y0), self.s(x1), self.s(y1)], radius=self.s(r), fill=fill)
        else:
            self.d.rectangle([self.s(x0), self.s(y0), self.s(x1), self.s(y1)], fill=fill)

    def circle(self, cx, cy, r, fill, outline=None, w=0):
        self.d.ellipse([self.s(cx - r), self.s(cy - r), self.s(cx + r), self.s(cy + r)], fill=fill, outline=outline, width=self.s(w))

    def poly(self, pts, fill):
        self.d.polygon([(self.s(x), self.s(y)) for x, y in pts], fill=fill)

    def line(self, pts, fill, w):
        self.d.line([(self.s(x), self.s(y)) for x, y in pts], fill=fill, width=self.s(w), joint="curve")

    def text(self, xy, t, size, fill, shadow=None, anchor="mm", off=4):
        f = font(size, t)
        if shadow is not None:
            self.d.text((self.s(xy[0] + off), self.s(xy[1] + off)), t, font=f, fill=shadow, anchor=anchor)
        self.d.text((self.s(xy[0]), self.s(xy[1])), t, font=f, fill=fill, anchor=anchor)

    def finish(self):
        # thin inner frame like an LED module edge
        self.rect(0, 0, CW, 6, (0, 0, 0, 40))
        self.rect(0, CH - 6, CW, CH, (0, 0, 0, 40))
        return self.im.resize((CW, CH), Image.LANCZOS)


def paste_icon(c, path, x, y, w, h, radius=0, border=0, border_col=(255, 255, 255, 255), shadow=True):
    """paste a PNG (our own Minitanks artwork, art_src/brand/minitanks) scaled to w x h at (x, y), optionally with rounded corners,
    a border and a soft drop shadow"""
    ic = Image.open(path).convert("RGBA").resize((c.s(w), c.s(h)), Image.LANCZOS)
    if radius:
        m = Image.new("L", ic.size, 0)
        ImageDraw.Draw(m).rounded_rectangle([0, 0, ic.size[0] - 1, ic.size[1] - 1], radius=c.s(radius), fill=255)
        a = ic.getchannel("A")
        from PIL import ImageChops
        ic.putalpha(ImageChops.multiply(a, m))
    if shadow:
        sh = Image.new("RGBA", ic.size, (0, 0, 0, 0))
        sh.putalpha(ic.getchannel("A").point(lambda v: int(v * 0.35)))
        c.im.alpha_composite(sh, (c.s(x + 4), c.s(y + 6)))
    if border:
        bd = Image.new("RGBA", (c.s(w + border * 2), c.s(h + border * 2)), (0, 0, 0, 0))
        ImageDraw.Draw(bd).rounded_rectangle([0, 0, bd.size[0] - 1, bd.size[1] - 1], radius=c.s(radius + border), fill=border_col)
        c.im.alpha_composite(bd, (c.s(x - border), c.s(y - border)))
    c.im.alpha_composite(ic, (c.s(x), c.s(y)))


MT = "art_src/brand/minitanks/"
URL = "game.if2.ai"


def ball(c, cx, cy, r):
    c.circle(cx, cy, r, hexc("ffffff"))
    c.circle(cx, cy, r, None, hexc("20344f"), 4)
    # three curved bands
    for k in (-1, 0, 1):
        pts = []
        for i in range(25):
            a = -0.9 + 1.8 * i / 24
            pts.append((cx + math.sin(a) * r * 0.95 + k * r * 0.0, cy + (a * r * 0.9) * 0.0 + math.cos(a) * r * 0.0 + (a * r * 0.95) * (0.0)))
    c.d.arc([c.s(cx - r * 1.5), c.s(cy - r * 0.6), c.s(cx + r * 0.5), c.s(cy + r * 1.4)], 200, 330, fill=hexc("2f7cff"), width=c.s(9))
    c.d.arc([c.s(cx - r * 0.5), c.s(cy - r * 1.4), c.s(cx + r * 1.5), c.s(cy + r * 0.6)], 20, 150, fill=hexc("ffc21f"), width=c.s(9))
    c.d.arc([c.s(cx - r * 0.9), c.s(cy - r * 0.9), c.s(cx + r * 0.9), c.s(cy + r * 0.9)], 60, 250, fill=hexc("2f7cff"), width=c.s(7))


def bolt(c, cx, cy, h, fill):
    w = h * 0.55
    c.poly([(cx + w * 0.15, cy - h / 2), (cx - w * 0.5, cy + h * 0.08), (cx - w * 0.02, cy + h * 0.08), (cx - w * 0.2, cy + h / 2),
            (cx + w * 0.55, cy - h * 0.12), (cx + w * 0.05, cy - h * 0.12)], fill)


def stripes(c, col, step=46, w=20, angle=1.0):
    for x in range(-CH, CW + CH, step):
        c.poly([(x, CH), (x + w, CH), (x + w + CH * angle, 0), (x + CH * angle, 0)], col)


def make():
    cells = []

    # 0 GO SPORTS
    c = Cell("13305c")
    stripes(c, hexc("1b4478"), 70, 30)
    ball(c, 112, 128, 64)
    c.text((396, 100), "GO SPORTS", 70, hexc("ffffff"), darker(hexc("13305c"), 0.5))
    c.rect(250, 156, 544, 184, hexc("2fd0b0"), 14)
    c.text((397, 170), "VOLLEYBALL", 24, hexc("0d2b3e"))
    cells.append(c.finish())

    # 1 SPIKE COLA
    c = Cell("e8322e")
    for i, (x, y, r) in enumerate([(60, 70, 18), (110, 190, 12), (560, 60, 14), (590, 190, 20), (500, 130, 8)]):
        c.circle(x, y, r, hexc("ff7a6e"))
    c.text((250, 108), "SPIKE", 112, hexc("ffffff"), darker(hexc("e8322e"), 0.55), off=6)
    c.rect(150, 168, 470, 232, hexc("ffd23a"), 32)
    c.text((310, 200), "COLA  ICE COLD", 38, hexc("a01818"))
    cells.append(c.finish())

    # 2 NOVA AIR
    c = Cell("6a45e0")
    stripes(c, hexc("7c58ee"), 80, 36)
    bolt(c, 112, 128, 150, hexc("ffe04a"))
    c.text((380, 100), "NOVA", 104, hexc("ffffff"), darker(hexc("6a45e0"), 0.5), off=6)
    c.text((380, 190), "A I R   S H O E S", 36, hexc("ffe04a"))
    cells.append(c.finish())

    # 3 SUNNY JUICE
    c = Cell("ffb02e")
    cx, cy = 118, 128
    for i in range(12):
        a = i * math.tau / 12
        c.line([(cx + math.cos(a) * 62, cy + math.sin(a) * 62), (cx + math.cos(a) * 92, cy + math.sin(a) * 92)], hexc("fff0a0"), 12)
    c.circle(cx, cy, 52, hexc("fff0a0"))
    c.circle(cx - 16, cy - 8, 6, hexc("c24a10"))
    c.circle(cx + 16, cy - 8, 6, hexc("c24a10"))
    c.d.arc([c.s(cx - 24), c.s(cy - 12), c.s(cx + 24), c.s(cy + 26)], 20, 160, fill=hexc("c24a10"), width=c.s(5))
    c.text((384, 98), "SUNNY", 100, hexc("b3320c"), hexc("ffd88a"), off=5)
    c.text((384, 186), "J U I C E", 56, hexc("ffffff"), hexc("c24a10"), off=4)
    cells.append(c.finish())

    # 4 BLOCK TV
    c = Cell("141a26")
    c.circle(70, 128, 22, hexc("ff3b3b"))
    c.text((70, 128), "", 10, hexc("ffffff"))
    c.text((236, 112), "BLOCK", 88, hexc("ffffff"))
    c.rect(452, 66, 608, 154, hexc("ff3b3b"), 20)
    c.text((530, 112), "TV", 72, hexc("ffffff"))
    c.text((330, 200), "L I V E   V O L L E Y B A L L", 28, hexc("8fa3c4"))
    cells.append(c.finish())

    # 5 MOCHI POP
    c = Cell("ff8fb8")
    for (x, y, r) in [(560, 60, 22), (600, 180, 14), (40, 200, 16)]:
        c.circle(x, y, r, hexc("ffc4d9"))
    c.circle(110, 132, 76, hexc("fff4f8"))
    c.circle(88, 120, 7, hexc("5a2d44"))
    c.circle(134, 120, 7, hexc("5a2d44"))
    c.d.arc([c.s(92), c.s(120), c.s(130), c.s(158)], 20, 160, fill=hexc("5a2d44"), width=c.s(6))
    c.circle(70, 144, 11, hexc("ffb0cc"))
    c.circle(150, 144, 11, hexc("ffb0cc"))
    c.text((400, 100), "MOCHI", 98, hexc("ffffff"), hexc("d44a82"), off=6)
    c.text((400, 190), "P O P !", 62, hexc("7a1f4a"))
    cells.append(c.finish())

    # 6 WAVE FM
    c = Cell("14b0a0")
    for k, a in enumerate([0.9, 0.6, 0.35]):
        pts = [(x, 200 + k * 0 + math.sin((x / 70.0) + k * 1.2) * (20 + k * 6)) for x in range(0, CW + 1, 8)]
        c.line(pts, hexc("ffffff", int(255 * a)), 10 - k * 2)
    c.text((200, 86), "WAVE FM", 82, hexc("ffffff"), hexc("0b6f66"), off=5)
    c.rect(400, 36, 600, 120, hexc("0b6f66"), 22)
    c.text((500, 78), "88.8", 62, hexc("ffe04a"))
    cells.append(c.finish())

    # 7 HAPPY BEE
    c = Cell("ffd22e")
    c.rect(0, 190, CW, CH, hexc("20232b"))
    stripes(c, hexc("ffd22e"), 56, 26, 0.0)
    c.rect(0, 0, CW, 190, hexc("ffd22e"))
    c.circle(110, 112, 56, hexc("20232b"))
    c.rect(78, 82, 142, 140, hexc("ffd22e"), 0)
    c.circle(110, 112, 56, None, hexc("20232b"), 8)
    c.circle(92, 104, 8, hexc("20232b"))
    c.circle(128, 104, 8, hexc("20232b"))
    c.circle(148, 52, 24, hexc("ffffff"))
    c.circle(76, 52, 24, hexc("ffffff"))
    c.text((390, 90), "HAPPY", 94, hexc("20232b"), hexc("fff0a0"), off=5)
    c.text((390, 164), "B E E   H O N E Y", 38, hexc("a8570a"))
    cells.append(c.finish())

    # 8 PIXEL BANK
    c = Cell("1fb06c")
    for gx in range(0, CW, 32):
        c.rect(gx, 0, gx + 2, CH, hexc("25bd76"))
    c.circle(112, 128, 66, hexc("ffd23a"))
    c.circle(112, 128, 50, None, hexc("d49a10"), 7)
    c.text((112, 128), "$", 66, hexc("d49a10"))
    c.text((390, 100), "PIXEL", 96, hexc("ffffff"), hexc("0e6b40"), off=5)
    c.text((390, 190), "B A N K", 58, hexc("0e3f27"))
    cells.append(c.finish())

    # 9 加油
    c = Cell("d8352a")
    stripes(c, hexc("e24a3d"), 90, 40)
    c.text((230, 128), "加油!", 128, hexc("ffd24a"), hexc("7a140e"), off=7)
    c.text((520, 100), "GO", 70, hexc("ffffff"))
    c.text((520, 170), "GO GO", 44, hexc("ffe9a0"))
    cells.append(c.finish())

    # 10 ACE ENERGY
    c = Cell("a6e22e")
    stripes(c, hexc("b8ee52"), 64, 22)
    bolt(c, 96, 128, 170, hexc("20301a"))
    c.text((384, 98), "ACE", 112, hexc("20301a"), hexc("d4f58a"), off=5)
    c.text((384, 188), "E N E R G Y   D R I N K", 34, hexc("3b5a1a"))
    cells.append(c.finish())

    # 11 CLOUD NINE
    c = Cell("5fb8ff")
    def cloud(cx, cy, k, col):
        for dx, dy, r in [(-34, 6, 26), (0, -8, 34), (36, 4, 28), (-8, 14, 30), (22, 16, 26)]:
            c.circle(cx + dx * k, cy + dy * k, r * k, col)
    cloud(96, 138, 1.5, hexc("ffffff"))
    cloud(560, 70, 0.9, hexc("e6f4ff"))
    c.text((380, 100), "CLOUD", 98, hexc("ffffff"), hexc("2b7fd0"), off=6)
    c.text((380, 192), "N I N E   T R A V E L", 36, hexc("0b3f7a"))
    cells.append(c.finish())

    # 12 MINITANKS - hero: the app icon on the game's own electric blue, speed lines, the web address in a capsule
    c = Cell("0a62d8")
    for k, (y, w, col) in enumerate([(52, 360, hexc("2f9bff")), (96, 300, hexc("63b8ff")), (204, 420, hexc("2f9bff"))]):
        c.poly([(CW, y), (CW - w, y + 14), (CW - w, y + 22), (CW, y + 34)], col)
    paste_icon(c, MT + "app_icon_1024.png", 26, 28, 200, 200, radius=40, border=6)
    c.text((434, 92), "MINITANKS", 62, hexc("ffffff"), hexc("07338a"), off=5)
    c.rect(280, 146, 590, 204, hexc("ffd23a"), 29)
    c.text((435, 175), URL, 40, hexc("123a7a"))
    cells.append(c.finish())

    # 13 TEAM UP (diagonals in the two team colours)
    c = Cell("2f7cff")
    c.poly([(CW * 0.5, 0), (CW, 0), (CW, CH), (CW * 0.5 - 90, CH)], hexc("ff4fa0"))
    c.poly([(CW * 0.5 - 14, 0), (CW * 0.5 + 8, 0), (CW * 0.5 - 70, CH), (CW * 0.5 - 92, CH)], hexc("ffffff"))
    c.text((142, 128), "TEAM", 78, hexc("ffffff"), hexc("1850b0"), off=5)
    c.text((470, 128), "UP!", 100, hexc("ffffff"), hexc("b02a70"), off=5)
    cells.append(c.finish())

    # 14 MINITANKS - stencil: black / yellow hazard stripes top and bottom, the tank pictogram on a yellow disc
    c = Cell("ffcf1f")
    for y0, y1 in ((0, 40), (CH - 40, CH)):
        c.rect(0, y0, CW, y1, hexc("14161c"))
        for x in range(-60, CW + 60, 56):
            c.poly([(x, y1), (x + 28, y1), (x + 28 + (y1 - y0) * 0.9, y0), (x + (y1 - y0) * 0.9, y0)], hexc("ffcf1f"))
    c.circle(112, 128, 82, hexc("14161c"))
    c.circle(112, 128, 72, hexc("ffffff"))
    paste_icon(c, MT + "tank_large.png", 52, 68, 120, 120, shadow=False)
    c.text((400, 100), "TANK TIME", 74, hexc("14161c"))
    c.rect(238, 150, 566, 196, hexc("14161c"), 8)
    c.text((402, 173), "MINITANKS  ·  " + URL, 26, hexc("ffcf1f"))
    cells.append(c.finish())

    # 15 MINITANKS - retro arcade: dark cabinet blue, scanlines, neon cyan / magenta, a pixel-grid tank badge
    c = Cell("110b2e")
    for gy in range(0, CH, 8):
        c.rect(0, gy, CW, gy + 2, hexc("1d1450"))
    for gx in range(0, CW, 40):
        c.rect(gx, 214, gx + 2, CH, hexc("2b1b78"))
    c.rect(34, 34, 218, 218, hexc("ff3da8"), 20)
    c.rect(42, 42, 210, 210, hexc("1a1140"), 14)
    paste_icon(c, MT + "tank_large.png", 56, 56, 140, 140, shadow=False)
    c.text((438, 92), "MINITANKS", 60, hexc("2ff3ff"), hexc("ff3da8"), off=5)
    c.text((438, 160), "PRESS START", 32, hexc("ffe14a"))
    c.text((438, 204), URL, 30, hexc("ffffff"))
    cells.append(c.finish())
    return cells


def main():
    atlas = Image.new("RGBA", (CW * COLS, CH * ROWS), (255, 255, 255, 255))
    for i, cell in enumerate(make()):
        atlas.paste(cell, ((i % COLS) * CW, (i // COLS) * CH))
    atlas.convert("RGB").save("assets/env/ads.png", optimize=True)
    print("assets/env/ads.png", atlas.size)


if __name__ == "__main__":
    main()
