from pathlib import Path

from c64 import C64, assemble


def seen(c, addr):
    c.wait(0.3)
    return c.peek(addr)[0] & 0x1F


with C64() as c:
    c.start(assemble(Path(__file__).with_name("joyport.asm")))
    c.joyport()                                  # nothing pressed, port 2 ($DC00)
    assert seen(c, 0x0400) == 0x1F
    c.joyport("fire")
    assert seen(c, 0x0400) == 0x0F
    c.joyport("up", "left")
    assert seen(c, 0x0400) == 0x1A
    c.joyport("right", port=1)                   # port 1 ($DC01)
    assert seen(c, 0x0401) == 0x17
    print("joyport ok")
