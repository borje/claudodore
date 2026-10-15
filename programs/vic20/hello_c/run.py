from pathlib import Path

from retro import VIC20, compile_c

# stock vic20.cfg is unexpanded-only (too small for stdio); stock vic20-32k.cfg puts the C stack at $8000,
# so use a local 8K cfg (RAM to $4000); it also runs on 16K
prg = compile_c(Path(__file__).with_name("hello.c"), target="vic20", cfg=Path(__file__).with_name("vic20-8k.cfg"))
for mem in (8, 16):
    with VIC20(mem=mem) as c:
        c.start(prg)
        assert c.wait_for_text("HELLO FROM C!"), f"mem={mem}K banner missing"
        print(f"mem={mem}K", c.screen_text())
