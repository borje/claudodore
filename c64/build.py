"""Build 6502 programs: ACME (.asm) and cc65 (C / .s) -> .prg."""
import subprocess
from pathlib import Path

BUILD = Path(__file__).resolve().parent.parent / "build"


def _run(cmd, tool, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{tool} failed:\n" + r.stdout + r.stderr)
    return out


def assemble(src, out=None):
    """Assemble with ACME -> .prg (default: build/<name>.prg). Returns the output path."""
    out = Path(out) if out else BUILD / (Path(src).stem + ".prg")
    return _run(["acme", "-f", "cbm", "-o", str(out), str(src)], "ACME", out.resolve())


def compile_c(*srcs, out=None, cfg=None):
    """Compile/link C and .s sources with cc65 (cl65 -t c64 -O) -> .prg (default: build/<first>.prg).

    cfg: optional linker config file (-C) for custom memory layouts.
    """
    out = Path(out) if out else BUILD / (Path(srcs[0]).stem + ".prg")
    cmd = ["cl65", "-t", "c64", "-O", "-o", str(out)] + (["-C", str(cfg)] if cfg else []) + [str(s) for s in srcs]
    return _run(cmd, "cl65", out.resolve())
