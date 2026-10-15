from pathlib import Path

from retro import VIC20, assemble

# (buttons, $9111 mask/value, $9120 mask/value): lines are active low
MASK_A, MASK_B = 0x3C, 0x80
CASES = [
    ((), 0x3C, 0x80),
    (("up",), 0x38, 0x80),
    (("down",), 0x34, 0x80),
    (("left",), 0x2C, 0x80),
    (("fire",), 0x1C, 0x80),
    (("right",), 0x3C, 0x00),
    (("up", "fire"), 0x18, 0x80),
]

with VIC20(mem=0) as c:
    c.start(assemble(Path(__file__).with_name("joyport.asm"), EXP=0))
    for buttons, a, b in CASES:
        c.joyport(*buttons)
        c.wait(0.5)
        hexes = c.screen_text().split()[:2]
        got_a, got_b = (int(h, 16) for h in hexes)
        print(buttons or "none", hexes)
        assert got_a & MASK_A == a, (buttons, hex(got_a))
        assert got_b & MASK_B == b, (buttons, hex(got_b))
    print("joyport ok")
