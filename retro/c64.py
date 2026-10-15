"""Commodore 64 on VICE x64sc."""
import struct

from .vice import CMD_JOYPORT_SET, JOY_BITS, Machine

# Colodore-ish C64 palette (index = C64 colour 0-15)
PALETTE = [
    (0, 0, 0), (255, 255, 255), (136, 57, 50), (103, 182, 189),
    (139, 63, 150), (85, 160, 73), (64, 49, 141), (191, 206, 114),
    (139, 84, 41), (87, 66, 0), (184, 105, 98), (80, 80, 80),
    (120, 120, 120), (148, 224, 137), (120, 105, 196), (159, 159, 159),
]


class C64(Machine):
    BIN = "x64sc"
    NAME = "C64"
    PALETTE = PALETTE
    DISPLAY_CHIP = 1  # VIC-II
    BASIC_STARTS = (0x0801,)

    def screen_dims(self):
        return 40, 25

    def screen_base(self):
        d018 = self.peek(0xD018)[0]
        dd00 = self.peek(0xDD00)[0]
        bank = (~dd00 & 3) * 0x4000
        return bank + ((d018 >> 4) & 0xF) * 0x400

    def crop_origin(self, xo, yo):
        # Measured on VICE 3.7.1: the reported Y offset is one line too low, so the
        # real 320x200 area is rows yo-1 .. yo+198 of the buffer (x offset is right).
        return xo, yo - 1

    # ------------------------------------------------------------ chip state
    def color_ram(self):
        """1000 colour-RAM nybbles ($D800), row-major."""
        return bytes(b & 15 for b in self.peek(0xD800, 1000))

    def sprites(self):
        """Enabled sprites as dicts: id, x (9-bit), y, color, ptr (sprite data address in VIC bank)."""
        vic = self.peek(0xD000, 0x2F)
        base = self.screen_base()
        bank = base & 0xC000
        ptrs = self.peek(base + 0x3F8, 8)
        return [
            {"id": i, "x": vic[2 * i] | (0x100 if vic[0x10] >> i & 1 else 0), "y": vic[2 * i + 1],
             "color": vic[0x27 + i] & 15, "ptr": bank + ptrs[i] * 64}
            for i in range(8) if vic[0x15] >> i & 1
        ]

    def joyport(self, *buttons, port=2):
        """Hold buttons on a real control port; the program sees them in CIA1 ($DC00 = port 2, $DC01 = port 1).

        Works with any program that reads the joystick normally. Level-triggered: stays until the
        next call; no args releases. Switches the port to VICE's "joyport I/O simulation" device
        (the only thing the binary monitor can drive), so a real/keyboard joystick on it is replaced.
        """
        self.set_resource(f"JoyPort{port}Device", 37)
        pins = 0x1F & ~sum(JOY_BITS[b] for b in buttons)  # joystick lines are active low
        self._command(CMD_JOYPORT_SET, struct.pack("<HH", port - 1, pins))

