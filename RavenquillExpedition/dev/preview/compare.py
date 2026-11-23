import glob
import json
import os
import re
import sys
import time

from PIL import Image, ImageChops, ImageFilter, ImageStat

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
PREVIEW = os.path.join(REPO, ".cache", "preview")
REF = os.path.join(REPO, ".cache", "preview-ref")
RENDER_SCALE, RENDER_OX, RENDER_OY = 1.5, 20, 30
PAD = (24, 24, 64, 40)
SHOT = re.compile(r"shot (\S+) (\d+) ([-\d.]+) ([-\d.]+) ([-\d.]+) ([-\d.]+) ([\d.]+) (\d+) (\d+) ([\d.]+)")


def shots_dir():
    wow = os.environ.get("WOW_DIR") or os.path.join(os.environ.get("ProgramFiles(x86)", ""), "World of Warcraft", "_forever_")
    return os.path.join(wow, "Screenshots")


def screenshot_at(epoch, folder):
    best = None
    for path in glob.glob(os.path.join(folder, "WoWScrnShot_*.jpg")):
        m = re.search(r"_(\d{6})_(\d{6})\.jpg$", path)
        if not m:
            continue
        stamp = time.mktime(time.strptime(m.group(1) + m.group(2), "%m%d%y%H%M%S"))
        gap = abs(stamp - epoch)
        if gap <= 3 and (best is None or gap < best[0]):
            best = (gap, path)
    return best and best[1]


def crop_reference(notes):
    os.makedirs(REF, exist_ok=True)
    folder = shots_dir()
    meta = {}
    for line in notes:
        m = SHOT.search(line)
        if not m:
            continue
        sid, epoch = m.group(1), int(m.group(2))
        left, top, w, h, eff, _, phys_h, world = (float(x) for x in m.groups()[2:])
        path = screenshot_at(epoch, folder)
        if not path:
            print("no screenshot for", sid)
            continue
        k = eff * phys_h / world
        x0, y0 = (left - PAD[0]) * k, phys_h - (top + PAD[1]) * k
        box = (int(x0), int(y0), int((left + w + PAD[2]) * k), int(phys_h - (top - h - PAD[3]) * k))
        Image.open(path).convert("RGB").crop(box).save(os.path.join(REF, sid + ".png"))
        meta[sid] = {"k": k, "w": w, "h": h, "source": os.path.basename(path)}
    with open(os.path.join(REF, "meta.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=1)
    return meta


def aligned_render(sid, info):
    path = os.path.join(PREVIEW, sid + ".png")
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert("RGB")
    k = info["k"]
    f = k / RENDER_SCALE
    im = im.resize((int(im.width * f), int(im.height * f)), Image.LANCZOS)
    x0, y0 = (RENDER_OX - PAD[0]) * k, (RENDER_OY - PAD[1]) * k
    w, h = (info["w"] + PAD[0] + PAD[2]) * k, (info["h"] + PAD[1] + PAD[3]) * k
    canvas = Image.new("RGB", (int(w), int(h)))
    canvas.paste(im.crop((int(x0), int(y0), int(x0 + w), int(y0 + h))), (0, 0))
    return canvas


def score(a, b, window):
    a, b = a.crop(window).convert("L"), b.crop(window).convert("L")
    a, b = a.filter(ImageFilter.GaussianBlur(1.5)), b.filter(ImageFilter.GaussianBlur(1.5))
    diff = ImageChops.difference(a, b)
    mean = ImageStat.Stat(diff).mean[0]
    close = sum(diff.histogram()[:24]) / (diff.width * diff.height)
    return round(100 - mean / 2.55, 1), round(close * 100, 1), diff


def compare(meta):
    out = os.path.join(REF, "compare")
    os.makedirs(out, exist_ok=True)
    rows = []
    for sid, info in meta.items():
        ref = Image.open(os.path.join(REF, sid + ".png")).convert("RGB")
        mine = aligned_render(sid, info)
        if mine is None:
            continue
        mine = mine.resize(ref.size)
        k = info["k"]
        window = (int(PAD[0] * k), int(PAD[1] * k), int((PAD[0] + info["w"]) * k), int((PAD[1] + info["h"]) * k))
        similarity, close, diff = score(ref, mine, window)
        heat = diff.point(lambda v: min(255, v * 4)).convert("RGB")
        sheet = Image.new("RGB", (ref.width * 3 + 40, ref.height), (0, 0, 0))
        sheet.paste(ref, (0, 0))
        sheet.paste(mine, (ref.width + 20, 0))
        sheet.paste(heat, (ref.width * 2 + 40 + window[0], window[1]))
        sheet.save(os.path.join(out, sid + ".jpg"), quality=85)
        rows.append((sid, similarity, close))
    rows.sort(key=lambda r: r[2])
    print("%-16s %10s %12s" % ("screen", "similar %", "pixels close %"))
    for sid, similarity, close in rows:
        print("%-16s %10.1f %12.1f" % (sid, similarity, close))
    with open(os.path.join(REF, "scores.json"), "w", encoding="utf-8") as fh:
        json.dump({sid: {"similar": s, "close": c} for sid, s, c in rows}, fh, indent=1)


def main():
    if len(sys.argv) > 1:
        with open(sys.argv[1], encoding="utf-8") as fh:
            meta = crop_reference(fh.read().splitlines())
    else:
        with open(os.path.join(REF, "meta.json"), encoding="utf-8") as fh:
            meta = json.load(fh)
    compare(meta)


if __name__ == "__main__":
    main()
