import sys
from pathlib import Path

from retro import BUILD, C64, assemble

CTX = 0xC160  # the active player's state (P1 between frames), field offsets as in tetris.asm
PX, PY, PID, CELLS, GCNT, SCORE, LINES, NXT, GARB, DFULL, GST = (CTX + o for o in (0, 1, 2, 4, 13, 15, 18, 22, 23, 29, 31))
BOARD = 0xC000
KINJ, KCH = 0x33D, 0x33F  # agent key input: hotkey bits P 1, G 2, M 4, H 8; one letter as getkey returns it (IRQs are off: no KERNAL key buffer)
SND, MON, MI = 0xC129, 0xC131, 0xC132
SCR = 0x400

prg = assemble(Path(__file__).with_name("tetris.asm"))
with C64() as c:
    c.start(prg)
    if sys.argv[1:] == ["play"]:  # interactive: play with VICE's joystick keys until the window is closed
        c.resume()
        c.proc.wait()
        sys.exit()
    c.wait(1)
    t = c.screen_text()
    assert "PRESS FIRE" in t and "SCORE" not in t, t  # title screen
    assert c.peek(SCR + 120, 200).count(69) == 51, "title blocks"
    assert c.peek(MON)[0] == 1, "title music"
    c.screenshot(BUILD / "c64" / "tetris0.png")
    c.poke(KINJ, bytes([8])); c.wait(0.3)  # H on the title: high-score board, fire returns to the title
    t = c.screen_text()
    assert "HIGH SCORES" in t and "1. ---" in t and "5. ---" in t, t
    c.joyport("fire", port=1); c.wait(0.3); c.joyport(port=1); c.wait(0.3)  # either port's fire (or space) leaves it
    t = c.screen_text()
    assert "PRESS FIRE" in t and "HIGH SCORES" not in t, t
    c.joyport("fire"); c.wait(0.3); c.joyport()
    c.wait(1)
    t = c.screen_text()
    assert "PRESS FIRE" not in t and "SCORE" in t and "LINES" in t and "NEXT" in t and "LEVEL" in t, t
    assert c.peek(0xD018)[0] & 0xFE == 0x1C and c.peek(0x3000 + 64 * 8, 2) == bytes([0x55, 0x7F]), "custom charset"
    assert c.peek(0xD016)[0] & 0x10, "multicolour text off"
    assert c.peek(SCR + 40 + 10)[0] == 68 and c.peek(SCR + 40 + 31)[0] == 68, "walls"
    ghosts = lambda: c.peek(SCR, 1000).count(66)
    assert ghosts() == 0, "ghost should be off by default"
    c.poke(KINJ, bytes([2])); c.wait(0.3)
    assert ghosts() == 4, "G should show the ghost"
    c.poke(KINJ, bytes([2])); c.wait(0.3)
    assert ghosts() == 0, "G again should hide it"
    # preview: 4 blocks (left halves) in the 4x4-cell box at screen row 6, col 32
    assert sum(c.peek(SCR + 6 * 40 + 32 + 40 * r, 8).count(64) for r in range(4)) == 4
    c.screenshot(BUILD / "c64" / "tetris1.png")

    # music: melody advances; M stops, M restarts
    mi = c.peek(MI)[0]
    c.wait(1)
    assert c.peek(MI)[0] != mi, "melody not advancing"
    c.poke(KINJ, bytes([4])); c.wait(0.3)
    assert c.peek(MON)[0] == 0, "M should stop music"
    c.poke(KINJ, bytes([4])); c.wait(0.3)
    assert c.peek(MON)[0] == 1, "M again should restart music"

    # move left/right
    x0 = c.peek(PX)[0]
    c.joyport("left"); c.wait(0.3); c.joyport()
    x1 = c.peek(PX)[0]
    assert x1 < x0, (x0, x1)
    c.joyport("right"); c.wait(0.3); c.joyport()
    assert c.peek(PX)[0] > x1

    # rotate (fire edge) changes the cells (unless it is the O piece)
    c.poke(PID, bytes([2]))  # force T piece
    c.poke(CELLS, bytes([0, 1, 1, 1, 2, 1, 1, 0]))
    c.poke(PX, bytes([3])); c.poke(PY, bytes([5]))
    before = c.peek(CELLS, 8)
    c.joyport("fire"); c.wait(0.2); c.joyport(); c.wait(0.1)
    assert c.peek(CELLS, 8) != before

    # gravity
    y0 = c.peek(PY)[0]
    c.wait(1.2)
    assert c.peek(PY)[0] > y0 or c.peek(PY)[0] == 0  # fell, or locked and respawned

    # pause: P freezes the piece and hides the well, P again resumes
    c.poke(KINJ, bytes([1])); c.wait(0.3)
    assert "PAUSED" in c.screen_text()
    y = c.peek(PY)[0]; c.wait(1)
    assert c.peek(PY)[0] == y, "piece moved while paused"
    c.poke(KINJ, bytes([1])); c.wait(0.3)
    assert "PAUSED" not in c.screen_text()

    # soft drop: 1 point per row fallen while down is held
    c.joyport("down"); c.wait(0.5); c.joyport()
    assert c.peek(SCORE)[0] > 0, "soft drop gives no points"
    c.poke(SCORE, bytes(3))

    # line clear: bottom row full except x=9; drop a vertical bar into the gap
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 190, bytes([1] * 9))
    c.poke(CELLS, bytes([0, 0, 0, 1, 0, 2, 0, 3]))
    c.poke(PX, bytes([9])); c.poke(PY, bytes([16]))
    n = c.peek(NXT)[0]
    for _ in range(80):  # poll until lines==1; SID regs are write-only, so check the sfx state
        c.wait(0.05)
        if c.peek(LINES)[0] == 1:
            break
    assert c.peek(SND)[0] > 0, "no line-clear sound"
    c.wait(2)
    assert c.peek(SND)[0] == 0, "sound stuck on"
    assert c.peek(0xD016)[0] & 0x1F == 0x18 and c.peek(0xD011)[0] & 0x7F == 0x1B, "shake not reset"
    assert c.peek(PID)[0] == n, "next piece not spawned"  # pid == previous nxt
    assert c.peek(LINES, 2) == bytes([1, 0]), c.peek(LINES, 2)
    assert c.peek(SCORE, 3) == bytes([0x40, 0, 0]), c.peek(SCORE, 3)
    row = c.peek(BOARD + 190, 10)  # bar's 3 leftover cells shifted down into x=9
    assert row[:9] == bytes(9) and row[9] != 0, row
    c.screenshot(BUILD / "c64" / "tetris2.png")

    # game over, then fire restarts
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 4, bytes([1] * 4)); c.poke(BOARD + 14, bytes([1] * 4))
    c.poke(CELLS, bytes([1, 0, 2, 0, 1, 1, 2, 1]))  # O at the top, locks at once
    c.poke(PX, bytes([3])); c.poke(PY, bytes([0]))
    c.wait(2)
    t = c.screen_text()
    assert "GAME OVER" in t, t
    assert c.peek(MON)[0] == 0, "music should stop at game over"
    c.screenshot(BUILD / "c64" / "tetris3.png")
    c.joyport("fire"); c.wait(0.5); c.joyport()
    t = c.screen_text()  # score 000040 made the board: type initials
    assert "NAME + RETURN" in t and "1. ---" in t, t
    for ch in (1, 2, 3, 4, 0x80, 0x80, 3, 0x81):  # A B C, a 4th letter is ignored, DEL DEL, C, RETURN: "AC" is too short to finish
        c.poke(KCH, bytes([ch])); c.wait(0.1)
    c.wait(0.4)
    t = c.screen_text()
    assert "1. A-" not in t and "NAME + RETURN" in t, t  # only 2 letters in: RETURN doesn't end it yet
    c.poke(KCH, bytes([2])); c.wait(0.1); c.poke(KCH, bytes([0x81])); c.wait(0.4)
    t = c.screen_text()
    assert "1. ACB 000040" in t and "NAME + RETURN" not in t, t
    c.screenshot(BUILD / "c64" / "tetris4.png")
    c.joyport("fire"); c.wait(0.5); c.joyport(); c.wait(0.5)
    t = c.screen_text()
    assert "GAME OVER" not in t and "SCORE" in t and "HI " in t and c.peek(SCR + 17 * 40 + 2, 6) == b"000040", t
    assert c.peek(SCORE, 3) == bytes(3)
    assert c.peek(MON)[0] == 1, "music should restart"

    # ---------------------------------------------------------------- 2 players
    # P1 lives in CTX (0xC160) between frames; P2 in PC2 (0xC1A0), board at BOARD2. P2's state is only
    # valid while waitframe spins (IDLE), so poke/peek it right after idle().
    PLAYERS, IDLE, PC2, BOARD2 = 0xC13D, 0xC143, 0xC1A0, 0xC300
    garb2 = PC2 + GARB - CTX  # P2's garbage queue

    def idle():
        for _ in range(300):
            if c.peek(IDLE)[0]:
                return
            c.run(0.003)
        raise AssertionError("machine never idle")

    def until(cond, secs=6):
        for _ in range(int(secs / 0.1)):
            c.run(0.1)
            idle()
            if cond():
                return
        raise AssertionError("timeout")

    O_PIECE = bytes([1, 0, 2, 0, 1, 1, 2, 1])  # O at px 3 occupies cols 4-5
    c.reload(prg); c.wait(1)
    c.joyport("right"); c.wait(0.3); c.joyport(); c.wait(0.3)  # right on the title picks 2 players
    t = c.screen_text()
    assert "2 PLAYERS" in t, t
    c.joyport("left"); c.wait(0.3); c.joyport(); c.wait(0.3)
    t = c.screen_text()
    assert "1 PLAYER" in t and "2 PLAYERS" not in t, t
    c.joyport("right"); c.wait(0.3); c.joyport(); c.wait(0.3)
    c.joyport("fire"); c.wait(0.3); c.joyport(); c.wait(1)
    t = c.screen_text()
    assert "P1" in t and "P2" in t and "LINES" in t and "GARB" in t and "SCORE" not in t, t
    assert c.peek(PLAYERS)[0] == 2
    for col in (1, 12, 27, 38):
        assert c.peek(SCR + 40 + col)[0] == 68 and c.peek(SCR + 20 * 40 + col)[0] == 68, f"wall col {col}"
    assert c.peek(SCR + 21 * 40 + 1, 12) == bytes([68] * 12) and c.peek(SCR + 21 * 40 + 27, 12) == bytes([68] * 12)
    c.screenshot(BUILD / "c64" / "tetris2p0.png")
    idle()
    assert c.peek(PID)[0] == c.peek(PC2 + 2)[0] and c.peek(NXT)[0] == c.peek(PC2 + 22)[0], "players should share the piece sequence"
    # inputs: port 2 joystick = P1, port 1 joystick = P2
    x1, x2 = c.peek(PX)[0], c.peek(PC2)[0]
    c.joyport("left"); c.wait(0.3); c.joyport(); idle()
    assert c.peek(PX)[0] < x1 and c.peek(PC2)[0] == x2, "port 2 should move P1 only"
    x1 = c.peek(PX)[0]
    c.joyport("right", port=1); c.wait(0.3); c.joyport(port=1); idle()
    assert c.peek(PC2)[0] > x2 and c.peek(PX)[0] == x1, "port 1 should move P2 only"
    # drawn cells: 1 char per cell, a piece is 4 blocks per board
    blocks = lambda x0: sum(c.peek(SCR + 40 + 40 * r + x0, 10).count(69) for r in range(20))
    assert blocks(2) == 4 and blocks(28) == 4, (blocks(2), blocks(28))
    assert sum(c.peek(SCR + 5 * 40 + 14 + 40 * r, 4).count(69) for r in range(2)) == 4, "P1 next preview"
    assert sum(c.peek(SCR + 5 * 40 + 21 + 40 * r, 4).count(69) for r in range(2)) == 4, "P2 next preview"

    # P1 clears 2 rows -> 1 garbage row queued for P2, applied (hole in the bottom row) at P2's next lock
    idle()
    c.poke(BOARD, bytes(200))
    c.poke(BOARD + 180, bytes([1] * 9)); c.poke(BOARD + 190, bytes([1] * 9))
    c.poke(CELLS, bytes([0, 0, 0, 1, 0, 2, 0, 3])); c.poke(PX, bytes([9])); c.poke(PY, bytes([16]))
    c.poke(BOARD2, bytes(200))
    until(lambda: c.peek(LINES)[0] == 2)
    assert c.peek(garb2)[0] == 1, "garbage not queued for P2"
    assert c.peek(GARB)[0] == 0, "P1 should get no garbage"
    assert c.peek(SCR + 18 * 40 + 21)[0] == 0x31, "P2's GARB stat should show the queued row"
    c.poke(PC2 + 4, O_PIECE); c.poke(PC2, bytes([3])); c.poke(PC2 + 1, bytes([18]))  # P2's piece locks next tick
    until(lambda: c.peek(garb2)[0] == 0)
    assert c.peek(SCR + 18 * 40 + 21)[0] == 0x30, "P2's GARB stat should be back to 0"
    row = c.peek(BOARD2 + 190, 10)
    assert row.count(0) == 1, row
    assert c.peek(BOARD2 + 174, 2) != bytes(2) and c.peek(BOARD2 + 184, 2) != bytes(2), "O should have moved up a row"
    c.wait(0.3); c.screenshot(BUILD / "c64" / "tetris2p1.png")
    assert row.count(8) == 9 and c.peek(SCR + 20 * 40 + 28, 10).count(75) == 9, (row, c.peek(SCR + 20 * 40 + 28, 10))

    # ghost lands via the column heights, or via fits when the piece slides under an overhang
    ghosts = lambda: [(y, x) for y in range(20) for x in range(10) if c.peek(SCR + 40 + 40 * y + 2 + x)[0] == 74]
    c.poke(KINJ, bytes([2])); c.wait(0.2); idle()
    c.poke(BOARD, bytes(200)); c.poke(BOARD + 190, bytes([1] * 5))  # row 19, cols 0-4
    c.poke(CELLS, O_PIECE); c.poke(PX, bytes([3])); c.poke(PY, bytes([2])); c.poke(DFULL, bytes([1])); c.poke(GCNT, bytes([1]))  # board changed, gravity next frame
    c.wait(0.2)
    assert ghosts() == [(17, 4), (17, 5), (18, 4), (18, 5)], ghosts()
    idle()
    c.poke(PX, bytes([2])); c.poke(GST, bytes([1])); c.poke(GCNT, bytes([1]))  # moved left, same landing row: the old outline goes
    c.wait(0.2)
    assert ghosts() == [(17, 3), (17, 4), (18, 3), (18, 4)], ghosts()
    idle()
    c.poke(BOARD, bytes(200)); c.poke(BOARD + 54, bytes([1]))  # block at row 5, col 4: O at row 8 sits under it
    c.poke(PX, bytes([3])); c.poke(PY, bytes([8])); c.poke(DFULL, bytes([1])); c.poke(GCNT, bytes([1]))
    c.wait(0.2)
    assert ghosts() == [(18, 4), (18, 5), (19, 4), (19, 5)], ghosts()
    c.poke(KINJ, bytes([2])); c.wait(0.2)
    assert ghosts() == [], (ghosts(), c.peek(0xC12F)[0])

    # pause freezes both players, P resumes and repaints the stats
    c.poke(KINJ, bytes([1])); c.wait(0.3)
    assert "PAUSED" in c.screen_text()
    y = c.peek(PY)[0]; c.wait(1)
    assert c.peek(PY)[0] == y, "P1 moved while paused"
    c.poke(KINJ, bytes([1])); c.wait(0.3)
    t = c.screen_text()
    assert "PAUSED" not in t and "LINES" in t, t

    # P2 tops out (its next piece can't spawn): P1 wins, fire starts over
    idle()
    c.poke(BOARD2, bytes(200)); c.poke(BOARD2 + 3, bytes([1] * 4))
    c.poke(PC2 + 4, O_PIECE); c.poke(PC2, bytes([3])); c.poke(PC2 + 1, bytes([18]))
    until(lambda: "P1 WINS" in c.screen_text())
    assert c.peek(MON)[0] == 0, "music should stop"
    c.screenshot(BUILD / "c64" / "tetris2p2.png"); c.wait(0.3)
    c.joyport("fire"); c.wait(0.5); c.joyport(); c.wait(0.5)
    t = c.screen_text()  # back at the title, 2 players still selected
    assert "WINS" not in t and "PRESS FIRE" in t and "2 PLAYERS" in t, t
    c.joyport("fire"); c.wait(0.3); c.joyport(); c.wait(1)
    t = c.screen_text()
    assert "GARB" in t and c.peek(BOARD2, 200) == bytes(200), t
    assert c.peek(MON)[0] == 1 and c.peek(PLAYERS)[0] == 2

    # garbage that pushes a block off the top loses: P1's top row is occupied and it has garbage waiting
    idle()
    c.poke(BOARD, bytes(200)); c.poke(BOARD + 9, bytes([1]))
    c.poke(GARB, bytes([1]))
    c.poke(CELLS, O_PIECE); c.poke(PX, bytes([3])); c.poke(PY, bytes([18]))
    until(lambda: "P2 WINS" in c.screen_text()); c.wait(0.3)  # fire held while the banner appears is ignored
    assert c.peek(SCR + 20 * 40 + 2, 10).count(75) == 9, "the fatal garbage row should be on screen under the banner"
    c.joyport("fire"); c.wait(0.5); c.joyport(); c.wait(0.5)
    t = c.screen_text()
    assert "WINS" not in t and "PRESS FIRE" in t, t
    c.joyport("left"); c.wait(0.3); c.joyport(); c.wait(0.3)  # left on the title: back to 1 player
    c.joyport("fire"); c.wait(0.3); c.joyport(); c.wait(1)
    t = c.screen_text()
    assert "SCORE" in t and "GARB" not in t and c.peek(PLAYERS)[0] == 1, t
    assert c.peek(SCR + 40 + 10)[0] == 68 and c.peek(SCR + 40 + 31)[0] == 68, "1P walls"
    print("tetris ok")
