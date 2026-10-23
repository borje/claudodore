"""Scripted playthrough: finish all 5 levels with joystick input only (no teleports, no state pokes but two).

    uv run programs/c64/midnight/playthrough.py [pip|nova|both]   (default both)

A Python copy of the player physics (frame exact, incl. the L4 gears/pendulums) plans each hop: a coarse cell
route picks the next surface, then walk/jump input sequences are simulated until one lands there (or touches the
item); that sequence is played on joystick port 2 one game frame at a time and the real state is compared with
the simulation. Fails if a pumpkin/key/slot/exit can't be reached.
The two pokes: invulnerability (enemies are not what this checks) and the minute counter (the clock is frozen;
the frames used are reported against each level's limit instead).
"""
import sys
from collections import deque

from retro import C64

import run  # noqa: F401  (builds, checks reachability, runs nothing in VICE when imported: see guard)
from run import S, pk, po, prg

ROWS = 23
SOLID, PLAT, HAZ = 1, 2, 3
GEAR, BOB = 8, 9
PLATW = {GEAR: 60, BOB: 36}
UP, LEFT, RIGHT = 1, 4, 8
VERBOSE = "-v" in sys.argv


def s8(v):
    return v - 256 if v >= 128 else v


class Level:
    """Map flags straight from the C64's RAM (map at $E000, tile flags at $F300)."""

    def __init__(self, c):
        self.w = pk(c, "lvw")
        raw = c.peek(0xE000, self.w * ROWS)
        ft = c.peek(0xF300, 256)
        self.flag = [[ft[raw[x * ROWS + y]] for y in range(ROWS)] for x in range(self.w)]
        self.wpx = self.w * 8
        self.sin = [s8(b) for b in c.peek(S["sin64"], 64)]
        self.hero = pk(c, "hero")
        self.spd = c.peek(S["spdlo"], 2)[self.hero]
        self.jmp = c.peek(S["jmpv"], 2)[self.hero]

    def f(self, x, y):
        if x < 0 or x >= 0x8000 or y >= ROWS * 8:
            return 0
        col = (x >> 3) & 255
        return 0 if col >= self.w else self.flag[col][y >> 3]


class State:
    FIELDS = ("x", "pxf", "py", "pyf", "vy", "gnd", "plat", "dead")

    def __init__(self, **kw):
        self.__dict__.update(kw)

    def copy(self):
        s = State(**{k: getattr(self, k) for k in self.FIELDS})
        s.plats = [dict(p) for p in self.plats]
        return s

    def key(self):
        return tuple(getattr(self, k) for k in self.FIELDS[:-1])


def read_state(c):
    z = c.peek(0x12, 0x30)  # zero page $12-$41
    g = lambda name: z[S[name] - 0x12]  # noqa: E731
    st = State(x=g("pxl") | g("pxh") << 8, pxf=g("pxf"), py=g("py"), pyf=g("pyf"), vy=g("vy"), gnd=g("onground"),
               plat=pk(c, "onplat"), dead=g("pstate") != 0)
    n = 5
    et, xl, xh, ey, edx, etim, ex0l, ex0h, ey0, eyf = (c.peek(S[a], n) for a in (
        "etype", "exl", "exh", "ey", "edx", "etim", "ex0l", "ex0h", "ey0", "eyf"))
    st.plats = [dict(i=i, t=et[i], x=xl[i] | xh[i] << 8, y=ey[i], dx=edx[i], tim=etim[i], x0=ex0l[i] | ex0h[i] << 8,
                     y0=ey0[i], f=eyf[i], dxl=0) for i in range(n) if et[i] in (GEAR, BOB)]
    return st


