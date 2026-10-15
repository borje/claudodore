import struct
from pathlib import Path

from retro import BUILD, C64, basic

prg = basic(Path(__file__).with_name("squares.bas"))

for how in ("inject", "autostart"):
    with C64() as c:
        c.start()
        if how == "inject":
            c.load_prg(prg)  # poke into RAM + type RUN
        else:  # monitor autostart cmd: VirtualFS, no drive ROM needed; run=1, file index 0
            name = str(prg).encode()
            c._command(0xDD, struct.pack("<BHB", 1, 0, len(name)) + name)
        t = c.wait_for_text("I*I= 25", timeout=20)
        assert t, f"{how} failed:\n{c.screen_text()}"
        print(how, "ok")
        c.screenshot(BUILD / "c64" / f"basic_{how}.png")
