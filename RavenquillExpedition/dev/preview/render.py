import json
import os
import re
import sys

from PIL import Image, ImageDraw, ImageFont

SCALE = 2
WIN_FONTS = os.path.join(os.environ.get("WINDIR", os.path.join(os.sep, "Windows")), "Fonts") + os.sep
WOW_ROOTS = [os.path.dirname(os.path.normpath(os.environ["WOW_DIR"]))] if os.environ.get("WOW_DIR") else []
WOW_ROOTS.append(os.path.join(os.environ.get("ProgramFiles(x86)", os.path.join(os.sep, "Program Files (x86)")), "World of Warcraft"))


def game_font(name, fallback):
    import glob
    for root in WOW_ROOTS:
        for pattern in ("*/Fonts/*", "*/Interface/AddOns/*/*", "*/Interface/AddOns/*/*/*", "*/Interface/AddOns/*/*/*/*"):
            for path in glob.glob(os.path.join(root, pattern)):
                if os.path.basename(path).lower() == name:
                    return path
    return fallback


GAME_FONTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", ".cache", "preview-art", "fonts")


def cached_font(name, fallback):
    path = os.path.join(GAME_FONTS, name)
    return path if os.path.exists(path) else fallback


UI_FONT = os.environ.get("RQ_FONT") or cached_font("frizqt__.ttf", game_font("frizqt__.ttf", WIN_FONTS + "seguisb.ttf"))
TITLE_FONT = os.environ.get("RQ_TITLE_FONT") or cached_font("morpheus.ttf", game_font("morpheus.ttf", WIN_FONTS + "palab.ttf"))
SYM_FONT = WIN_FONTS + "seguisym.ttf"
REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
ICON_DIR = os.path.join(REPO, ".cache", "preview-icons")
ART_DIR = os.path.join(REPO, ".cache", "preview-art")
try:
    with open(os.path.join(ART_DIR, "manifest.json"), encoding="utf-8") as _fh:
        ART = json.load(_fh)
except OSError:
    ART = {"atlas": {}, "file": {}}
_art_cache = {}


def art(entry):
    if entry["png"] not in _art_cache:
        _art_cache[entry["png"]] = Image.open(os.path.join(ART_DIR, entry["png"])).convert("RGBA")
    return _art_cache[entry["png"]]


def art_for(texture):
    if not texture:
        return None, None
    if texture.startswith("atlas:"):
        e = ART["atlas"].get(texture[6:].lower())
        return e, "atlas"
    key = re.sub(r"\.(blp|tga|png)$", "", texture.replace("\\", "/").lower())
    e = ART["file"].get(key)
    return e, "file"


LAYERS = {"BACKGROUND": 0, "BORDER": 1, "ARTWORK": 2, "OVERLAY": 3, "HIGHLIGHT": 9}
FONT_INK = {
    "GameFontNormal": (255, 209, 0), "GameFontNormalSmall": (255, 209, 0), "GameFontNormalLarge": (255, 209, 0),
    "GameFontNormalHuge": (255, 209, 0), "GameFontNormalMed1": (255, 209, 0), "GameFontNormalMed2": (255, 209, 0),
    "GameFontNormalMed3": (255, 209, 0),
    "GameFontHighlight": (255, 255, 255), "GameFontHighlightSmall": (255, 255, 255), "GameFontHighlightLarge": (255, 255, 255),
    "GameFontHighlightMedium": (255, 255, 255), "GameFontHighlightMed2": (255, 255, 255),
    "GameFontDisable": (128, 128, 128), "GameFontDisableSmall": (128, 128, 128),
}
ATLAS = {
    "Profession-Background-Overview": ((38, 33, 27, 255), None),
    "Profession-Background-Template2": ((30, 26, 21, 255), None),
    "Profession-overview-Card": ((16, 12, 9, 160), (92, 72, 46, 255)),
    "Professions-background-summarylist": ((20, 17, 13, 255), (80, 66, 44, 255)),
    "common-insideframe": ((0, 0, 0, 0), (110, 90, 58, 255)),
    "common-sidetab": ((22, 17, 12, 255), (118, 92, 54, 255)),
    "common-sidetab-selected": ((0, 0, 0, 0), (255, 209, 0, 255)),
    "common-dropdown-bg": ((12, 10, 8, 255), (110, 90, 58, 255)),
    "Professions-skillbar-bg": ((10, 10, 10, 255), None),
    "Professions-skillbar-frame": ((0, 0, 0, 0), (160, 130, 80, 255)),
    "UI-Character-Info-GearSlot": ((30, 24, 16, 255), (120, 98, 60, 255)),
    "Professions-Slot-Frame": ((0, 0, 0, 0), (140, 112, 66, 255)),
    "Professions-Slot-bg": ((25, 20, 14, 255), None),
}
GRAIN = {"Profession-Background-Overview": (27, 21, 16), "Profession-Background-Template2": (25, 19, 14)}
SKIP_ATLAS = ("hover", "Hover", "highlight", "Highlight", "mask", "Flare", "Flipbook")
_fonts = {}


