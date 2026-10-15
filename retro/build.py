"""Build programs: ACME (.asm), cc65 (C / .s) and petcat (text BASIC) -> .prg.

Default output: build/<machine>/<name>.prg, where <machine> is the directory above the program's
own dir (programs/<machine>/<name>/...), so c64 and vic20 programs of the same name don't collide.
"""
import subprocess
from pathlib import Path

BUILD = Path(__file__).resolve().parent.parent / "build"


def _run(cmd, tool, out):
    out.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError(f"{tool} failed:\n" + r.stdout + r.stderr)
    return out


def _out(src, out):
    src = Path(src).resolve()
    return Path(out) if out else BUILD / src.parent.parent.name / (src.stem + ".prg")


def assemble(src, out=None, **defs):
    """Assemble with ACME -> .prg. Returns the output path. defs: -DNAME=value symbols."""
    out = _out(src, out)
    d = [f"-D{k}={v}" for k, v in defs.items()]
    return _run(["acme", "-f", "cbm", *d, "-o", str(out), str(src)], "ACME", out.resolve())


def compile_c(*srcs, out=None, cfg=None, target="c64"):
    """Compile/link C and .s sources with cc65 (cl65 -t <target> -O) -> .prg.

    cfg: optional linker config file (-C) for custom memory layouts.
    """
    out = _out(srcs[0], out)
    cmd = ["cl65", "-t", target, "-O", "-o", str(out)] + (["-C", str(cfg)] if cfg else []) + [str(s) for s in srcs]
    return _run(cmd, "cl65", out.resolve())


def compile_oscar(src, out=None, target="c64", *flags):
    """Compile/link C/C++ with Oscar64 (oscar64 -tm=<target> -O2) -> .prg. See docs/oscar64.md."""
    out = _out(src, out)
    return _run(["oscar64", f"-tm={target}", "-O2", *flags, f"-o={out.resolve()}", str(src)], "oscar64", out.resolve())


def basic(src, out=None, load=0x0801):
    """Tokenize text BASIC 2 with petcat -> .prg. Source must be lowercase.

    load: PRG load address (C64 $0801; VIC-20 $1001 unexpanded, $1201 with 8K+).
    """
    out = _out(src, out)
    return _run(["petcat", "-w2", "-l", f"{load:x}", "-o", str(out), "--", str(src)], "petcat", out.resolve())
