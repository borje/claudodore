import sys
from pathlib import Path

from retro import BUILD, C64, assemble

RLO, RHI = 0xC000, 0xC100
HD, DIR, ND, GROW, SCORE, WINS = 0xC300, 0xC304, 0xC306, 0xC308, 0xC310, 0xC312
TICK, SPEED, PLAYERS, DEAD = 0xC321, 0xC322, 0xC32C, 0xC30A
AX, AY, HX, HY, HI, MI, MON = 0xC330, 0xC332, 0xC334, 0xC336, 0xC341, 0xC343, 0xC346
HS_SC, HS_NM, NEWROW, POS, ENTRY = 0xC350, 0xC355, 0xC364, 0xC365, 0xC366
LEVEL, LAPPLES, ASLOT = 0xC36E, 0xC371, 0xC32F
SCR = 0x400
HID, CH_LD, CH_RU, APPLE, WALL, BLK = 89, 74, 77, 78, 80, 88
OUT = BUILD / "c64"


def head(c, p):  # screen address of player p's head
    i = (c.peek(HD + p)[0] & 0x7F) | p * 128
    return c.peek(RLO + i)[0] | c.peek(RHI + i)[0] << 8


def count(c, chars):
    scr = c.peek(SCR, 1000)
    return sum(scr.count(ch) for ch in chars)


def step(c):  # one game step: snakes are parked (huge SPEED), so force the tick
    c.poke(TICK, bytes([1]))
    c.wait(0.1)


def fire(c, port):
    c.joyport("fire", port=port); c.wait(0.3); c.joyport(port=port)


def start_round(c, port):
    fire(c, port)
    assert c.run_until(TICK, op="store")  # end of the "get ready" pause (sta speed, sta tick): park before anything moves
    c.poke(SPEED, bytes([250])); c.poke(TICK, bytes([250])); c.wait(0.05)


