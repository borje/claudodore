import sys
from pathlib import Path

from retro import BUILD, VIC20, assemble, built

MEMS = (0, 8, 16)  # unexpanded, 8K, 16K
prgs = built(*(assemble(Path(__file__).with_name("hello.asm"), out=BUILD / "vic20" / f"hello{m}.prg", EXP=m) for m in MEMS))
for mem, prg in zip(MEMS, prgs):
    print(f"--- mem={mem}K assembled:", prg)
    with VIC20(mem=mem) as c:
        c.start(prg)  # boots, injects the PRG into RAM, types RUN
        t = c.wait_for_text("PRESS A KEY", timeout=30)
        if t is None:
            print("TIMEOUT waiting for banner; screen:")
            print(c.screen_text())
            print(open("/tmp/vice_%d.log" % c.port).read()[-1500:])
            sys.exit(1)
        print(t)
        assert c.screen_dims() == (22, 23), c.screen_dims()
        c.type("q")
        c.wait(1)
        t = c.screen_text()
        assert "KEY: Q" in t, t
        print("screenshot:", c.screenshot(BUILD / "vic20" / f"hello{mem}.png"))

        c.reload(prg)  # same VICE process, fresh machine
        assert c.wait_for_text("PRESS A KEY", timeout=30), "reload failed"
        print("reload ok")