def step(L, s, joy):
    """One game frame of player() + the platform part of enemies()/ride, mirroring midnight.asm."""
    def wall(x):
        return any(L.f(x, (s.py + d) & 255) == SOLID for d in (3, 11, 19))

    def support2(y):
        return any(L.f(s.x + d, y) in (SOLID, PLAT) for d in (7, 16))

    pos = s.x * 256 + s.pxf
    if joy & LEFT:
        n = (pos - 256 - L.spd) & 0xFFFFFF
        nx = n >> 8
        if not nx & 0x8000 and not wall((nx + 6) & 0xFFFF):
            s.x, s.pxf = nx, n & 255
    elif joy & RIGHT:
        n = pos + 256 + L.spd
        nx = n >> 8
        if nx + 24 < L.wpx and not wall(nx + 17):
            s.x, s.pxf = nx, n & 255
    air = True
    if s.gnd:
        if joy & UP:
            s.vy, s.gnd, s.plat = (256 - L.jmp) & 255, 0, 0
        elif s.plat or support2((s.py + 21) & 255):
            air = False
        else:
            s.gnd = 0
    if air:
        vy = (s.vy + 4) & 255
        if vy < 128 and vy >= 64:
            vy = 64
        s.vy = vy
        oldfeet = (s.py + 20) & 255
        t0 = (vy + s.pyf) & 255
        s.pyf = t0 & 15
        new = (s.py + (s8(t0) >> 4)) & 255
        if vy >= 128:
            if new > s.py:
                s.vy, new = 0, 0
            s.py = new
            t2 = (s.py + 2) & 255
            if t2 < ROWS * 8 and (L.f(s.x + 8, t2) == SOLID or L.f(s.x + 15, t2) == SOLID):
                s.py, s.vy, s.pyf = (t2 & 0xF8) + 6, 0, 0
        else:
            s.py = new
            landed = False
            for p in sorted(s.plats, key=lambda p: -p["i"]):  # platland: slots 4..0
                if (p["y"] - 1) & 255 < oldfeet or (s.py + 20) & 255 < p["y"]:
                    continue
                d = s.x - p["x"] + 12
                if 0 <= d < PLATW[p["t"]]:
                    s.py, s.vy, s.pyf, s.gnd, s.plat = (p["y"] - 21) & 255, 0, 0, 1, p["i"] + 1
                    landed = True
                    break
            if not landed:
                t2 = (s.py + 20) & 255
                if t2 < 192 and (t2 ^ oldfeet) & 0xF8 and oldfeet < 192 and any(
                        L.f(s.x + d, t2) in (SOLID, PLAT) and L.f(s.x + d, (t2 - 8) & 255) not in (SOLID, PLAT)
                        for d in (7, 16)):
                    s.py, s.vy, s.pyf, s.gnd = ((t2 & 0xF8) - 21) & 255, 0, 0, 1
    if 188 <= s.py < 224 or L.f(s.x + 12, (s.py + 12) & 255) == HAZ or L.f(s.x + 12, (s.py + 20) & 255) == HAZ:
        s.dead = True
    # enemies(): platforms move, then ride
    for p in sorted(s.plats, key=lambda p: -p["i"]):
        if p["t"] == GEAR:
            p["dxl"] = p["dx"]
            p["x"] += s8(p["dx"])
            p["tim"] = (p["tim"] + 1) & 255
            if p["tim"] >= 80:
                p["tim"], p["dx"] = 0, (-p["dx"]) & 255
        else:
            p["f"] = (p["f"] + 1) & 255
            t0 = L.sin[(p["f"] >> 1) & 63]
            nx = p["x0"] + t0
            p["dxl"] = (nx - p["x"]) & 255
            p["x"] = nx
            p["y"] = (p["y0"] + 16 - (abs(t0) >> 1)) & 255
    if s.plat:
        p = next((p for p in s.plats if p["i"] == s.plat - 1), None)
        if p and not s.dead and s.gnd:
            s.x += s8(p["dxl"])
            s.py = (p["y"] - 21) & 255
            if not 0 <= s.x - p["x"] + 12 < PLATW[p["t"]]:
                s.plat, s.gnd = 0, 0
        else:
            s.plat, s.gnd = 0, 0
    return s


def box(s):
    """Player box in cells (objects routine)."""
    return ((s.x + 6) >> 3, (s.x + 17) >> 3, ((s.py + 2) & 255) >> 3, min(255, s.py + 20) >> 3)


def touches(s, o):
    t, col, row, w, h = o
    c0, c1, r0, r1 = box(s)
    return col <= c1 and col + w - 1 >= c0 and row <= r1 and row + h - 1 >= r0


