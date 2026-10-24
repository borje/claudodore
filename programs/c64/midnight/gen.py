"""Midnight Hollow asset converter: gfx/tiles.txt, gfx/sprites.txt, levels/l*.txt -> build/c64/midnight_gen.asm.

Tiles: blocks headed `== <name> <sets> <kind> <colours> [hires]`, art rows until a blank line.
  name: 1 char = map letter, longer = only referenced from asm/levels (alt stamps, icons).
  sets: comma list of tilesets (ui,l1..l5) or `all` (same char codes in every set: allocated first).
  kind: deco | solid | plat | hazard | obj:<pump|candy|key|exit|lamp|slot|heart>[:<alt stamp>]
  colours: one digit 0-7 for the whole stamp, or digits per char row-major with `/` between rows.
  MC art: 4 pixels per char, `.` $D021, `o` $D022, `+` $D023, `#` colour RAM. hires: 8 per char, `#` set.
Sprites: `== <name> [mirror] [own=<c>] [ovl=<c>]`, 21 rows x 12 MC pixels: `.` clear, `k` $D025 (black),
  `c` own colour, `y` $D026 (yellow), `p` hires overlay sprite (stored right after, pointer+1).
Levels: header lines (name/set/d021/d023/bands/time/fill/card) then `map` and 23 rows.
  lowercase enemy letters (see ENEMIES), `@` start, anything else = tile/stamp anchor (top-left).
"""
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent.parent
OUT = ROOT / "build" / "c64"
SETS = ["ui", "l1", "l2", "l3", "l4", "l5"]
KINDS = {"deco": 0, "solid": 1, "plat": 2, "hazard": 3}
OBJS = {"pump": 1, "candy": 2, "key": 3, "exit": 4, "lamp": 5, "slot": 6, "heart": 7}
ENEMIES = {"b": 1, "g": 2, "z": 3, "k": 4, "s": 5, "r": 6, "y": 7, "w": 8, "p": 9, "v": 10}
ROWS = 23
MCBITS = {".": 0, "o": 1, "+": 2, "#": 3}


def blocks(path):
    """(header words, art rows) per `==` block."""
    out, cur = [], None
    for line in path.read_text().splitlines():
        if line.startswith("=="):
            cur = (line[2:].split(), [])
            out.append(cur)
        elif cur and line.strip() and not line.startswith(";"):
            cur[1].append(line.rstrip())
        elif not line.strip():
            cur = None
    return out


class Stamp:
    def __init__(self, hdr, art):
        self.name, sets, kind, cols = hdr[:4]
        self.letter = ""
        if len(self.name) > 2 and self.name[-2] == "=":  # `long=X`: long name, map letter X
            self.name, self.letter = self.name[:-2], self.name[-1]
        self.hires = "hires" in hdr[4:]
        self.sets = SETS if sets == "all" else sets.split(",")
        self.isall = sets == "all"
        k = kind.split(":")
        self.flag = KINDS.get(k[0], 0)
        self.obj = OBJS[k[1]] if k[0] == "obj" else 0
        self.alt = k[2] if len(k) > 2 else None
        cw = 8 if self.hires else 4
        width = max(len(r) for r in art)
        assert width % cw == 0 and len(art) % 8 == 0, (self.name, width, len(art))
        self.w, self.h = width // cw, len(art) // 8
        rows = cols.split("/")
        if len(rows) == 1 and len(rows[0]) == 1:
            rows = [rows[0] * self.w] * self.h
        assert len(rows) == self.h and all(len(r) == self.w for r in rows), (self.name, cols)
        self.chars = []  # row-major (bytes, cram, flag)
        for cy in range(self.h):
            for cx in range(self.w):
                data = []
                for y in range(8):
                    row = art[cy * 8 + y].ljust(width, ".")[cx * cw:(cx + 1) * cw]
                    if self.hires:
                        data.append(sum(128 >> i for i, ch in enumerate(row) if ch != "."))
                    else:
                        data.append(sum(MCBITS[ch] << (6 - 2 * i) for i, ch in enumerate(row)))
                c = int(rows[cy][cx])
                self.chars.append((bytes(data), c if self.hires else c | 8, self.flag))


class Charset:
    def __init__(self, name):
        self.name, self.codes, self.data = name, {}, []  # (bytes,cram,flag) -> code
        self.stamps = {}  # stamp name -> list of codes

    def add(self, st):
        codes = []
        for ch in st.chars:
            if ch not in self.codes:
                self.codes[ch] = 64 + len(self.data)
                self.data.append(ch)
            codes.append(self.codes[ch])
        assert 64 + len(self.data) <= 256, f"charset {self.name} full"
        self.stamps[st.name] = codes


