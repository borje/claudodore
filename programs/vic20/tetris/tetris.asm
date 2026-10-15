; VIC-20 Tetris, unexpanded. Joystick: left/right move, down soft-drop, fire/up rotate.
; Board 10x20 at BOARD (0 = empty, else colour 1-7); screen at $1E00, colour RAM $9600.
CHROUT = $ffd2
JIFFY  = $a2
SCR    = $1e00
BOARD  = $1a00
; zero page pointers
sptr   = $fb
cptr   = $fd
; variables
px     = $1b00
py     = $1b01
pid    = $1b02
pcol   = $1b03
cells  = $1b04          ; 4 x (x,y)
scells = $1b0c
t1     = $1b14
t2     = $1b15
t3     = $1b16
row    = $1b17
idx    = $1b18
ci     = $1b19
hcnt   = $1b1a
gcnt   = $1b1b
gint   = $1b1c
score  = $1b1d          ; 2 bytes BCD
lines  = $1b1f          ; BCD
nlines = $1b20
joy    = $1b21
prev   = $1b22
rnd    = $1b23
dirty  = $1b24
nxt    = $1b25
ncol   = $1b26
snd    = $1b27          ; sound: frames left, note, per-frame note delta
snote  = $1b28
sdelta = $1b29
pch    = $1b2a
cnt    = $1b2c
ghost  = $1b2b          ; 1 = show landing outline (toggle with G)
CH_BLK   = 60           ; custom tiles (screen codes 60-62)
CH_GHOST = 61
CH_WALL  = 62
J_UP   = $04
J_DN   = $08
J_LF   = $10
J_FIRE = $20
J_RT   = $80

!macro puts .dst, .src, .len {
        ldx #0
.l      lda .src,x
        sta .dst,x
        inx
        cpx #.len
        bne .l
}

!macro cyc .row {               ; colour-cycle one title row
        ldx #20
.l      txa
        clc
        adc t1
        and #7
        tay
        lda pal,y
        sta SCR+$7800+66+.row*22,x
        dex
        bpl .l
}

!macro fill .dst, .col, .len {
        ldx #.len-1
        lda #.col
.l      sta .dst,x
        dex
        bpl .l
}

* = $1001
        !byte $0d,$10,$0a,$00,$9e
        !text "4112"
        !byte 0,0,0

