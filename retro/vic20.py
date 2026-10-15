"""Commodore VIC-20 on VICE xvic. Memory config: mem=0 (unexpanded), 8 or 16 (KB expansion)."""
import struct

from .vice import CMD_JOYPORT_SET, JOY_BITS, Machine

# Pepto's VIC-20 palette (index = VIC-I colour 0-15)
PALETTE = [
    (0, 0, 0), (255, 255, 255), (120, 41, 34), (135, 214, 221),
    (170, 95, 182), (85, 160, 73), (64, 49, 141), (191, 206, 114),
    (170, 116, 73), (234, 180, 137), (184, 105, 98), (199, 255, 255),
    (234, 159, 246), (148, 224, 137), (128, 113, 204), (255, 255, 178),
]

MEMORY = {0: "none", 8: "8k", 16: "16k"}


class VIC20(Machine):
    BIN = "xvic"
    NAME = "VIC-20"
    PALETTE = PALETTE
    DISPLAY_CHIP = 0

    def __init__(self, mem=0, **kw):
        if mem not in MEMORY:
            raise ValueError(f"mem must be one of {sorted(MEMORY)} (KB of expansion)")
        super().__init__(**kw)
        self.mem = mem
        # BASIC start moves up when expansion RAM occupies $2000+ (screen then lives at $1000)
        self.BASIC_STARTS = (0x1001,) if mem == 0 else (0x1201,)

    def extra_args(self):
        return ["-memory", MEMORY[self.mem]]

    def screen_dims(self):
        v = self.peek(0x9000, 4)
        return v[2] & 0x7F, (v[3] >> 1) & 0x3F

    def screen_base(self):
        v = self.peek(0x9000, 6)
        # VIC-I address bits: $9005 b6-4 -> A12-10... b7 inverted -> A13; $9002 b7 -> A9
        return ((v[5] & 0x70) << 6) | (0 if v[5] & 0x80 else 0x2000) | ((v[2] & 0x80) << 2)

    def color_ram_base(self):
        return 0x9400 | ((self.peek(0x9002)[0] & 0x80) << 2)

    def color_ram(self):
        """Colour-RAM nybbles for the text screen, row-major."""
        cols, rows = self.screen_dims()
        return bytes(b & 15 for b in self.peek(self.color_ram_base(), cols * rows))

    def joyport(self, *buttons):
        """Hold buttons on the joystick port (VIA1 $9111 up/down/left/fire, VIA2 $9120 b7 right).

        Level-triggered: stays until the next call; no args releases. Switches the port to VICE's
        "joyport I/O simulation" device (the only thing the binary monitor can drive).
        """
        self.set_resource("JoyPort1Device", 37)
        pins = 0x1F & ~sum(JOY_BITS[b] for b in buttons)  # active low
        self._command(CMD_JOYPORT_SET, struct.pack("<HH", 0, pins))
