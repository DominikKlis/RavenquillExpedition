import sys

from PIL import Image, ImageDraw, ImageFont

TITLE = "Rabenblatt"
WIDTH, HEIGHT = 512, 128
SUPERSAMPLE = 4
PAD_X, PAD_Y = 24, 10
INK = (43, 33, 24)


def fitted_font(path, draw, box_w, box_h):
    size = box_h
    while size > 8:
        font = ImageFont.truetype(path, size)
        left, top, right, bottom = draw.textbbox((0, 0), TITLE, font=font)
        if right - left <= box_w and bottom - top <= box_h:
            return font, (left, top, right, bottom)
        size -= 2
    raise SystemExit("no font size fits")


def coverage(font_path):
    w, h = WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE
    mask = Image.new("L", (w, h), 0)
    draw = ImageDraw.Draw(mask)
    font, (left, top, right, bottom) = fitted_font(font_path, draw, w - 2 * PAD_X * SUPERSAMPLE, h - 2 * PAD_Y * SUPERSAMPLE)
    x = (w - (right - left)) // 2 - left
    y = (h - (bottom - top)) // 2 - top
    draw.text((x, y), TITLE, font=font, fill=255)
    return mask.resize((WIDTH, HEIGHT), Image.LANCZOS)


def main(font_path, out_path):
    alpha = coverage(font_path)
    image = Image.new("RGBA", (WIDTH, HEIGHT), INK + (0,))
    image.putalpha(alpha)
    image.save(out_path, format="TGA")
    print(f"{out_path}: {WIDTH}x{HEIGHT} RGBA")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: python masthead.py <UnifrakturMaguntia.ttf> <out.tga>")
    main(sys.argv[1], sys.argv[2])
