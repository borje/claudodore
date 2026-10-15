# Oscar64 (C/C++ for 6502)

Alternative to cc65 (`compile_c`): faster generated code, C++ support. Added as `compile_oscar()`; demo `programs/c64/hello_oscar/`.

- Not in brew. Built from source (github.com/drmortalwombat/oscar64): `make -f make/makefile compiler` (any C++ compiler, no cmake).
- Installed to `~/.local/oscar64/{bin,include}`; `~/.local/bin/oscar64` is a **wrapper script**, not a symlink (the compiler finds `../include` relative to its real path, symlinks break it).
- Rebuild/reinstall: clone, `make -f make/makefile -j8`, `cp -R bin include ~/.local/oscar64/`.
- Usage: `compile_oscar("x.c", "-Os", target="c64")`. Flags: `-tm=<target>` (c64, vic20, ...), `-O2`; extra flags pass through.
- Charset gotcha: `printf` strings are ASCII; lowercase renders as PETSCII graphics in the default charset. Use uppercase (demo does), or `p"..."` PETSCII literals.
- Default C64 output has a BASIC stub at $0801, so `C64.start()` injection works.
- Run: `uv run programs/c64/hello_oscar/run.py`.
- Docs: `oscar64.md` in the repo above (67KB reference).
- VIC-20: targets `vic20`, `vic20+3|8|16|24`; must match `VIC20(mem=...)`. Verified 8K and 16K in `programs/vic20/hello_oscar/` (`uv run programs/vic20/hello_oscar/run.py`). Unexpanded not tried.
