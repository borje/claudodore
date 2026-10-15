# C64 feedback loop

Assemble -> boot headless VICE -> read the screen -> send keys -> screenshot.

Tools (apt on Linux; `brew install acme vice` on macOS, no xvfb needed): `acme`, `cc65`, `vice` (x64sc 3.7.1), `xvfb`.
C64 ROMs live in `~/.local/share/vice/C64/` (fetched from VICE's GitHub source; the
Ubuntu package ships none).

```python
from c64 import C64, assemble

prg = assemble("programs/hello/hello.asm")  # ACME -> build/hello.prg
with C64() as c:
    c.start(prg)                       # boot to READY., inject the PRG into RAM, type RUN
    c.wait_for_text("PRESS A KEY")     # run until text appears (returns screen text or None)
    c.type("q")                        # keys as typed; \n = RETURN
    c.wait(1)
    print(c.screen_text())             # 40x25 text read from screen RAM
    c.screenshot("screen.png")         # real VIC-II output as PNG (shows sprites, colours, graphics)
    c.peek(0xD020, 1); c.poke(0x0400, b"A")   # raw memory access
    c.sprites(); c.color_ram()         # VIC sprite state / colour RAM
    c.joy("fire"); c.joy_hold("left")   # agent input bytes $033C/$033E (program must read them)
    c.record_gif("demo.gif", seconds=3)  # run + capture frames
    c.reload(prg)                      # reset and reload in the same VICE
    # C: from c64 import compile_c; compile_c("game.c")   (cc65)
```

How it behaves (VICE binary monitor, verified on this install):
- VICE stops the machine whenever a monitor command arrives. The C64 only runs
  between `resume()`/`run(s)`/`wait(s)` and the next command, so time passes in
  slices you control.
- PRGs are injected straight into RAM, because autostart needs drive ROMs that
  aren't available. Programs that load further files from disk won't work.
- `screen_text()` shows graphics characters as `#`; use `screenshot()` for anything
  that isn't plain text.

Layout: `c64/` framework, `programs/<name>/` (`.asm` + `run.py`), `build/` output.
Run `uv run programs/hello/run.py` to check the whole chain; `uv run programs/sprite/run.py` for the sprite demo.