FONT_SCALE = float(os.environ.get("RQ_FONT_SCALE", "1.038"))


def font(path, size):
    key = (path, size)
    if key not in _fonts:
        _fonts[key] = ImageFont.truetype(path, max(6, int(round(size * SCALE * FONT_SCALE))))
    return _fonts[key]


def rgba(c, alpha=1.0):
    if not c:
        return None
    a = c[3] if len(c) > 3 and c[3] is not None else 1
    return (int(c[0] * 255), int(c[1] * 255), int(c[2] * 255), int(a * alpha * 255))


def runs(text, base):
    out, color = [], base
    pos = 0
    text = re.sub(r"\|T([^:|]*)[^|]*\|t", lambda m: "\x01" + m.group(1) + "\x02", text)
    text = re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", text)
    for m in re.finditer(r"\|c([0-9a-fA-F]{8})|\|r", text):
        if m.start() > pos:
            out.append((text[pos:m.start()], color))
        if m.group(0) == "|r":
            color = base
        else:
            h = m.group(1)
            color = (int(h[2:4], 16), int(h[4:6], 16), int(h[6:8], 16), 255)
        pos = m.end()
    if pos < len(text):
        out.append((text[pos:], color))
    return out


def measure(s, fnt):
    if s.startswith("\x01"):
        return fnt.size * 1.05
    return fnt.getlength(s)


def wrap_runs(rs, fnt, width):
    lines, line, used = [], [], 0
    space = fnt.getlength(" ")
    for chunk, color in rs:
        parts = chunk.split("\n")
        for i, part in enumerate(parts):
            if i > 0:
                lines.append(line)
                line, used = [], 0
            for j, word in enumerate(re.split(r"(\s+|\x01[^\x02]*\x02)", part)):
                if word == "":
                    continue
                if word.isspace():
                    if used > 0:
                        line.append((" ", color))
                        used += space
                    continue
                w = measure(word, fnt)
                if width and used + w > width + 1 and used > 0:
                    while line and line[-1][0] == " ":
                        line.pop()
                    lines.append(line)
                    line, used = [], 0
                line.append((word, color))
                used += w
    lines.append(line)
    return lines


