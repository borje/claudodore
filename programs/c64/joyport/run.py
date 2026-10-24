from pathlib import Path

from retro import BUILD, C64, built, compile_oscar

BALL = 81


def cursor(c):
    scr = c.peek(0x0400, 1000)
    at = [i for i, b in enumerate(scr) if b & 0x80]
    assert len(at) == 1, f"cursor cells: {at}"
    return divmod(at[0], 40)                     # (row, col)


def hold(c, *buttons, s=0.3):
    c.joyport(*buttons)
    c.wait(s)
    c.joyport()
    c.wait(0.1)


prg = built(compile_oscar(Path(__file__).with_name("joyport.c"), out=BUILD / "c64" / "joyport.prg"))
with C64() as c:
    c.start(prg)
    c.wait(0.5)
    assert cursor(c) == (12, 20), cursor(c)
    hold(c, "fire")
    assert c.peek(0x0400 + 12 * 40 + 20)[0] == BALL | 0x80, "no ball under cursor"
    hold(c, "fire")
    assert c.peek(0x0400 + 12 * 40 + 20)[0] == 0x20 | 0x80, "ball not erased"
    hold(c, "fire")
    hold(c, "right")
    r, col = cursor(c)
    assert r == 12 and col > 20, (r, col)
    assert c.peek(0x0400 + 12 * 40 + 20)[0] == BALL, "ball not left behind"
    hold(c, "up", "left", s=10)                  # runs into the top-left corner and stops
    assert cursor(c) == (0, 0), cursor(c)
    hold(c, "down", "fire", s=0.5)               # draws a vertical line
    r, col = cursor(c)
    assert col == 0 and r > 1, (r, col)
    assert all(c.peek(0x0400 + i * 40)[0] & 0x7f == BALL for i in range(r)), "line not drawn"
    c.screenshot(BUILD / "c64" / "joyport.png")
    hold(c, "up", s=10)                          # back on the ball at (0, 0)
    hold(c, "down", "fire", s=0.3)               # fire on a ball: erases along the way
    r2, _ = cursor(c)
    assert r2 > 0 and all(c.peek(0x0400 + i * 40)[0] & 0x7f == 0x20 for i in range(r2)), "line not erased"
    c.type("q")
    assert c.wait_for_text("READY."), "Q did not quit to BASIC"
    print("joyport ok")
