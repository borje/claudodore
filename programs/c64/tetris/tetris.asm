; C64 Tetris. Joystick port 2: left/right move, down soft-drop, fire/up rotate. G toggles ghost, M music, P pauses.
; Title: left/right picks 1 or 2 players (a 2P round ends back at the title). 2 players (versus): P1 joystick port 2, P2 W/A/S/D or joystick port 1;
; clearing 2/3/4 rows sends 1/2/4 garbage rows (one hole) to the other board at their next lock; first to top out loses.
; Board 10x20 at BOARD (0 = empty, else colour 1-7). 1P: each cell = 2 screen chars (multicolour bevelled tile:
; D022 highlight, D023 shadow, colour RAM = body). 2P: 1 char per cell, board 2 at BOARD2. Screen $0400, charset in
; RAM at $3000, colour RAM $D800.
; SID: voice 1 pulse (PWM) melody, voice 2 triangle bass (Korobeiniki), voice 3 sound effects.
; IRQs stay off: waitframe syncs on the raster and readin scans the keyboard matrix itself.
SCR    = $0400
COL    = $d800
BOARD  = $c000
BOARD2 = $c300
SEQ    = $c400          ; shared piece sequence, 256-entry ring
CHARS  = $3000
PV     = SCR+6*40+32            ; next-piece preview, 4 rows x 8 cols
FQ     = 17.0284                ; Hz -> SID freq (PAL clock)
KINJ   = $033d          ; agent input: bits P 1, G 2, M 4, H 8 are ORed into the new key presses, cleared once read
KCH    = $033f          ; agent input: a typed key as getkey returns it (screen code A-Z 1-26, $80 del), cleared once read
; zero page pointers
sptr   = $fb
cptr   = $fd
cpp    = $f7
; per-player state, CTX = the active player (P1 between frames; in 2P P2 is exchanged in for its step, see swapctx)
CTX    = $c160
px     = CTX
py     = CTX+1
pid    = CTX+2
pcol   = CTX+3
cells  = CTX+4          ; 4 x (x,y)
hcnt   = CTX+12
gcnt   = CTX+13
gint   = CTX+14
score  = CTX+15         ; 3 bytes BCD
lines  = CTX+18         ; 2 bytes BCD
lvl    = CTX+20
prev   = CTX+21
nxt    = CTX+22
garb   = CTX+23         ; garbage rows waiting for this player's next lock
ridx   = CTX+24         ; read index into SEQ
pn     = CTX+25         ; player number 0/1
c0     = CTX+26         ; screen column of board cell 0
ly     = CTX+27         ; 2P: piece row and ghost row as last drawn
lgy    = CTX+28
dfull  = CTX+29         ; 2P: board changed, repaint every row
gy     = CTX+30         ; 2P: ghost row (kept while only gravity moves the piece)
gst    = CTX+31         ; 2P: piece moved sideways/rotated, ghost row stale
hgt    = CTX+32         ; 2P: row of the top block per column (20 = empty), valid while ghost is on
CTXN   = 42
PC2    = $c1a0          ; P2 while P1 is active (and P1 while P2 is)
; variables
scells = $c100
t1     = $c114
t2     = $c115
t3     = $c116
row    = $c117
idx    = $c118
ci     = $c119
nlines = $c122
joy    = $c123
rnd    = $c125
dirty  = $c126
ncol   = $c128
snd    = $c129          ; sfx: frames left, pitch (SID hi byte), per-frame delta, waveform|gate
snote  = $c12a
sdelta = $c12b
swav   = $c12c
pch    = $c12d
cnt    = $c12e
ghost  = $c12f          ; 1 = show landing outline
mon    = $c131          ; music on
mi     = $c132          ; melody index
mcnt   = $c133          ; frames left in melody note
bi     = $c134          ; bass step 0-31
bcnt   = $c135
pwv    = $c136          ; pulse width LFO
mt     = $c137
fcol   = $c138          ; row flash colour
fcnt   = $c139
sfr    = $c13a          ; starfield frame counter
mt2    = $c13b
cur    = $c13c          ; player being stepped / the loser
players = $c13d         ; 1 or 2
cw     = $c13e          ; screen chars per board cell (2 in 1P, 1 in 2P)
tblk   = $c13f          ; tile codes: block, ghost
tgh    = $c140
wptr   = $c141          ; pieces generated into SEQ so far
redraw = $c142          ; G toggled: every board redraws
idle   = $c143          ; 1 while waitframe spins (agents poke/peek P2's state only then)
hk     = $c144          ; hotkeys held: P 1, G 2, M 4, H 8
hkp    = $c145
hkn    = $c146          ; newly pressed
fire   = $c147          ; any fire button or space
rmask  = $c148
jin    = $c149          ; 2 bytes: P1 = joystick port 2, P2 = W/A/S/D or joystick port 1
km     = $c14b          ; 8 bytes: keyboard matrix, one byte per column, bit set = key down
kmp    = $c158          ; 8 bytes: km at the last getkey
blo    = $c154          ; 2P: board rows to repaint
bhi    = $c155
HS_SC  = $c200         ; top 5 scores, 3 bytes BCD big-endian each (RAM only)
HS_NM  = $c20f          ; 5 x 3 screen codes
hnew   = $c21e          ; board row being entered, pos = letters typed
hpos   = $c21f
hent   = $c220          ; 1 = typing initials
harm   = $c221          ; fire seen released
CH_BLKL   = 64          ; custom tiles: block L/R, ghost L/R, wall, single block, blank L/R
CH_GHL    = 66
CH_WALL   = 68
CH_BLK1   = 69
CH_BLANKL = 70
CH_WELL   = 72          ; solid black cell for the well
CH_GH1    = 74          ; 1-char ghost (2P)
CH_GARB   = 75          ; 2P garbage cell (board value 8): greys only, so it can't be mistaken for a piece
N_A4 = 1
N_B4 = 2
N_C5 = 3
N_D5 = 4
N_E5 = 5
N_F5 = 6
N_G5 = 7
N_A5 = 8
J_UP   = $01
J_DN   = $02
J_LF   = $04
J_RT   = $08
J_FIRE = $10

!macro puts .dst, .src, .len {
        ldx #0
.l      lda .src,x
        sta .dst,x
        inx
        cpx #.len
        bne .l
}

!macro fill .dst, .col, .len {
        ldx #.len-1
        lda #.col
.l      sta .dst,x
        dex
        bpl .l
}

!macro cyc .row {               ; colour-cycle one title row
        ldx #21
.l      txa
        clc
        adc t1
        and #7
        tay
        lda pal,y
        sta COL+3*40+9+.row*40,x
        dex
        bpl .l
}

!macro trow .r {                ; title art row -> screen
        ldx #21
.l      lda title+.r*22,x
        cmp #35                 ; '#'
        bne .e
        lda #CH_BLK1
        bne .s
.e      lda #32
.s      sta SCR+3*40+9+.r*40,x
        dex
        bpl .l
}

!macro sound .hi, .fr, .dl, .wv {
        lda #.wv
        sta swav
        lda #.hi
        ldx #.fr
        ldy #.dl
        jsr sfx
}

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        sei                     ; IRQs stay off for good
        lda #<nmi               ; RUN/STOP+RESTORE: see nmi
        sta $0318
        lda #>nmi
        sta $0319
        jsr cls
        lda #14
        sta $d020
        lda #6
        sta $d021
        lda #15                 ; multicolour highlight (light grey) / shadow (dark grey)
        sta $d022
        lda #11
        sta $d023
        ; charset in RAM: copy of the ROM's first 64 chars + our tiles
        lda #$33                ; char ROM visible at $D000
        sta 1
        ldx #0
-       lda $d000,x
        sta CHARS,x
        lda $d100,x
        sta CHARS+$100,x
        inx
        bne -
        lda #$37
        sta 1
        ldx #12*8-1
-       lda tiles,x
        sta CHARS+CH_BLKL*8,x
        dex
        bpl -
        lda #$1c                ; screen $0400, charset $3000
        sta $d018
        lda #$18                ; multicolour text on, 40 cols
        sta $d016
        ; SID
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #$18
        sta $d405
        lda #$a6
        sta $d406
        lda #$08
        sta $d40c
        lda #$88
        sta $d40d
        lda #$08                ; sfx voice: pulse width 50%
        sta $d411
        lda #$09
        sta $d413
        lda #$a4
        sta $d414
        lda #$0f
        sta $d418
        ldx #0                  ; clear variables ($c100-$c1ff)
        txa
-       sta $c100,x
        inx
        bne -
        lda #1
        sta players
        jsr setmode
        ldx #14                 ; empty high-score table
-       lda #0
        sta HS_SC,x
        lda #$2d
        sta HS_NM,x
        dex
        bpl -
        jsr initstars
        lda $d012
        ora #1
        sta rnd
restart: jsr cls
        jsr intro
        lda players
        cmp #2
        bne setup
        jmp setup2
setup:  jsr cls                 ; clear for the game
        jsr walls
        +puts SCR+4*40+2, t_score, 5
        +puts SCR+8*40+2, t_lines, 5
        +puts SCR+12*40+2, t_level, 5
        +puts SCR+16*40+2, t_hi, 5
        +puts SCR+4*40+34, t_next, 4
        +fill COL+4*40+2, 3, 5
        +fill COL+8*40+2, 3, 5
        +fill COL+12*40+2, 3, 5
        +fill COL+16*40+2, 3, 5
        +fill COL+4*40+34, 3, 4
        lda sfr
        ora #1
        sta rnd
newgame:
        jsr setmode
        lda #0
        sta wptr
        sta redraw
        jsr initplayer          ; P1 in CTX
        lda players
        cmp #2
        bne +
        jsr swapctx             ; P2 built in CTX, then exchanged out
        lda #1
        jsr initplayer
        jsr swapctx
+       jsr musicstart

loop:
        jsr waitframe
        jsr readin
        jsr hotkeys
        lsr hkn                 ; P pauses, G toggles the ghost, M the music
        bcc +
        jsr pause
+       lsr hkn
        bcc +
        lda ghost
        eor #1
        sta ghost
        inc redraw
+       lsr hkn
        bcc +
        lda mon
        beq ++
        jsr musicstop
        jmp +
++      jsr musicstart
+       lda #0
        sta cur
        jsr step                ; P1
        bcs lost
        lda players
        cmp #2
        bne +
        jsr swapctx
        inc cur
        jsr step                ; P2
        php
        jsr swapctx
        plp
        bcs lost
+       lda #0
        sta redraw
        jmp loop
lost:   jmp gameover            ; cur = loser, CTX = P1 again

; one tick of the player in CTX: input, move, gravity, lock. C set if they topped out.
step:   lda redraw
        sta dirty
        beq +
        sta dfull
+        ldx pn
        lda jin,x
        sta joy
        ; rotate on press edge of up/fire
        lda prev
        eor #$ff
        and joy
        and #J_UP|J_FIRE
        beq +
        jsr rotate
        inc dirty
        inc gst
        +sound 45, 4, 5, $41
+       lda joy
        sta prev
        ; left/right with auto-repeat
        lda joy
        and #J_LF|J_RT
        bne +
        sta hcnt
        beq nohmove
+       lda hcnt
        beq hdo
        dec hcnt
        jmp nohmove
hdo:    lda #6
        sta hcnt
        lda joy
        and #J_LF
        beq hright
        dec px
        jsr fits
        beq hok
        inc px
        jmp nohmove
hright: inc px
        jsr fits
        beq hok
        dec px
        jmp nohmove
hok:    inc dirty
        inc gst
        +sound 28, 2, 0, $11
nohmove:
        ; gravity (down held = fast)
        dec gcnt
        lda joy
        and #J_DN
        beq +
        lda gcnt
        cmp #3
        bcc +
        lda #2
        sta gcnt
+       lda gcnt
        beq +
        jmp nograv
+       lda gint
        sta gcnt
        inc dirty
        inc py
        jsr fits
        bne +
        lda joy                 ; soft drop: 1 point per row fallen with down held (1P shows the score)
        and #J_DN
        beq nosd
        lda players
        cmp #2
        beq nosd
        sed
        clc
        lda score
        adc #1
        sta score
        lda score+1
        adc #0
        sta score+1
        lda score+2
        adc #0
        sta score+2
        cld
        jsr showstats
nosd:   jmp nograv
+       dec py
        jsr draw                ; make sure the final position is on screen
        jsr lock
        +sound 14, 5, $fd, $81
        jsr clear
        jsr garbapply           ; C: the garbage pushed the stack over the top
        bcs topped
        jsr spawn
        bne topped
        jsr showstats
nograv: lda dirty
        beq +
        jsr draw
+       clc
        rts
topped: sec
        rts

; round over, cur = loser. 1P: banner, fire, maybe the high-score board; 2P: winner banner, fire = rematch.
gameover:
        lda players
        cmp #2
        bne +
        jmp gameover2
+       jsr draw
        jsr showstats
        jsr musicstop
        +sound 90, 60, $ff, $21   ; falling saw
        +puts SCR+10*40+16, t_over, 9
        +puts SCR+12*40+15, t_fire, 10
        +fill COL+10*40+16, 1, 9
        +fill COL+12*40+15, 1, 10
-       jsr waitframe           ; wait for fire release, then press
        jsr readin
        lda fire
        bne -
-       jsr waitframe
        jsr readin
        lda fire
        beq -
        jsr insert
        bcc ngame
        lda #1
        jsr board
        jmp setup
ngame:  jmp newgame

gameover2:
        lda cur                 ; the loser's board as it ended: its last clear / the garbage that pushed it over isn't drawn yet
        beq +
        jsr swapctx
+       lda #0
        sta blo
        lda #19
        sta bhi
        jsr rows2
        lda cur
        beq +
        jsr swapctx
+       jsr musicstop
        +sound 90, 60, $ff, $21
        +puts SCR+11*40+16, t_win, 7
        lda cur                 ; winner = the other player
        eor #1
        clc
        adc #$31
        sta SCR+11*40+17
        +puts SCR+12*40+15, t_fire, 10
        +fill COL+11*40+16, 1, 7
        +fill COL+12*40+15, 1, 10
-       jsr waitframe           ; wait for fire release, then press
        jsr readin
        lda fire
        bne -
-       jsr waitframe
        jsr readin
        lda fire
        beq -
-       jsr waitframe           ; release, so the title doesn't start at once
        jsr readin
        lda fire
        bne -
        jmp restart

; title screen: raster bars, cycling TETRIS, blinking "press fire", pieces raining below; fire/any key starts
intro:
        +trow 0
        +trow 1
        +trow 2
        +trow 3
        +trow 4
        +puts SCR+11*40+15, t_fire, 10
        +puts SCR+10*40+15, t_lr, 10
        +fill COL+10*40+15, 12, 10
        +fill COL+9*40+15, 7, 9
        lda #11                 ; the raining piece uses the 1P tiles
        sta c0
        lda #2
        sta cw
        lda #CH_BLKL
        sta tblk
        jsr spawn
        lda #3
        sta px
        lda #12
        sta py
        lda #0
        sta cnt
        jsr musicstart
iloop:  jsr waitframe
        inc cnt
        lda cnt
        lsr
        lsr
        sta t1
        +cyc 0
        +cyc 1
        +cyc 2
        +cyc 3
        +cyc 4
        lda cnt
        and #$10
        bne boff
        +fill COL+11*40+15, 1, 10
        jmp bdone
boff:   +fill COL+11*40+15, 0, 10
bdone:  lda cnt
        and #3
        bne irain
        lda #CH_BLANKL          ; erase, move, redraw the raining piece
        sta pch
        jsr drawpiece
        inc py
        lda py
        cmp #18
        bcc rdraw
        jsr spawn
        jsr random7
        sta px
        lda #12
        sta py
rdraw:  lda #CH_BLKL
        sta pch
        jsr drawpiece
irain:  jsr bars
        jsr readin
        lda jin                 ; left = 1 player, right = 2 players
        ora jin+1
        sta t2
        and #J_LF
        beq +
        lda #1
        sta players
+       lda t2
        and #J_RT
        beq +
        lda #2
        sta players
+       jsr showmode
        lda fire
        bne istart
        lda km                  ; RETURN starts too
        and #2
        bne istart
        jsr hotkeys
        and #8                  ; H = high scores
        beq +
        lda #0
        jsr board
        jmp intro
+       jmp iloop
istart: +sound 50, 10, 5, $41
        rts

showmode:
        lda players
        cmp #2
        beq +
        +puts SCR+9*40+15, t_1p, 9
        rts
+       +puts SCR+9*40+15, t_2p, 9
        rts

; three raster bars (border + background) bobbing in their own screen bands
bars:
-       lda $d012               ; wait for the next frame's top
        cmp #200
        bcs -
        lda #0
        sta idx
bk:     ldx idx
        lda cnt
        lsr
        clc
        adc boff3,x
        and #31
        tay
        lda sine,y
        clc
        adc bbase,x
        sta t1
-       lda $d012
        cmp t1
        bcc -
        txa
        asl
        asl
        asl
        asl
        tax
        ldy #16
bl1:    lda barcol,x
        sta $d020
        sta $d021
        inx
        inc t1
-       lda $d012
        cmp t1
        bcc -
        dey
        bne bl1
        lda #14
        sta $d020
        lda #6
        sta $d021
        inc idx
        lda idx
        cmp #3
        bne bk
        rts

; sync to raster line 251 (start of the bottom border), then tick sound
waitframe:
        lda #1                  ; idle: agents poke/peek P2's state only now
        sta idle
-       lda $d012
        cmp #251
        bne -
        lda #0
        sta idle
        ; fall through

soundtick:
        txa
        pha
        tya
        pha
        jsr stars
        jsr music
        jsr sfxtick
        pla
        tay
        pla
        tax
        rts

; 8 star sprites (1 colour, behind chars) drifting down at different speeds, twinkling
initstars:
        ldx #63
        lda #0
-       sta CHARS+$280,x
        dex
        bpl -
        ldx #8
-       lda star,x
        sta CHARS+$280,x
        dex
        bpl -
        ldx #7
-       lda #CHARS/64+10
        sta SCR+$3f8,x
        txa
        asl
        tay
        lda sx,x
        sta $d000,y
        lda sy,x
        sta $d001,y
        dex
        bpl -
        lda #$c0
        sta $d010
        lda #$ff
        sta $d01b
        sta $d015
        rts

stars:  inc sfr
        lda sfr
        lsr
        lsr
        lsr
        sta mt2
        ldx #7
st1:    txa
        clc
        adc mt2
        and #7
        tay
        lda scol,y
        sta $d027,x
        lda sfr
        and smask,x
        bne st2
        txa
        asl
        tay
        lda $d001,y
        clc
        adc #1
        cmp #250
        bcc st3
        lda #50
st3:    sta $d001,y
st2:    dex
        bpl st1
        rts

sfxtick:
        lda snd
        beq +
        dec snd
        lda snote
        sta $d40f
        clc
        adc sdelta
        sta snote
        lda swav
        sta $d412
        rts
+       lda swav
        and #$fe
        sta $d412
        rts

; A = pitch (SID hi byte), X = frames, Y = delta per frame; waveform|gate in swav
sfx:    sta snote
        stx snd
        sty sdelta
        rts

musicstart:
        lda #1
        sta mcnt
        sta bcnt
        sta mon
        lda #0
        sta mi
        sta bi
        rts

musicstop:
        lda #0
        sta mon
        sta $d404
        sta $d40b
        rts

; one frame of music: melody on voice 1 (note,frames pairs, $ff = loop), bass on voice 2 (20 frames/step)
music:  lda mon
        bne +
        rts
+       lda pwv                 ; triangle LFO on the pulse width
        clc
        adc #2
        sta pwv
        bpl +
        eor #$7f
+       ora #$10
        sta mt
        asl
        asl
        asl
        asl
        asl
        sta $d402
        lda mt
        lsr
        lsr
        lsr
        sta $d403
        dec mcnt
        bne m1
        ldy mi
        lda mel,y
        cmp #$ff
        bne +
        ldy #0
        lda mel
+       tax
        lda mel+1,y
        sta mcnt
        iny
        iny
        sty mi
        txa
        beq mrest
        asl
        tax
        lda nf,x
        sta $d400
        lda nf+1,x
        sta $d401
        lda #$41
        sta $d404
        bne m2
mrest:  lda #$40
        sta $d404
        beq m2
m1:     lda mcnt                ; release on the last frame so repeated notes retrigger
        cmp #1
        bne m2
        lda #$40
        sta $d404
m2:     dec bcnt
        bne b1
        lda #20
        sta bcnt
        lda bi
        lsr
        and #$0e
        sta mt
        lda bi
        and #1
        ora mt
        asl
        tax
        lda bf,x
        sta $d407
        lda bf+1,x
        sta $d408
        lda #$11
        sta $d40b
        lda bi
        clc
        adc #1
        and #31
        sta bi
        rts
b1:     lda bcnt
        cmp #1
        bne +
        lda #$10
        sta $d40b
+       rts

random7:
        lda rnd
        asl
        bcc +
        eor #$1d
+       sta rnd
        eor sfr
-       cmp #7
        bcc +
        sbc #7
        bcs -
+       rts

; new piece at top; Z set if it fits
spawn:
        lda nxt
        sta pid
        jsr getseq
        sta nxt
        ldx pid
        lda pcols,x
        sta pcol
        txa
        asl
        asl
        asl
        tax
        ldy #0
-       lda shapes,x
        sta cells,y
        inx
        iny
        cpy #8
        bne -
        lda #3
        sta px
        lda #0
        sta py
        ; fall through

; A=0/Z set if the piece at px,py doesn't collide
fits:
        ldy #0
-       lda cells,y
        clc
        adc px
        cmp #10
        bcs bad
        sta t1
        lda cells+1,y
        clc
        adc py
        cmp #20
        bcs bad
        sta t2
        asl
        asl
        asl
        sta t3
        lda t2
        asl
        clc
        adc t3                  ; 10*y
        clc
        adc t1
        tax
bpa:    lda BOARD,x             ; (the BOARD operands are patched to the active board's page by setboard)
        bne bad
        iny
        iny
        cpy #8
        bne -
        lda #0
        rts
bad:    lda #1
        rts

; rotate clockwise in the n x n box; try kicking 1 right / 1 left; O doesn't rotate
rotate:
        lda pid
        cmp #1
        beq rdone
        ldy #7
-       lda cells,y
        sta scells,y
        dey
        bpl -
        ldx pid
        lda psize,x
        sta t3
        ldy #0
-       lda cells,y
        sta t1
        lda t3
        sec
        sbc #1
        sec
        sbc cells+1,y
        sta cells,y
        lda t1
        sta cells+1,y
        iny
        iny
        cpy #8
        bne -
        jsr fits
        beq rdone
        inc px
        jsr fits
        beq rdone
        dec px
        dec px
        jsr fits
        beq rdone
        inc px
        ldy #7
-       lda scells,y
        sta cells,y
        dey
        bpl -
rdone:  rts

lock:
        lda #1
        sta dfull
        ldy #0
-       lda cells,y
        clc
        adc px
        sta t1
        lda cells+1,y
        clc
        adc py
        sta t2
        asl
        asl
        asl
        sta t3
        lda t2
        asl
        clc
        adc t3
        clc
        adc t1
        tax
        lda pcol
bpb:    sta BOARD,x
        iny
        iny
        cpy #8
        bne -
        rts

; remove full rows, update score/lines/speed
clear:
        lda #0
        sta nlines
        lda #19
        sta row
cf1:    jsr rowfull
        bne +
        inc nlines
+       dec row
        bpl cf1
        lda nlines
        beq +
        ldx players             ; no blocking flash in 2P: the other board keeps running
        cpx #2
        beq +
        lda #8                  ; let the flash show, shaking the screen
        sta fcnt
-       jsr waitframe
        jsr flashall
        ldx fcnt
        lda shk,x
        ora #$18
        sta $d016
        lda shk,x
        and #3
        ora #$18
        sta $d011
        dec fcnt
        bne -
        lda #$18
        sta $d016
        lda #$1b
        sta $d011
+       lda #19
        sta row
cl1:    jsr rowfull
        bne cl2
        jsr rmrow
        jmp cl1
cl2:    dec row
        bpl cl1
        ldx nlines
        beq +
        jsr sendgarb
        ldx nlines
        sed
        lda lvl                 ; score += pts * (level + 1)
        sta t1
-       clc
        lda score
        adc ptslo,x
        sta score
        lda score+1
        adc pthi,x
        sta score+1
        lda score+2
        adc #0
        sta score+2
        dec t1
        bpl -
        clc
        lda lines
        adc nlines
        sta lines
        lda lines+1
        adc #0
        sta lines+1
        cld
        lda lines+1             ; level = tens digit (9 from 100 lines on)
        beq lv1
        lda #9
        bne lv2
lv1:    lda lines
        lsr
        lsr
        lsr
        lsr
lv2:    sta lvl
        tax
        lda gtab,x              ; NES frames per row
        sta gint
        lda #$41                ; rising sweep, longer for bigger clears
        sta swav
        lda nlines
        asl
        asl
        clc
        adc #8
        tax
        lda #30
        ldy #3
        jsr sfx
+       rts

; Z set if board row `row` is full
rowfull:
        jsr rowidx
        ldy #10
-
bpc:    lda BOARD,x
        beq +
        inx
        dey
        bne -
        lda #0
        rts
+       lda #1
        rts

; rainbow-colour every full row
flashall:
        lda #19
        sta row
fa1:    jsr rowfull
        bne +
        lda fcnt
        clc
        adc row
        and #7
        tax
        lda pal,x
        sta fcol
        jsr flashrow
+       dec row
        bpl fa1
        rts

; recolour screen row `row` with fcol
flashrow:
        ldx row
        lda scrlo,x
        sta cptr
        lda scrhi,x
        clc
        adc #$d4
        sta cptr+1
        lda fcol
        ldy #20
-       sta (cptr),y
        dey
        bne -
        rts

; X = 10*row
rowidx:
        lda row
        asl
        sta t3
        asl
        asl
        clc
        adc t3
        tax
        rts

; drop everything above `row` by one, clear top row
rmrow:
        lda #1
        sta dfull
        jsr rowidx
        txa
        clc
        adc #9
        tax
-       cpx #10
        bcc +
bpd:    lda BOARD-10,x
bpe:    sta BOARD,x
        dex
        jmp -
+       ldx #9
        lda #0
-
bpf:    sta BOARD,x
        dex
        bpl -
        rts

draw:
        lda players
        cmp #2
        bne +
        jmp draw2
+       lda #0
        sta row
        sta idx
dr1:    ldx row
        lda scrlo,x
        sta sptr
        sta cptr
        lda scrhi,x
        sta sptr+1
        clc
        adc #$d4                ; colour RAM = screen + $D400
        sta cptr+1
        ldy #1
dr2:    ldx idx
bpg:    lda BOARD,x
        beq dr5
        ora #8                  ; multicolour body colour
        tax
        lda #CH_BLKL
        bne dr3
dr5:    ldx #8                  ; black multicolour
        lda #CH_WELL
dr3:    sta (sptr),y
        pha
        txa
        sta (cptr),y
        iny
        sta (cptr),y
        pla
        clc
        adc #1
        sta (sptr),y
        iny
        inc idx
        cpy #21
        bne dr2
        inc row
        lda row
        cmp #20
        bne dr1
dtail:  lda ghost
        beq noghost
        lda py                  ; ghost: where it would land
        pha
-       inc py
        jsr fits
        beq -
        dec py
        lda tgh
        sta pch
        jsr drawpiece
        pla
        sta py
noghost:
        lda tblk
        sta pch
        ; fall through

; draw the 4 cells of the current piece with tile `pch` (+1 for the right half in 1P)
drawpiece:
        lda #0
        sta ci
dr4:    ldx ci
        lda cells,x
        clc
        adc px
        ldy cw
        cpy #2
        bne +
        asl
+       clc
        adc c0
        sta t1
        lda cells+1,x
        clc
        adc py
        tax
        lda scr0lo,x
        clc
        adc t1
        sta sptr
        sta cptr
        lda scr0hi,x
        adc #0
        sta sptr+1
        clc
        adc #$d4
        sta cptr+1
        lda pcol
        ora #8
        tax
        ldy #0
        lda pch
        sta (sptr),y
        txa
        sta (cptr),y
        lda cw
        cmp #2
        bne +
        iny
        lda pch
        clc
        adc #1
        sta (sptr),y
        txa
        sta (cptr),y
+       inc ci
        inc ci
        lda ci
        cmp #8
        bne dr4
        rts

walls:
        ldx #0
wl:     lda scrlo,x
        sta sptr
        sta cptr
        lda scrhi,x
        sta sptr+1
        clc
        adc #$d4
        sta cptr+1
        cpx #20
        beq wbot
        ldy #0
        jsr wput
        ldy #21
        jsr wput
        inx
        bne wl
wbot:   ldy #21
-       jsr wput
        dey
        bpl -
        rts
wput:   lda #CH_WALL
        sta (sptr),y
        lda #$0a                ; red bricks, grey mortar (multicolour)
        sta (cptr),y
        rts

; clear the screen (not the sprite pointers) and colour RAM to white. The KERNAL's CHROUT would re-enable IRQs.
cls:    ldx #0
-       lda #32
        sta SCR,x
        sta SCR+$100,x
        sta SCR+$200,x
        sta SCR+$2e8,x
        lda #1
        sta COL,x
        sta COL+$100,x
        sta COL+$200,x
        sta COL+$2e8,x
        inx
        bne -
        rts

; ---------------------------------------------------------------- 2 players
; 2P screen: board 1 at cells 2-11 (walls 1/12), board 2 at cells 28-37 (walls 27/38), stats in the middle.
setup2: jsr cls
        jsr walls2
        +puts SCR+2*40+14, t_p1, 2
        +puts SCR+2*40+21, t_p2, 2
        +puts SCR+4*40+14, t_next, 4
        +puts SCR+4*40+21, t_next, 4
        +puts SCR+9*40+14, t_lines, 5
        +puts SCR+9*40+21, t_lines, 5
        +puts SCR+13*40+14, t_level, 5
        +puts SCR+13*40+21, t_level, 5
        +puts SCR+17*40+14, t_garb, 4
        +puts SCR+17*40+21, t_garb, 4
        +fill COL+2*40+14, 7, 2
        +fill COL+2*40+21, 2, 2
        +fill COL+4*40+14, 3, 4
        +fill COL+4*40+21, 3, 4
        +fill COL+9*40+14, 3, 5
        +fill COL+9*40+21, 3, 5
        +fill COL+13*40+14, 3, 5
        +fill COL+13*40+21, 3, 5
        +fill COL+17*40+14, 3, 4
        +fill COL+17*40+21, 3, 4
        lda sfr
        ora #1
        sta rnd
        jmp newgame

walls2:
        ldx #0
w2l:    lda scr0lo,x
        sta sptr
        sta cptr
        lda scr0hi,x
        sta sptr+1
        clc
        adc #$d4
        sta cptr+1
        cpx #20
        beq w2b
        ldy #1
        jsr wput
        ldy #12
        jsr wput
        ldy #27
        jsr wput
        ldy #38
        jsr wput
        inx
        bne w2l
w2b:    ldy #12
-       jsr wput
        dey
        bne -
        ldy #38
-       jsr wput
        dey
        cpy #26
        bne -
        rts

; 2P draw: the board rows the piece or ghost touched now or at the last draw (all if the board changed), then ghost + piece
draw2:  lda ghost
        beq +
        lda gst                 ; ghost landing row, unless only gravity moved the piece
        ora dfull
        beq +
        lda dfull
        beq +++
        jsr calch
+++     jsr ghostrow
+       lda dfull
        beq d2b
        lda #0
        sta dfull
        sta blo
        lda #19
        sta bhi
        bne d2r
d2b:    lda py
        sta blo
        sta bhi
        lda ly
        jsr span
        lda ghost               ; the ghost's rows when it moved: a new landing row, or sideways/rotated at the same one
        beq +
        lda gy
        cmp lgy
        bne ++
        lda gst
        beq +
++      lda gy
        jsr span
        lda lgy
        jsr span
+       lda bhi
        clc
        adc #3
        cmp #20
        bcc +
        lda #19
+       sta bhi
d2r:    jsr rows2
        lda ghost
        beq +
        lda py
        pha
        lda gy
        sta py
        lda tgh
        sta pch
        jsr drawpiece
        pla
        sta py
+       lda tblk
        sta pch
        jsr drawpiece
        lda py
        sta ly
        lda gy
        sta lgy
        lda #0
        sta gst
        rts

; repaint board rows blo..bhi of the active board
rows2:  lda blo
        sta row
d21:    jsr rowidx
        stx idx
        ldx row
        lda scr0lo,x
        clc
        adc c0
        sta sptr
        sta cptr
        lda scr0hi,x
        adc #0
        sta sptr+1
        clc
        adc #$d4
        sta cptr+1
        ldy #0
d22:    ldx idx
bpg2:   lda BOARD,x
        beq d23
        ora #8
        tax
        lda #CH_BLK1
        cpx #8                  ; 8 = garbage
        bne d24
        lda #CH_GARB
        bne d24
d23:    ldx #8
        lda #CH_WELL
d24:    sta (sptr),y
        txa
        sta (cptr),y
        inc idx
        iny
        cpy #10
        bne d22
        inc row
        lda bhi
        cmp row
        bcs d21
        rts

; top block row of every column of the active board -> hgt
calch:  ldy #9
ch1:    sty t1
        ldx t1
        lda #0
        sta t2
ch2:
bph2:   lda BOARD,x
        bne ch3
        inc t2
        txa
        clc
        adc #10
        tax
        cpx #200
        bcc ch2
ch3:    ldy t1
        lda t2
        sta hgt,y
        dey
        bpl ch1
        rts

; gy = row the piece lands on. Straight from the column heights when all 4 cells are above their column's top
; block, else (sliding under an overhang) by dropping it with fits.
ghostrow:
        lda #$ff
        sta t3
        ldy #0
gr1:    lda cells,y
        clc
        adc px
        tax
        lda hgt,x
        sec
        sbc cells+1,y
        bcc gslow
        sbc #1
        bcc gslow
        cmp py
        bcc gslow
        cmp t3
        bcs +
        sta t3
+       iny
        iny
        cpy #8
        bne gr1
        lda t3
        sta gy
        rts
gslow:  lda py
        pha
-       inc py
        jsr fits
        beq -
        dec py
        lda py
        sta gy
        pla
        sta py
        rts

; blo/bhi widened to include A
span:   cmp blo
        bcs +
        sta blo
+       cmp bhi
        bcc +
        sta bhi
+       rts

; level, lines and garbage of the active player under its heading, then its next piece
showstats2:
        ldx pn
        ldy sct,x
        lda lines+1
        jsr bcd
        pha
        txa
        sta SCR+10*40,y
        pla
        sta SCR+10*40+1,y
        lda lines
        jsr bcd
        pha
        txa
        sta SCR+10*40+2,y
        pla
        sta SCR+10*40+3,y
        lda lvl
        ora #$30
        sta SCR+14*40,y
        lda garb
        cmp #10
        bcc +
        lda #9
+       ora #$30
        sta SCR+18*40,y
        ; fall through

; 4x2-cell preview of `nxt`
shownext2:
        ldx pn
        lda sct,x
        clc
        adc #<(SCR+5*40)
        sta sptr
        sta cptr
        lda #>(SCR+5*40)
        adc #0
        sta sptr+1
        clc
        adc #$d4
        sta cptr+1
        lda #CH_BLANKL
        ldy #3
-       sta (sptr),y
        dey
        bpl -
        ldy #43
-       sta (sptr),y
        dey
        cpy #39
        bne -
        ldx nxt
        lda pcols,x
        ora #8
        sta ncol
        txa
        asl
        asl
        asl
        sta t3
        lda #0
        sta ci
-       lda ci
        clc
        adc t3
        tax
        lda shapes+1,x          ; y is 0 or 1
        beq +
        lda #40
+       sta t1
        lda shapes,x
        clc
        adc t1
        tay
        lda #CH_BLK1
        sta (sptr),y
        lda ncol
        sta (cptr),y
        inc ci
        inc ci
        lda ci
        cmp #8
        bne -
        rts

; tile set and cell width for `players`
setmode:
        lda players
        cmp #2
        beq +
        lda #2
        sta cw
        lda #CH_BLKL
        sta tblk
        lda #CH_GHL
        sta tgh
        rts
+       lda #1
        sta cw
        lda #CH_BLK1
        sta tblk
        lda #CH_GH1
        sta tgh
        rts

; A = player number: fresh state in CTX with an empty board, first piece spawned and drawn
initplayer:
        pha
        ldx #CTXN-1
        lda #0
-       sta CTX,x
        dex
        bpl -
        pla
        sta pn
        inc dfull
        tax
        lda bht,x
        jsr setboard
        ldx #0
        txa
-
bpk:    sta BOARD,x
        inx
        cpx #200
        bne -
        lda #11
        ldx players
        cpx #2
        bne +
        ldx pn
        lda c0t2,x
+       sta c0
        lda #$ff
        sta prev
        lda #48                 ; NES gravity table, level 0
        sta gint
        sta gcnt
        jsr getseq
        sta nxt
        jsr spawn
        jsr draw
        jmp showstats

; exchange CTX with PC2 (P1 <-> P2) and aim the BOARD operands at the new active board.
; ponytail: self-modifying BOARD,x operands keep the game code single-board; zero-page pointers would cost a rewrite.
swapctx:
        ldx #CTXN-1
-       ldy PC2,x
        lda CTX,x
        sta PC2,x
        tya
        sta CTX,x
        dex
        bpl -
        ldx pn
        lda bht,x
        ; fall through

; A = page of the active board
setboard:
        sta bpa+2
        sta bpb+2
        sta bpc+2
        sta bpe+2
        sta bpf+2
        sta bpg+2
        sta bpg2+2
        sta bph2+2
        sta bpk+2
        sta bpt+2
        sta bph+2
        sta bpi+2
        sta bpj+2
        sec
        sbc #1
        sta bpd+2
        rts

; next piece of the shared sequence for this player; the one furthest ahead extends it
; (a player 256 pieces ahead of the other would lap the ring: a soft-dropping player gains ~20 pieces a minute at level 0)
getseq: lda ridx
        cmp wptr
        bne +
        jsr random7
        ldx wptr
        sta SEQ,x
        inc wptr
+       ldx ridx
        inc ridx
        lda SEQ,x
        rts

; 2P: nlines cleared -> garbage rows for the other player (2/3/4 -> 1/2/4); their context is always in PC2.
; Their GARB stat is repainted now: their own showstats only runs after a spawn, by which time garbapply has zeroed it.
sendgarb:
        lda players
        cmp #2
        bne +
        ldx nlines
        lda gtbl,x
        beq +
        clc
        adc PC2+garb-CTX
        sta PC2+garb-CTX
        jsr swapctx
        jsr showstats
        jmp swapctx
+       rts

; push the waiting garbage rows in, all with the same hole. C set if a block got pushed off the top.
garbapply:
        lda garb
        beq +
        sta t2
        lda #0
        sta garb
        jsr random7             ; hole column 0-9
        sta t1
        lda rnd
        and #3
        clc
        adc t1
        sta t1
-       jsr garbrow
        bcs ++
        dec t2
        bne -
+       clc
++      rts

; shift the board up one row, new bottom row = garbage with a hole at column t1. C set if the top row wasn't empty.
garbrow:
        lda #1
        sta dfull
        ldx #9
        lda #0
-
bpt:    ora BOARD,x
        dex
        bpl -
        cmp #1
        php
        ldx #0
-
bph:    lda BOARD+10,x
bpi:    sta BOARD,x
        inx
        cpx #190
        bne -
        ldx #9
-       lda #8                  ; garbage cell
        cpx t1
        bne +
        lda #0
+
bpj:    sta BOARD+190,x
        dex
        bpl -
        plp
        rts

; ---------------------------------------------------------------- keys and joysticks
!macro kbit .var, .col, .mask, .bit {   ; .var |= .bit if that key is down
        lda km+.col
        and #.mask
        beq .n
        lda .var
        ora #.bit
        sta .var
.n
}

; jin = P1: joystick port 2, jin+1 = P2: W A S D or joystick port 1; fire = any fire button or space; km = keyboard matrix.
; ponytail: a joystick held while scanning also selects its columns, so P1 left/down can ghost keys of P2; P2 on a joystick avoids it.
; The KERNAL's NMI stop test reads $DC01 without selecting a column, so it needs $DC00 = $7F (column 7, as its
; own IRQ scan leaves it). Our scans end with $FF, so RUN/STOP+RESTORE did nothing.
nmi:    pha
        lda #$7f
        sta $dc00
        pla
        jmp $fe47

readin: lda #$ff
        sta $dc00
        lda $dc01               ; no column selected: only port 1's joystick pulls rows low
        eor #$ff
        sta rmask               ; (VICE's joyport sim device also pulls rows 5-7)
        and #$1f
        sta jin+1
        lda $dc00               ; port 2 joystick
        eor #$ff
        and #$1f
        sta jin
        lda rmask
        eor #$ff
        sta rmask               ; rows free to read as keys
        lda #$fe
        sta t2
        ldx #0
-       lda t2
        sta $dc00
        lda $dc01
        eor #$ff
        and rmask
        sta km,x
        sec
        rol t2
        inx
        cpx #8
        bne -
        lda #$ff
        sta $dc00
        +kbit jin+1, 1, $02, J_UP       ; W
        +kbit jin+1, 1, $20, J_DN       ; S
        lda km+1                ; A and D share row 2. P1's joystick down/left holds column 1/2 low in every scan,
        and #$04                ; so A/D show up in each other's column: tell them apart, or drop both if both are held.
        sta t1                  ; A
        lda km+2
        and #$04
        sta t2                  ; D
        lda jin
        and #J_DN|J_LF
        cmp #J_DN|J_LF
        bne +
        lda #0
        sta t1
        sta t2
+       lda jin
        and #J_DN
        beq +
        lda t1                  ; down: A is real, D only if A is up
        beq +
        lda #0
        sta t2
+       lda jin
        and #J_LF
        beq +
        lda t2                  ; left: D is real, A only if D is up
        beq +
        lda #0
        sta t1
+       lda t1
        beq +
        lda jin+1
        ora #J_LF
        sta jin+1
+       lda t2
        beq +
        lda jin+1
        ora #J_RT
        sta jin+1
+
        +kbit jin+1, 7, $10, J_FIRE     ; space
        lda jin
        ora jin+1
        and #J_FIRE
        sta fire
        rts

; hkn and A = hotkeys newly pressed: P 1, G 2, M 4, H 8 (agents: bits in KINJ count too)
hotkeys:
        lda #0
        sta hk
        +kbit hk, 5, $02, 1     ; P
        +kbit hk, 3, $04, 2     ; G
        +kbit hk, 4, $10, 4     ; M
        +kbit hk, 3, $20, 8     ; H
        lda hkp
        eor #$ff
        and hk
        ora KINJ
        ldx #0
        stx KINJ
        ldx hk
        stx hkp
        sta hkn
        rts

; one newly pressed key from km per call: A = screen code A-Z (1-26), $80 del, 0 none (agents: KCH)
getkey: lda KCH
        beq gk0
        ldx #0
        stx KCH
        ora #0
        rts
gk0:    ldx #0
-       lda kmp,x               ; keys down now that weren't at the last call (so a key still held doesn't hide the next)
        eor #$ff
        and km,x
        bne gk2
        inx
        cpx #8
        bne -
        lda #0
        beq gk4
gk2:    ldy #0                  ; column x, lowest set row bit -> y
-       lsr
        bcs +
        iny
        bne -
+       txa
        asl
        asl
        asl
        sta t1
        tya
        clc
        adc t1
        tax
        lda ktab,x
gk4:    pha
        ldx #7
-       lda km,x
        sta kmp,x
        dex
        bpl -
        pla
        ora #0                  ; flags for the caller
        rts

bcd:    pha
        lsr
        lsr
        lsr
        lsr
        ora #$30
        tax
        pla
        and #$0f
        ora #$30
        rts

; repaint the boards and stats of both players
redrawall:
        inc dfull
        jsr draw
        jsr showstats
        lda players
        cmp #2
        bne +
        jsr swapctx
        inc dfull
        jsr draw
        jsr showstats
        jsr swapctx
+       rts

; P: silence the music, wait for P again
pause:  lda mon
        pha
        lda hkn
        pha
        jsr musicstop
        +puts SCR+10*40+18, t_pause, 6
        +fill COL+10*40+18, 1, 6
-       lda $d012               ; plain frame sync, no sound tick
        cmp #251
        bne -
        jsr readin
        jsr hotkeys
        and #1
        beq -
        +puts SCR+10*40+18, t_blank, 6  ; (2P: the stats columns don't cover all of it)
        jsr redrawall
        pla
        sta hkn
        pla
        beq +
        jsr musicstart
+       rts

; insert `score` into the top 5 (ties below older entries, 0 never): carry set if it made it, hnew = its row
insert: lda score
        ora score+1
        ora score+2
        beq insno
        ldx #0
        ldy #0
insl:   lda score+2
        cmp HS_SC,x
        bcc insnx
        bne insfound
        lda score+1
        cmp HS_SC+1,x
        bcc insnx
        bne insfound
        lda score
        cmp HS_SC+2,x
        beq insnx
        bcs insfound
insnx:  inx
        inx
        inx
        iny
        cpy #5
        bne insl
insno:  clc
        rts
insfound:
        sty hnew
        tya
        asl
        sta t1
        tya
        clc
        adc t1
        sta t1                  ; 3 * row
        ldx #11                 ; shift lower rows down
-       cpx t1
        bcc +
        lda HS_SC,x
        sta HS_SC+3,x
        lda HS_NM,x
        sta HS_NM+3,x
        dex
        bpl -
+       ldx t1
        lda score+2
        sta HS_SC,x
        lda score+1
        sta HS_SC+1,x
        lda score
        sta HS_SC+2,x
        lda #$2d
        sta HS_NM,x
        sta HS_NM+1,x
        sta HS_NM+2,x
        lda #0
        sta hpos
        sec
        rts

; high-score screen; A = 1: type initials into row hnew first. Fire returns.
board:  sta hent
        lda #0
        sta harm
        jsr cls
        +puts SCR+4*40+14, t_hs, 11
        +fill COL+4*40+14, 7, 11
bloop:  jsr waitframe
        jsr readin
        jsr hsrows
        lda hent
        beq bwait
        +puts SCR+20*40+13, t_ent, 13
        +fill COL+20*40+13, 3, 13
        jsr getkey
        bne +
        jmp bloop
+       cmp #$80                ; DEL
        bne +
        lda hpos
        beq bloop
        dec hpos
        jsr hsoff
        lda #$2d
        sta HS_NM,x
        jmp bloop
+       cmp #$81                ; RETURN ends the entry once 3 letters are in
        bne +
        lda hpos
        cmp #3
        bne bl2
        lda #0
        sta hent
        +fill COL+20*40+13, 0, 13
        +puts SCR+20*40+13, t_blank, 13
bl2:    jmp bloop
+       cmp #27                 ; letters only (screen codes 1-26), 3 at most
        bcs bl2
        ldx hpos
        cpx #3
        bcs bl2
        pha
        jsr hsoff
        pla
        sta HS_NM,x
        inc hpos
        jmp bloop
bwait:  +puts SCR+20*40+15, t_fire, 10
        +fill COL+20*40+15, 1, 10
        lda fire                ; (readin ran at bloop)
        bne +
        sta harm
        inc harm
        jmp bloop
+       lda harm
        bne brel
        jmp bloop
brel:   jsr waitframe           ; wait for release so the caller doesn't see fire
        jsr readin
        lda fire
        bne brel
        rts

; X = offset in HS_NM of the letter at hpos in row hnew
hsoff:  lda hnew
        asl
        adc hnew
        adc hpos
        tax
        rts

; draw the 5 rows: "1. ABC 012345", the new entry in yellow
hsrows: lda #0
        sta row
hr1:    ldx row
        lda hsl,x
        sta sptr
        lda hsh,x
        sta sptr+1
        lda row
        clc
        adc #$31
        ldy #0
        sta (sptr),y
        lda #$2e
        iny
        sta (sptr),y
        lda row
        asl
        adc row
        sta idx
        tax
        lda HS_NM,x
        ldy #3
        sta (sptr),y
        lda HS_NM+1,x
        iny
        sta (sptr),y
        lda HS_NM+2,x
        iny
        sta (sptr),y
        lda sptr+1              ; colour pointer
        clc
        adc #$d4
        sta cptr+1
        lda sptr
        sta cptr
        lda #1
        ldx hent
        beq +
        ldx row
        cpx hnew
        bne +
        lda #7
+       ldy #13
-       sta (cptr),y
        dey
        bpl -
        ldx idx
        lda HS_SC,x
        jsr bcd
        ldy #7
        pha
        txa
        sta (sptr),y
        pla
        iny
        sta (sptr),y
        ldx idx
        lda HS_SC+1,x
        jsr bcd
        ldy #9
        pha
        txa
        sta (sptr),y
        pla
        iny
        sta (sptr),y
        ldx idx
        lda HS_SC+2,x
        jsr bcd
        ldy #11
        pha
        txa
        sta (sptr),y
        pla
        iny
        sta (sptr),y
        inc row
        lda row
        cmp #5
        beq +
        jmp hr1
+       rts

showstats:
        lda players
        cmp #2
        bne +
        jmp showstats2
+       lda score+2
        jsr bcd
        stx SCR+5*40+2
        sta SCR+5*40+3
        lda score+1
        jsr bcd
        stx SCR+5*40+4
        sta SCR+5*40+5
        lda score
        jsr bcd
        stx SCR+5*40+6
        sta SCR+5*40+7
        lda lines+1
        jsr bcd
        stx SCR+9*40+2
        sta SCR+9*40+3
        lda lines
        jsr bcd
        stx SCR+9*40+4
        sta SCR+9*40+5
        lda lvl
        ora #$30
        sta SCR+13*40+2
        lda lvl
        tax
        lda lvcol,x
        sta $d020
        lda HS_SC
        jsr bcd
        stx SCR+17*40+2
        sta SCR+17*40+3
        lda HS_SC+1
        jsr bcd
        stx SCR+17*40+4
        sta SCR+17*40+5
        lda HS_SC+2
        jsr bcd
        stx SCR+17*40+6
        sta SCR+17*40+7
        +fill COL+17*40+2, 1, 6
        +fill COL+5*40+2, 1, 6
        +fill COL+9*40+2, 1, 4
        +fill COL+13*40+2, 1, 1
        ; fall through

; preview of `nxt` in the 4x4-cell box at PV
shownext:
        ldx #7
        lda #CH_BLANKL
-       sta PV,x
        sta PV+40,x
        sta PV+80,x
        sta PV+120,x
        dex
        bpl -
        ldx nxt
        lda pcols,x
        ora #8
        sta ncol
        txa
        asl
        asl
        asl
        sta t3
        lda #0
        sta ci
-       lda ci
        clc
        adc t3
        tax
        lda shapes+1,x          ; y
        asl
        asl
        asl
        sta t1                  ; 8y
        asl
        asl
        clc
        adc t1                  ; 40y
        sta t1
        lda shapes,x
        asl
        clc
        adc t1                  ; + 2x
        tax
        lda #CH_BLKL
        sta PV,x
        lda #CH_BLKL+1
        sta PV+1,x
        lda ncol
        sta PV+COL-SCR,x
        sta PV+COL-SCR+1,x
        inc ci
        inc ci
        lda ci
        cmp #8
        bne -
        rts

; 7 pieces x 4 (x,y) in their box: I O T S Z J L
shapes: !byte 0,1, 1,1, 2,1, 3,1
        !byte 1,0, 2,0, 1,1, 2,1
        !byte 0,1, 1,1, 2,1, 1,0
        !byte 1,0, 2,0, 0,1, 1,1
        !byte 0,0, 1,0, 1,1, 2,1
        !byte 0,0, 0,1, 1,1, 2,1
        !byte 2,0, 0,1, 1,1, 2,1
psize:  !byte 4,3,3,3,3,3,3
pcols:  !byte 3,7,4,5,2,6,1
gtab:   !byte 48,43,38,33,28,23,18,13,8,6
ptslo:  !byte 0,$40,$00,$00,$00         ; 40 / 100 / 300 / 1200 (BCD)
pthi:   !byte 0,$00,$01,$03,$12
lvcol:  !byte 14,3,13,5,7,10,2,4,1,0        ; border colour per level
star:   !byte $40,0,0,$e0,0,0,$40,0,0
sx:     !byte 36,70,100,150,190,240,44,74
sy:     !byte 60,130,200,90,170,70,150,110
smask:  !byte 1,0,3,1,3,0,1,3
scol:   !byte 11,12,15,1,15,12,11,6
shk:    !byte 0,0,3,6,2,5,1,3,0
; screen address of board row y, wall column (20 = bottom wall row)
scrlo:  !for i, 0, 20 { !byte <(SCR+(1+i)*40+10) }
scrhi:  !for i, 0, 20 { !byte >(SCR+(1+i)*40+10) }
; same from column 0
scr0lo: !for i, 0, 20 { !byte <(SCR+(1+i)*40) }
scr0hi: !for i, 0, 20 { !byte >(SCR+(1+i)*40) }
bht:    !byte >BOARD, >BOARD2   ; board page per player
c0t2:   !byte 2, 28             ; 2P: screen column of cell 0
sct:    !byte 14, 21            ; 2P: stats column
gtbl:   !byte 0,0,1,2,4         ; garbage rows per rows cleared
; keyboard matrix (column * 8 + row) -> A-Z screen codes, $80 del, $81 return
ktab:   !byte $80, $81, 0, 0, 0, 0, 0, 0
        !byte 0, 23, 1, 0, 26, 19, 5, 0
        !byte 0, 18, 4, 0, 3, 6, 20, 24
        !byte 0, 25, 7, 0, 2, 8, 21, 22
        !byte 0, 9, 10, 0, 13, 11, 15, 14
        !byte 0, 16, 12, 0, 0, 0, 0, 0
        !byte 0, 0, 0, 0, 0, 0, 0, 0
        !byte 0, 0, 0, 0, 0, 0, 17, 0
; tiles (screen codes 64-71), all multicolour 4x8: 01 = D022 highlight, 10 = D023 shadow, 11 = colour RAM
tiles:  !byte $55,$7f,$7f,$7f,$7f,$7f,$7f,$aa   ; block left
        !byte $55,$fe,$fe,$fe,$fe,$fe,$fe,$aa   ; block right
        !byte $ff,$c0,$c0,$c0,$c0,$c0,$c0,$ff   ; ghost left (outline in the piece colour)
        !byte $ff,$03,$03,$03,$03,$03,$03,$ff   ; ghost right
        !byte $55,$f7,$f7,$f7,$55,$df,$df,$df   ; brick wall
        !byte $55,$7e,$7e,$7e,$7e,$7e,$7e,$aa   ; single block (title)
        !fill 16, 0                             ; transparent blank L/R
        !fill 16, $ff                           ; well L/R (solid colour 11)
        !byte $ff,$c3,$c3,$c3,$c3,$c3,$c3,$ff   ; 1-char ghost (2P)
        !byte $55,$6a,$6a,$6a,$6a,$6a,$6a,$aa   ; garbage: D022 light grey edge, D023 dark grey body
title:
        !text "### ### ### ##  # ### "
        !text " #  #    #  # # # #   "
        !text " #  ###  #  ##  # ### "
        !text " #  #    #  # # #   # "
        !text " #  ###  #  # # # ### "
pal:    !byte 2+8,7+8,5+8,3+8,1+8,4+8,5+8,3+8
sine:   !for i, 0, 31 { !byte int(15.5+15.5*sin(i*6.2831853/32)) }
bbase:  !byte 66,114,162
boff3:  !byte 0,11,22
barcol: !byte 6,6,14,14,3,3,1,1,1,1,3,3,14,14,6,6
        !byte 2,2,10,10,8,8,7,7,7,7,8,8,10,10,2,2
        !byte 5,5,13,13,7,7,1,1,1,1,7,7,13,13,5,5
t_score: !scr "score"
t_lines: !scr "lines"
t_level: !scr "level"
t_next:  !scr "next"
t_over:  !scr "game over"
t_fire:  !scr "press fire"
t_hi:    !scr "hi   "
t_blank: !scr "             "
t_hs:    !scr "high scores"
t_pause: !scr "paused"
t_ent:   !scr "name + return"
t_win:   !scr "p? wins"
t_p1:    !scr "p1"
t_p2:    !scr "p2"
t_garb:  !scr "garb"
t_1p:    !scr "1 player "
t_2p:    !scr "2 players"
t_lr:    !scr "left/right"
hsl:     !for i, 0, 4 { !byte <(SCR+(7+2*i)*40+14) }
hsh:     !for i, 0, 4 { !byte >(SCR+(7+2*i)*40+14) }

; Korobeiniki: (note, frames); 0 = rest, $ff = loop. Bass: root/fifth per bar, 4 steps of 20 frames.
mel:    !byte N_E5,20, N_B4,10, N_C5,10, N_D5,20, N_C5,10, N_B4,10
        !byte N_A4,20, N_A4,10, N_C5,10, N_E5,20, N_D5,10, N_C5,10
        !byte N_B4,30, N_C5,10, N_D5,20, N_E5,20
        !byte N_C5,20, N_A4,20, N_A4,40
        !byte 0,10, N_D5,20, N_F5,10, N_A5,20, N_G5,10, N_F5,10
        !byte N_E5,30, N_C5,10, N_E5,20, N_D5,10, N_C5,10
        !byte N_B4,20, N_B4,10, N_C5,10, N_D5,20, N_E5,20
        !byte N_C5,20, N_A4,20, N_A4,40
        !byte $ff
nf:     !word 0
        !word int(440*FQ), int(493.88*FQ), int(523.25*FQ), int(587.33*FQ)
        !word int(659.25*FQ), int(698.46*FQ), int(783.99*FQ), int(880*FQ)
bf:     !word int(110*FQ), int(164.81*FQ)       ; A
        !word int(110*FQ), int(164.81*FQ)       ; A
        !word int(82.41*FQ), int(123.47*FQ)     ; E
        !word int(110*FQ), int(164.81*FQ)       ; A
        !word int(146.83*FQ), int(220*FQ)       ; D
        !word int(130.81*FQ), int(196*FQ)       ; C
        !word int(82.41*FQ), int(123.47*FQ)     ; E
        !word int(110*FQ), int(164.81*FQ)       ; A
!if * > CHARS { !error "code overlaps the charset" }
