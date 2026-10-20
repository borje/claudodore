; C64 Tetris. Joystick port 2: left/right move, down soft-drop, fire/up rotate. G toggles ghost, M music.
; Board 10x20 at BOARD (0 = empty, else colour 1-7). Each cell = 2 screen chars (multicolour bevelled tile:
; D022 highlight, D023 shadow, colour RAM = body). Screen $0400, charset in RAM at $3000, colour RAM $D800.
; SID: voice 1 pulse (PWM) melody, voice 2 triangle bass (Korobeiniki), voice 3 sound effects.
CHROUT = $ffd2
GETIN  = $ffe4
JIFFY  = $a2
SCR    = $0400
COL    = $d800
BOARD  = $c000
CHARS  = $3000
PV     = SCR+6*40+32            ; next-piece preview, 4 rows x 8 cols
FQ     = 17.0284                ; Hz -> SID freq (PAL clock)
; zero page pointers
sptr   = $fb
cptr   = $fd
; variables
px     = $c100
py     = $c101
pid    = $c102
pcol   = $c103
cells  = $c104          ; 4 x (x,y)
scells = $c10c
t1     = $c114
t2     = $c115
t3     = $c116
row    = $c117
idx    = $c118
ci     = $c119
hcnt   = $c11a
gcnt   = $c11b
gint   = $c11c
score  = $c11d          ; 3 bytes BCD
lines  = $c120          ; 2 bytes BCD
nlines = $c122
joy    = $c123
prev   = $c124
rnd    = $c125
dirty  = $c126
nxt    = $c127
ncol   = $c128
snd    = $c129          ; sfx: frames left, pitch (SID hi byte), per-frame delta, waveform|gate
snote  = $c12a
sdelta = $c12b
swav   = $c12c
pch    = $c12d
cnt    = $c12e
ghost  = $c12f          ; 1 = show landing outline
lvl    = $c130
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
CH_BLKL   = 64          ; custom tiles: block L/R, ghost L/R, wall, single block, blank L/R
CH_GHL    = 66
CH_WALL   = 68
CH_BLK1   = 69
CH_BLANKL = 70
CH_WELL   = 72          ; solid black cell for the well
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
        lda #5                  ; white text
        jsr CHROUT
        lda #$93                ; clear (screen + colour RAM)
        jsr CHROUT
        lda #14
        sta $d020
        lda #6
        sta $d021
        lda #15                 ; multicolour highlight (light grey) / shadow (dark grey)
        sta $d022
        lda #11
        sta $d023
        ; charset in RAM: copy of the ROM's first 64 chars + our tiles
        sei
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
        cli
        ldx #10*8-1
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
        ldx #$3f                ; clear variables
        lda #0
-       sta $c100,x
        dex
        bpl -
        jsr initstars
        lda JIFFY
        ora #1
        sta rnd
        jsr intro
        lda #$93                ; clear for the game
        jsr CHROUT
        jsr walls
        +puts SCR+4*40+2, t_score, 5
        +puts SCR+8*40+2, t_lines, 5
        +puts SCR+12*40+2, t_level, 5
        +puts SCR+4*40+34, t_next, 4
        +fill COL+4*40+2, 3, 5
        +fill COL+8*40+2, 3, 5
        +fill COL+12*40+2, 3, 5
        +fill COL+4*40+34, 3, 4
        lda JIFFY
        ora #1
        sta rnd
newgame:
        ldx #0
        txa
-       sta BOARD,x
        inx
        cpx #200
        bne -
        sta score
        sta score+1
        sta score+2
        sta lines
        sta lines+1
        sta lvl
        sta hcnt
        lda #$ff
        sta prev
        lda #48                 ; NES gravity table, level 0
        sta gint
        sta gcnt
        jsr random7
        sta nxt
        jsr spawn
        jsr draw
        jsr showstats
        jsr musicstart

loop:
        jsr waitframe
        lda #0
        sta dirty
        jsr readjoy
        sta joy
        ; rotate on press edge of up/fire
        lda prev
        eor #$ff
        and joy
        and #J_UP|J_FIRE
        beq +
        jsr rotate
        inc dirty
        +sound 45, 4, 5, $41
+       lda joy
        sta prev
        jsr GETIN               ; G toggles the ghost, M the music
        cmp #$47
        bne +
        lda ghost
        eor #1
        sta ghost
        inc dirty
