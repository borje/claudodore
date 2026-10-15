from pathlib import Path

from retro import C64, compile_oscar

with C64() as c:
    c.start(compile_oscar(Path(__file__).with_name("hello.c")))
    assert c.wait_for_text("HELLO FROM OSCAR64!"), "banner missing"
    print(c.screen_text())