* = $1010
        lda #5                  ; white text
        jsr CHROUT
        lda #$93                ; clear (screen + colour RAM)
        jsr CHROUT
        lda #8                  ; black background and border
        sta $900f
        lda #$1a                ; aux colour (multicolour highlight) white, volume 10
        sta $900e
        ; charset in RAM at $1C00 (copy of the ROM's first 64 chars + our tiles)
        ldx #0
-       lda $8000,x
        sta $1c00,x
        lda $8100,x
        sta $1d00,x
        inx
        bne -
        ldx #23
-       lda tiles,x
        sta $1c00+CH_BLK*8,x
        dex
        bpl -
        lda $9005
        ora #$0f
        sta $9005
        lda #0
        sta ghost
        lda JIFFY
        ora #1
        sta rnd
        jsr intro
        lda #$93                ; clear for the game
        jsr CHROUT
        jsr walls
        +puts SCR+22, t_score, 5
        +puts SCR+88, t_lines, 5
        +puts SCR+61, t_next, 4
        +puts SCR+154, t_level, 5
        +fill SCR+$7800+22, 7, 5
        +fill SCR+$7800+88, 7, 5
        +fill SCR+$7800+61, 7, 4
        +fill SCR+$7800+154, 7, 5
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
        sta lines
        sta hcnt
        lda #$ff
        sta prev
        lda #30
        sta gint
        sta gcnt
        jsr random7
        sta nxt
        jsr spawn
        jsr draw
        jsr showstats

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
        lda #115
        ldx #3
        ldy #0
        jsr sfx
+       lda joy
        sta prev
        jsr $ffe4               ; GETIN: G toggles the ghost
        cmp #$47
        bne +
        lda ghost
        eor #1
        sta ghost
        inc dirty
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
        lda #95
        ldx #2
        ldy #0
        jsr sfx
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
        bne nograv
        lda gint
        sta gcnt
        inc dirty
        inc py
        jsr fits
        beq nograv
        dec py
        jsr draw                ; make sure the final position is on screen
        jsr lock
        lda #15
        ldx #4
        ldy #0
        jsr sfx
        jsr clear
        jsr spawn
        beq +
        jsr draw
        jsr showstats
        lda #100                ; falling sweep
        ldx #40
        ldy #$fe
        jsr sfx
        +puts SCR+10*22+6, t_over, 9
        +puts SCR+12*22+6, t_fire, 10
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

; title screen: cycling TETRIS, blinking "press fire", pieces raining below; fire/any key starts
intro:
        ldx #0
-       ldy #32
        lda title,x
        cmp #35                 ; '#'
        bne +
        ldy #CH_BLK
+       tya
        sta SCR+66,x
        inx
        cpx #110
        bne -
        +puts SCR+9*22+6, t_fire, 10
        jsr spawn
        lda #3
        sta px
        lda #10
        sta py
        lda #0
        sta cnt
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
        +fill SCR+$7800+9*22+6, 1, 10
        jmp bdone
boff:   +fill SCR+$7800+9*22+6, 0, 10
bdone:  lda cnt
        and #3
        bne irain
        lda #32                 ; erase, move, redraw the raining piece
        sta pch
        jsr drawpiece
        inc py
        lda py
        cmp #18
        bcc rdraw
        jsr spawn
        jsr random7
        sta px
        lda #10
        sta py
rdraw:  lda #CH_BLK
        sta pch
        jsr drawpiece
irain:  jsr readjoy
        and #J_FIRE
        bne istart
        jsr $ffe4
        bne istart
        jmp iloop
istart: lda #50
        ldx #10
        ldy #5
        jmp sfx

waitframe:
        lda JIFFY
-       cmp JIFFY
        beq -
        ; fall through

; once per frame: play/advance the current sound on the soprano voice
soundtick:
        lda snd
        beq +
        dec snd
        lda snote
        and #$7f
        ora #$80
        sta $900c
        lda snote
        clc
        adc sdelta
        sta snote
        rts
+       sta $900c
        rts

; A = note (0-127, higher = higher pitch), X = frames, Y = delta per frame
sfx:    sta snote
        stx snd
        sty sdelta
        rts

; A = pressed bits (J_*), positive logic
readjoy:
        lda $9111
        eor #$ff
        and #$3c
        sta t1
        sei
        ldx $9122               ; right is on VIA2 PB7: needs DDR bit 7 = input
        lda #$7f
        sta $9122
        lda $9120
        stx $9122
        cli
        and #$80
        eor #$80
        ora t1
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
        jsr flashrow
+       dec row
        bpl cf1
        lda nlines
        beq +
        ldx #8                  ; let the flash show
-       jsr waitframe
        dex
        bne -
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
        clc
        lda score
        adc pts,x
        sta score
        lda score+1
        adc #0
        sta score+1
        clc
        lda lines
        adc nlines
        sta lines
        cld
        cli
        lda lines               ; level = tens digit: interval 30 - 3*level
        lsr
        lsr
        lsr
        lsr
        sta t1
        asl
        adc t1
        sta t1
        lda #30
        sec
        sbc t1
        sta gint
        lda #60                 ; rising sweep
        ldx #12
        ldy #4
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

; recolour screen row `row` white
flashrow:
        ldx row
        lda scrlo,x
        sta cptr
        lda scrhi,x
        clc
        adc #$78
        sta cptr+1
        lda #1                  ; white
        ldy #10
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
        adc #$78                ; colour RAM = screen + $7800
        sta cptr+1
        ldy #1
dr2:    ldx idx
        lda BOARD,x
        bne +
        lda #32
        ldx #1
        bne dr3
+       tax
        lda #CH_BLK
dr3:    sta (sptr),y
        txa
        sta (cptr),y
        inc idx
        iny
        cpy #11
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
        lda #CH_GHOST
        sta pch
        jsr drawpiece
        pla
        sta py
noghost:
        lda #CH_BLK
        sta pch
        ; fall through

; draw the 4 cells of the current piece with char `pch`
drawpiece:
        lda #0
        sta ci
dr4:    ldx ci
        lda cells,x
        sec
        adc px                  ; +1 for the wall column
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
        adc #$78
        sta cptr+1
        ldy #0
        lda pch
        sta (sptr),y
        lda pcol
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
        adc #$78
        sta cptr+1
        cpx #20
        beq wbot
        ldy #0
        jsr wput
        ldy #11
        jsr wput
        inx
        bne wl
wbot:   ldy #11
-       jsr wput
        dey
        bpl -
        rts
wput:   lda #CH_WALL
        sta (sptr),y
        lda #$0a                ; red bricks, white mortar (multicolour)
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
        lda score+1
        jsr bcd
        stx SCR+44
        sta SCR+45
        lda score
        jsr bcd
        stx SCR+46
        sta SCR+47
        lda lines
        jsr bcd
        stx SCR+110
        sta SCR+111
        lda lines               ; level = tens digit
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta SCR+176
        ; fall through

; preview of `nxt` in the 4x4 box at row 3, col 17
shownext:
        ldx #3
        lda #32
-       sta SCR+83,x
        sta SCR+83+22,x
        sta SCR+83+44,x
        sta SCR+83+66,x
        dex
        bpl -
        ldx nxt
        lda pcols,x
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
        sta t1                  ; 2y
        asl
        sta t2                  ; 4y
        asl
        asl                     ; 16y
        clc
        adc t2
        adc t1                  ; 22y
        clc
        adc shapes,x            ; + x
        tax
        lda #CH_BLK
        sta SCR+83,x
        lda ncol
        sta SCR+$7800+83,x
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
pts:    !byte 0,$10,$30,$50,$80
; screen address of board row y, wall column (21 = bottom wall row)
scrlo:  !for i, 0, 20 { !byte <(SCR+27+i*22) }
scrhi:  !for i, 0, 20 { !byte >(SCR+27+i*22) }
; 8x8 tiles for CH_BLK, CH_GHOST, CH_WALL
; CH_BLK/CH_GHOST are hires; CH_WALL is multicolour 4x8 (10 = cell colour, 11 = aux white)
tiles:  !byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        !byte $fe,$82,$82,$82,$82,$82,$fe,$00
        !byte $ff,$ae,$ae,$ae,$ff,$ba,$ba,$ba
title:
        !text "### ### ### ##  # ### "
        !text " #  #    #  # # # #   "
        !text " #  ###  #  ##  # ### "
        !text " #  #    #  # # #   # "
        !text " #  ###  #  # # # ### "
pal:    !byte 2,7,5,3,6,4,5,3
t_score: !scr "score"
t_lines: !scr "lines"
t_next:  !scr "next"
t_level: !scr "level"
t_over:  !scr "game over"
t_fire:  !scr "press fire"
!if * > BOARD { !error "code overlaps the board" }  ; code, then board, variables and the $1C00 charset
