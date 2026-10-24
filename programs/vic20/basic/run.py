import struct
from pathlib import Path

from retro import BUILD, VIC20, basic, built

MEMS = ((0, 0x1001), (8, 0x1201), (16, 0x1201))
prgs = built(*(basic(Path(__file__).with_name("squares.bas"), out=BUILD / "vic20" / f"squares{m}.prg", load=a) for m, a in MEMS))
for (mem, _), prg in zip(MEMS, prgs):
    for how in ("inject", "autostart"):
        with VIC20(mem=mem) as c:
            c.start()
            if how == "inject":
                c.load_prg(prg)  # poke into RAM + type RUN
            else:  # monitor autostart cmd: VirtualFS, no drive ROM needed; run=1, file index 0
                name = str(prg).encode()
                c._command(0xDD, struct.pack("<BHB", 1, 0, len(name)) + name)
            t = c.wait_for_text("I*I= 25", timeout=20)
            assert t, f"mem={mem} {how} failed:\n{c.screen_text()}"
            print(f"mem={mem}K {how} ok")
