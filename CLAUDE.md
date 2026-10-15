# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Feedback loop for C64 development: assemble with ACME -> boot headless VICE (`x64sc`, under `xvfb-run` if available, else a normal window) -> drive it through VICE's binary monitor (TCP) -> read screen RAM / screenshot. Layout:
- `c64/` — framework package: `vice.py` (`C64` class), `build.py` (`assemble()` ACME, `compile_c()` cl65, `BUILD` dir), re-exported from `c64/__init__.py`.
- `programs/<name>/` — one dir per program: `<name>.asm` + `run.py` (assemble, drive VICE, assert/screenshot). `hello` is the end-to-end check (also tests `reload`), `hello_c` the cc65 path, `sprite` the sprite demo (also `sprites()`, `record_gif`), `joy` the memory-byte input demo, `joyport` the real joystick-port demo.
- `build/` — gitignored output (`.prg`, `.png`).

Needs system tools: `acme`, `cc65` (`cl65`), `x64sc` (VICE; macOS: `brew install acme cc65 vice`, tested on 3.10; Linux 3.7.1 also needs `xvfb-run`, used automatically when on PATH), plus Pillow for `screenshot()` (managed by uv; `c64` is installed editable via `uv sync`). Linux only: C64 ROMs must be in `~/.local/share/vice/C64/` (brew VICE bundles them).

## Commands

- Full chain test: `uv run programs/hello/run.py` (assembles `hello.asm`, boots, types `q`, writes `build/hello.png`; exits 1 on timeout)
- Run each program: `uv run programs/<name>/run.py` (`hello`, `hello_c`, `sprite`, `joy`, `joyport`)
- Assemble only: `acme -f cbm -o build/hello.prg programs/hello/hello.asm`
- VICE stdout/stderr go to `/tmp/vice_<port>.log`. Port is picked free per instance.
- Sprite demo: `uv run programs/sprite/run.py` (asserts sprite 0 moves in X and Y, writes `build/sprite{1,2}.png`)
- No linter, no pytest suite; each `run.py` is a script; new programs follow the same pattern.

## Architecture / gotchas

- **Machine is paused between commands.** VICE halts the C64 on every monitor command. Emulated time only advances during `resume()`/`run(s)`/`wait(s)`/`wait_for_text`/`type`. Any peek/screen read freezes it again.
- **PRGs are injected into RAM** (`load_prg` pokes at the load address, then types `RUN`), not autostarted — drive ROMs aren't available, so programs loading from disk won't work. Loads at `$0801` get BASIC pointers (`$2D/$2F/$31`) fixed up. Needs C64 at READY.
- **Agent input convention** (a program must opt in, see `programs/joy`): `joy()` ORs bits into `$033C` (edge-triggered; program clears it after reading), `joy_hold()` sets `$033E` (level). Bits: up 1, down 2, left 4, right 8, fire 16.
- **Real joystick input**: `joyport(*buttons, port=2)` uses the binary monitor's joyport-set (0xA2), which only drives VICE's "joyport I/O simulation" device (type 37), so it first switches `JoyPort<n>Device` to 37 via resource-set. Pins are active low; port 2 reads at `$DC00`, port 1 at `$DC01`. Level-triggered. Works with any program reading the joystick normally. Keyboard-matrix injection is NOT possible via the monitor (only the KERNAL buffer via `type()`).
- `reload(prg)` = hard reset + `load_prg` in the same VICE process; `load_prg` verifies the bytes it poked.
- `type()` chunks to 10 keys (KERNAL keyboard buffer size), uppercases unless `raw=True`, `\n` -> CR.
- `screen_text()` reads screen RAM at the VIC bank/`$D018` base; graphics chars render as `#`. Use `screenshot()` for sprites/colours/graphics.
- `screenshot()` has VICE 3.7.1 workarounds (crop verified still correct on 3.10): Y offset is off by one (`yo -= 1`) and the pixel buffer comes back a few bytes short (zero-padded). Revisit if VICE is upgraded.
- `stop()` kills the whole process group (xvfb-run, Xvfb, x64sc share it).
- `hello.asm` uses ACME syntax: `!pet` for PETSCII text, anonymous `-`/`+` labels, BASIC stub `10 SYS 2064` at `$0801`, code at `$0810`.

## Working on the framework

- Every framework capability gets a `programs/<name>/` program plus a `run.py` that asserts it end to end (a tiny asm program that mirrors the register/byte under test into screen RAM works well). A monitor command returning OK does not mean it did anything: `joyport` was accepted for a plain joystick yet had no effect until the device type was switched.
- C64 memory map / register reference: `docs/mapping-c64.txt` ("Mapping the Commodore 64", 526KB). Too big to read whole; grep it by address or name (e.g. `D015`, `53269`, `SPRITE`) and read only the matching range.
- VICE docs are not installed by brew. For monitor capabilities, read the upstream `vice/doc/vice.texi` (binary monitor chapter) and `vice/src/monitor/monitor_binary.c` from github.com/VICE-Team/svn-mirror; the command's C handler shows what it actually does.
- Deliberately not built (judged over-scope vs. github.com/dexmac221/C64AIToolChain): VLM screenshot analysis (read `screenshot()` PNGs directly), the System 1/2 agent control loop, per-game shell launchers. Not yet built, add when a program needs them: asset pipeline (sprite sheets, image-to-sprite), cycle/frame-loss profiling, scheduled monitor commands during GIF recording.
