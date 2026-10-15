# Oscar64 (C/C++ for 6502)

Alternative to cc65 (`compile_c`): faster generated code, C++ support. Added as `compile_oscar()`; demo `programs/c64/hello_oscar/`.

- Not in brew. Built from source (github.com/drmortalwombat/oscar64): `make -f make/makefile compiler` (any C++ compiler, no cmake).
- Installed to `~/.local/oscar64/{bin,include}`; `~/.local/bin/oscar64` is a **wrapper script**, not a symlink (the compiler finds `../include` relative to its real path, symlinks break it).
- Rebuild/reinstall: clone, `make -f make/makefile -j8`, `cp -R bin include ~/.local/oscar64/`.
- Usage: `compile_oscar("x.c", target="c64", "-Os")`. Flags: `-tm=<target>` (c64, vic20, ...), `-O2`; extra flags pass through.
- Default C64 output has a BASIC stub at $0801, so `C64.start()` injection works.
- Run: `uv run programs/c64/hello_oscar/run.py`.
- Docs: `oscar64.md` in the repo above (67KB reference).
