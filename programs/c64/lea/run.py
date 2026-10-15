import sys
from pathlib import Path

from retro import BUILD, C64, assemble

with C64() as c:
    c.start(assemble(Path(__file__).with_name("lea.asm")))
    if "play" in sys.argv:  # just play, no checks (they pause VICE and glitch audio); Ctrl-C quits
        c.run(1e9)
    c.run(10)  # listen first: every peek/screenshot pauses VICE and glitches the audio
    xs, ticks = [], []
    for i in range(6):
        c.wait(0.6)
        xs.append(c.peek(0xC000, 2))
        ticks.append(c.peek(0xC004)[0])
        c.screenshot(BUILD / "c64" / f"lea{i}.png")
    print("bx:", [b[0] | b[1] << 8 for b in xs], "tick:", ticks)
    assert len(set(ticks)) > 3, "music not ticking"
    assert len(set(map(tuple, xs))) > 3, "no scroll"
    c.record_gif(BUILD / "c64" / "lea.gif", seconds=4)
