import time
from pathlib import Path

from retro import C64, assemble

COUNT, HOOKS, HOOK = 0xC000, 0xC002, 0x0840


def count(c):
    return int.from_bytes(c.peek(COUNT, 2), "little")


with C64() as c:  # warp: frame counts must come out exact anyway
    c.start(assemble(Path(__file__).with_name("frames.asm")))
    assert c.run_until(HOOK), "hook never ran"
    h, n = c.peek(HOOKS)[0], count(c)
    assert c.run_until(HOOK), "hook not hit again"
    assert (c.peek(HOOKS)[0], count(c)) == (h + 1, n + 1), "run_until should stop at hook once per frame"
    assert c.run_until(HOOKS, op="store") and c.peek(HOOKS)[0] == h + 2, "store watch"

    c.run_frames(1)  # align: now just past the start of raster line 0
    n = count(c)
    t = time.time()
    c.run_frames(250)
    t = time.time() - t
    assert count(c) - n == 250, count(c) - n
    c.wait(1)  # under warp: exactly 50 frames
    assert count(c) - n == 300, count(c) - n

    assert not c.run_until(0xFFF0, timeout=1), "an address never executed must time out"
    assert count(c) - n > 300, "machine did not run before the timeout"
    c.run_frames(1)  # still usable after a timeout
    print(f"frames ok: 250 frames (5 s emulated) in {t:.2f} s wall")
