import csv
import glob
import json
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import casc

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
OUT = os.path.join(REPO, ".cache", "preview-art")
WAGO = "https://wago.tools/db2/%s/csv"
TABLES = ("UiTextureAtlas", "UiTextureAtlasMember", "UiTextureAtlasElement", "UiTextureAtlasElementSliceData")
TEMPLATE_ATLASES = [
    "UI-Frame-PortraitMetal-CornerTopLeft", "UI-Frame-Metal-CornerTopRight", "UI-Frame-Metal-CornerBottomLeft",
    "UI-Frame-Metal-CornerBottomRight", "_UI-Frame-Metal-EdgeTop", "_UI-Frame-Metal-EdgeBottom", "!UI-Frame-Metal-EdgeLeft",
    "!UI-Frame-Metal-EdgeRight", "_UI-Frame-TopTileStreaks", "RedButton-Exit", "128-RedButton-Left", "128-RedButton-Right",
    "_128-RedButton-Center", "128-RedButton-Left-Disabled", "128-RedButton-Right-Disabled", "_128-RedButton-Center-Disabled",
    "checkbox-minimal", "checkmark-minimal", "uiframe-tab-left", "uiframe-tab-right", "_uiframe-tab-center",
    "uiframe-activetab-left", "uiframe-activetab-right", "_uiframe-activetab-center", "common-search-border",
    "common-dropdown-a-button", "common-dropdown-bg", "minimal-scrollbar-track-top", "minimal-scrollbar-track-middle",
    "minimal-scrollbar-track-bottom", "minimal-scrollbar-small-thumb-top", "minimal-scrollbar-small-thumb-middle",
    "minimal-scrollbar-small-thumb-bottom",
]
FONT_FILES = ["Fonts/frizqt__.ttf", "Fonts/MORPHEUS.TTF"]
TEMPLATE_FILES = ["Interface/FrameGeneral/UI-Background-Rock", "Interface/CharacterFrame/TempPortraitAlphaMask"]


BUILD = {}


def table(name):
    path = os.path.join(OUT, "db", BUILD["version"], name + ".csv")
    if not os.path.exists(path):
        os.makedirs(os.path.dirname(path), exist_ok=True)
        print("downloading", name, BUILD["version"], "from wago.tools")
        req = urllib.request.Request((WAGO % name) + "?build=" + BUILD["version"], headers={"User-Agent": "addon-preview/1.0"})
        with urllib.request.urlopen(req) as resp, open(path, "wb") as out:
            out.write(resp.read())
    with open(path, encoding="utf-8") as fh:
        return list(csv.DictReader(fh))


def build_version(wow, product):
    with open(os.path.join(wow, ".build.info"), encoding="utf-8") as fh:
        rows = [line.rstrip("\n").split("|") for line in fh if line.strip()]
    names = [h.split("!")[0] for h in rows[0]]
    for row in rows[1:]:
        rec = dict(zip(names, row))
        if rec.get("Product") == product:
            return rec["Version"]
    raise SystemExit("product %s not installed" % product)


def atlas_index():
    atlases = {r["ID"]: r for r in table("UiTextureAtlas")}
    members = {}
    for r in table("UiTextureAtlasMember"):
        members.setdefault(r["UiTextureAtlasElementID"], []).append(r)
    names = {}
    for r in table("UiTextureAtlasElement"):
        names[r["Name"].lower()] = r["ID"]
    slices = {r["UiTextureAtlasElementID"]: r for r in table("UiTextureAtlasElementSliceData")}
    return atlases, members, names, slices


def pick(element_members, atlases):
    best = None
    for m in element_members:
        a = atlases.get(m["UiTextureAtlasID"])
        if not a:
            continue
        low = m["CommittedName"].lower()
        hires = low.endswith("-2x")
        rank = (0 if "-c60" in low else 2) + (1 if hires else 0)
        if best is None or rank < best[0]:
            best = (rank, m, a)
    return best


def used_names(known):
    found = set(n.lower() for n in TEMPLATE_ATLASES)
    strings = re.compile(r'"([^"\n]{3,80})"')
    for path in glob.glob(os.path.join(REPO, "RavenquillExpedition*", "**", "*.lua"), recursive=True):
        if os.sep + "dev" + os.sep in path or os.sep + "libs" + os.sep in path:
            continue
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for s in strings.findall(fh.read()):
                low = s.lower()
                if low in known:
                    found.add(low)
    for prefix in ("profession-background-card-", "skillbar_fill_flipbook_", "professions-recipe-"):
        found.update(k for k in known if k.startswith(prefix))
    return found