def cell(s):
    return ((s.x + 12) >> 3, ((s.py + 21) & 255) >> 3)


# ---------------------------------------------------------------- coarse route (cells)
def surfaces(L, plats):
    def surf(x, r):
        if not (0 <= x < L.w and 0 < r < ROWS):
            return False
        ok = L.flag[x][r] in (SOLID, PLAT) or any(a <= x <= b and r == py for a, b, py in plats)
        return ok and L.flag[x][r - 1] not in (SOLID, PLAT) and all(L.flag[x][rr] != SOLID for rr in range(max(0, r - 3), r))
    return surf


def route(L, surf, start, goals, banned):
    """BFS over standing cells; edges like run.unreachable(). Returns the cell path."""
    def land(x, r):
        for rr in range(r, ROWS):
            if L.flag[x][rr] == HAZ:
                return None
            if surf(x, rr):
                return rr
        return None

    prev, todo = {start: None}, deque([start])
    while todo:
        cur = todo.popleft()
        if cur in goals:
            path = [cur]
            while prev[path[-1]]:
                path.append(prev[path[-1]])
            return path[::-1]
        x, r = cur
        nxt = []
        for dx in (-1, 1):
            if surf(x + dx, r):
                nxt.append((x + dx, r))
            elif 0 <= x + dx < L.w and land(x + dx, r):
                nxt.append((x + dx, land(x + dx, r)))
        for dx in range(-9, 10):
            for r2 in range(max(1, r - 6), ROWS):
                if abs(dx) <= (6 if r2 <= r - 3 else 8 if r2 <= r else 9) and surf(x + dx, r2):
                    nxt.append((x + dx, r2))
        for n in nxt:
            if n not in prev and (cur, n) not in banned:
                prev[n] = cur
                todo.append(n)
    return None


# ---------------------------------------------------------------- local search
def candidates(toward, waits):
    away = LEFT if toward == RIGHT else RIGHT
    for w in waits:
        for k in [0, 2, 4, 6, 8, 12, 16, 20, 24, 30, 36, 44, 52, 60]:
            for wd in (toward, away):
                if k == 0 and wd == away:
                    continue
                for up in (UP, 0):
                    for d1 in (toward, 0, away):
                        for n1 in (99, 40, 32, 24, 16, 12, 8, 4, 0):
                            for d2 in (0, away if d1 == toward else toward):
                                yield w, wd, k, up, d1, n1, d2


def simulate(L, s0, cand, goal):
    """Inputs for cand, or None. goal(state) -> True when reached (checked every frame)."""
    w, wd, k, up, d1, n1, d2 = cand
    s = s0.copy()
    inputs = []

    def go(j):
        inputs.append(j)
        step(L, s, j)
        return not s.dead

    for _ in range(w):
        if not go(0):
            return None
        if goal(s):
            return inputs
    for _ in range(k):
        if not go(wd):
            return None
        if goal(s):
            return inputs
    if s.gnd and not up:
        return None  # a plain walk that didn't reach the goal
    if up and not s.gnd:
        return None
    first = True
    for t in range(150):
        j = (d1 if t < n1 else d2) | (UP if first and up else 0)
        first = False
        if not go(j):
            return None
        if goal(s):
            return inputs
        if s.gnd:
            return None
    return None


def search(L, s0, goal, toward, waits=(0,), reset=None):
    for cand in candidates(toward, waits):
        if reset:
            reset[0] = False
        r = simulate(L, s0, cand, goal)
        if r is not None:
            return r
    return None


