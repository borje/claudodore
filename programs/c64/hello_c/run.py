from pathlib import Path

from retro import C64, compile_c

with C64() as c:
    c.start(compile_c(Path(__file__).with_name("hello.c")))
    assert c.wait_for_text("HELLO FROM C!"), "banner missing"
    print(c.screen_text())
