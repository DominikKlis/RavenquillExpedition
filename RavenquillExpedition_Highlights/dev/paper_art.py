import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

SUPERSAMPLE = 4
INK = (43, 33, 24)
VIGNETTE_SIZE = 256
VIGNETTE_LIGHT = ((255, 251, 238), 0.6, (0.5, 0.45), 0.62)
VIGNETTE_DARK = ((120, 88, 46), 0.28, 0.62)


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
            dark_a = dark_max * min(1.0, max(0.0, (dark_d - dark_from) / (1 - dark_from)))
            rgb, a = over(dark_rgb, dark_a, light_rgb, light_a)
            pixels[x, y] = tuple(round(c) for c in rgb) + (round(a * 255),)
    return image


def main(font_path, out_dir):
    art = {"masthead": masthead(font_path), "vignette": vignette()}
    for name, image in art.items():
        path = os.path.join(out_dir, name + ".tga")
        image.save(path, format="TGA")
        print(f"{path}: {image.width}x{image.height} RGBA")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: python paper_art.py <UnifrakturMaguntia.ttf> <Media dir>")
    main(sys.argv[1], sys.argv[2])