def used_files():
    found = set(f.lower() for f in TEMPLATE_FILES)
    pattern = re.compile(r'"(Interface\\\\[^"]+)"')
    for path in glob.glob(os.path.join(REPO, "RavenquillExpedition*", "**", "*.lua"), recursive=True):
        if os.sep + "dev" + os.sep in path or os.sep + "libs" + os.sep in path:
            continue
        with open(path, encoding="utf-8", errors="ignore") as fh:
            for s in pattern.findall(fh.read()):
                low = s.replace("\\\\", "/").lower()
                if "/icons/" in low or "/addons/" in low:
                    continue
                found.add(low)
    return found


def write_widths(font_path, out_path):
    from PIL import ImageFont
    if not os.path.exists(font_path):
        return
    f = ImageFont.truetype(font_path, 1000)
    chars = [chr(c) for c in range(32, 127)] + list("äöüÄÖÜß€„“”–—…·»«°é")
    with open(out_path, "w", encoding="utf-8") as fh:
        fh.write("return {\n")
        for ch in chars:
            key = ch.replace("\\", "\\\\").replace('"', '\\"')
            fh.write('  ["%s"] = %.4f,\n' % (key, f.getlength(ch) / 1000))
        fh.write("}\n")


def safe(name):
    return re.sub(r"[^a-z0-9_.!-]", "_", name.lower())


def main():
    wow = os.environ.get("WOW_ROOT") or os.path.join(os.environ.get("ProgramFiles(x86)", "C:" + os.sep + "Program Files (x86)"), "World of Warcraft")
    product = os.environ.get("WOW_PRODUCT", "wowf")
    os.makedirs(OUT, exist_ok=True)
    BUILD["version"] = build_version(wow, product)
    atlases, members, names, slices = atlas_index()
    wanted = used_names(names)
    plan = {}
    for name in sorted(wanted):
        if name not in names:
            continue
        hit = pick(members.get(names[name], []), atlases)
        if hit:
            plan[name] = hit
    fdids = {int(a["FileDataID"]) for _, _, a in plan.values()}
    paths = used_files()
    store = casc.Casc(wow, product)
    blobs = {}
    for key, data in store.files(sorted(fdids), [p + ".blp" for p in sorted(paths)]):
        blobs[key] = data
    manifest = {"atlas": {}, "file": {}}
    images = {}
    for name, (rank, m, a) in plan.items():
        fid = int(a["FileDataID"])
        if fid not in blobs:
            continue
        if fid not in images:
            images[fid] = casc.decode_blp(blobs[fid])
        im = images[fid]
        sx, sy = im.width / int(a["AtlasWidth"]), im.height / int(a["AtlasHeight"])
        box = (int(int(m["CommittedLeft"]) * sx), int(int(m["CommittedTop"]) * sy), int(int(m["CommittedRight"]) * sx),
               int(int(m["CommittedBottom"]) * sy))
        crop = im.crop(box)
        scale = 0.5 if m["CommittedName"].lower().endswith("-2x") else 1
        w = int(m["OverrideWidth"]) or int(m["Width"])
        h = int(m["OverrideHeight"]) or int(m["Height"])
        flags = int(m["CommittedFlags"])
        png = "a_" + safe(name) + ".png"
        crop.save(os.path.join(OUT, png))
        entry = {"png": png, "w": round(w * scale, 2), "h": round(h * scale, 2),
                 "tileH": bool(flags & 4) or name.startswith("_"), "tileV": bool(flags & 2) or name.startswith("!")}
        sl = slices.get(m["UiTextureAtlasElementID"])
        if sl:
            entry["slice"] = [int(sl[k]) * sx for k in ("Left", "Top", "Right", "Bottom")]
            entry["sliceScale"] = scale
            entry["sliceMode"] = int(sl["SliceMode"])
        manifest["atlas"][name] = entry
    for key, data in blobs.items():
        if isinstance(key, str):
            im = casc.decode_blp(data)
            png = "f_" + safe(key[:-4].replace("/", "_")) + ".png"
            im.save(os.path.join(OUT, png))
            manifest["file"][key[:-4].lower()] = {"png": png, "w": im.width, "h": im.height}
    os.makedirs(os.path.join(OUT, "fonts"), exist_ok=True)
    for name, data in store.files([], FONT_FILES):
        with open(os.path.join(OUT, "fonts", os.path.basename(name).lower()), "wb") as fh:
            fh.write(data)
    write_widths(os.path.join(OUT, "fonts", "frizqt__.ttf"), os.path.join(OUT, "fontwidths.lua"))
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)
    with open(os.path.join(OUT, "atlas.lua"), "w", encoding="utf-8") as fh:
        fh.write("return {\n")
        for name, info in sorted(manifest["atlas"].items()):
            fh.write('  ["%s"] = { %s, %s },\n' % (name, info["w"], info["h"]))
        fh.write("}\n")
    print("%d atlases, %d files -> %s" % (len(manifest["atlas"]), len(manifest["file"]), OUT))
    missing = sorted(set(wanted) - set(manifest["atlas"]))
    if missing:
        print("not found:", ", ".join(missing[:20]))


if __name__ == "__main__":
    main()
