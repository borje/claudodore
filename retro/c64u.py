"""Real C64 Ultimate, driven through the `c64u` CLI (REST API: DMA peek/poke, PRG upload, keyboard buffer).

Same API as `C64` where the hardware allows. The machine runs freely, so unlike VICE nothing is
paused between commands. screenshot/gif are re-rendered from DMA (see `screen_image`), and no joyport (DMA writes to $DC00 are overwritten
by the KERNAL scan); use the opt-in `joy()`/`joy_hold()` memory bytes.
"""
import subprocess
import time
from pathlib import Path

from .c64 import C64


class C64U(C64):
    NAME = "C64 Ultimate"

    def __init__(self, device=None, host=None, verbose=False):
        self.verbose = verbose
        self.warp = False
        self.base = ["c64u"] + (["-D", device] if device else []) + (["--host", host] if host else [])

    def _c64u(self, *args, text=True):
        r = subprocess.run(self.base + list(args), capture_output=True, text=text)
        if r.returncode:
            err = r.stderr if text else r.stderr.decode(errors="replace")
            raise RuntimeError(f"c64u {' '.join(args)}: {err.strip() or r.stdout}")
        return r.stdout

    def start(self, prg=None, timeout=20, run=True):
        self.reset()
        if self.wait_for_text("READY.", timeout=timeout) is None:
            raise RuntimeError(f"{self.NAME} never reached READY. after reset")
        if prg:
            self.load_prg(prg, run=run)

    def load_prg(self, path, run=True):
        """Upload a PRG; the device fixes BASIC pointers itself. run=False loads without starting."""
        self._c64u("runners", "run-prg-upload" if run else "load-prg-upload", str(path))

    def reload(self, prg, run=True):
        self.start(prg, run=run)

    def stop(self):
        pass  # leave the hardware as is; nothing to clean up

    def reset(self, hard=True):
        self._c64u("machine", "reset")

    def resume(self):
        pass  # never paused

    def run(self, seconds):
        time.sleep(seconds)

    def peek(self, start, length=1):
        return self._c64u("machine", "read-mem", f"{start:04x}", "--length", str(length), "--raw", text=False)

    def poke(self, addr, data):
        if isinstance(data, int):
            data = bytes([data])
        for i in range(0, len(data), 128):  # write-mem takes at most 128 bytes
            self._c64u("machine", "write-mem", f"{addr + i:04x}", bytes(data[i:i + 128]).hex())

    def type(self, text, raw=False):
        """Feed text to the keyboard buffer. A newline is RETURN.

        Like `C64.type`: letters are uppercased. raw=True sends the text as-is, so sendkey
        escapes (\\f1, \\stop, \\clr...) apply; otherwise a backslash is an error (the C64 has
        no such key and sendkey has no literal-backslash escape).
        """
        if not raw:
            if "\\" in text:
                raise ValueError("backslash is a sendkey escape; pass raw=True")
            text = text.upper()
        self._c64u("machine", "sendkey", text.replace("\n", "\\n"))
        time.sleep(0.3)

    def joyport(self, *buttons, port=2):
        raise NotImplementedError("DMA writes to $DC00/$DC01 do not stick; use joy()/joy_hold()")

    def screen_image(self, scale=2, border=False):
        """Re-render the screen from DMA (no video capture on this unit): text modes only, no sprites.

        Standard and multicolour text, charset from RAM or the bundled char ROM (`chargen.bin`).
        """
        from PIL import Image
        vic = self.peek(0xD000, 0x30)
        if vic[0x11] & 0x60:
            raise NotImplementedError("screen_image: bitmap/ECM modes not rendered")
        base = self.screen_base()
        bank, cbase = base & 0xC000, (vic[0x18] >> 1 & 7) * 0x800
        if bank in (0, 0x8000) and 0x1000 <= cbase < 0x2000:  # VIC sees char ROM here
            rom = Path(__file__).with_name("chargen.bin").read_bytes()
            chars = rom[cbase - 0x1000:cbase - 0x1000 + 0x800]
        else:
            chars = self.peek(bank + cbase, 0x800)
        screen, colors = self.peek(base, 1000), self.color_ram()
        multi = vic[0x16] & 0x10
        bg = [vic[0x21 + i] & 15 for i in range(3)]
        img = Image.new("RGB", (320, 200), self.PALETTE[bg[0]])
        px = img.load()
        for n in range(1000):
            cx, cy, col = n % 40 * 8, n // 40 * 8, colors[n]
            for y in range(8):
                b = chars[screen[n] * 8 + y]
                if multi and col & 8:
                    for x in range(4):
                        c = (b >> (6 - 2 * x)) & 3
                        c = (bg[0], bg[1], bg[2], col & 7)[c]
                        px[cx + 2 * x, cy + y] = px[cx + 2 * x + 1, cy + y] = self.PALETTE[c]
                else:
                    for x in range(8):
                        if b >> (7 - x) & 1:
                            px[cx + x, cy + y] = self.PALETTE[col & 15 if not multi else col & 7]
        if border:
            full = Image.new("RGB", (384, 272), self.PALETTE[vic[0x20] & 15])
            full.paste(img, (32, 36))
            img = full
        return img.resize((img.width * scale, img.height * scale), Image.NEAREST) if scale != 1 else img
