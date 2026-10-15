# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Feedback loop for C64 development: assemble with ACME -> boot headless VICE (`x64sc`, under `xvfb-run` if available, else a normal window) -> drive it through VICE's binary monitor (TCP) -> read screen RAM / screenshot. All logic lives in `c64.py` (`C64` class + `assemble()`); `hello.asm` is the sample program; `test_loop.py` is the end-to-end check.

Needs system tools: `acme`, `x64sc` (VICE; macOS: `brew install acme vice`, tested on 3.10; Linux 3.7.1 also needs `xvfb-run`, used automatically when on PATH), plus Pillow for `screenshot()` (managed by uv: `pyproject.toml`, `uv sync`). Linux only: C64 ROMs must be in `~/.local/share/vice/C64/` (brew VICE bundles them).

## Commands

- Full chain test: `uv run test_loop.py` (assembles `hello.asm`, boots, types `q`, writes `screen.png`; exits 1 on timeout)
- Assemble only: `acme -f cbm -o hello.prg hello.asm`
- VICE stdout/stderr go to `/tmp/vice_<port>.log`. Port is picked free per instance.
- Sprite demo: `uv run sprite_demo.py` (assembles `sprite.asm`, asserts sprite 0 moves in X and Y, writes `sprite1.png`/`sprite2.png`)
- No linter, no pytest suite; `test_loop.py` is a script.

## Architecture / gotchas

- **Machine is paused between commands.** VICE halts the C64 on every monitor command. Emulated time only advances during `resume()`/`run(s)`/`wait(s)`/`wait_for_text`/`type`. Any peek/screen read freezes it again.
- **PRGs are injected into RAM** (`load_prg` pokes at the load address, then types `RUN`), not autostarted — drive ROMs aren't available, so programs loading from disk won't work. Loads at `$0801` get BASIC pointers (`$2D/$2F/$31`) fixed up. Needs C64 at READY.
- `type()` chunks to 10 keys (KERNAL keyboard buffer size), uppercases unless `raw=True`, `\n` -> CR.
- `screen_text()` reads screen RAM at the VIC bank/`$D018` base; graphics chars render as `#`. Use `screenshot()` for sprites/colours/graphics.
- `screenshot()` has VICE 3.7.1 workarounds (crop verified still correct on 3.10): Y offset is off by one (`yo -= 1`) and the pixel buffer comes back a few bytes short (zero-padded). Revisit if VICE is upgraded.
- `stop()` kills the whole process group (xvfb-run, Xvfb, x64sc share it).
- `hello.asm` uses ACME syntax: `!pet` for PETSCII text, anonymous `-`/`+` labels, BASIC stub `10 SYS 2064` at `$0801`, code at `$0810`.
