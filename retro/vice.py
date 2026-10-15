"""Drive a headless VICE (x64sc / xvic) through its binary monitor.

`Machine` is the shared base; `retro.c64.C64` and `retro.vic20.VIC20` set the machine specifics.

Gives a feedback loop: assemble -> launch -> read screen -> send keys -> screenshot.
"""
import os
import shutil
import signal
import socket
import struct
import subprocess
import time

HOST, PORT = "127.0.0.1", 6502

# Command codes from the VICE manual, "Binary monitor" chapter
CMD_MEM_GET, CMD_MEM_SET = 0x01, 0x02
CMD_REGS_GET = 0x31
CMD_RESOURCE_SET = 0x52
CMD_KEYBOARD_FEED = 0x72
CMD_PING = 0x81
CMD_DISPLAY_GET = 0x84
CMD_JOYPORT_SET = 0xA2
CMD_EXIT, CMD_QUIT, CMD_RESET, CMD_AUTOSTART = 0xAA, 0xBB, 0xCC, 0xDD


# Agent input convention (programs opt in): OR a bit into JOY_PRESS (the program clears it after
# reading -> edge-triggered), or set bits in JOY_HOLD (level-triggered).
JOY_PRESS, JOY_HOLD = 0x033C, 0x033E
JOY_BITS = {"up": 1, "down": 2, "left": 4, "right": 8, "fire": 16}


def screencode_to_char(c):
    """C64/VIC-20 screen code -> printable ASCII (uppercase/graphics set; graphics become '#')."""
    c &= 0x7F  # ignore reverse bit
    if c == 0:
        return "@"
    if 1 <= c <= 26:
        return chr(ord("A") + c - 1)
    if 27 <= c <= 31:
        return "[\\]^_"[c - 27]
    if 32 <= c <= 63:
        return chr(c)
    return "#"


