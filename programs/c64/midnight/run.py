"""Midnight Hollow: build (gen.py + ACME), check every level can be finished, then drive the game in VICE.

`uv run programs/c64/midnight/run.py` runs the checks; `... run.py play` just starts the game (real time).
Teleports go through the game's own respawn: poke the checkpoint cell, kill the player (one life given back).
"""
import sys
from pathlib import Path

from retro import BUILD, C64, assemble, labels

sys.path.insert(0, str(Path(__file__).parent))
import gen  # noqa: E402

OUT = BUILD / "c64"
prg = assemble(gen.main(), out=OUT / "midnight.prg", symbols=OUT / "midnight.sym")
S = labels(OUT / "midnight.sym")


# ---------------------------------------------------------------- level check (no emulator)
def load(path):
    stamps = {}
    for hdr, art in gen.blocks(gen.HERE / "gfx" / "tiles.txt"):
        st = gen.Stamp(hdr, art)
        stamps[st.name] = st
        if st.letter:
            stamps[st.letter] = st
    rows = path.read_text().split("\nmap\n")[1].splitlines()[:23]
    W = max(len(r) for r in rows)
    flag = [[0] * 23 for _ in range(W)]
    items, start, plats = [], None, []
    for y, row in enumerate(rows):
        for x, ch in enumerate(row.ljust(W, ".")):
            if ch == ".":
                continue
            if ch == "@":
                start = (x, y)
            elif ch in gen.ENEMIES:
                if ch == "w":  # gear: 48 px wide, swings +-40 px
                    plats.append((x - 4, x + 10, y))
                if ch == "p":  # pendulum bob
                    plats.append((x - 4, x + 6, y + 1))
            else:
                st = stamps[ch]
                for i, (_, _, f) in enumerate(st.chars):
                    cx, cy = x + i % st.w, y + i // st.w
                    if cx < W and cy < 23:
                        flag[cx][cy] = f
                if st.obj in (1, 3, 4, 6):  # pumpkin, key, exit, lantern slot
                    items.append((ch, x, y, st.w, st.h))
    return W, flag, items, start, plats


def unreachable(path, up=6):
    """Items no standing spot can touch. Coarse model of the weaker jump (Nova: 52 px = 6 rows up)."""
    W, flag, items, start, plats = load(path)

    def surf(x, r):  # feet can rest on top of row r in column x
        if not (0 <= x < W and 0 < r < 23):
            return False
        ok = flag[x][r] in (1, 2) or any(a <= x <= b and r == py for a, b, py in plats)
        return ok and flag[x][r - 1] not in (1, 2) and all(flag[x][rr] != 1 for rr in range(max(0, r - 3), r))

    def land(x, r):  # fall down column x from row r
        for rr in range(r, 23):
            if flag[x][rr] == 3:
                return None
            if surf(x, rr):
                return rr
        return None

    first = (start[0], land(start[0], start[1] + 1))
    seen, todo = {first}, [first]
    while todo:
        x, r = todo.pop()
        nxt = []
        for dx in (-1, 1):
            if surf(x + dx, r):
                nxt.append((x + dx, r))
            elif 0 <= x + dx < W and land(x + dx, r):
                nxt.append((x + dx, land(x + dx, r)))
        for dx in range(-9, 10):
            for r2 in range(max(1, r - up), 23):
                if abs(dx) <= (6 if r2 <= r - 3 else 8 if r2 <= r else 9) and surf(x + dx, r2):
                    nxt.append((x + dx, r2))
        for n in nxt:
            if n not in seen:
                seen.add(n)
                todo.append(n)
    return [(ch, x, y) for ch, x, y, w, h in items
            if not any(x - 2 <= sx <= x + w and y <= sr - 1 and y + h - 1 >= sr - 3 - up for sx, sr in seen)]


for lv in sorted((gen.HERE / "levels").glob("l*.txt")):
    assert not unreachable(lv), (lv.name, unreachable(lv))
    assert sum(r.count("P") for r in lv.read_text().split("\nmap\n")[1].splitlines()) in (20, 6), lv.name
print("levels: everything reachable")


