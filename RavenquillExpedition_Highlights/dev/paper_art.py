import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SUPERSAMPLE = 4
INK = (43, 33, 24)
RULE = (122, 102, 74)
DROP_CAP_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZÄÖÜ"
DROP_CAP_GRID = (8, 4)
DROP_CAP_CELL = 64
DROP_CAP_PAD = 2
HEADINGS = {"inbrief_deDE": "In Kürze", "inbrief_enUS": "In Brief"}
VIGNETTE_SIZE = 256
VIGNETTE_LIGHT = ((255, 248, 228), 0.38, (0.5, 0.45), 0.65)
VIGNETTE_DARK = ((110, 80, 40), 0.34, 0.55)
DOTTED_SIZE = (512, 4)
DOTTED_PERIOD, DOTTED_ON = 4, 2


def fitted_font(path, draw, text, box_w, box_h):
    size = box_h
    while size > 8:
        font = ImageFont.truetype(path, size)
        left, top, right, bottom = draw.textbbox((0, 0), text, font=font)
        if right - left <= box_w and bottom - top <= box_h:
            return font, (left, top, right, bottom)
        size -= 2
    raise SystemExit("no font size fits " + text)


def centred_text(font_path, text, width, height, pad_x, pad_y):
    w, h = width * SUPERSAMPLE, height * SUPERSAMPLE
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    font, (left, top, right, bottom) = fitted_font(font_path, draw, text, w - 2 * pad_x * SUPERSAMPLE,
                                                   h - 2 * pad_y * SUPERSAMPLE)
    draw.text(((w - (right - left)) // 2 - left, (h - (bottom - top)) // 2 - top), text, font=font, fill=255)
    return mask.resize((width, height), Image.LANCZOS)


def inked(alpha, colour=INK):
    image = Image.new("RGBA", alpha.size, colour + (0,))
    image.putalpha(alpha)
    return image


def masthead(font_path):
    return inked(centred_text(font_path, "Rabenblatt", 512, 128, 24, 10))


def heading(font_path, text):
    return inked(centred_text(font_path, text, 256, 64, 6, 6))


def drop_cap_font(font_path, cell):
    probe = ImageDraw.Draw(Image.new("L", (1, 1)))
    size = cell * 2
    while size > 8:
        font = ImageFont.truetype(font_path, size)
        boxes = [probe.textbbox((0, 0), letter, font=font) for letter in DROP_CAP_LETTERS]
        top, bottom = min(b[1] for b in boxes), max(b[3] for b in boxes)
        widest = max(b[2] - b[0] for b in boxes)
        if widest <= cell and bottom - top <= cell:
            return font, boxes, top
        size -= 1
    raise SystemExit("no drop cap size fits")


def drop_caps(font_path):
    cols, rows = DROP_CAP_GRID
    cell = DROP_CAP_CELL * SUPERSAMPLE
    inner = cell - 2 * DROP_CAP_PAD * SUPERSAMPLE
    mask = Image.new("L", (cols * cell, rows * cell), 0)
    draw = ImageDraw.Draw(mask)
    font, boxes, top = drop_cap_font(font_path, inner)
    pad = DROP_CAP_PAD * SUPERSAMPLE
    for i, letter in enumerate(DROP_CAP_LETTERS):
        col, row = i % cols, i // cols
        x = col * cell + pad - boxes[i][0]
        y = row * cell + pad - top
        draw.text((x, y), letter, font=font, fill=255)
    widths = [round((b[2] - b[0] + 2 * pad) / cell, 2) for b in boxes]
    return inked(mask.resize((cols * DROP_CAP_CELL, rows * DROP_CAP_CELL), Image.LANCZOS)), widths


def over(top_rgb, top_a, under_rgb, under_a):
    a = top_a + under_a * (1 - top_a)
    if a <= 0:
        return (0, 0, 0), 0.0
    rgb = tuple((t * top_a + u * under_a * (1 - top_a)) / a for t, u in zip(top_rgb, under_rgb))
    return rgb, a


def vignette():
    n = VIGNETTE_SIZE
    light_rgb, light_max, (lx, ly), light_reach = VIGNETTE_LIGHT
    dark_rgb, dark_max, dark_from = VIGNETTE_DARK
    image = Image.new("RGBA", (n, n))
    pixels = image.load()
    for y in range(n):
        for x in range(n):
            u, v = (x + 0.5) / n, (y + 0.5) / n
            light_d = math.hypot((u - lx) / 0.5, (v - ly) / 0.55) / math.sqrt(2)
            dark_d = math.hypot((u - 0.5) / 0.5, (v - 0.5) / 0.5) / math.sqrt(2)
            light_a = light_max * max(0.0, 1 - light_d / light_reach)
            dark_a = dark_max * min(1.0, max(0.0, (dark_d - dark_from) / (1 - dark_from))) ** 1.4
            rgb, a = over(dark_rgb, dark_a, light_rgb, light_a)
            pixels[x, y] = tuple(round(c) for c in rgb) + (round(a * 255),)
    return image


def dotted():
    w, h = DOTTED_SIZE
    image = Image.new("RGBA", (w, h), RULE + (0,))
    pixels = image.load()
    for x in range(w):
        if x % DOTTED_PERIOD < DOTTED_ON:
            for y in range(h):
                pixels[x, y] = RULE + (235,)
    return image


def main(font_path, out_dir):
    caps, widths = drop_caps(font_path)
    art = {"masthead": masthead(font_path), "dropcaps": caps, "vignette": vignette(), "dotted": dotted()}
    for name, text in HEADINGS.items():
        art[name] = heading(font_path, text)
    for name, image in art.items():
        path = os.path.join(out_dir, name + ".tga")
        image.save(path, format="TGA")
        print(f"{path}: {image.width}x{image.height} RGBA")
    print("DROP_CAP_WIDTH = { " + ", ".join(f"{w:g}" for w in widths) + " }")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: python paper_art.py <UnifrakturMaguntia.ttf> <Media dir>")
    main(sys.argv[1], sys.argv[2])