def bigfont(letters):
    """2x scaled ROM letters as MC stamps: yellow (#) with an orange (o) drop shadow."""
    rom = (ROOT / "retro" / "chargen.bin").read_bytes()
    out = []
    for L in letters:
        sc = ord(L) - 64 if "A" <= L <= "Z" else ord(L)
        g = [[(rom[sc * 8 + y] >> (7 - x)) & 1 for x in range(8)] for y in range(8)]
        art = [["."] * 8 for _ in range(16)]
        for y in range(8):
            for x in range(8):
                if g[y][x]:
                    for yy in (2 * y, 2 * y + 1):
                        art[yy][x] = "#"
                        if x + 1 < 8 and art[yy][x + 1] == ".":
                            art[yy][x + 1] = "o"
                    if 2 * y + 2 < 16 and art[2 * y + 2][x] == ".":
                        art[2 * y + 2][x] = "o"
        # re-apply letter pixels over shadows written by earlier pixels
        for y in range(8):
            for x in range(8):
                if g[y][x]:
                    art[2 * y][x] = art[2 * y + 1][x] = "#"
        out.append(Stamp([f"big{L}", "ui", "deco", "7"], ["".join(r) for r in art]))
    return out


def rle(data):
    out, i = [], 0
    while i < len(data):
        j = i
        while j < len(data) and data[j] == data[i] and j - i < 255:
            j += 1
        if j - i > 3 or data[i] == 0xFF:
            out += [0xFF, j - i, data[i]]
        else:
            out += data[i:j]
        i = j
    return out


def scr(text):
    """ASCII -> screen codes (uppercase font)."""
    o = []
    for ch in text:
        c = ord(ch)
        o.append(c - 64 if 64 <= c <= 95 else c if 32 <= c < 64 else 32)
    return o


def bytes_asm(label, data, per=24):
    lines = [f"{label}:" if label else ""]
    for i in range(0, len(data), per):
        lines.append("        !byte " + ",".join(str(b) for b in data[i:i + per]))
    return "\n".join(l for l in lines if l)


def level(path, sets, stamps, idx):
    hdr, maprows, inmap = {}, [], False
    for line in path.read_text().splitlines():
        if inmap:
            maprows.append(line.rstrip("\n"))
        elif line.strip() == "map":
            inmap = True
        elif line.strip() and not line.startswith("#"):
            k, _, v = line.partition(" ")
            hdr[k] = v.strip()
    maprows = maprows[:ROWS]
    assert len(maprows) == ROWS, (path, len(maprows))
    W = max(len(r) for r in maprows)
    assert 40 <= W <= 160, (path, W)
    cs = sets[hdr["set"]]
    fillname = hdr.get("fill", ".")
    fill = 32 if fillname == "." else cs.stamps[stamps[fillname].name][0]
    grid = [[fill] * ROWS for _ in range(W)]  # column-major
    objs, enem, start = [], [], (2, 20)
    for y, row in enumerate(maprows):
        for x, ch in enumerate(row.ljust(W, ".")):
            if ch in ".":
                continue
            if ch == "@":
                start = (x, y)
            elif ch in ENEMIES:
                enem.append((ENEMIES[ch], x, y))
                if ch == "s":  # spider thread: 6 cells below the hanging point
                    for t in range(6):
                        if y + t < ROWS:
                            grid[x][y + t] = cs.stamps["thread"][0]
            else:
                st = stamps[ch]
                codes = cs.stamps[st.name]
                for i, code in enumerate(codes):
                    cx, cy = x + i % st.w, y + i // st.w
                    if cx < W and cy < ROWS:
                        grid[cx][cy] = code
                if st.obj:
                    objs.append((st.obj, x, y))
    # object types: size + alt stamp (exit open, lamp lit, slot filled)
    types = {}
    for st in {id(v): v for v in stamps.values()}.values():
        if st.obj and hdr["set"] in st.sets and st.name in cs.stamps and any(o[0] == st.obj for o in objs):
            types[st.obj] = st
    flat = [c for col in grid for c in col]
    n = f"lv{idx}"
    a = [f"; {path.name}", f"{n}_w = {W}", bytes_asm(f"{n}_map", rle(flat))]
    a.append(f"{n}_start: !byte {start[0]},{start[1]}")
    a.append(f"{n}_set = {SETS.index(hdr['set'])}")
    a.append(f"{n}_fill = {fill}")
    d021 = int(hdr.get("d021", "0"))
    bands = [tuple(int(v) for v in b.split(":")) for b in hdr.get("bands", "").split()]
    a.append(f"{n}_colors: !byte {d021},{int(hdr.get('d023', '12'))},{len(bands)}")
    a.append(f"{n}_bands: !byte " + ",".join(f"{r},{c}" for r, c in bands) if bands else f"{n}_bands:")
    t = [int(v) for v in hdr.get("time", "9 0 10 0 150").split()]
    a.append(f"{n}_time: !byte {t[0]},${t[1]:02d},{t[2]},${t[3]:02d},{t[4]}")
    a.append(bytes_asm(f"{n}_name", scr(hdr["name"].ljust(21)[:21])))
    card = hdr.get("card", "").split("|")
    a.append(bytes_asm(f"{n}_card", sum((scr(l.center(38)[:38]) for l in card), []) + [0]))
    a.append(f"{n}_nobj = {len(objs)}")
    assert len(objs) <= 48, (path, len(objs))
    a.append(f"{n}_obj: !byte " + ",".join(f"{t},{x},{y}" for t, x, y in objs) if objs else f"{n}_obj:")
    a.append(f"{n}_nen = {len(enem)}")
    assert len(enem) <= 32, (path, len(enem))
    a.append(f"{n}_en: !byte " + ",".join(f"{t},{x},{y}" for t, x, y in enem) if enem else f"{n}_en:")
    # per object type 1..7: w, h, alt codes pointer
    tw = [types[t].w if t in types else 1 for t in range(1, 8)]
    th = [types[t].h if t in types else 1 for t in range(1, 8)]
    a.append(f"{n}_ow: !byte " + ",".join(map(str, tw)))
    a.append(f"{n}_oh: !byte " + ",".join(map(str, th)))
    alts = []
    for t in range(1, 8):
        st = types.get(t)
        if st and st.alt:
            alts.append(f"{n}_alt{t}")
            a.append(bytes_asm(f"{n}_alt{t}", cs.stamps[st.alt]))
        else:
            alts.append("0")
    a.append(f"{n}_alt: !word " + ",".join(alts))
    npump = sum(1 for o in objs if o[0] == 1)
    a.append(f"{n}_npump = {npump}")
    return "\n".join(a)


