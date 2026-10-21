import sys
from pathlib import Path

from retro import BUILD, VIC20, assemble

PX, PY, CELLS, SCORE, LINES, BOARD, NXT = 0x1B00, 0x1B01, 0x1B04, 0x1B1D, 0x1B1F, 0x1A00, 0x1B25

with VIC20(mem=0, warp=sys.argv[1:] != ["play"]) as c:  # a human plays in real time
    c.start(assemble(Path(__file__).with_name("tetris.asm")))
    if sys.argv[1:] == ["play"]:  # interactive: play with VICE's joystick keys until the window is closed
        c.resume()
        c.proc.wait()
        sys.exit()
    c.wait(1)
    t = c.screen_text()
    assert "PRESS FIRE" in t and "SCORE" not in t, t  # title screen
    assert c.peek(0x1E00 + 66, 110).count(60) == 51, "title blocks"
    c.screenshot(BUILD / "vic20" / "tetris0.png")
    c.joyport("fire"); c.wait(0.3); c.joyport()
    c.wait(1)
    t = c.screen_text()
    assert "PRESS FIRE" not in t and "SCORE" in t and "LINES" in t and "NEXT" in t and "LEVEL" in t, t
    assert c.peek(0x9005)[0] & 15 == 15 and c.peek(0x1C00 + 60 * 8, 8) == bytes([0xFF] * 8), "custom charset"
    ghosts = lambda: c.peek(0x1E00, 506).count(61)
    assert ghosts() == 0, "ghost should be off by default"
    c.type("g"); c.wait(0.3)
    assert ghosts() == 4, "G should show the ghost"
    c.type("g"); c.wait(0.3)
    assert ghosts() == 0, "G again should hide it"
    # preview: 4 solid cells in the 4x4 box at screen row 3, col 17
    assert sum(c.peek(0x1E00 + 83 + 22 * r, 4).count(60) for r in range(4)) == 4
    c.screenshot(BUILD / "vic20" / "tetris1.png")

    # move left/right
    x0 = c.peek(PX)[0]
    c.joyport("left"); c.wait(0.3); c.joyport()
    x1 = c.peek(PX)[0]
    assert x1 < x0, (x0, x1)
    c.joyport("right"); c.wait(0.3); c.joyport()
    assert c.peek(PX)[0] > x1

    # rotate (fire edge) changes the cells (unless it is the O piece)
    c.poke(0x1B02, bytes([2]))  # force T piece
    c.poke(CELLS, bytes([0, 1, 1, 1, 2, 1, 1, 0]))
    c.poke(PX, bytes([3])); c.poke(PY, bytes([5]))
    before = c.peek(CELLS, 8)
    c.joyport("fire"); c.wait(0.2); c.joyport(); c.wait(0.1)
    assert c.peek(CELLS, 8) != before

    # gravity
    y0 = c.peek(PY)[0]
    c.wait(1.2)
    assert c.peek(PY)[0] > y0 or c.peek(PY)[0] == 0  # fell, or locked and respawned

    # line clear: bottom row full except x=9; drop a vertical bar into the gap
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 190, bytes([1] * 9))
    c.poke(CELLS, bytes([0, 0, 0, 1, 0, 2, 0, 3]))
    c.poke(PX, bytes([9])); c.poke(PY, bytes([16]))
    n = c.peek(NXT)[0]
    assert c.peek(0x900E)[0] & 15 == 10, "volume not set"
    for _ in range(60):  # line-clear sweep: poll until lines==1, voice must be on right then
        c.wait(0.05)
        if c.peek(LINES)[0] == 1:
            break
    assert c.peek(0x900C)[0] & 0x80, "no line-clear sound"
    c.wait(2)
    assert c.peek(0x900C)[0] == 0, "sound stuck on"
    assert c.peek(0x1B02)[0] == n, "next piece not spawned"  # pid == previous nxt
    assert c.peek(LINES)[0] == 1, c.peek(LINES)[0]
    assert c.peek(SCORE, 2) == bytes([0x10, 0]), c.peek(SCORE, 2)
    row = c.peek(BOARD + 190, 10)  # bar's 3 leftover cells shifted down into x=9
    assert row[:9] == bytes(9) and row[9] != 0, row
    c.screenshot(BUILD / "vic20" / "tetris2.png")

    # game over, then fire restarts
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 4, bytes([1] * 4)); c.poke(BOARD + 14, bytes([1] * 4))
    c.poke(CELLS, bytes([1, 0, 2, 0, 1, 1, 2, 1]))  # O at the top, locks at once
    c.poke(PX, bytes([3])); c.poke(PY, bytes([0]))
    c.wait(2)
    t = c.screen_text()
    assert "GAME OVER" in t, t
    c.screenshot(BUILD / "vic20" / "tetris3.png")
    c.joyport("fire"); c.wait(0.5); c.joyport()
    assert "GAME OVER" not in c.screen_text()
    assert c.peek(SCORE, 2) == bytes(2)
    print("tetris ok")
