from pathlib import Path

from c64 import C64, assemble

with C64() as c:
    c.start(assemble(Path(__file__).with_name("joy.asm")))
    c.wait(0.5)
    c.joy("fire", "left")
    c.wait(0.2)
    assert c.peek(0x0400)[0] == 20 and c.peek(0x033C)[0] == 0, "press not seen/cleared"
    c.joy_hold("up", "right")
    c.wait(0.2)
    assert c.peek(0x0401)[0] == 9, "hold not seen"
    c.joy_hold()
    c.wait(0.2)
    assert c.peek(0x0401)[0] == 0, "hold not released"
    print("joy ok")
