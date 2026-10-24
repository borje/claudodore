from pathlib import Path

from retro import BUILD, C64, built, compile_c

prg = built(compile_c(Path(__file__).with_name("hello.c"), out=BUILD / "c64" / "hello_c.prg"))
with C64() as c:
    c.start(prg)
    assert c.wait_for_text("HELLO FROM C!"), "banner missing"
    print(c.screen_text())
