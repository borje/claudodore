"""ACME assembly."""
import subprocess
from pathlib import Path

BUILD = Path(__file__).resolve().parent.parent / "build"


def assemble(src, out=None):
    """Assemble with ACME -> .prg (default: build/<name>.prg). Returns the output path."""
    out = Path(out) if out else BUILD / (Path(src).stem + ".prg")
    out.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(["acme", "-f", "cbm", "-o", str(out), str(src)], capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("ACME failed:\n" + r.stdout + r.stderr)
    return out
