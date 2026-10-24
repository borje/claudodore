from pathlib import Path

from retro import BUILD, VIC20, built, compile_oscar

# target must match VICE's memory config (BASIC stub at $1201 for 8K+)
MEMS = (8, 16)
prgs = built(*(compile_oscar(Path(__file__).with_name("hello.c"), target=f"vic20+{m}", out=BUILD / "vic20" / f"hello_oscar{m}.prg") for m in MEMS))
for mem, prg in zip(MEMS, prgs):
    with VIC20(mem=mem) as c:
        c.start(prg)
        assert c.wait_for_text("HELLO FROM OSCAR64!"), f"mem={mem}K banner missing"
        print(f"mem={mem}K", c.screen_text())
