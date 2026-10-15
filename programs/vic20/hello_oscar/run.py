from pathlib import Path

from retro import VIC20, compile_oscar

# target must match VICE's memory config (BASIC stub at $1201 for 8K+)
for mem in (8, 16):
    prg = compile_oscar(Path(__file__).with_name("hello.c"), target=f"vic20+{mem}", out=f"build/vic20/hello_oscar{mem}.prg")
    with VIC20(mem=mem) as c:
        c.start(prg)
        assert c.wait_for_text("HELLO FROM OSCAR64!"), f"mem={mem}K banner missing"
        print(f"mem={mem}K", c.screen_text())
