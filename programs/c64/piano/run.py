import struct
import sys
from pathlib import Path

from retro import C64, assemble
from retro.vice import CMD_KEYBOARD_FEED

HL, HL2 = 0x033F, 0x0340


def cell(col, row):
    return row * 40 + col


def arp_notes(c, seconds=0.6):
    """Set of notes the arpeggio lit over a while (sampled every frame)."""
    seen = set()
    for _ in range(int(seconds / 0.02)):
        c.wait(0.02)
        seen.add(c.peek(HL2)[0])
    seen.discard(0xFF)
    return seen


def text(c, col, row, n):
    return bytes(c.peek(0x0400 + cell(col, row), n))


with C64() as c:
    c.start(assemble(Path(__file__).with_name("piano.asm")))
    c.wait(0.5)
    if sys.argv[1:] == ["play"]:  # interactive: play on the real keyboard until the window is closed
        c.resume()
        c.proc.wait()
        sys.exit()
    cr = c.color_ram()
    assert cr[cell(1, 16)] == 1 and cr[cell(3, 10)] == 11, "idle colours wrong"
    assert text(c, 7, 19, 2) == b"\x43\x20", "key name not C"
    assert text(c, 2, 21, 3) == b"\x43\x20\x20" and text(c, 7, 21, 2) == b"\x44\x0d", "chord names (C, Dm)"
    assert text(c, 32, 21, 2) == b"\x45\x37", "chord name E7"

    # melody
    for key, hz in (("a", 261.63), ("k", 523.25), ("w", 277.18)):
        c.type(key)
        c.wait(0.02)
        lo, hi = c.peek(0x033C, 2)
        got = (hi << 8 | lo) * 985248 / 16777216
        assert abs(got - hz) < 0.5, f"{key}: {got:.1f} Hz, want {hz}"
        assert c.peek(0x033E)[0] > 0, "gate not set"
        cr = c.color_ram()
        if key == "a":  # C lit; the C# black key stays dark on top of it
            assert cr[cell(1, 16)] == 2 and cr[cell(1, 6)] == 2 and cr[cell(2, 6)] == 11, "C not lit"
            assert cr[cell(5, 16)] == 1, "D lit too"
        if key == "w":  # C# lit, C white again
            assert cr[cell(3, 10)] == 2 and cr[cell(1, 16)] == 1, "C# not lit"
    c.wait(2)
    assert c.peek(0x033E)[0] == 0, "gate not released"
    assert c.color_ram()[cell(3, 10)] == 11, "highlight not cleared"

    # chords: C = C E G, Dm = D F A, E7 = E G# B D
    c.type("z")
    assert arp_notes(c) == {0, 4, 7}, "C chord"
    assert c.color_ram()[cell(9, 16)] in (1, 5), "arp colour"
    c.screenshot("build/c64/piano.png")
    c.type("x")
    assert arp_notes(c) == {2, 5, 9}, "Dm chord"
    c.type("m")
    assert arp_notes(c) == {4, 8, 11, 14}, "E7 chord"
    c.type(" ", raw=True)
    c.wait(0.1)
    assert c.peek(HL2)[0] == 0xFF, "space did not stop arp"

    # switching chords mid-bar keeps tempo phase and step position. Control: feed an ignored
    # key (Q) at the same point of the bar; the first step change must come at the same time,
    # and the pattern must go on with step 3 of Dm (F) instead of restarting on D.
    def switch(c, key):
        c.type(" ", raw=True)
        c.type("z")
        last = c.peek(HL2)[0]
        while True:  # sync to the start of the G step (index 2 of the C pattern)
            c.wait(0.02)
            v = c.peek(HL2)[0]
            if v == 7 and last != 7:
                break
            last = v
        c._command(CMD_KEYBOARD_FEED, struct.pack("<B", 1) + key)  # no run: stay mid-step
        for f in range(1, 14):
            c.wait(0.02)
            v = c.peek(HL2)[0]
            if v != 7:
                return f, v
        return None, None

    fq, vq = switch(c, b"Q")
    fx, vx = switch(c, b"X")
    assert vq == 4, f"control should continue C E G E, got {vq}"
    assert vx == 5, f"chord switch should continue the pattern with F (5), got {vx}"
    assert abs(fx - fq) <= 1, f"chord switch changed the step timing ({fx} vs control {fq} samples)"
    c.type(" ", raw=True)

    # tempo: default 125 bpm (6 frames/step); left = slower, right = faster, clamped
    def steps(c, seconds=1.2):
        c.type("z")
        n, last = 0, None
        for _ in range(int(seconds / 0.02)):
            c.wait(0.02)
            v = c.peek(HL2)[0]
            n += v != last
            last = v
        return n

    assert text(c, 18, 19, 3) == bytes([0x31, 0x32, 0x35]), "default 125 bpm"
    fast = steps(c)
    c.type("\x9d" * 3, raw=True)
    assert text(c, 18, 19, 3) == bytes([0x20, 0x36, 0x32]), "62 bpm"
    slow = steps(c)
    assert slow < fast * 0.7, f"tempo did not slow the arp ({slow} vs {fast} steps)"
    c.type("\x9d" * 10, raw=True)
    assert text(c, 18, 19, 3) == bytes([0x20, 0x33, 0x38]), "slow clamp 38"
    c.type("\x1d" * 20, raw=True)
    assert text(c, 18, 19, 3) == bytes([0x32, 0x35, 0x30]), "fast clamp 250"
    c.type(" ", raw=True)
    c.type("\x9d" * 3, raw=True)  # back to 125

    # key change: up 1 = Db (flat name), Z = Db major; up 6 more = G
    c.type("\x91", raw=True)
    assert text(c, 7, 19, 2) == b"\x44\x02", "key name Db"
    assert text(c, 2, 21, 2) == b"\x44\x02", "chord name Db"
    c.type("z")
    assert arp_notes(c) == {1, 5, 8}, "Db chord"
    c.type("\x91" * 6, raw=True)
    assert text(c, 7, 19, 1) == b"\x47", "key name G"
    c.type("z")
    assert arp_notes(c) == {7, 11, 14}, "G chord"
    c.type("\x11" * 7, raw=True)
    assert text(c, 7, 19, 2) == b"\x43\x20", "key back to C"
    c.screenshot("build/c64/piano_keyG.png")
    print("piano ok")