# ---------------------------------------------------------------- driving VICE
class Bot:
    def __init__(self, c):
        self.c = c
        self.frames = 0
        self.mismatch = 0
        self.joy = None

    def frame(self, joy):
        if joy != self.joy:
            names = [n for b, n in ((UP, "up"), (LEFT, "left"), (RIGHT, "right")) if joy & b]
            self.c.joyport(*names)
            self.joy = joy
        if not self.c.run_until(S["gameframe"], timeout=10):
            return False
        self.frames += 1
        if self.frames % 64 == 0:  # the two pokes: keep invulnerable, freeze the clock
            po(self.c, "inv", 200)
            po(self.c, "tfr", 0)
        return True

    def play(self, L, s0, inputs):
        sim = s0.copy()
        for j in inputs:
            step(L, sim, j)
            if not self.frame(j):
                return False
            if pk(self.c, "state") or pk(self.c, "level") != self.level:
                return True  # level over (its card may already have timed out)
        real = read_state(self.c)
        if real.key() != sim.key():
            self.mismatch += 1
            raise AssertionError(f"sim/real differ after {len(inputs)} frames: sim {sim.key()} real {real.key()}")
        if any(j & (LEFT | RIGHT) for j in inputs) and (real.x, real.py) == (s0.x, s0.py) and not real.plat:
            raise AssertionError(f"inputs {inputs} did not move the player from x={s0.x} py={s0.py}")
        return True


def goals_now(c, L):
    """Object list and the ones to go for next: pumpkins (+ key), lantern slots when carrying, else the exit."""
    n = pk(c, "nobj")
    objs = [(t, col, row, pk(c, "ow", 6)[t - 1], pk(c, "oh", 6)[t - 1]) for t, col, row in
            zip(pk(c, "otype", 48)[:n], pk(c, "ocol", 48)[:n], pk(c, "orow", 48)[:n])]
    st = pk(c, "ostat", 48)[:n]
    level = pk(c, "level")
    if level == 4:
        want = (6,) if pk(c, "carry") else (1,)
    else:
        want = (1, 3)
    todo = [o for o, s in zip(objs, st) if not s and o[0] in want]
    if not todo:
        todo = [o for o in objs if o[0] == 4]
    return todo


def goal_cells(surf, L, o):
    t, col, row, w, h = o
    out = set()
    for x in range(col - 1, col + w + 1):
        for r in range(1, ROWS):
            if surf(x, r) and row <= r - 1 and row + h - 1 >= r - 3 - 6:
                out.add((x, r))
    return out


