from pathlib import Path

from retro import BUILD, C64, assemble, built

prg = built(assemble(Path(__file__).with_name("sprite.asm")))
with C64() as c:
    c.start(prg)
    c.wait(1)
    p1 = tuple(c.peek(0xD000, 2))
    c.screenshot(BUILD / "c64" / "sprite1.png")
    c.wait(1)
    p2 = tuple(c.peek(0xD000, 2))
    c.screenshot(BUILD / "c64" / "sprite2.png")
    sp = c.sprites()
    assert len(sp) == 1 and sp[0]["ptr"] == 0x2000 and sp[0]["color"] == 7, sp
    c.record_gif(BUILD / "c64" / "sprite.gif", seconds=2)
    print("sprite (x, y):", p1, "->", p2)
    assert p1[0] != p2[0] and p1[1] != p2[1], "sprite did not move in both axes"