# ---------------------------------------------------------------- in VICE
def pk(c, name, n=1):
    v = c.peek(S[name], n)
    return v[0] if n == 1 else v


def po(c, name, *vals):
    c.poke(S[name], bytes(vals))


def fire(c):
    c.joyport("fire")
    c.run_frames(3)
    c.joyport()
    c.run_frames(3)


def frame(c, n=1):
    for _ in range(n):
        assert c.run_until(S["gameframe"], timeout=5)
        c.run_frames(1)


def goto(c, col, row):
    """Respawn the player standing with feet in cell (col, row)."""
    po(c, "chkc", col)
    po(c, "chkr", row)
    po(c, "lives", pk(c, "lives") + 1)
    po(c, "pstate", 1)
    po(c, "dtimer", 1)
    frame(c, 3)
    assert pk(c, "pstate") == 0


def objects(c):
    n = pk(c, "nobj")
    return list(zip(pk(c, "otype", 48)[:n], pk(c, "ocol", 48)[:n], pk(c, "orow", 48)[:n], pk(c, "ostat", 48)[:n]))


def bottom(c):
    return c.screen_text().splitlines()[-1]


def skip_intro(c):
    """Fire during the intro; returns stopped in the title's input loop."""
    assert c.run_until(S["iwait"], timeout=15)
    fire(c)
    assert c.run_until(S["firenew"], timeout=10)
    assert "PRESS FIRE TO START" in c.screen_text()


def start_level(c, lv, hero=0):
    """From the title: pick a hero, jump straight to level lv (0-4) at its card, then play."""
    assert c.run_until(S["firenew"], timeout=15)
    fire(c)
    assert c.run_until(S["selp"], timeout=10)
    if hero:
        c.joyport("right")
        c.run_frames(3)
        c.joyport()
    c.run_frames(3)
    c.joyport("fire")
    assert c.run_until(S["levelcard"], timeout=10)
    c.joyport()
    po(c, "level", lv)
    assert c.run_until(S["firenew"], timeout=10)
    fire(c)
    assert c.run_until(S["gameframe"], timeout=10)
    frame(c, 2)