def play_level(c, bot):
    L = Level(c)
    level = pk(c, "level")
    limit = 0
    h0, m0, h1, m1, fpm = (pk(c, n) for n in ("hour", "minute", "endh", "endm", "fpm"))
    mins = (h1 * 60 + int(f"{m1:x}")) - (h0 * 60 + int(f"{m0:x}"))
    limit = mins * fpm
    f0 = bot.frames
    banned = set()
    visits = {}
    waited = 0
    last_item, last_pumps = bot.frames, -1
    bot.level = level
    while True:
        if pk(c, "state") or pk(c, "level") != level:
            break
        got = pk(c, "pumps") + pk(c, "haskey") + pk(c, "carry")
        if got != last_pumps:
            last_pumps, last_item = got, bot.frames
        if bot.frames - last_item > 3000:
            raise AssertionError(f"level {level + 1}: no item for 3000 frames, at {cell(read_state(c))}")
        s0 = read_state(c)
        if s0.dead:
            raise AssertionError(f"level {level + 1}: died at {cell(s0)}")
        if not s0.gnd:  # a move can end mid-air (item touched): let the player come down first
            if not bot.frame(0):
                break
            continue
        spot = (s0.x, s0.py, s0.pxf)
        visits[spot] = visits.get(spot, 0) + 1
        if visits[spot] > 3:
            raise AssertionError(f"level {level + 1}: stuck at {cell(s0)} px={s0.x} py={s0.py}")
        todo = goals_now(c, L)
        plats = [(p["x"] // 8 - 4, p["x"] // 8 + 6, p["y"] // 8) for p in s0.plats]
        surf = surfaces(L, plats)
        cur = cell(s0)
        # an item touchable from here?
        here = {cur}
        if s0.plat:  # riding: anything reachable from anywhere along the platform's swing
            here = {(x, r) for a, b, r in plats for x in range(a, b + 1) if r == cur[1]}
        near = [o for o in todo if here & goal_cells(surf, L, o)]
        if near:
            o = near[0]
            tow = RIGHT if o[1] * 8 + 4 > s0.x + 12 else LEFT
            hit = [False]

            def got(s, o=o, hit=hit):  # touched the item, then landed somewhere safe
                hit[0] = hit[0] or touches(s, o)
                return hit[0] and s.gnd
            inp = search(L, s0, got, tow, range(0, 160, 4) if s0.plat else (0,), reset=hit)
            if inp:
                bot.play(L, s0, inp)
                continue
        goals = set().union(*(goal_cells(surf, L, o) for o in todo))
        path = route(L, surf, cur, goals, banned)
        if (not path or len(path) < 2) and waited < 8:  # a platform may not have spawned yet
            waited += 1
            for _ in range(25):
                bot.frame(0)
            continue
        if not path or len(path) < 2:
            raise AssertionError(f"level {level + 1}: no route from {cur} to {[o[1:3] for o in todo]};"
                                 f" slots {list(pk(c, 'etype', 5))}")
        waited = 0
        # next hop: run of walking cells, else the first jump/fall
        i = 1
        while i + 1 < len(path) and path[i][1] == cur[1] and abs(path[i][0] - path[i - 1][0]) == 1 \
                and path[i + 1][1] == cur[1] and abs(path[i + 1][0] - path[i][0]) == 1:
            i += 1
        def onplats(cl):
            return any(a <= cl[0] <= b and cl[1] == py for a, b, py in plats)
        if s0.plat:  # riding: the platform's own cells are not a destination
            while i + 1 < len(path) and onplats(path[i]):
                i += 1
        tx, tr = path[i]
        onplat_target = onplats((tx, tr))
        tow = RIGHT if tx * 8 + 4 > s0.x + 12 else LEFT

        tol = 6 if onplat_target else 0 if tr == cur[1] else 1  # walking: exact cell

        def landed(s, tx=tx, tr=tr, tol=tol, cur=cur):
            x, r = cell(s)
            if onplat_target:
                return bool(s.plat) and not s0.plat
            return s.gnd and r == tr and abs(x - tx) <= tol and (x, r) != cur
        waits = range(0, 160, 4) if (onplat_target or s0.plat) else (0,)
        inp = search(L, s0, landed, tow, waits)
        if VERBOSE:
            print(f"   at {cur} px={s0.x} py={s0.py} gnd={s0.gnd} -> {(tx, tr)}: {'ok' if inp else 'no'}")
        if inp is None:
            banned.add((cur, path[i]) if i == 1 else (path[i - 1], path[i]))
            continue
        bot.play(L, s0, inp)
    used = bot.frames - f0
    clock = f"of the {limit} the clock allows" if limit else "(no clock)"
    print(f"  level {level + 1}: {used} frames ({used / 50:.0f} s) {clock}"
          + ("" if not limit or used <= limit else "  ** slower than the clock **"))
    return used


def run_game(hero):
    with C64() as c:
        c.start(prg)
        run.skip_intro(c)
        run.fire(c)
        assert c.run_until(S["selp"], timeout=10)
        if hero:
            c.joyport("right")
            c.run_frames(3)
            c.joyport()
        c.run_frames(3)
        c.joyport("fire")
        assert c.run_until(S["levelcard"], timeout=10)
        c.joyport()
        bot = Bot(c)
        for lv in range(5):
            if lv == 0 or pk(c, "level") != lv or pk(c, "state"):  # not already playing it: through its card
                assert c.run_until(S["firenew"], timeout=20), "level card"
                run.fire(c)
                assert c.run_until(S["gameframe"], timeout=10)
            assert pk(c, "level") == lv
            bot.joy = None
            play_level(c, bot)
            c.joyport()
            bot.joy = 0
        assert c.run_until(S["ending"], timeout=10) or pk(c, "state") == 3
        assert c.run_until(S["firenew"], timeout=30)
        assert "THE CLOCK STRIKES TWELVE." in c.screen_text()
        print(f"  {['pip', 'nova'][hero]}: game finished, {bot.frames} frames, sim/real mismatches: {bot.mismatch}")
        assert bot.mismatch == 0


args = [a for a in sys.argv[1:] if a != "-v"]
arg = args[0] if args else "both"
for h in {"pip": [0], "nova": [1], "both": [0, 1]}[arg]:
    print(["Pip", "Dr. Nova"][h])
    run_game(h)
print("playthrough ok")