+       cmp #$4d
        bne +
        lda mon
        beq ++
        jsr musicstop
        jmp +
++      jsr musicstart
+       ; left/right with auto-repeat
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
        lda joy                 ; soft drop: 1 point per row fallen with down held
        and #J_DN
        beq nosd
        sei
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
        cli
        jsr showstats
nosd:   jmp nograv
+       dec py
        jsr draw                ; make sure the final position is on screen
        jsr lock
        +sound 14, 5, $fd, $81
        jsr clear
        jsr spawn
        beq +
        jsr draw
        jsr showstats
        jsr musicstop
        +sound 90, 60, $ff, $21   ; falling saw
        +puts SCR+10*40+16, t_over, 9
        +puts SCR+12*40+15, t_fire, 10
        +fill COL+10*40+16, 1, 9
        +fill COL+12*40+15, 1, 10
-       jsr waitframe           ; wait for fire release, then press
        jsr readjoy
        and #J_FIRE
        bne -
-       jsr waitframe
        jsr readjoy
        and #J_FIRE
        beq -
        jmp newgame
+       jsr showstats
nograv:
        lda dirty
        beq +
        jsr draw
+       jmp loop

; title screen: raster bars, cycling TETRIS, blinking "press fire", pieces raining below; fire/any key starts
intro:
        +trow 0
        +trow 1
        +trow 2
        +trow 3
        +trow 4
        +puts SCR+11*40+15, t_fire, 10
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
        jsr readjoy
        and #J_FIRE
        bne istart
        jsr GETIN
        bne istart
        jmp iloop
istart: +sound 50, 10, 5, $41
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
-       lda $d012
        cmp #251
        bne -
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

; A = pressed bits (J_*), positive logic
readjoy:
        lda $dc00
        eor #$ff
        and #$1f
        rts

random7:
        lda rnd
        asl
        bcc +
        eor #$1d
+       sta rnd
        eor JIFFY
-       cmp #7
        bcc +
        sbc #7
        bcs -
+       rts

; new piece at top; Z set if it fits
spawn:
        lda nxt
        sta pid
        jsr random7
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
        lda BOARD,x
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
        sta BOARD,x
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
        sei
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
        cli
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
-       lda BOARD,x
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
        jsr rowidx
        txa
        clc
        adc #9
        tax
-       cpx #10
        bcc +
        lda BOARD-10,x
        sta BOARD,x
        dex
        jmp -
+       ldx #9
        lda #0
-       sta BOARD,x
        dex
        bpl -
        rts

draw:
        lda #0
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
        lda BOARD,x
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
        lda ghost
        beq noghost
        lda py                  ; ghost: where it would land
        pha
-       inc py
        jsr fits
        beq -
        dec py
        lda #CH_GHL
        sta pch
        jsr drawpiece
        pla
        sta py
noghost:
        lda #CH_BLKL
        sta pch
        ; fall through

; draw the 4 cells of the current piece with tile `pch` (+1 for the right half)
drawpiece:
        lda #0
        sta ci
dr4:    ldx ci
        lda cells,x
        clc
        adc px
        asl
        sec
        adc #0                  ; 2*x + 1 for the wall column
        sta t1
        lda cells+1,x
        clc
        adc py
        tax
        lda scrlo,x
        clc
        adc t1
        sta sptr
        sta cptr
        lda scrhi,x
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
        iny
        lda pch
        clc
        adc #1
        sta (sptr),y
        txa
        sta (cptr),y
        inc ci
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

showstats:
        lda score+2
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
; tiles (screen codes 64-71), all multicolour 4x8: 01 = D022 highlight, 10 = D023 shadow, 11 = colour RAM
tiles:  !byte $55,$7f,$7f,$7f,$7f,$7f,$7f,$aa   ; block left
        !byte $55,$fe,$fe,$fe,$fe,$fe,$fe,$aa   ; block right
        !byte $ff,$c0,$c0,$c0,$c0,$c0,$c0,$ff   ; ghost left (outline in the piece colour)
        !byte $ff,$03,$03,$03,$03,$03,$03,$ff   ; ghost right
        !byte $55,$f7,$f7,$f7,$55,$df,$df,$df   ; brick wall
        !byte $55,$7e,$7e,$7e,$7e,$7e,$7e,$aa   ; single block (title)
        !fill 16, 0                             ; transparent blank L/R
        !fill 16, $ff                           ; well L/R (solid colour 11)
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