def main():
    with C64(warp=sys.argv[1:] != ["play"]) as c:
        c.start(prg)
        if sys.argv[1:] == ["play"]:
            c.resume()
            c.proc.wait()
            sys.exit()

        # ---- intro: eyes, lightning, title rises from the ground (dark red, gold after the lightning),
        # the story (the Count, Grandma Hazel), the rules, then the title screen; intro tune throughout
        tune = lambda: pk(c, "mcur")  # noqa: E731
        assert c.run_until(S["eyeson"], timeout=15)
        assert tune() == 1, "intro tune from boot"
        c.run_frames(2)
        c.screenshot(OUT / "midnight_intro0.png")
        assert c.run_until(S["risetitle"], timeout=30)
        c.run_frames(60)
        c.screenshot(OUT / "midnight_intro_rise.png")
        assert c.run_until(S["titlecol"], timeout=30)  # all letters up, the lightning struck
        assert c.peek(0xD800 + 2 * 40 + 6)[0] & 15 == 2 + 8, "title dark red while rising"
        c.run_frames(2)
        assert c.peek(0xD800 + 2 * 40 + 6)[0] & 15 == 7 + 8, "gold after the lightning"
        for _ in range(80):
            c.run_frames(25)
            if "GRANDMA HAZEL" in c.screen_text():
                break
        t = c.screen_text()
        assert "COUNT VESPER MORROW HAS STOLEN" in t and "TAKE MY PAIL, CHILD. FIND THE" in t, t
        assert len(c.sprites()) == 3, c.sprites()
        c.screenshot(OUT / "midnight_intro1.png")
        for _ in range(80):
            c.run_frames(25)
            if "PUMPKINS TO THE MOON LANTERN" in c.screen_text():
                break
        t = c.screen_text()
        assert "COLLECT 20 GLOWING PUMPKINS" in t and "FIRE THROWS CANDY. UP JUMPS." in t, t
        c.screenshot(OUT / "midnight_intro2.png")
        assert c.run_until(S["title"], timeout=30), "the intro runs into the title screen"
        assert c.run_until(S["firenew"], timeout=10)
        t = c.screen_text()
        assert "PRESS FIRE TO START" in t and "F1 MUSIC ON/OFF" in t, t
        assert tune() == 1 and pk(c, "mpend") == 0, "no tune change into the title"

        # ---- title, select
        c.screenshot(OUT / "midnight_title.png")
        fire(c)
        assert c.run_until(S["selp"], timeout=10)
        t = c.screen_text()
        assert "PIP" in t and "DR. NOVA" in t and "WITCH-HAT KID" in t and "LEFT/RIGHT CHOOSE" in t, t
        c.run_frames(3)
        assert len(c.sprites()) == 4, c.sprites()
        c.joyport("right")
        c.run_frames(3)
        c.joyport()
        c.run_frames(2)
        assert pk(c, "hero") == 1
        c.screenshot(OUT / "midnight_select.png")
        c.joyport("left")
        c.run_frames(3)
        c.joyport()
        c.run_frames(2)
        assert pk(c, "hero") == 0
        fire(c)
        assert c.run_until(S["firenew"], timeout=10)
        assert "9 PM. THE GRAVEYARD." in c.screen_text()
        c.run_frames(20)
        assert tune() == 2 and pk(c, "mpend") == 0, "faded into the levels' tune on the card"
        assert c.peek(S["mmel"], 2) == bytes([S["tune_dance"] & 255, S["tune_dance"] >> 8])
        c.screenshot(OUT / "midnight_card1.png")
        fire(c)
        assert c.run_until(S["gameframe"], timeout=10)
        frame(c, 5)

        # ---- level 1: HUD, scrolling, frame rate
        t = c.screen_text().splitlines()
        assert t[0].startswith("SCORE 000000 HI 020000"), t[0]
        assert t[-1].startswith("LEVEL 1 THE GRAVEYARD CANDY 00/20") and t[-1].endswith("9:00"), t[-1]
        assert pk(c, "lives") == 3 and pk(c, "ammo") == 5 and pk(c, "npump") == 20
        c.screenshot(OUT / "midnight_l1.png")
        po(c, "inv", 255)  # enemies walk in from the right edge: don't die mid-measurement
        c.joyport("right")
        frame(c, 60)
        po(c, "inv", 255)
        f0, a0 = pk(c, "frame"), pk(c, "anim")
        c.run_frames(200)
        f1, a1 = pk(c, "frame"), pk(c, "anim")
        c.joyport()
        assert (a1 - a0) % 256 >= 194, ("logic frames per 200 while scrolling", (a1 - a0) % 256, (f1 - f0) % 256)
        assert pk(c, "coarse") > 5 and pk(c, "pstate") == 0
        c.screenshot(OUT / "midnight_l1_scrolled.png")

        # ---- pumpkin pickup: stand on one
        po(c, "lucky", 0, 0)  # no luck: any touch kills
        pump = next(o for o in objects(c) if o[0] == 1 and o[3] == 0)
        sc, n = pk(c, "score", 3), pk(c, "pumps")
        goto(c, pump[1], pump[2] + 1)
        frame(c, 2)
        assert pk(c, "pumps") == n + 1, (pk(c, "pumps"), pump)
        assert pk(c, "score", 3)[1] == sc[1] + 1  # +100 (BCD hundreds)
        assert [o for o in objects(c) if o[1:3] == pump[1:3]][0][3] == 1

        # ---- candy throw kills a zombie
        goto(c, 10, 20)  # zombie at column 16 is in view: it must not pop up there
        frame(c, 12)  # spawn points are checked a few per frame
        assert 3 not in pk(c, "etype", 5), pk(c, "etype", 5)
        goto(c, 35, 20)  # camera x 132: the zombie at column 58 is just off the right edge
        frame(c, 12)
        i = pk(c, "etype", 5).index(3)
        assert pk(c, "exl", 5)[i] + 256 * pk(c, "exh", 5)[i] - (pk(c, "cxl") + 256 * pk(c, "cxh")) >= 312
        sc = pk(c, "score", 3)
        ammo = pk(c, "ammo")
        po(c, "facing", 0)
        c.joyport("fire")
        frame(c, 2)
        c.joyport()
        assert pk(c, "ammo") == ammo - 1 and pk(c, "cact") == 1
        frame(c, 60)  # it walks in from the edge, candy flies to meet it
        assert 3 not in pk(c, "etype", 5), "zombie should be gone"
        assert pk(c, "score", 3)[1] == sc[1] + 2, (pk(c, "score", 3), sc)  # +200

        # ---- an enemy touch kills (no luck): hat drops, life lost, back at the checkpoint
        goto(c, 35, 20)
        lives = pk(c, "lives")
        frame(c, 12)
        i = next(i for i, e in enumerate(pk(c, "etype", 5)) if e)
        po(c, "pxl", pk(c, "exl", 5)[i])
        po(c, "pxh", pk(c, "exh", 5)[i])
        po(c, "py", pk(c, "ey", 5)[i])
        po(c, "inv", 0)
        frame(c, 2)
        assert pk(c, "pstate") == 1 and pk(c, "hatact") == 1
        c.screenshot(OUT / "midnight_death.png")
        frame(c, 110)
        assert pk(c, "pstate") == 0 and pk(c, "lives") == lives - 1

        # ---- the clock: time out costs a life and restarts the clock
        h, m = pk(c, "endh"), pk(c, "endm")  # one game minute before the end (BCD minutes)
        h, m = (h - 1, 0x59) if m == 0 else (h, m - (7 if m & 15 == 0 else 1))
        po(c, "hour", h)
        po(c, "minute", m)
        po(c, "tfr", pk(c, "fpm") - 1)
        po(c, "inv", 50)
        frame(c, 2)
        assert pk(c, "pstate") == 2, pk(c, "pstate")
        assert "TOO SLOW" in bottom(c)
        lives = pk(c, "lives")
        frame(c, 110)
        assert pk(c, "lives") == lives - 1 and (pk(c, "hour"), pk(c, "minute")) == (9, 0)

        # ---- last pumpkin opens the gate, the gate ends the level
        po(c, "lives", 3)
        pump = next(o for o in objects(c) if o[0] == 1 and o[3] == 0)
        po(c, "pumps", 19)
        goto(c, pump[1], pump[2] + 1)
        frame(c, 2)
        assert pk(c, "exitopen") == 1 and "THE WAY IS OPEN" in bottom(c), bottom(c)
        c.screenshot(OUT / "midnight_open.png")
        gate = next(o for o in objects(c) if o[0] == 4)
        po(c, "chkc", gate[1])
        po(c, "chkr", gate[2] + 2)
        po(c, "lives", 4)
        po(c, "pstate", 1)
        po(c, "dtimer", 1)
        assert c.run_until(S["leveldone"], timeout=5)
        assert c.run_until(S["firenew"], timeout=10)
        assert "10 PM. THE CROOKED WOODS." in c.screen_text()
        assert pk(c, "level") == 1
        fire(c)
        assert c.run_until(S["gameframe"], timeout=10)
        frame(c, 5)
        assert c.screen_text().splitlines()[-1].startswith("LEVEL 2 CROOKED WOODS")
        c.screenshot(OUT / "midnight_l2.png")

        # ---- swamp water kills
        goto(c, 19, 19)
        frame(c, 30)
        assert pk(c, "pstate") == 1

        # ---- game over
        frame(c, 110)
        po(c, "lives", 1)
        po(c, "pstate", 1)
        po(c, "dtimer", 1)
        assert c.run_until(S["gameover"], timeout=5)
        assert c.run_until(S["firenew"], timeout=10)
        t = c.screen_text()
        assert "THE NIGHT NEVER ENDS..." in t and "TRY AGAIN?" in t, t
        c.run_frames(20)
        assert tune() == 1, "game over: back to the intro tune"
        c.screenshot(OUT / "midnight_gameover.png")

        # ---- level 3 with Dr. Nova: the key is needed too; 6-row jump
        fire(c)
        start_level(c, 2, hero=1)
        assert pk(c, "hero") == 1 and pk(c, "needkey"), (pk(c, "hero"), pk(c, "needkey"))
        c.screenshot(OUT / "midnight_l3.png")
        po(c, "lucky", 0, 0)
        frame(c, 20)
        py0 = pk(c, "py")
        c.joyport("up")
        frame(c, 2)
        c.joyport()
        top = py0
        for _ in range(30):
            frame(c)
            top = min(top, pk(c, "py"))
        assert py0 - top >= 49, ("Nova jumps 6 rows", py0, top)
        pump = next(o for o in objects(c) if o[0] == 1 and o[3] == 0)
        po(c, "pumps", 19)
        goto(c, pump[1], pump[2] + 1)
        frame(c, 2)
        assert pk(c, "pumps") == 20 and pk(c, "exitopen") == 0, "door stays shut without the key"
        key = next(o for o in objects(c) if o[0] == 3)
        goto(c, key[1], key[2] + 1)
        frame(c, 2)
        assert pk(c, "haskey") == 1 and pk(c, "exitopen") == 1
        assert "GOLDEN KEY! THE TOWER DOOR OPENS." in bottom(c), bottom(c)
        c.screenshot(OUT / "midnight_key.png")

        # ---- level 4: land on a gear and ride it
        c.reload(prg)
        skip_intro(c)
        start_level(c, 3)
        c.screenshot(OUT / "midnight_l4.png")
        po(c, "lucky", 0, 0)
        goto(c, 28, 17)  # end of the first ledge; the gear swings past
        landed = False
        for _ in range(120):
            po(c, "inv", 100)
            c.joyport("right", "up")
            frame(c)
            c.joyport()
            frame(c)
            if pk(c, "onplat"):
                landed = True
                break
            if pk(c, "pstate"):
                frame(c, 110)
                goto(c, 28, 17)
        assert landed, "never landed on the gear"
        x0 = pk(c, "pxl")
        frame(c, 10)
        assert pk(c, "onplat") and pk(c, "pxl") != x0, "rides along"
        c.screenshot(OUT / "midnight_gear.png")

        # ---- level 5: carry pumpkins to the lantern, the last one wins
        c.reload(prg)
        skip_intro(c)
        start_level(c, 4)
        assert pk(c, "npump") == 6
        assert pk(c, "mcur") == 3, "the Count's chase in the Moon Chamber"
        c.screenshot(OUT / "midnight_l5.png")
        po(c, "lucky", 255, 255)
        pump = next(o for o in objects(c) if o[0] == 1)
        goto(c, pump[1], pump[2] + 1)
        frame(c, 2)
        assert pk(c, "carry") == 1
        slots = [o for o in objects(c) if o[0] == 6]
        goto(c, slots[-1][1], 20)
        frame(c, 2)
        assert pk(c, "placed") == 1 and pk(c, "carry") == 0
        po(c, "placed", 5)
        po(c, "pumps", 5)
        po(c, "carry", 1)
        po(c, "chkc", slots[-2][1])
        po(c, "chkr", 20)
        po(c, "lives", 4)
        po(c, "pstate", 1)
        po(c, "dtimer", 1)
        assert c.run_until(S["ending"], timeout=5)
        assert c.run_until(S["firenew"], timeout=20)
        t = c.screen_text()
        assert "THE CLOCK STRIKES TWELVE." in t and "WELL DONE!" in t, t
        assert pk(c, "mcur") == 0, "ending: the cheerful theme"
        c.screenshot(OUT / "midnight_ending.png")

        # ---- port-1 fire throws candy but must not toggle the music (it shares row 4 with F1)
        for _ in range(3):
            c.joyport("fire", port=1)
            c.run_frames(3)
            c.joyport(port=1)
            c.run_frames(3)
        assert pk(c, "mon") == 1

        # ---- music plays and stops when switched off (F1 flips mon; the key matrix can't be driven)
        m0 = pk(c, "mstep")
        c.run_frames(30)
        assert pk(c, "mstep") != m0
        po(c, "mon", 0)
        m0 = pk(c, "mstep")
        c.run_frames(30)
        assert pk(c, "mstep") == m0
        print("all checks passed")


if __name__ == "__main__":
    main()