class Machine:
    """Base: subclasses set BIN/PALETTE/BASIC_START and implement screen_dims/screen_base/joyport."""
    BIN = None            # VICE binary, e.g. "x64sc"
    NAME = None           # for messages
    PALETTE = None        # index = colour 0-15
    DISPLAY_CHIP = 0      # display-get chip selector byte
    BASIC_STARTS = ()     # load addresses that are BASIC programs (pointers get fixed up)

    def __init__(self, port=None, warp=False, verbose=False):
        if port is None:  # pick a free port so a stale instance can never be mistaken for ours
            with socket.socket() as s:
                s.bind((HOST, 0))
                port = s.getsockname()[1]
        self.port = port
        self.warp = warp
        self.verbose = verbose
        self.proc = None
        self.sock = None
        self._req = 0

    # ---------------------------------------------------------------- process
    def extra_args(self):
        """Extra VICE command-line args (e.g. memory config)."""
        return []

    def start(self, prg=None, timeout=20, run=True):
        """Boot a fresh machine to the READY prompt; if prg is given, load and (optionally) run it."""
        # xvfb-run is Linux-only; on macOS VICE opens a normal window.
        xvfb = ["xvfb-run", "-a", "-s", "-screen 0 800x600x24"] if shutil.which("xvfb-run") else []
        # real audio unless headless (xvfb)
        cmd = xvfb + [
            self.BIN, "-default", *(["+sound", "-sounddev", "dummy"] if xvfb else ["-sound"]),
            "+confirmonexit", *self.extra_args(), "-binarymonitor",
            "-binarymonitoraddress", f"ip4://{HOST}:{self.port}",
        ]
        if self.warp:
            cmd.append("-warp")
        log = open(f"/tmp/vice_{self.port}.log", "w")
        self.proc = subprocess.Popen(
            cmd, stdout=log, stderr=subprocess.STDOUT, start_new_session=True
        )
        deadline = time.time() + timeout
        while time.time() < deadline:
            try:
                self.sock = socket.create_connection((HOST, self.port), timeout=2)
                self.sock.settimeout(10)
                self.ping()
                break
            except OSError:
                time.sleep(0.3)
        else:
            self.stop()
            raise RuntimeError("VICE binary monitor never came up; see /tmp/vice_%d.log" % self.port)
        # VICE freezes the machine when a monitor client connects; resume it.
        self.resume()
        if self.wait_for_text("READY.", timeout=30) is None:
            raise RuntimeError(f"{self.NAME} never reached READY.; see /tmp/vice_%d.log" % self.port)
        if prg:
            self.load_prg(prg, run=run)
        return self

    def load_prg(self, path, run=True):
        """Inject a .prg straight into RAM (no disk drive needed). Needs the machine at READY."""
        data = open(path, "rb").read()
        addr = struct.unpack("<H", data[:2])[0]
        body = data[2:]
        self.poke(addr, body)
        if self.peek(addr, len(body)) != body:
            raise RuntimeError(f"PRG verify failed at ${addr:04x}")
        end = addr + len(body)
        if addr in self.BASIC_STARTS:  # BASIC program: fix up start-of-variables pointers
            self.poke(0x2D, struct.pack("<H", end))
            self.poke(0x2F, struct.pack("<H", end))
            self.poke(0x31, struct.pack("<H", end))
        if run:
            self.type("RUN\n")

    def reload(self, prg, run=True):
        """Hard-reset the running machine and load prg again (no new VICE process)."""
        self.reset()
        self.resume()
        if self.wait_for_text("READY.", timeout=30) is None:
            raise RuntimeError(f"{self.NAME} never reached READY. after reset")
        self.load_prg(prg, run=run)

    def stop(self):
        try:
            if self.sock:
                try:
                    self._command(CMD_QUIT)  # ask VICE to quit cleanly
                except Exception:
                    pass
                self.sock.close()
        except OSError:
            pass
        self.sock = None
        if self.proc:
            # xvfb-run, Xvfb and x64sc share a process group: terminate, then make sure.
            for sig in (signal.SIGTERM, signal.SIGKILL):
                try:
                    os.killpg(self.proc.pid, sig)
                except (ProcessLookupError, PermissionError):  # macOS: EPERM once the group is gone
                    break
                try:
                    self.proc.wait(timeout=3)
                    break
                except subprocess.TimeoutExpired:
                    continue
            self.proc = None

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.stop()

    # --------------------------------------------------------------- protocol
    def _recv_exact(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError("monitor connection closed")
            buf += chunk
        return buf

    def _command(self, cmd, body=b""):
        self._req += 1
        rid = self._req
        self.sock.sendall(struct.pack("<BBIIB", 0x02, 0x02, len(body), rid, cmd) + body)
        while True:
            hdr = self._recv_exact(12)
            stx, api, blen, rtype, err, rrid = struct.unpack("<BBIBBI", hdr)
            payload = self._recv_exact(blen)
            if rrid == rid:
                if err != 0:
                    raise RuntimeError(f"monitor error 0x{err:02x} for cmd 0x{cmd:02x}")
                return payload
            # else: async event (0xFFFFFFFF) - ignore

    def ping(self):
        self._command(CMD_PING)

    def resume(self):
        """Leave the monitor so the emulated machine runs.

        VICE stops the machine whenever a monitor command arrives, so the machine
        only advances between a resume() and the next command. run(s) wraps that.
        """
        try:
            self._command(CMD_EXIT)
        except RuntimeError:
            pass  # already running

    def run(self, seconds):
        """Let the machine run for `seconds` of wall-clock time, then leave it for inspection."""
        self.resume()
        time.sleep(seconds)

    # ----------------------------------------------------------------- memory
    def peek(self, start, length=1):
        end = start + length - 1
        body = struct.pack("<BHHBH", 0, start, end, 0, 0)
        data = self._command(CMD_MEM_GET, body)
        n = struct.unpack("<H", data[:2])[0]
        return data[2:2 + n]

    def poke(self, addr, data):
        if isinstance(data, int):
            data = bytes([data])
        body = struct.pack("<BHHBH", 0, addr, addr + len(data) - 1, 0, 0) + bytes(data)
        self._command(CMD_MEM_SET, body)

    # ----------------------------------------------------------------- screen
    def screen_dims(self):
        """(cols, rows) of the text screen."""
        raise NotImplementedError

    def screen_base(self):
        """Address of screen RAM."""
        raise NotImplementedError

    def screen_text(self):
        """Return the text screen as a string (via screen RAM)."""
        cols, rows = self.screen_dims()
        if not cols * rows:  # video chip not initialised yet (VIC-I registers are 0 right after power-on)
            return ""
        raw = self.peek(self.screen_base(), cols * rows)
        lines = ["".join(screencode_to_char(c) for c in raw[r * cols:(r + 1) * cols]) for r in range(rows)]
        return "\n".join(r.rstrip() for r in lines).rstrip("\n")

    def screen_image(self, scale=2, border=False):
        """PIL Image of the video chip output using the monitor's display-get."""
        from PIL import Image
        data = self._command(CMD_DISPLAY_GET, struct.pack("<BB", self.DISPLAY_CHIP, 0))  # 8-bit indexed
        info_len = struct.unpack("<I", data[:4])[0]
        (dw, dh, xo, yo, iw, ih, bpp) = struct.unpack("<HHHHHHB", data[4:4 + 13])
        start = 4 + info_len                      # buffer-length field follows the info fields
        ilen = struct.unpack("<I", data[start:start + 4])[0]
        pix = data[start + 4:start + 4 + ilen]    # pixel data starts after that 4-byte field
        pix += bytes(max(0, dw * dh - len(pix)))  # VICE 3.7 sends the buffer a few bytes short
        img = Image.new("RGB", (dw, dh))
        px = img.load()
        for y in range(dh):
            row = pix[y * dw:(y + 1) * dw]
            for x, v in enumerate(row):
                px[x, y] = self.PALETTE[v & 15]
        if not border:
            xo, yo = self.crop_origin(xo, yo)
            img = img.crop((xo, yo, xo + iw, yo + ih))
        if scale != 1:
            img = img.resize((img.width * scale, img.height * scale), Image.NEAREST)
        return img

    def crop_origin(self, xo, yo):
        return xo, yo

    def screenshot(self, path="screen.png", **kw):
        """Save a PNG of the VIC-II output (see screen_image)."""
        self.screen_image(**kw).save(path)
        return path

    def record_gif(self, path, seconds=5, interval=0.15, fps=7, scale=1):
        """Run the machine, capturing a frame every `interval` s of wall time, and save a GIF."""
        frames = []
        end = time.time() + seconds
        while time.time() < end:
            self.run(interval)
            frames.append(self.screen_image(scale=scale))
        frames[0].save(path, save_all=True, append_images=frames[1:], duration=int(1000 / fps), loop=0)
        return path

    # ------------------------------------------------------------------ input
    def set_resource(self, name, value):
        """Set an integer VICE resource (as in -resource files)."""
        n = name.encode()
        self._command(CMD_RESOURCE_SET, struct.pack("<BB", 1, len(n)) + n + struct.pack("<BI", 4, value))

    def joyport(self, *buttons, port=None):
        """Hold buttons on a real control port (see subclasses)."""
        raise NotImplementedError

    def joy(self, *buttons):
        """Press buttons (up/down/left/right/fire) via the edge-triggered JOY_PRESS byte."""
        self.poke(JOY_PRESS, self.peek(JOY_PRESS)[0] | sum(JOY_BITS[b] for b in buttons))

    def joy_hold(self, *buttons):
        """Set the held buttons (level-triggered JOY_HOLD byte); no args releases all."""
        self.poke(JOY_HOLD, sum(JOY_BITS[b] for b in buttons))

    def type(self, text, raw=False):
        """Feed text to the keyboard buffer as if typed. \\n = RETURN.

        Letters are sent as unshifted keys (PETSCII uppercase) unless raw=True, in
        which case the string is sent as-is (PETSCII bytes, latin-1 encoded).
        """
        text = text.replace("\n", "\r")
        if not raw:
            text = text.upper()
        for i in range(0, len(text), 10):  # C64 keyboard buffer holds 10 keys
            chunk = text[i:i + 10].encode("latin-1")
            self._command(CMD_KEYBOARD_FEED, struct.pack("<B", len(chunk)) + chunk)
            self.run(0.3 if not self.warp else 0.05)  # let the KERNAL consume the keys

    def reset(self, hard=True):
        self._command(CMD_RESET, struct.pack("<B", 1 if hard else 0))

    def wait(self, seconds):
        self.run(seconds)

    def wait_for_text(self, needle, timeout=15, poll=0.5):
        """Run the machine until `needle` shows on screen. Returns the screen text or None."""
        end = time.time() + timeout
        while time.time() < end:
            self.run(poll)
            t = self.screen_text()  # this command also stops the machine
            if needle.upper() in t:
                return t
        return None