def sprites(path):
    out, names, data = [], [], []
    for hdr, art in blocks(path):
        name, opts = hdr[0], dict(o.split("=") if "=" in o else (o, "1") for o in hdr[1:])
        assert len(art) == 21 and all(len(r) <= 12 for r in art), (name, len(art))
        art = [r.ljust(12, ".") for r in art]
        variants = [(name, art)]
        if "mirror" in opts:
            variants.append((name + "_l", [r[::-1] for r in art]))
        for vn, va in variants:
            mc, ov = [], []
            for r in va:
                bits = 0
                obits = 0
                for i, ch in enumerate(r):
                    v = {".": 0, "k": 1, "c": 2, "y": 3, "p": 0}[ch]
                    bits |= v << (22 - 2 * i)
                    if ch == "p":
                        obits |= 3 << (22 - 2 * i)
                mc += [bits >> 16 & 255, bits >> 8 & 255, bits & 255]
                ov += [obits >> 16 & 255, obits >> 8 & 255, obits & 255]
            names.append((vn, len(data)))
            data.append(mc + [0])
            if any("p" in r for r in va):
                data.append(ov + [0])
    return names, data


NOTES = {"C": 0, "C#": 1, "D": 2, "D#": 3, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "A#": 10, "B": 11}


def music(path):
    """`<name>` lines of note tokens (D4, C#5, `.` rest, `-` hold), one per step -> note index bytes (0 rest, 1 hold)."""
    tunes = {}
    for line in path.read_text().splitlines():
        if not line.strip() or line.startswith(";"):
            continue
        name, *toks = line.split()
        tunes.setdefault(name, [])
        for t in toks:
            tunes[name].append(0 if t == "." else 1 if t == "-" else NOTES[t[:-1]] + 12 * int(t[-1]))
    a = [f"; music: PAL SID frequencies, index = octave*12 + semitone"]
    freqs = [int(16.3516 * 2 ** (n / 12) * 16777216 / 985248) for n in range(96)]
    a.append(bytes_asm("ntlo", [f & 255 for f in freqs]))
    a.append(bytes_asm("nthi", [min(255, f >> 8) for f in freqs]))
    for name, notes in tunes.items():
        a.append(f"{name}_len = {len(notes)}")
        a.append(bytes_asm(f"tune_{name}", notes))
    return "\n".join(a)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    stamps = {}
    for hdr, art in blocks(HERE / "gfx" / "tiles.txt"):
        st = Stamp(hdr, art)
        assert st.name not in stamps, st.name
        stamps[st.name] = st
        if st.letter:
            assert st.letter not in stamps, st.letter
            stamps[st.letter] = st
    big = bigfont("ABCDEGHILMNORSTUVWY")
    for st in big:
        stamps[st.name] = st
    sets = {s: Charset(s) for s in SETS}
    uniq = list({id(st): st for st in stamps.values()}.values())
    for st in sorted(uniq, key=lambda s: not s.isall):  # `all` stamps get the same codes everywhere
        for s in st.sets:
            sets[s].add(st)
    a = ["; generated by gen.py - do not edit"]
    for st in uniq:
        if st.isall:
            sym = {"*": "STAR", ",": "DOT"}.get(st.name, st.name.upper())
            a.append(f"T_{sym} = {sets['ui'].stamps[st.name][0]}")
    for s in SETS:
        cs = sets[s]
        a.append(f"; tileset {s}: {len(cs.data)} chars")
        a.append(f"cs_{s}_n = {len(cs.data)}")
        a.append(bytes_asm(f"cs_{s}", [b for d, _, _ in cs.data for b in d]))
        a.append(bytes_asm(f"cs_{s}_col", [c for _, c, _ in cs.data]))
        a.append(bytes_asm(f"cs_{s}_flg", [f for _, _, f in cs.data]))
    # ui stamps referenced from asm: codes row-major + w,h
    for st in uniq:
        name = st.name
        if "ui" in st.sets and name.isalnum():
            a.append(f"ui_{name}: !byte {st.w},{st.h}," + ",".join(map(str, sets["ui"].stamps[name])))
    a.append("cs_tab_lo: !byte " + ",".join(f"<cs_{s}" for s in SETS))
    a.append("cs_tab_hi: !byte " + ",".join(f">cs_{s}" for s in SETS))
    a.append("cs_col_lo: !byte " + ",".join(f"<cs_{s}_col" for s in SETS))
    a.append("cs_col_hi: !byte " + ",".join(f">cs_{s}_col" for s in SETS))
    a.append("cs_flg_lo: !byte " + ",".join(f"<cs_{s}_flg" for s in SETS))
    a.append("cs_flg_hi: !byte " + ",".join(f">cs_{s}_flg" for s in SETS))
    a.append("cs_n: !byte " + ",".join(f"cs_{s}_n" for s in SETS))
    lv = sorted((HERE / "levels").glob("l*.txt"))
    for i, p in enumerate(lv, 1):
        a.append(level(p, sets, stamps, i))
    a.append(f"NLEVELS = {len(lv)}")
    a.append(music(HERE / "gfx" / "music.txt"))
    for f in ("w", "map", "start", "set", "fill", "colors", "bands", "time", "name", "card", "nobj", "obj", "nen", "en",
              "ow", "oh", "alt", "npump"):
        if f in ("w", "set", "fill", "nobj", "nen", "npump"):
            a.append(f"lt_{f}: !byte " + ",".join(f"lv{i}_{f}" for i in range(1, len(lv) + 1)))
        else:
            a.append(f"lt_{f}_lo: !byte " + ",".join(f"<lv{i}_{f}" for i in range(1, len(lv) + 1)))
            a.append(f"lt_{f}_hi: !byte " + ",".join(f">lv{i}_{f}" for i in range(1, len(lv) + 1)))
    gen = OUT / "midnight_gen.asm"
    gen.write_text("\n".join(a) + "\n")
    names, data = sprites(HERE / "gfx" / "sprites.txt")
    sp = ["; generated sprites, pointer = $40 + index (VIC bank $4000)"]
    for n, i in names:
        sp.append(f"SP_{n.upper()} = {0x40 + i}")
    sp.append(f"NSPRITES = {len(data)}")
    sp.append(bytes_asm("spritedata", [b for d in data for b in d], 32))
    (OUT / "midnight_spr.asm").write_text("\n".join(sp) + "\n")
    wrap = OUT / "midnight_all.asm"
    wrap.write_text(f'!source "{HERE / "midnight.asm"}"\n'
                    f'* = $5000\n!source "{OUT / "midnight_spr.asm"}"\n'
                    f'!source "{gen}"\n!if * > $a000 {{ !error "data runs into the screen code" }}\n')
    return wrap


if __name__ == "__main__":
    print(main())
    sys.exit(0)
