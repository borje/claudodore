from c64 import C64, assemble

with C64() as c:
    c.start(assemble("sprite.asm"))
    c.wait(1)
    p1 = tuple(c.peek(0xD000, 2))
    c.screenshot("sprite1.png")
    c.wait(1)
    p2 = tuple(c.peek(0xD000, 2))
    c.screenshot("sprite2.png")
    print("sprite (x, y):", p1, "->", p2)
    assert p1[0] != p2[0] and p1[1] != p2[1], "sprite did not move in both axes"