class Renderer:
    def __init__(self, screen):
        self.s = screen
        self.nodes = {n["id"]: n for n in screen["nodes"]}
        self.kids = {}
        for n in screen["nodes"]:
            self.kids.setdefault(n.get("parent"), []).append(n)
        w, h = int(screen["w"]) + 80, int(screen["h"]) + 60
        self.ox, self.oy = 20, 30
        self.img = Image.new("RGB", (w * SCALE, h * SCALE), (24, 28, 20))
        self.d = ImageDraw.Draw(self.img, "RGBA")
        self.boxes = []

    def box(self, n):
        if n.get("x") is None or n.get("w") is None:
            return None
        x0 = (n["x"] + self.ox) * SCALE
        y0 = (n["y"] + self.oy) * SCALE
        return [x0, y0, x0 + n["w"] * SCALE, y0 + n["h"] * SCALE]

    def alpha(self, n):
        a = 1.0
        cur = n
        while cur:
            if cur.get("alpha") is not None:
                a *= cur["alpha"]
            cur = self.nodes.get(cur.get("parent"))
        return a

    def fill(self, b, color, outline=None, width=1, radius=0):
        if b[2] <= b[0] or b[3] <= b[1]:
            return
        if color is not None and color[3] == 0:
            color = None
        if color is None and outline is None:
            return
        if radius:
            self.d.rounded_rectangle(b, radius * SCALE, fill=color, outline=outline, width=width * SCALE)
        else:
            self.d.rectangle(b, fill=color, outline=outline, width=width * SCALE)

    def grain(self, b, base):
        import random
        w, h = int(b[2] - b[0]), int(b[3] - b[1])
        if w <= 0 or h <= 0:
            return
        rnd = random.Random(7)
        im = Image.new("RGB", (w, h), base)
        d = ImageDraw.Draw(im)
        for _ in range(w // 6):
            x = rnd.randrange(w)
            y0 = rnd.randrange(h)
            length = rnd.randrange(h // 8 + 1, h // 2 + 2)
            shade = rnd.choice((-3, -2, -2, 2))
            col = tuple(max(0, min(255, c + shade)) for c in base)
            d.line([x, y0, x + rnd.choice((-1, 0, 1)), y0 + length], fill=col, width=rnd.choice((1, 2, 3)))
        self.img.paste(im, (int(b[0]), int(b[1])))

    def gradient(self, b, top, bottom, edge, radius=3):
        x0, y0, x1, y1 = [int(v) for v in b]
        if x1 <= x0 or y1 <= y0:
            return
        grad = Image.new("RGB", (1, y1 - y0))
        for y in range(y1 - y0):
            t = y / max(1, y1 - y0 - 1)
            grad.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
        grad = grad.resize((x1 - x0, y1 - y0))
        mask = Image.new("L", grad.size, 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, grad.size[0] - 1, grad.size[1] - 1], radius * SCALE, fill=255)
        self.img.paste(grad, (x0, y0), mask)
        self.d.rounded_rectangle(b, radius * SCALE, outline=edge, width=SCALE)

    def blit(self, im, b, a, tint=None, tile_w=None, tile_h=None, mask=None):
        x0, y0 = int(b[0]), int(b[1])
        w, h = int(round(b[2] - b[0])), int(round(b[3] - b[1]))
        if w <= 0 or h <= 0:
            return
        if tile_w or tile_h:
            tw = int(round(tile_w)) if tile_w else w
            th = int(round(tile_h)) if tile_h else h
            piece = im.resize((max(1, tw), max(1, th)), Image.LANCZOS)
            out = Image.new("RGBA", (w, h))
            for yy in range(0, h, piece.height):
                for xx in range(0, w, piece.width):
                    out.paste(piece, (xx, yy))
            im = out
        else:
            im = im.resize((w, h), Image.LANCZOS)
        if tint:
            r, g, bl, al = im.split()
            r = r.point(lambda v: v * tint[0])
            g = g.point(lambda v: v * tint[1])
            bl = bl.point(lambda v: v * tint[2])
            im = Image.merge("RGBA", (r, g, bl, al))
            a = a * (tint[3] if len(tint) > 3 else 1)
        if mask == "circle":
            m = Image.new("L", im.size, 0)
            ImageDraw.Draw(m).ellipse([0, 0, im.size[0] - 1, im.size[1] - 1], fill=255)
            from PIL import ImageChops
            im.putalpha(ImageChops.multiply(im.split()[3], m))
        if a < 1:
            im.putalpha(im.split()[3].point(lambda v: int(v * a)))
        self.img.paste(im, (x0, y0), im)

    def nine(self, im, entry, b, a, tint):
        l, t, r, btm = entry["slice"]
        k = entry.get("sliceScale", 1) * SCALE
        dl, dt, dr, db = l * k, t * k, r * k, btm * k
        w, h = b[2] - b[0], b[3] - b[1]
        if dl + dr > w:
            f = w / (dl + dr); dl, dr = dl * f, dr * f
        if dt + db > h:
            f = h / (dt + db); dt, db = dt * f, db * f
        W, H = im.size
        xs_src = [0, l, W - r, W]
        ys_src = [0, t, H - btm, H]
        xs_dst = [b[0], b[0] + dl, b[2] - dr, b[2]]
        ys_dst = [b[1], b[1] + dt, b[3] - db, b[3]]
        for i in range(3):
            for j in range(3):
                src = (int(xs_src[i]), int(ys_src[j]), int(xs_src[i + 1]), int(ys_src[j + 1]))
                if src[2] <= src[0] or src[3] <= src[1]:
                    continue
                self.blit(im.crop(src), [xs_dst[i], ys_dst[j], xs_dst[i + 1], ys_dst[j + 1]], a, tint)

    def draw_art(self, entry, kind, n, b, a):
        im = art(entry)
        tc = n.get("tc")
        if entry.get("slice") and not tc:
            self.nine(im, entry, b, a, n.get("tint"))
            return
        if tc:
            w, h = im.size
            im = im.crop((int(tc[0] * w), int(tc[2] * h), max(int(tc[1] * w), int(tc[0] * w) + 1), max(int(tc[3] * h), int(tc[2] * h) + 1)))
        tile_w = tile_h = None
        if kind == "atlas" and entry.get("tileH") and not tc:
            tile_w = entry["w"] * SCALE * ((b[3] - b[1]) / (entry["h"] * SCALE)) if entry["h"] else None
        if kind == "atlas" and entry.get("tileV") and not tc:
            tile_h = entry["h"] * SCALE * ((b[2] - b[0]) / (entry["w"] * SCALE)) if entry["w"] else None
        if kind == "file" and n.get("tile"):
            tile_w, tile_h = entry["w"] * SCALE, entry["h"] * SCALE
        self.blit(im, b, a, n.get("tint"), tile_w, tile_h, n.get("mask"))

    def texture(self, n, b, a):
        if n.get("layer") == "HIGHLIGHT":
            return
        tint = n.get("tint")
        ref = ("atlas:" + n["atlas"]) if n.get("atlas") else (n.get("file") or "")
        entry, kind = art_for(ref)
        if entry and not n.get("color"):
            self.draw_art(entry, kind, n, b, a)
            return
        if n.get("color"):
            c = list(n["color"])
            if tint:
                c = [c[0] * tint[0], c[1] * tint[1], c[2] * tint[2], (c[3] if len(c) > 3 else 1) * (tint[3] if len(tint) > 3 else 1)]
            self.fill(b, rgba(c, a))
            return
        atlas = n.get("atlas")
        f = n.get("file") or ""
        if f.startswith("atlas:"):
            atlas = f[6:]
        if atlas:
            if any(k in atlas for k in SKIP_ATLAS):
                return
            if atlas in GRAIN:
                self.grain(b, GRAIN[atlas])
                return
            fill, edge = ATLAS.get(atlas, ((255, 255, 255, 14), None))
            if tint and fill[3]:
                fill = (int(fill[0] * tint[0]), int(fill[1] * tint[1]), int(fill[2] * tint[2]), fill[3])
            fill = fill[:3] + (int(fill[3] * a),)
            sliced = f.startswith("atlas:") and n.get("tc")
            self.fill(b, fill, None if sliced else edge, radius=3 if edge and not sliced else 0)
            return
        if f:
            self.picture(n, b, f, a)

    def picture(self, n, b, f, a):
        local = None
        m = re.search(r"AddOns\\+([^\\]+)\\+(.+)$", f)
        if m:
            path = os.path.join(REPO, m.group(1), *m.group(2).split("\\"))
            for ext in ("", ".tga", ".blp", ".png"):
                if os.path.exists(path + ext) and not (path + ext).endswith(".blp"):
                    local = path + ext
                    break
        if local:
            try:
                im = Image.open(local).convert("RGBA")
                tc = n.get("tc")
                if tc:
                    w, h = im.size
                    im = im.crop((int(tc[0] * w), int(tc[2] * h), max(int(tc[1] * w), 1), max(int(tc[3] * h), 1)))
                tw, th = int(b[2] - b[0]), int(b[3] - b[1])
                if tw > 0 and th > 0:
                    im = im.resize((tw, th))
                    if n.get("tint"):
                        t = n["tint"]
                        r, g, bl, al = im.split()
                        r = r.point(lambda v: v * t[0])
                        g = g.point(lambda v: v * t[1])
                        bl = bl.point(lambda v: v * t[2])
                        im = Image.merge("RGBA", (r, g, bl, al))
                    if a < 1:
                        al = im.split()[3].point(lambda v: v * a)
                        im.putalpha(al)
                    self.img.paste(im, (int(b[0]), int(b[1])), im)
                return
            except Exception:
                pass
        icon = "Icons" in f or re.fullmatch(r"\d+", f)
        name = re.sub(r".*\\", "", f)
        if "Icons" in f and self.icon_image(name, n, b, a):
            return
        if icon:
            self.fill(b, (70, 58, 40, int(255 * a)), (150, 125, 80, int(255 * a)), radius=2)
            label = "".join(p[0] for p in re.split(r"[_\s]+", name) if p)[:3].upper() or "?"
            fnt = font(UI_FONT, max(6, (b[3] - b[1]) / SCALE * 0.32))
            self.d.text(((b[0] + b[2]) / 2, (b[1] + b[3]) / 2), label, font=fnt, fill=(255, 220, 150, int(220 * a)), anchor="mm")
        else:
            self.fill(b, (255, 255, 255, int(12 * a)))

    def icon_image(self, name, n, b, a):
        path = os.path.join(ICON_DIR, name.lower() + ".jpg")
        if not os.path.exists(path):
            miss = path + ".missing"
            if os.path.exists(miss):
                return False
            try:
                import urllib.request
                urllib.request.urlretrieve("https://wow.zamimg.com/images/wow/icons/large/" + name.lower() + ".jpg", path)
            except Exception:
                open(miss, "w").close()
                return False
        try:
            im = Image.open(path).convert("RGBA")
            tc = n.get("tc")
            if tc:
                w, h = im.size
                im = im.crop((int(tc[0] * w), int(tc[2] * h), max(int(tc[1] * w), 1), max(int(tc[3] * h), 1)))
            tw, th = int(b[2] - b[0]), int(b[3] - b[1])
            if tw <= 0 or th <= 0:
                return True
            im = im.resize((tw, th), Image.LANCZOS)
            if n.get("desat"):
                im = Image.merge("RGBA", (*[im.convert("L")] * 3, im.split()[3]))
            if n.get("mask") == "circle":
                mask = Image.new("L", im.size, 0)
                ImageDraw.Draw(mask).ellipse([0, 0, im.size[0] - 1, im.size[1] - 1], fill=255)
                im.putalpha(mask)
                self.img.paste(im, (int(b[0]), int(b[1])), im)
                return True
            if a < 1:
                im.putalpha(im.split()[3].point(lambda v: int(v * a)))
            self.img.paste(im, (int(b[0]), int(b[1])), im)
            return True
        except Exception:
            return False

    def menu_mark(self, n, b, a):
        kind = n.get("menuKind")
        if kind == "divider":
            y = (b[1] + b[3]) / 2
            self.d.line([b[0], y, b[2], y], fill=(90, 90, 90, 255), width=SCALE)
        elif kind in ("radio", "check"):
            glyph = ("◉" if n.get("on") else "○") if kind == "radio" else ("☑" if n.get("on") else "☐")
            self.d.text((b[0] - 10 * SCALE, (b[1] + b[3]) / 2), glyph, font=font(SYM_FONT, 12),
                        fill=(255, 209, 0, 255) if n.get("on") else (200, 200, 200, 255), anchor="mm")

    def ellipsize(self, line, fnt, width):
        dots = fnt.getlength("…")
        while line and sum(measure(s, fnt) for s, _ in line) + dots > width:
            s, color = line[-1]
            if len(s) <= 1:
                line.pop()
            else:
                line[-1] = (s[:-1], color)
        if line:
            line[-1] = (line[-1][0].rstrip() + "…", line[-1][1])

    def text(self, n, b, a):
        if n.get("menuKind"):
            self.menu_mark(n, b, a)
        t = n.get("text")
        if not t:
            return
        size = n.get("fontSize") or 12
        ff = n.get("fontFile") or ""
        path = TITLE_FONT if "MORPHEUS" in ff.upper() else UI_FONT
        fnt = font(path, size)
        base = FONT_INK.get(n.get("font") or "", (255, 209, 0))
        if n.get("ink"):
            base = rgba(n["ink"])[:3]
        if n.get("disabled"):
            base = (128, 128, 128)
        base = base + (int(255 * a),)
        width = b[2] - b[0] if b[2] > b[0] else None
        bound = n.get("boundW") is not False
        lines = wrap_runs(runs(t, base), fnt, width if bound else None)
        limit = n.get("maxLines") or (1 if bound and width and n.get("h") and n["h"] < size * 2.2 else None)
        if limit and len(lines) > limit:
            lines = lines[:limit]
            if not n.get("clipOnly"):
                self.ellipsize(lines[-1], fnt, width)
        lh = size * (n.get("lineH") or 1.2) * SCALE
        total = lh * len(lines)
        jv = n.get("justifyV") or "MIDDLE"
        top = b[1] if jv == "TOP" else ((b[1] + b[3]) / 2 - total / 2 if jv == "MIDDLE" else b[3] - total)
        just = n.get("justify") or "CENTER"
        if not bound:
            just = n.get("anchorX") or just
        for i, line in enumerate(lines):
            lw = sum(measure(s, fnt) for s, _ in line)
            if just == "LEFT" or width is None:
                x = b[0]
            elif just == "RIGHT":
                x = b[2] - lw
            else:
                x = (b[0] + b[2]) / 2 - lw / 2
            y = top + i * lh
            shadow = n.get("font") and not n.get("fontFile")
            off = max(1, SCALE // 2)
            for s, color in line:
                if s.startswith("\x01"):
                    sz = fnt.size
                    path = s[1:-1]
                    self.picture({"tc": [0.08, 0.92, 0.08, 0.92]}, [x, y + lh / 2 - sz / 2, x + sz, y + lh / 2 + sz / 2], path, color[3] / 255)
                    x += measure(s, fnt)
                    continue
                if shadow:
                    self.d.text((x + off, y + off), s, font=fnt, fill=(0, 0, 0, int(color[3] * 0.75)))
                self.d.text((x, y), s, font=fnt, fill=color)
                x += fnt.getlength(s)

    def three_slice(self, b, a, left, center, right):
        el, ec, er = (ART["atlas"].get(k) for k in (left, center, right))
        if not (el and ec and er):
            return False
        h = b[3] - b[1]
        lw = el["w"] * h / el["h"]
        rw = er["w"] * h / er["h"]
        if lw + rw > b[2] - b[0]:
            k = (b[2] - b[0]) / (lw + rw)
            lw, rw = lw * k, rw * k
        self.blit(art(el), [b[0], b[1], b[0] + lw, b[3]], a)
        self.blit(art(ec), [b[0] + lw, b[1], b[2] - rw, b[3]], a)
        self.blit(art(er), [b[2] - rw, b[1], b[2], b[3]], a)
        return True

    def real_widget(self, n, b, a):
        role = n.get("role")
        if role == "button":
            suffix = "-disabled" if n.get("disabled") else ""
            if not self.three_slice(b, a, "128-redbutton-left" + suffix, "_128-redbutton-center" + suffix, "128-redbutton-right" + suffix):
                return False
            if n.get("text") and not self.has_label(n):
                self.text(dict(n, font="GameFontDisable" if n.get("disabled") else "GameFontNormal", justify="CENTER"), b, a)
            return True
        if role == "tab":
            if not self.three_slice([b[0], b[1] - 4 * SCALE, b[2], b[3]], a, "uiframe-tab-left", "_uiframe-tab-center", "uiframe-tab-right"):
                return False
            if n.get("text"):
                self.text(dict(n, font="GameFontNormalSmall", justify="CENTER"), [b[0], b[1] + 2 * SCALE, b[2], b[3]], a)
            return True
        entry, kind = art_for(n.get("normal"))
        if not entry:
            return False
        if role == "check":
            s = min(b[2] - b[0], b[3] - b[1])
            b = [b[0], (b[1] + b[3]) / 2 - s / 2, b[0] + s, (b[1] + b[3]) / 2 + s / 2]
        self.draw_art(entry, kind, {}, b, a)
        if n.get("checked"):
            ce, ck = art_for(n.get("checkedTex"))
            if ce:
                self.draw_art(ce, ck, {}, b, a)
        return True

    def widget(self, n, b, a):
        role = n.get("role")
        if any(k.get("role") == "border" for k in self.kids.get(n["id"], [])):
            band = [b[0], b[1], b[2], b[1] + 22 * SCALE]
            self.gradient(band, (52, 38, 24), (30, 22, 15), (18, 13, 9), radius=4)
            self.d.line([b[0] + 4 * SCALE, band[3], b[2] - 4 * SCALE, band[3]], fill=(96, 74, 44, 255), width=SCALE)
        if n.get("bdColor") or n.get("backdrop"):
            bg = rgba(n.get("bdColor") or (0, 0, 0, 0.8), a)
            bd = rgba(n.get("bdBorder") or (0.5, 0.42, 0.28, 1), a)
            self.fill(b, bg, bd, radius=3)
        if self.real_widget(n, b, a):
            pass
        elif role == "button":
            dis = n.get("disabled")
            if dis:
                self.gradient(b, (70, 66, 60), (38, 35, 32), (20, 18, 16))
            else:
                self.gradient(b, (128, 14, 8), (62, 5, 3), (24, 12, 6))
                self.d.line([b[0] + 2 * SCALE, b[1] + SCALE, b[2] - 2 * SCALE, b[1] + SCALE], fill=(190, 90, 60, 120), width=1)
            if n.get("text"):
                tn = dict(n, font="GameFontDisable" if dis else "GameFontNormal", justify="CENTER")
                self.text(tn, b, a)
        elif role == "close":
            inner = [b[0] + SCALE, b[1] + SCALE, b[2] - SCALE, b[3] - SCALE]
            self.gradient(inner, (170, 20, 10), (100, 8, 4), (200, 160, 70), radius=2)
            p = 6 * SCALE
            for seg in ([inner[0] + p, inner[1] + p, inner[2] - p, inner[3] - p], [inner[0] + p, inner[3] - p, inner[2] - p, inner[1] + p]):
                self.d.line(seg, fill=(255, 209, 0, 255), width=int(3 * SCALE))
        elif role == "portrait":
            self.d.ellipse(b, fill=(40, 32, 22, 255))
        elif role == "border":
            self.fill(b, None, (18, 13, 9, 255), width=1, radius=4)
            self.fill([b[0] + 2 * SCALE, b[1] + 2 * SCALE, b[2] - 2 * SCALE, b[3] - 2 * SCALE], None, (96, 74, 44, 255), width=2, radius=4)
            self.fill([b[0] + SCALE, b[1] + SCALE, b[2] - SCALE, b[3] - SCALE], None, (112, 88, 52, 255), width=3, radius=4)
            self.fill([b[0] + 4 * SCALE, b[1] + 4 * SCALE, b[2] - 4 * SCALE, b[3] - 4 * SCALE], None, (24, 18, 12, 255), width=1, radius=3)
        elif role == "menu":
            self.fill(b, (8, 8, 10, 245), (150, 150, 150, 255), radius=4)
        elif role == "tab":
            self.fill(b, (40, 32, 22, int(255 * a)), (130, 105, 65, int(255 * a)), radius=4)
            if n.get("text"):
                self.text(dict(n, font="GameFontNormalSmall", justify="CENTER"), b, a)
        elif role == "dropdown":
            self.fill(b, (12, 10, 8, int(255 * a)), (110, 90, 58, int(255 * a)), radius=3)
            if n.get("text"):
                self.text(dict(n, font="GameFontHighlightSmall", justify="LEFT"), [b[0] + 8 * SCALE, b[1], b[2] - 18 * SCALE, b[3]], a)
            self.d.text((b[2] - 9 * SCALE, (b[1] + b[3]) / 2), "\u25be", font=font(SYM_FONT, 11), fill=(255, 209, 0, 255), anchor="mm")
        elif role == "editbox":
            self.fill(b, (0, 0, 0, int(200 * a)), (90, 90, 90, int(255 * a)), radius=3)
            if n.get("text"):
                before = self.img.copy()
                self.text(dict(n, font="GameFontHighlightSmall", justify="LEFT", maxLines=1, clipOnly=True), [b[0] + 6 * SCALE, b[1], b[2] + 4000, b[3]], a)
                mask = Image.new("L", self.img.size, 255)
                ImageDraw.Draw(mask).rectangle([int(b[0]), int(b[1]), int(b[2] - 4 * SCALE), int(b[3])], fill=0)
                self.img.paste(before, (0, 0), mask)
        elif role == "check":
            s = min(b[2] - b[0], b[3] - b[1], 18 * SCALE)
            cb = [b[0], (b[1] + b[3]) / 2 - s / 2, b[0] + s, (b[1] + b[3]) / 2 + s / 2]
            self.fill(cb, (0, 0, 0, int(255 * a)), (160, 130, 80, int(255 * a)), radius=2)
            if n.get("checked"):
                self.d.text(((cb[0] + cb[2]) / 2, (cb[1] + cb[3]) / 2), "\u2713", font=font(SYM_FONT, s / SCALE * 0.8), fill=(255, 209, 0, int(255 * a)), anchor="mm")
        elif role == "scrollbar":
            self.fill([b[2] - 6 * SCALE, b[1], b[2] - 2 * SCALE, b[3]], (255, 255, 255, int(30 * a)), radius=2)
        elif n.get("type") in ("Button", "CheckButton") and n.get("text") and not role and not self.has_label(n):
            self.text(dict(n, justify=n.get("justify") or "CENTER"), b, a)
        if n.get("lines"):
            self.messages(n, b, a)

    def messages(self, n, b, a):
        size = n.get("fontSize") or 12
        fnt = font(UI_FONT, size)
        lh = size * 1.1 * SCALE
        rows = []
        for entry in n["lines"]:
            text, ink = (entry[0], entry[1:4]) if isinstance(entry, list) else (entry, None)
            node = {"text": text, "fontSize": size, "font": n.get("font") or "GameFontHighlightSmall", "justify": "LEFT",
                    "justifyV": "TOP", "ink": ink if ink and ink[0] is not None else None}
            count = max(1, len(wrap_runs(runs(text, (0, 0, 0, 0)), fnt, b[2] - b[0])))
            rows.append((node, count))
        total = sum(c for _, c in rows) * lh
        y = b[1] if total <= b[3] - b[1] else b[3] - total
        for node, count in rows:
            if y >= b[1] - 1:
                self.text(node, [b[0], y, b[2], y + count * lh], a)
            y += count * lh

    def fallback_sidetabs(self, regions):
        for r in regions:
            rb = self.box(r)
            if rb and r.get("atlas") in ("common-sidetab", "common-sidetab-selected"):
                sel = r["atlas"] == "common-sidetab-selected"
                inset = [rb[0] + 2 * SCALE, rb[1] + 5 * SCALE, rb[2] - 2 * SCALE, rb[3] - 5 * SCALE]
                self.d.rounded_rectangle(inset, 7 * SCALE, outline=(20, 15, 10, 255), width=5 * SCALE)
                self.d.rounded_rectangle(inset, 7 * SCALE, outline=(255, 209, 0, 255) if sel else (120, 92, 54, 255), width=(2 if sel else 1) * SCALE)

    def has_label(self, n):
        return any(k.get("type") == "FontString" and k.get("text") == n.get("text") for k in self.kids.get(n["id"], []))

    def draw(self, n):
        b = self.box(n)
        a = self.alpha(n)
        kids = self.kids.get(n["id"], [])
        regions = [k for k in kids if k.get("type") in ("Texture", "FontString")]
        frames = [k for k in kids if k.get("type") not in ("Texture", "FontString")]
        regions.sort(key=lambda k: (LAYERS.get(k.get("layer") or "ARTWORK", 2), k.get("sub") or 0, 0 if k["type"] == "Texture" else 1))
        if b and n.get("type") not in ("Texture", "FontString"):
            if n.get("click"):
                self.boxes.append({"id": n["id"], "x": n["x"], "y": n["y"], "w": n["w"], "h": n["h"], "text": n.get("text")})
        if b:
            self.widget(n, b, a) if n.get("type") not in ("Texture", "FontString") else None
        border_after = None
        for r in regions:
            rb = self.box(r)
            if not rb:
                continue
            if r["type"] == "Texture":
                self.texture(r, rb, self.alpha(r))
            else:
                self.text(r, rb, self.alpha(r))
        if not ART["atlas"]:
            self.fallback_sidetabs(regions)
        sliced = [r for r in regions if r["type"] == "Texture" and (r.get("file") or "").startswith("atlas:") and r.get("tc")]
        if b and len(sliced) >= 9:
            atlas = sliced[0]["file"][6:]
            edge = ATLAS.get(atlas, (None, (110, 90, 58, 255)))[1]
            if edge:
                self.fill(b, None, edge[:3] + (int(255 * a),), radius=6)
        frames.sort(key=lambda k: (k.get("level") or 0))
        clip = b if n.get("type") == "ScrollFrame" else None
        before = self.img.copy() if clip and frames else None
        for f in frames:
            self.draw(f)
        if before is not None:
            mask = Image.new("L", self.img.size, 255)
            ImageDraw.Draw(mask).rectangle([int(clip[0]), int(clip[1]), int(clip[2]), int(clip[3])], fill=0)
            self.img.paste(before, (0, 0), mask)

    def render(self, out):
        for root in self.kids.get(None, []):
            self.draw(root)
        img = self.img.resize((self.img.width * 3 // (2 * SCALE) * 1, self.img.height * 3 // (2 * SCALE)), Image.LANCZOS)
        img.save(out)
        return img.size


PAGE = """<!doctype html><meta charset="utf-8"><title>Ravenquill preview</title>
<style>body{background:#15130f;color:#e8e0cf;font:14px "Segoe UI",sans-serif;margin:0;padding:16px}
h1{font-size:18px;color:#ffd100}nav{display:flex;flex-wrap:wrap;gap:6px;margin:8px 0 16px}nav a{color:#ffd100;
text-decoration:none;border:1px solid #6b5531;border-radius:4px;padding:2px 8px}section{margin:0 0 32px}
h2{font-size:15px;color:#ffd100}img{max-width:100%;height:auto;display:block}</style>
<h1>Ravenquill preview</h1><nav>{nav}</nav>{body}"""


def gallery(outdir, index):
    nav = "".join('<a href="#%s">%s</a>' % (s["id"], s["title"]) for s in index)
    body = "".join('<section id="%s"><h2>%s</h2><img src="%s" alt="%s"></section>' % (s["id"], s["title"], s["png"], s["title"])
                   for s in index)
    with open(os.path.join(outdir, "index.html"), "w", encoding="utf-8") as fh:
        fh.write(PAGE.replace("{nav}", nav).replace("{body}", body))


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(REPO, ".cache", "preview")
    os.makedirs(ICON_DIR, exist_ok=True)
    data = json.load(open(os.path.join(outdir, "screens.json"), encoding="utf-8"))
    index = []
    for s in data["screens"]:
        r = Renderer(s)
        size = r.render(os.path.join(outdir, s["id"] + ".png"))
        index.append({"id": s["id"], "title": s["title"], "w": s["w"], "h": s["h"], "png": s["id"] + ".png", "size": size,
                      "clicks": r.boxes, "ox": r.ox, "oy": r.oy, "scale": 1.5})
    json.dump(index, open(os.path.join(outdir, "index.json"), "w", encoding="utf-8"), ensure_ascii=False)
    gallery(outdir, index)
    print("%d screens -> %s" % (len(index), os.path.join(outdir, "index.html")))


if __name__ == "__main__":
    main()
