"""hello on a real C64 Ultimate (host from ~/.config/c64u/config.toml)."""
import sys
from pathlib import Path

from retro import C64U, assemble

prg = assemble(Path(__file__).with_name("hello.asm"))

with C64U() as c:
    c.start(prg)
    t = c.wait_for_text("PRESS A KEY", timeout=30)
    print(t if t else c.screen_text())
    if t is None:
        sys.exit(1)
    assert "HELLO FROM ASM!" in t
    c.type("q")
    c.wait(1)
    print("--- after q ---")
    print(c.screen_text())
    c.reload(prg)  # reset + upload again
    assert c.wait_for_text("PRESS A KEY", timeout=30), "reload failed"
    print("reload ok")
