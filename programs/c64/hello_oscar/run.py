from pathlib import Path

from retro import BUILD, C64, built, compile_oscar

prg = built(compile_oscar(Path(__file__).with_name("hello.c"), out=BUILD / "c64" / "hello_oscar.prg"))
with C64() as c:
    c.start(prg)
    assert c.wait_for_text("HELLO FROM OSCAR64!"), "banner missing"
    print(c.screen_text())
