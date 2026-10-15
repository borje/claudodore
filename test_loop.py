import sys
from c64 import C64, assemble

prg = assemble("hello.asm")
print("assembled:", prg)

with C64() as c:
    c.start(prg)  # boots, injects the PRG into RAM, types RUN
    t = c.wait_for_text("PRESS A KEY", timeout=30)
    print("--- screen after boot+run ---")
    print(t if t else c.screen_text())
    if t is None:
        print("TIMEOUT waiting for banner; log tail:")
        print(open("/tmp/vice_%d.log" % c.port + "").read()[-1500:])
        sys.exit(1)
    c.type("q")
    c.wait(1)   # let it run 1s, then it is stopped for inspection
    print("--- screen after typing q ---")
    print(c.screen_text())
    print("screenshot:", c.screenshot("screen.png"))
