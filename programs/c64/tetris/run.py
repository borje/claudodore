import sys
from pathlib import Path

from retro import BUILD, C64, assemble

PX, PY, PID, CELLS, SCORE, LINES, BOARD, NXT = 0xC100, 0xC101, 0xC102, 0xC104, 0xC11D, 0xC120, 0xC000, 0xC127
SND, MON, MI = 0xC129, 0xC131, 0xC132
SCR = 0x400

with C64() as c:
    c.start(assemble(Path(__file__).with_name("tetris.asm")))
    if sys.argv[1:] == ["play"]:  # interactive: play with VICE's joystick keys until the window is closed
        c.resume()
        c.proc.wait()
        sys.exit()
    c.wait(1)
    t = c.screen_text()
    assert "PRESS FIRE" in t and "SCORE" not in t, t  # title screen
    assert c.peek(SCR + 120, 200).count(69) == 51, "title blocks"
    assert c.peek(MON)[0] == 1, "title music"
    c.screenshot(BUILD / "c64" / "tetris0.png")
    c.joyport("fire"); c.wait(0.3); c.joyport()
    c.wait(1)
    t = c.screen_text()
    assert "PRESS FIRE" not in t and "SCORE" in t and "LINES" in t and "NEXT" in t and "LEVEL" in t, t
    assert c.peek(0xD018)[0] & 0xFE == 0x1C and c.peek(0x3000 + 64 * 8, 2) == bytes([0x55, 0x7F]), "custom charset"
    assert c.peek(0xD016)[0] & 0x10, "multicolour text off"
    assert c.peek(SCR + 40 + 10)[0] == 68 and c.peek(SCR + 40 + 31)[0] == 68, "walls"
    ghosts = lambda: c.peek(SCR, 1000).count(66)
    assert ghosts() == 0, "ghost should be off by default"
    c.type("g"); c.wait(0.3)
    assert ghosts() == 4, "G should show the ghost"
    c.type("g"); c.wait(0.3)
    assert ghosts() == 0, "G again should hide it"
    # preview: 4 blocks (left halves) in the 4x4-cell box at screen row 6, col 32
    assert sum(c.peek(SCR + 6 * 40 + 32 + 40 * r, 8).count(64) for r in range(4)) == 4
    c.screenshot(BUILD / "c64" / "tetris1.png")

    # music: melody advances; M stops, M restarts
    mi = c.peek(MI)[0]
    c.wait(1)
    assert c.peek(MI)[0] != mi, "melody not advancing"
    c.type("m"); c.wait(0.3)
    assert c.peek(MON)[0] == 0, "M should stop music"
    c.type("m"); c.wait(0.3)
    assert c.peek(MON)[0] == 1, "M again should restart music"

    # move left/right
    x0 = c.peek(PX)[0]
    c.joyport("left"); c.wait(0.3); c.joyport()
    x1 = c.peek(PX)[0]
    assert x1 < x0, (x0, x1)
    c.joyport("right"); c.wait(0.3); c.joyport()
    assert c.peek(PX)[0] > x1

    # rotate (fire edge) changes the cells (unless it is the O piece)
    c.poke(PID, bytes([2]))  # force T piece
    c.poke(CELLS, bytes([0, 1, 1, 1, 2, 1, 1, 0]))
    c.poke(PX, bytes([3])); c.poke(PY, bytes([5]))
    before = c.peek(CELLS, 8)
    c.joyport("fire"); c.wait(0.2); c.joyport(); c.wait(0.1)
    assert c.peek(CELLS, 8) != before

    # gravity
    y0 = c.peek(PY)[0]
    c.wait(1.2)
    assert c.peek(PY)[0] > y0 or c.peek(PY)[0] == 0  # fell, or locked and respawned

    # soft drop: 1 point per row fallen while down is held
    c.joyport("down"); c.wait(0.5); c.joyport()
    assert c.peek(SCORE)[0] > 0, "soft drop gives no points"
    c.poke(SCORE, bytes(3))

    # line clear: bottom row full except x=9; drop a vertical bar into the gap
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 190, bytes([1] * 9))
    c.poke(CELLS, bytes([0, 0, 0, 1, 0, 2, 0, 3]))
    c.poke(PX, bytes([9])); c.poke(PY, bytes([16]))
    n = c.peek(NXT)[0]
    for _ in range(80):  # poll until lines==1; SID regs are write-only, so check the sfx state
        c.wait(0.05)
        if c.peek(LINES)[0] == 1:
            break
    assert c.peek(SND)[0] > 0, "no line-clear sound"
    c.wait(2)
    assert c.peek(SND)[0] == 0, "sound stuck on"
    assert c.peek(0xD016)[0] & 0x1F == 0x18 and c.peek(0xD011)[0] & 0x7F == 0x1B, "shake not reset"
    assert c.peek(PID)[0] == n, "next piece not spawned"  # pid == previous nxt
    assert c.peek(LINES, 2) == bytes([1, 0]), c.peek(LINES, 2)
    assert c.peek(SCORE, 3) == bytes([0x40, 0, 0]), c.peek(SCORE, 3)
    row = c.peek(BOARD + 190, 10)  # bar's 3 leftover cells shifted down into x=9
    assert row[:9] == bytes(9) and row[9] != 0, row
    c.screenshot(BUILD / "c64" / "tetris2.png")

    # game over, then fire restarts
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 4, bytes([1] * 4)); c.poke(BOARD + 14, bytes([1] * 4))
    c.poke(CELLS, bytes([1, 0, 2, 0, 1, 1, 2, 1]))  # O at the top, locks at once
    c.poke(PX, bytes([3])); c.poke(PY, bytes([0]))
    c.wait(2)
    t = c.screen_text()
    assert "GAME OVER" in t, t
    assert c.peek(MON)[0] == 0, "music should stop at game over"
    c.screenshot(BUILD / "c64" / "tetris3.png")
    c.joyport("fire"); c.wait(0.5); c.joyport()
    assert "GAME OVER" not in c.screen_text()
    assert c.peek(SCORE, 3) == bytes(3)
    assert c.peek(MON)[0] == 1, "music should restart"
    print("tetris ok")