with C64(warp=sys.argv[1:] != ["play"]) as c:  # a human plays in real time
    c.start(assemble(Path(__file__).with_name("snake.asm")))
    if sys.argv[1:] == ["play"]:  # interactive: play with VICE's joystick keys until the window is closed
        c.resume()
        c.proc.wait()
        sys.exit()
    c.wait(1.5)
    t = c.screen_text()
    assert "PRESS FIRE" in t and "F1 MUSIC ON/OFF" in t and "PORT 2 / W A S D" in t and "PORT 1 / I J K L" in t, t
    assert c.peek(0xD018)[0] & 0x0E == 0x0C, "charset at $3000"
    assert count(c, [BLK]) == 67, count(c, [BLK])  # SNAKE logo
    c.screenshot(OUT / "snake0.png")

    start_round(c, 2)
    t = c.screen_text()
    assert "P1" in t and "P2" in t and "S N A K E" in t and "GET READY" not in t, t
    assert count(c, [HID]) == 2 and count(c, [APPLE]) == 2, (count(c, [HID]), count(c, [APPLE]))
    assert c.peek(DIR, 2) == bytes([1, 3]), c.peek(DIR, 2)
    # heads are sprites sitting on their (parked) cells
    for s in c.sprites():
        p = s["id"]
        assert (s["x"], s["y"]) == (24 + 8 * c.peek(HX + p)[0], 50 + 8 * c.peek(HY + p)[0]), s
        assert head(c, p) == SCR + 40 * c.peek(HY + p)[0] + c.peek(HX + p)[0]
    assert len(c.sprites()) == 2
    # music plays
    mi = c.peek(MI)[0]
    c.wait(0.5)
    assert c.peek(MI)[0] != mi, "music not advancing"
    # muted (what F1 toggles; the keyboard matrix can't be driven from the monitor)
    c.poke(MON, bytes([0])); mi = c.peek(MI)[0]; c.wait(0.5)
    assert c.peek(MI)[0] == mi, "music should be stopped"
    c.poke(MON, bytes([1]))

    # both joystick ports steer their own snake
    c.joyport("down", port=2); c.joyport("up", port=1); c.wait(0.2)
    c.joyport(port=2); c.joyport(port=1)
    assert c.peek(ND, 2) == bytes([2, 0]), c.peek(ND, 2)
    h0, h1 = head(c, 0), head(c, 1)
    step(c)
    assert c.peek(DIR, 2) == bytes([2, 0])
    assert (head(c, 0), head(c, 1)) == (h0 + 40, h1 - 40)
    assert c.peek(h0)[0] == CH_LD and c.peek(h1)[0] == CH_RU, "corner tiles"
    # reversing is ignored
    c.joyport("up", port=2); c.wait(0.2); c.joyport(port=2)
    assert c.peek(ND)[0] == 2, (c.peek(ND, 2), c.peek(DIR, 2))

    # eat an apple: score, the eater grows 1 and the other snake 3, respawn
    h0 = head(c, 0)
    c.poke(h0 + 40, bytes([APPLE]))
    step(c)
    assert c.peek(SCORE)[0] == 1 and c.peek(GROW, 2) == bytes([1, 3]), (c.peek(SCORE), c.peek(GROW, 2))
    assert count(c, [APPLE]) == 3, "apple not respawned"
    assert "01" in c.screen_text().splitlines()[0]
    # a respawned apple is never within 2 cells of a head
    for _ in range(4):
        c.poke(head(c, 0) + 40, bytes([APPLE]))
        step(c)
        a = c.peek(ASLOT)[0]
        ax, ay = c.peek(AX + a)[0], c.peek(AY + a)[0]
        for p in (0, 1):
            assert abs(ax - c.peek(HX + p)[0]) + abs(ay - c.peek(HY + p)[0]) >= 3, (p, ax, ay)
    assert c.peek(SCORE)[0] == 5
    c.screenshot(OUT / "snake1.png")

    # P1 hits a wall -> P2 takes the round
    c.poke(head(c, 0) + 40, bytes([WALL]))
    step(c)
    c.wait(1.5)
    t = c.screen_text()
    assert "PLAYER 2 WINS ROUND" in t, t
    assert c.peek(SCORE, 2) == bytes([5, 5]), c.peek(SCORE, 2)  # round win +5
    c.screenshot(OUT / "snake2.png")

    # next round (fire on port 1): scores carry over
    start_round(c, 1)
    assert c.peek(MON)[0] == 1, "port-1 fire must not toggle music"
    assert count(c, [HID]) == 2 and c.peek(SCORE, 2) == bytes([5, 5])
    # 10th apple on a level by one player -> next level with obstacles, scores kept
    c.poke(LAPPLES, bytes([9]))
    c.poke(head(c, 0) + 1, bytes([APPLE]))
    step(c); c.wait(0.3)
    assert "NEXT LEVEL" in c.screen_text()
    assert c.run_until(TICK, op="store")
    c.poke(SPEED, bytes([250])); c.poke(TICK, bytes([250])); c.wait(0.05)
    assert c.peek(LEVEL)[0] == 1 and c.peek(LAPPLES, 2) == bytes(2) and c.peek(SCORE, 2) == bytes([6, 5])
    assert count(c, [BLK]) == 18, count(c, [BLK])
    # P2 crashes, the round win takes P1 to 50: match
    c.poke(SCORE, bytes([0x45]))
    c.poke(head(c, 1) - 1, bytes([WALL]))
    step(c)
    c.wait(1.5)
    t = c.screen_text()
    assert "PLAYER 1 WINS THE MATCH" in t, t
    c.screenshot(OUT / "snake3.png")
    fire(c, 2)
    c.wait(0.5)
    assert "PRESS FIRE OR SPACE" in c.screen_text()
    assert "<    2 PLAYERS    >" in c.screen_text() and c.peek(PLAYERS)[0] == 2

    # 1 player vs computer: left toggles the mode
    c.joyport("left"); c.wait(0.2); c.joyport(); c.wait(0.2)
    t = c.screen_text()
    assert "<   VS COMPUTER   >" in t and "PLAYER 2  COMPUTER" in t, t
    c.screenshot(OUT / "snake4.png")
    start_round(c, 2)
    assert c.screen_text().splitlines()[0].endswith("CP"), c.screen_text().splitlines()[0]
    assert c.peek(SCORE, 2) == bytes(2) and c.peek(LEVEL)[0] == 0 and count(c, [BLK]) == 0
    # P1 takes either controller
    c.joyport("down", port=1); c.wait(0.2); c.joyport(port=1)
    assert c.peek(ND)[0] == 2
    # computer turns towards the apple (both apple slots pointed straight above its head)
    hx, hy = c.peek(HX + 1)[0], c.peek(HY + 1)[0]
    c.poke(AX, bytes([hx, hx])); c.poke(AY, bytes([4, 4]))
    step(c)
    assert c.peek(DIR + 1)[0] == 0, c.peek(DIR, 2)
    assert (c.peek(HX + 1)[0], c.peek(HY + 1)[0]) == (hx, hy - 1)
    # target to the left, wall in the way: it must dodge left or right of it, not crash
    c.poke(AX, bytes([2, 2])); c.poke(AY, bytes([hy - 1] * 2))
    step(c)
    assert c.peek(DIR + 1)[0] == 3, c.peek(DIR, 2)
    c.poke(head(c, 1) - 1, bytes([WALL]))
    step(c)
    assert c.peek(DEAD, 2) == bytes(2) and c.peek(DIR + 1)[0] in (0, 2), (c.peek(DEAD, 2), c.peek(DIR, 2))
    c.screenshot(OUT / "snake5.png")

    # heads glide: at real speed the sprite passes through in-between pixels
    c.poke(SPEED, bytes([7])); c.poke(TICK, bytes([7]))
    xs = set()
    for _ in range(12):
        c.wait(0.03)
        xs |= {(s["x"] - 24) % 8 + ((s["y"] - 50) % 8) for s in c.sprites()}
    assert xs - {0}, xs

    # solo: one snake, high score
    # an apple taking P1 to 50 ends the match mid-round
    c.poke(SPEED, bytes([250])); c.poke(TICK, bytes([250])); c.wait(0.05)
    c.poke(SCORE, bytes([0x49])); c.poke(head(c, 0) + 40, bytes([APPLE]))
    step(c); c.wait(0.5)
    assert "PLAYER 1 WINS THE MATCH" in c.screen_text(), c.screen_text()
    fire(c, 2); c.wait(0.5)
    assert "<   VS COMPUTER   >" in c.screen_text(), c.screen_text()
    c.joyport("left"); c.wait(0.2); c.joyport(); c.wait(0.2)
    t = c.screen_text()
    assert "<      SOLO       >" in t and "3 LIVES" in t and "COMPUTER" not in t, t
    start_round(c, 2)
    assert count(c, [HID]) == 1 and len(c.sprites()) == 1
    assert c.screen_text().splitlines()[0].endswith("00 HI"), c.screen_text().splitlines()[0]
    c.poke(head(c, 0) + 1, bytes([APPLE]))
    step(c)
    assert c.peek(SCORE)[0] == 1
    assert c.peek(WINS)[0] == 3 and c.peek(LAPPLES)[0] == 1
    # a crash costs a life, score and level carry on
    c.poke(head(c, 0) + 1, bytes([WALL]))
    step(c); c.wait(1.5)
    assert "LIFE LOST" in c.screen_text() and c.peek(WINS)[0] == 2
    start_round(c, 2)
    assert c.peek(SCORE)[0] == 1 and c.peek(LEVEL)[0] == 0 and count(c, [BLK]) == 0
    # 10th apple -> next level with obstacles, solo score kept
    c.poke(LAPPLES, bytes([9]))
    c.poke(head(c, 0) + 1, bytes([APPLE]))
    step(c); c.wait(0.3)
    assert "NEXT LEVEL" in c.screen_text()
    c.wait(3.5)
    assert c.peek(LEVEL)[0] == 1 and c.peek(LAPPLES)[0] == 0 and c.peek(SCORE)[0] == 2 and c.peek(WINS)[0] == 2
    assert count(c, [BLK]) == 18, count(c, [BLK])
    c.screenshot(OUT / "snake7.png")
    # the other layouts (plus, slash, X) and the wrap back to the open level
    for lv, n in ((2, 32), (5, 34), (6, 36), (7, 70), (8, 0)):
        c.poke(LEVEL, bytes([lv])); c.poke(WINS, bytes([3]))
        c.poke(head(c, 0) + 1, bytes([WALL])); step(c); c.wait(1.5)
        start_round(c, 2)
        assert count(c, [BLK]) == n, (lv, count(c, [BLK]))
    c.poke(WINS, bytes([1]))
    c.poke(head(c, 0) + 1, bytes([WALL]))
    step(c); c.wait(1.5)
    # top-5 board: made the cut -> type initials (matrix keys can't be injected: poke them, then finish entry)
    t = c.screen_text()
    assert "HIGH SCORES" in t and "TYPE INITIALS" in t, t
    assert c.peek(NEWROW)[0] == 0 and c.peek(HS_SC)[0] == 2 and c.peek(HI)[0] == 2
    c.poke(HS_NM, bytes([1, 2, 3])); c.poke(POS, bytes([3])); c.poke(ENTRY, bytes([0])); c.wait(0.3)
    rows = c.screen_text().splitlines()
    assert "1  ABC   02" in rows[8] and "2  ---   00" in rows[10] and "PRESS FIRE" in rows[20], rows
    c.screenshot(OUT / "snake6.png")
    fire(c, 2); c.wait(0.5)
    assert "<      SOLO       >" in c.screen_text()

    # score 0 never qualifies: plain game over, then the board unchanged
    start_round(c, 2)
    c.poke(WINS, bytes([1]))
    c.poke(head(c, 0) + 1, bytes([WALL]))
    step(c); c.wait(1.5)
    assert "GAME OVER" in c.screen_text()
    fire(c, 2); c.wait(0.5)
    rows = c.screen_text().splitlines()
    assert "HIGH SCORES" in "".join(rows) and "TYPE INITIALS" not in "".join(rows) and "1  ABC   02" in rows[8]
    assert c.peek(NEWROW)[0] == 0xFF
    fire(c, 2); c.wait(0.5)
    assert "<      SOLO       >" in c.screen_text()

    # a tie ranks below the older entry
    start_round(c, 2)
    c.poke(WINS, bytes([1])); c.poke(SCORE, bytes([2]))
    c.poke(head(c, 0) + 1, bytes([WALL]))
    step(c); c.wait(1.5)
    assert c.peek(NEWROW)[0] == 1 and c.peek(HS_SC, 2) == bytes([2, 2]), (c.peek(NEWROW), c.peek(HS_SC, 5))
    assert c.peek(HS_NM, 6) == bytes([1, 2, 3, 0x2D, 0x2D, 0x2D])
    # a better score goes on top and pushes the rest down
    c.poke(ENTRY, bytes([0])); c.poke(HS_NM + 3, bytes([4, 5, 6]))
    fire(c, 2); c.wait(0.5)
    fire(c, 2); c.wait(0.5)
    start_round(c, 2)
    c.poke(WINS, bytes([1])); c.poke(SCORE, bytes([0x12]))
    c.poke(head(c, 0) + 1, bytes([WALL]))
    step(c); c.wait(1.5)
    assert c.peek(NEWROW)[0] == 0 and c.peek(HS_SC, 3) == bytes([0x12, 2, 2]) and c.peek(HI)[0] == 0x12
    assert c.peek(HS_NM + 3, 6) == bytes([1, 2, 3, 4, 5, 6])
    print("snake ok")
