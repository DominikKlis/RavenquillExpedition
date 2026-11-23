import glob
import os
import struct
import zlib


class Casc:
    def __init__(self, wow_root, product):
        self.root_dir = wow_root
        self.data = os.path.join(wow_root, "Data")
        self.build = self.read_build_config(product)
        self.index = self.read_indices()
        self.archives = {}

    def read_build_config(self, product):
        with open(os.path.join(self.root_dir, ".build.info"), encoding="utf-8") as fh:
            rows = [line.rstrip("\n").split("|") for line in fh if line.strip()]
        names = [h.split("!")[0] for h in rows[0]]
        for row in rows[1:]:
            rec = dict(zip(names, row))
            if rec.get("Product") == product:
                key = rec["Build Key"]
                return self.read_config(key)
        raise SystemExit("product %s not in .build.info" % product)

    def read_config(self, key):
        path = os.path.join(self.data, "config", key[0:2], key[2:4], key)
        out = {}
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                if " = " in line:
                    k, v = line.strip().split(" = ", 1)
                    out[k] = v.split()
        return out

    def read_indices(self):
        latest = {}
        for path in glob.glob(os.path.join(self.data, "data", "*.idx")):
            name = os.path.basename(path)
            bucket, version = name[:2], int(name[2:10], 16)
            if bucket not in latest or latest[bucket][0] < version:
                latest[bucket] = (version, path)
        index = {}
        for _, path in latest.values():
            with open(path, "rb") as fh:
                raw = fh.read()
            header_size = struct.unpack_from("<I", raw, 0)[0]
            entries_at = (8 + header_size + 15) & ~15
            size = struct.unpack_from("<I", raw, entries_at)[0]
            pos = entries_at + 8
            for i in range(size // 18):
                at = pos + i * 18
                ekey = raw[at:at + 9]
                packed = int.from_bytes(raw[at + 9:at + 14], "big")
                length = struct.unpack_from("<I", raw, at + 14)[0]
                if ekey not in index:
                    index[ekey] = (packed >> 30, packed & 0x3FFFFFFF, length)
        return index

    def archive(self, n):
        if n not in self.archives:
            self.archives[n] = open(os.path.join(self.data, "data", "data.%03d" % n), "rb")
        return self.archives[n]

    def read_ekey(self, ekey):
        hit = self.index.get(ekey[:9])
        if not hit:
            return None
        n, offset, length = hit
        fh = self.archive(n)
        fh.seek(offset + 0x1E)
        return blte(fh.read(length - 0x1E))

    def encoding_pages(self):
        ekey = bytes.fromhex(self.build["encoding"][1])
        raw = self.read_ekey(ekey)
        _, _, ckey_len, ekey_len, cpage_kb, _, cpages, _, _, espec = struct.unpack_from(">2sBBBHHIIBI", raw, 0)
        pos = 22 + espec + cpages * 32
        size = cpage_kb * 1024
        for p in range(cpages):
            yield raw, pos + p * size, pos + (p + 1) * size, ckey_len, ekey_len

    def ekeys_for(self, ckeys):
        want, found = set(ckeys), {}
        for raw, at, end, ckey_len, ekey_len in self.encoding_pages():
            while at + 6 + ckey_len <= end:
                count = raw[at]
                if count == 0:
                    break
                ckey = raw[at + 6:at + 6 + ckey_len]
                if ckey in want and ckey not in found:
                    found[ckey] = raw[at + 6 + ckey_len:at + 6 + ckey_len + ekey_len]
                at += 6 + ckey_len + count * ekey_len
            if len(found) == len(want):
                break
        return found

    def read_ckey(self, ckey):
        ekey = self.ekeys_for([ckey]).get(ckey)
        return ekey and self.read_ekey(ekey)

    def root_map(self, fdids, names=()):
        raw = self.root_raw()
        want, out = set(fdids), {}
        hashes = {name_hash(n): n for n in names}
        pos, version = 0, 1
        if raw[:4] == b"TSFM":
            header_size, version = struct.unpack_from("<II", raw, 4)
            if header_size > 1000:
                header_size, version, pos = 0, 1, 12
            else:
                pos = header_size
        while pos < len(raw):
            if version >= 2:
                count, _, f1, f2, f3 = struct.unpack_from("<IIIIB", raw, pos)
                pos += 17
                flags = f1 | f2 | (f3 << 17)
            else:
                count, flags, _ = struct.unpack_from("<III", raw, pos)
                pos += 12
            ids = struct.unpack_from("<%di" % count, raw, pos)
            pos += 4 * count
            ckeys_at = pos
            pos += 16 * count
            hashes_at = None
            if not (flags & 0x10000000):
                hashes_at = pos
                pos += 8 * count
            fid = -1
            for i, delta in enumerate(ids):
                fid += delta + 1
                ckey = raw[ckeys_at + 16 * i:ckeys_at + 16 * (i + 1)]
                if fid in want and fid not in out:
                    out[fid] = ckey
                if hashes and hashes_at is not None:
                    h = struct.unpack_from("<Q", raw, hashes_at + 8 * i)[0]
                    if h in hashes and hashes[h] not in out:
                        out[hashes[h]] = ckey
        return out

    def root_raw(self):
        if not hasattr(self, "_root"):
            self._root = self.read_ckey(bytes.fromhex(self.build["root"][0]))
        return self._root

    def files(self, fdids=(), names=()):
        ckeys = self.root_map(fdids, names)
        ekeys = self.ekeys_for(ckeys.values())
        for fid, ckey in ckeys.items():
            ekey = ekeys.get(ckey)
            data = ekey and self.read_ekey(ekey)
            if data:
                yield fid, data


def blte(raw):
    if raw[:4] != b"BLTE":
        raise ValueError("not BLTE")
    header = struct.unpack_from(">I", raw, 4)[0]
    if header == 0:
        return chunk(raw[8:])
    count = int.from_bytes(raw[9:12], "big")
    sizes = [struct.unpack_from(">II", raw, 12 + i * 24) for i in range(count)]
    pos, out = header, bytearray()
    for comp, decomp in sizes:
        out += chunk(raw[pos:pos + comp], decomp)
        pos += comp
    return bytes(out)


def chunk(data, size=None):
    mode = data[:1]
    if mode == b"N":
        return data[1:]
    if mode == b"Z":
        return zlib.decompress(data[1:])
    if mode == b"F":
        return blte(data[1:])
    return bytes(size or 0)


def decode_blp(data):
    import io
    from PIL import Image
    encoding = data[8]
    width, height = struct.unpack_from("<II", data, 12)
    if encoding == 3:
        offset = struct.unpack_from("<I", data, 20)[0]
        raw = data[offset:offset + width * height * 4]
        return Image.frombytes("RGBA", (width, height), raw, "raw", "BGRA")
    return Image.open(io.BytesIO(data)).convert("RGBA")


def rot(x, k):
    return ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF


def mix(a, b, c):
    a = (a - c) & 0xFFFFFFFF; a ^= rot(c, 4); c = (c + b) & 0xFFFFFFFF
    b = (b - a) & 0xFFFFFFFF; b ^= rot(a, 6); a = (a + c) & 0xFFFFFFFF
    c = (c - b) & 0xFFFFFFFF; c ^= rot(b, 8); b = (b + a) & 0xFFFFFFFF
    a = (a - c) & 0xFFFFFFFF; a ^= rot(c, 16); c = (c + b) & 0xFFFFFFFF
    b = (b - a) & 0xFFFFFFFF; b ^= rot(a, 19); a = (a + c) & 0xFFFFFFFF
    c = (c - b) & 0xFFFFFFFF; c ^= rot(b, 4); b = (b + a) & 0xFFFFFFFF
    return a, b, c


def final(a, b, c):
    c ^= b; c = (c - rot(b, 14)) & 0xFFFFFFFF
    a ^= c; a = (a - rot(c, 11)) & 0xFFFFFFFF
    b ^= a; b = (b - rot(a, 25)) & 0xFFFFFFFF
    c ^= b; c = (c - rot(b, 16)) & 0xFFFFFFFF
    a ^= c; a = (a - rot(c, 4)) & 0xFFFFFFFF
    b ^= a; b = (b - rot(a, 14)) & 0xFFFFFFFF
    c ^= b; c = (c - rot(b, 24)) & 0xFFFFFFFF
    return a, b, c


def hashlittle2(data, pc=0, pb=0):
    length = len(data)
    a = b = c = (0xDEADBEEF + length + pc) & 0xFFFFFFFF
    c = (c + pb) & 0xFFFFFFFF
    pos = 0
    while length > 12:
        a = (a + int.from_bytes(data[pos:pos + 4], "little")) & 0xFFFFFFFF
        b = (b + int.from_bytes(data[pos + 4:pos + 8], "little")) & 0xFFFFFFFF
        c = (c + int.from_bytes(data[pos + 8:pos + 12], "little")) & 0xFFFFFFFF
        a, b, c = mix(a, b, c)
        length -= 12
        pos += 12
    if length == 0:
        return c, b
    tail = data[pos:] + bytes(12 - length)
    a = (a + int.from_bytes(tail[0:4], "little")) & 0xFFFFFFFF
    b = (b + int.from_bytes(tail[4:8], "little")) & 0xFFFFFFFF
    c = (c + int.from_bytes(tail[8:12], "little")) & 0xFFFFFFFF
    a, b, c = final(a, b, c)
    return c, b


def name_hash(path):
    c, b = hashlittle2(path.replace("/", "\\").upper().encode("ascii"))
    return (c << 32) | b
