from c64 import C64, assemble

with C64() as c:
    c.start(assemble("sprite.asm"))
    c.wait(1)
    x1 = c.peek(0xD000)[0]
    c.screenshot("sprite1.png")
    c.wait(1)
    x2 = c.peek(0xD000)[0]
    c.screenshot("sprite2.png")
    print("sprite x:", x1, "->", x2)
    assert x1 != x2, "sprite did not move"
