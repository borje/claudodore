; C64 two-player Snake. P1: joystick port 2 or W/A/S/D, P2: joystick port 1
; or I/J/K/M. Any mix of 0, 1 or 2 joysticks works with no setup. First to 5 round wins takes the match.
; Title: H shows the top-5 board (solo game over: type initials). Left/right picks solo (high score), vs computer, or 2 players. In 1-player modes P1 takes any
; controller; vs computer the computer steers P2.
; Heads are sprites gliding between cells (the cell itself holds an invisible CH_HID); bodies are chars.
; SID: voice 1 melody, voice 2 bass, voice 3 sound effects; F1 toggles the music.
; Hires custom charset at $3000 (ROM letters + tiles at 64+), screen $0400, black background.
; A snake is a ring of cells, 128 per player (slot = index | player*128): screen addr lo/hi and
; the direction it moved in to reach the cell. Dirs: 0 up 1 right 2 down 3 left.
; IRQs stay off: the main loop syncs on the raster and scans the keyboard matrix itself.
SCR    = $0400
COL    = $d800
CHARS  = $3000
; zero page pointers
p      = $fb
q      = $fd
s      = $22
; ring
rlo    = $c000
rhi    = $c100
rdir   = $c200
; per player (2 bytes each, indexed by X)
hd     = $c300          ; ring index of head
tl     = $c302          ; ring index of tail
dir    = $c304          ; last moved direction
nd     = $c306          ; next direction
grow   = $c308          ; cells still to grow
dead   = $c30a
nhl    = $c30c          ; new head address
nhh    = $c30e
score  = $c310          ; apples this round, BCD
wins   = $c312
eat    = $c314
joy    = $c316          ; joystick-format bits: up 1, down 2, left 4, right 8, fire 16
; globals
frame  = $c320
tick   = $c321
speed  = $c322          ; frames per step
ecnt   = $c323          ; apples until the next speed-up
sfx    = $c324          ; voice 3 effect: frames left, per-frame pitch delta, pitch
sdel   = $c325
t1     = $c326
t2     = $c327
t3     = $c328
fire   = $c329
cnt    = $c32a
intitle = $c32b
players = $c32c         ; 0 = solo, 1 = vs computer, 2
prevj  = $c32d          ; title: directions held last frame
shi    = $c32e
aslot  = $c32f          ; apple slot the next spawn fills
ax     = $c330          ; apple col/row, 2 apples
ay     = $c332
hx     = $c334          ; head col/row per player
hy     = $c336
best   = $c338          ; computer: best score / dir so far, target apple, candidate
bdir   = $c339
tx     = $c33a
ty     = $c33b
cand   = $c33c
kk     = $c33d
sy     = $c33e
last   = $c33f          ; highest player index in play (0 solo, else 1)
glide  = $c340          ; 1 = head sprites interpolate between cells
hi     = $c341          ; HUD high score = hs_sc[0], BCD
rnd    = $c342
mi     = $c343          ; music step 0-63
mcnt   = $c344          ; frames left in step
spry   = $c345
mon    = $c346          ; music on
prevf1 = $c347
hs_sc  = $c350          ; solo top 5 scores, BCD
hs_nm  = $c355          ; 5 x 3 screen codes
newrow = $c364          ; board row being entered/highlighted, $ff = none
pos    = $c365          ; initials typed so far
entry  = $c366          ; board: 1 = typing initials
armed  = $c367          ; board: fire seen released
ri     = $c369          ; drawrows row
rc     = $c36a          ; drawlevel rect: col, row, width, height
rr     = $c36b
rw     = $c36c
rh     = $c36d
level  = $c36e          ; solo: obstacle layout, +1 every LEVAPPLES apples
lapples = $c36f
lvlup  = $c370
kmp    = $c380          ; getkey: keyboard matrix at the last call, 8 bytes
knw    = $c388          ; getkey: keys newly down per column, 8 bytes
lives  = wins           ; solo: lives left (pips), 3 at the start
LEVAPPLES = 10
NLEVELS = 8
; tiles
CH_HEAD  = 64           ; +dir
CH_TAIL  = 68           ; +dir towards the next segment
CH_H     = 72
CH_V     = 73
CH_LD    = 74           ; corners named by the two edges they join
CH_RD    = 75
CH_LU    = 76
CH_RU    = 77
CH_APPLE = 78
CH_FLOOR = 79
CH_WH    = 80
CH_WV    = 81
CH_WTL   = 82
CH_WTR   = 83
CH_WBL   = 84
CH_WBR   = 85
CH_PIP   = 86
CH_PIPE  = 87
CH_BLK   = 88
CH_HID   = 89           ; head cell: occupied but drawn by the sprite
NTILES   = 26
SPR      = $3800        ; head sprites, one per dir
TEMPO    = 6
FLOORCOL = 11
WALLCOL  = 6
APPLECOL = 10
WINS     = 5
LOGO     = SCR+3*40+6

!macro text .c, .r, .col, .str {
        lda #<.str
        sta s
        lda #>.str
        sta s+1
        lda #.c
        sta t1
        lda #.col
        sta t2
        ldy #.r
        jsr print
}

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        sei
        lda #<nmi               ; RUN/STOP+RESTORE: see nmi
        sta $0318
        lda #>nmi
        sta $0319
        lda #0
        sta $d020
        sta $d021
        ; charset: ROM letters/digits (first 64 chars) + tiles
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
        ldx #0
-       lda tiles,x
        sta CHARS+CH_HEAD*8,x
        inx
        cpx #NTILES*8
        bne -
        lda #$1c                ; screen $0400, charset $3000
        sta $d018
        lda #$c8                ; hires text
        sta $d016
        ; SID: v1 pulse melody, v2 saw bass, v3 effects
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #8
        sta $d403
        lda #$0a
        sta $d405
        lda #$84
        sta $d406
        lda #$08
        sta $d40c
        lda #$a6
        sta $d40d
        lda #$0a
        sta $d413
        lda #$0f
        sta $d418
        lda #1
        sta mcnt
        lda #$5a
        sta rnd
        lda #1
        sta mon
        ; head sprites: tile glyph in the top-left 8x8 of each
        ldx #0
        txa
-       sta SPR,x
        inx
        bne -
        ldx #31
-       txa
        and #7
        sta t1
        asl
        adc t1
        sta t1                  ; row*3
        txa
        and #$18
        asl
        asl
        asl                     ; dir*64
        ora t1
        tay
        lda tiles,x
        sta SPR,y
        dex
        bpl -
        lda #$ff
        sta $dc02               ; CIA1 port A out (keyboard columns), port B in
        lda #0
        sta $dc03

        lda #2
        sta players
        lda #0
        sta hi
        ldx #4
-       sta hs_sc,x
        dex
        bpl -
        ldx #14
        lda #$2d                ; '-'
-       sta hs_nm,x
        dex
        bpl -
        lda #$ff
        sta newrow

; ---------------------------------------------------------------- title
title:  ldx #$ff                ; the board can be entered from deep in the title loop
        txs
        lda #1
        sta intitle
        lda #0
        sta $d015
        jsr drawfield
        ; logo: 5 rows x 29 cols of '#'
        ldx #0
        ldy #0
-       lda logo,x
        cmp #'#'
        bne +
        lda #CH_BLK
        sta LOGO,y
+       lda logo+29,x
        cmp #'#'
        bne +
        lda #CH_BLK
        sta LOGO+40,y
+       lda logo+58,x
        cmp #'#'
        bne +
        lda #CH_BLK
        sta LOGO+80,y
+       lda logo+87,x
        cmp #'#'
        bne +
        lda #CH_BLK
        sta LOGO+120,y
+       lda logo+116,x
        cmp #'#'
        bne +
        lda #CH_BLK
        sta LOGO+160,y
+       inx
        iny
        cpx #29
        bne -
        ; two demo snakes eyeing an apple
        ldx #6
-       lda demo1,x
        sta SCR+10*40+8,x
        lda democ1,x
        sta COL+10*40+8,x
        lda demo2,x
        sta SCR+10*40+25,x
        lda democ2,x
        sta COL+10*40+25,x
        dex
        bpl -
        lda #CH_APPLE
        sta SCR+10*40+19
        lda #APPLECOL
        sta COL+10*40+19
        +text 8, 13, 13, t_ctl1
        +text 10, 21, 1, t_start
        +text 8, 23, 11, t_f1
        lda #0
        sta wins
        sta wins+1
        jsr waitfire
        lda #0
        sta intitle
        sta score               ; solo: score, level and lives run across rounds
        sta level
        sta lapples
        sta lvlup
        lda players
        bne round
        lda #3
        sta lives

; ---------------------------------------------------------------- round
round:  ldx #0
        lda players
        beq +
        inx
+       stx last
        lda #0
        sta glide
        jsr drawfield
        jsr drawlevel
        lda score
        pha
        jsr initsnakes
        pla
        ldx players
        bne +
        sta score               ; solo keeps its score between lives
+       jsr hud
        lda #13
        sta $d027
        lda #3
        sta $d028
        lda #3
        ldx last
        bne +
        lda #1
+       sta $d015
        +text 15, 12, 1, t_ready
        lda #90
        sta cnt
-       jsr vsync
        jsr fx
        dec cnt
        bne -
        ldx #9
-       lda #CH_FLOOR
        sta SCR+12*40+15,x
        lda #FLOORCOL
        sta COL+12*40+15,x
        dex
        bpl -
        jsr drawlevel           ; the ready text's floor patch may have erased obstacles
        lda #0
        sta aslot
        jsr spawn
        inc aslot
        jsr spawn
        lda #7
        sta speed
        sta tick
        lda #5
        sta ecnt
        lda #1
        sta glide
loop:   jsr vsync
        jsr readin
        lda players
        cmp #2
        beq +
        lda joy                 ; 1 player: any controller
        ora joy+1
        sta joy
+       ldx #0
        jsr steer
        lda players
        cmp #2
        bne +
        ldx #1
        jsr steer
+       jsr fx
        dec tick
        bne loop
        jsr step
        lda speed               ; after step: eating may have sped up
        sta tick
        lda dead
        ora dead+1
        bne crash
        lda lvlup
        beq +
        jmp levelup
+       jmp loop
crash:  lda #0
        sta glide

        ; round over: flash the crashed snake(s), then grey them out
        jsr sfxcrash
        lda #48
        sta cnt
--      jsr vsync
        jsr fx
        lda #1
        sta t2
        lda cnt
        and #4
        beq +
        lda #2
        sta t2
+       lda cnt
        cmp #1
        bne +
        lda #11
        sta t2
+       ldx #1
-       lda dead,x
        beq +
        jsr paint
+       dex
        bpl -
        dec cnt
        bne --
        +text 7, 11, 1, t_blank
        +text 7, 13, 1, t_blank
        +text 7, 14, 1, t_fire
        lda players
        beq +
        jmp versus
+       dec lives
        beq gameover
        jsr hud
        +text 7, 12, 1, t_life
        jsr waitfire
        jmp round
gameover:
        lda score               ; solo: top 5 board, initials if it made the cut
        jsr insert
        bcs +
        +text 7, 12, 1, t_over
        jsr waitfire
        lda #0
        beq ++
+       lda hs_sc
        sta hi
        lda #1
++      jsr board
        jmp title
levelup:
        lda #0
        sta lvlup
        sta lapples
        sta glide
        lda level
        cmp #250
        bcs +
        inc level
+       +text 7, 12, 1, t_lvl
        lda #70
        sta cnt
-       jsr vsync
        jsr fx
        dec cnt
        bne -
        jmp round
versus: lda dead
        and dead+1
        beq +
        +text 7, 12, 1, t_draw
        jmp next
+       ldx #0                  ; winner = the one still alive
        lda dead
        beq +
        inx
+       inc wins,x
        txa
        pha
        jsr hud
        pla
        tax
        lda wins,x
        cmp #WINS
        beq match
        txa
        bne +
        +text 7, 12, 13, t_win1
        jmp next
+       lda players
        cmp #2
        bne +
        +text 7, 12, 3, t_win2
        jmp next
+       +text 7, 12, 3, t_winc
next:   jsr waitfire
        jmp round
match:  txa
        bne +
        +text 7, 12, 13, t_match1
        jmp ++
+       lda players
        cmp #2
        bne +
        +text 7, 12, 3, t_match2
        jmp ++
+       +text 7, 12, 3, t_matchc
++      jsr waitfire
        jmp title

; ---------------------------------------------------------------- frame helpers
vsync:
-       lda $d011               ; wait for the bottom border, then the next frame's top
        bpl -
-       lda $d011
        bmi -
        rts

; per-frame effects: apple bob, sound, title animation
fx:     inc frame
        lda frame
        and #15
        bne ++
        lda frame
        and #16
        lsr
        tax
        ldy #0
-       lda apple,x
        sta CHARS+CH_APPLE*8,y
        inx
        iny
        cpy #8
        bne -
++      jsr sfxtick
        jsr f1key
        jsr music
        lda intitle
        bne +
        jmp sprpos
+        ; logo: gradient bands scrolling down
        lda frame
        lsr
        lsr
        sta t1
        ldy #0
-       tya
        sec
        sbc t1
        and #7
        sta t3
        lda #<(COL+3*40+6)
        clc
        adc rowoff,y
        sta q
        lda #>(COL+3*40+6)
        adc #0
        sta q+1
        ldx t3
        lda wave,x
        sty t3
        ldy #28
--      sta (q),y
        dey
        bpl --
        ldy t3
        iny
        cpy #5
        bne -
        lda frame               ; blink "press fire"
        and #32
        beq +
        lda #1
+       ldx #19
-       sta COL+21*40+10,x
        dex
        bpl -
++      rts

; wait for fire released, then pressed
waitfire:
-       jsr vsync
        jsr fx
        jsr readin
        lda fire
        bne -
-       jsr vsync
        jsr fx
        jsr readin
        lda intitle
        beq +
        jsr menu
+       lda fire
        beq -
        rts

; title: left picks the previous mode, any other direction the next
menu:   lda joy
        ora joy+1
        and #$0f
        tay
        eor prevj
        sty prevj
        and prevj               ; newly pressed
        beq mshow
        and #4
        beq +
        dec players
        bpl mshow
        lda #2
        sta players
        bne mshow
+       inc players
        lda players
        cmp #3
        bne mshow
        lda #0
        sta players
mshow:  jsr getkey
        cmp #8                  ; H
        bne +
        lda #0
        jsr board
        jmp title
+       lda players
        bne +
        +text 10, 19, 1, t_m0
        +text 8, 15, 3, t_blank
        +text 7, 17, 15, t_rule0
        rts
+       cmp #1
        bne +
        +text 10, 19, 1, t_m1
        +text 8, 15, 3, t_cpu
        +text 7, 17, 15, t_rule
        rts
+       +text 10, 19, 1, t_2p
        +text 8, 15, 3, t_ctl2
        +text 7, 17, 15, t_rule
        rts

; ---------------------------------------------------------------- high scores
; A = score: insert into the top 5 (ties below older entries, 0 never) -> carry set, newrow = its row
insert: cmp #0
        beq insno
        ldx #0
-       cmp hs_sc,x
        beq +
        bcs insfound
+       inx
        cpx #5
        bne -
insno:  clc
        rts
insfound:
        stx newrow
        pha
        ldx #4
-       cpx newrow
        beq +
        lda hs_sc-1,x
        sta hs_sc,x
        txa
        asl
        sta t1
        txa
        adc t1                  ; 3 * x (asl cleared carry)
        tay
        lda hs_nm-3,y
        sta hs_nm,y
        lda hs_nm-2,y
        sta hs_nm+1,y
        lda hs_nm-1,y
        sta hs_nm+2,y
        dex
        bne -
+       pla
        ldx newrow
        sta hs_sc,x
        lda #0
        sta pos
        jsr noff
        lda #$2d
        sta hs_nm,x
        sta hs_nm+1,x
        sta hs_nm+2,x
        sec
        rts

; X = offset in hs_nm of the letter at pos in row newrow
noff:   lda newrow
        asl
        adc newrow
        adc pos
        tax
        rts

; the board; A = 1: type initials into row newrow first. Fire/space returns.
board:  sta entry
        lda #0
        sta $d015
        sta intitle
        sta armed
        jsr drawfield
        +text 12, 5, 3, t_hs
bloop:  jsr vsync
        jsr fx
        jsr readin
        jsr drawrows
        lda entry
        bne bentry
        +text 7, 20, 1, t_fire
        lda fire
        bne +
        lda #1
        sta armed
        bne bloop
+       lda armed
        beq bloop
        lda #$ff
        sta newrow
        rts
bentry: +text 7, 20, 3, t_ent
        jsr getkey
        beq bloop
        bmi +
        pha                     ; a letter
        lda pos
        cmp #3
        bne ++
        pla
        jmp bloop
++      jsr noff
        pla
        sta hs_nm,x
        inc pos
        jmp bloop
+       cmp #$81                ; return
        beq +
        lda pos                 ; del
        beq bgo
        dec pos
        jsr noff
        lda #$2d
        sta hs_nm,x
        jmp bloop
+       lda pos
        beq bgo
        jsr sfxeat
        lda #0
        sta entry
bgo:    jmp bloop

drawrows:
        lda #0
        sta ri
rowlp:  asl
        clc
        adc #8
        tay                     ; screen row 8, 10, ...
        lda rowlo,y
        clc
        adc #14
        sta p
        sta q
        lda rowhi,y
        adc #0
        sta p+1
        adc #>(COL-SCR)
        sta q+1
        ldx ri
        lda rankcol,x
        sta t2
        cpx newrow
        bne +
        lda frame               ; the new row blinks white
        and #8
        beq +
        lda #1
        sta t2
+       ldy #10
-       lda #$20
        sta (p),y
        lda t2
        sta (q),y
        dey
        bpl -
        lda ri
        clc
        adc #$31                ; rank digit
        ldy #0
        sta (p),y
        lda ri
        asl
        adc ri
        tax
        ldy #3
-       lda hs_nm,x
        sta (p),y
        inx
        iny
        cpy #6
        bne -
        ldx ri
        lda hs_sc,x
        lsr
        lsr
        lsr
        lsr
        ora #$30
        ldy #9
        sta (p),y
        lda hs_sc,x
        and #15
        ora #$30
        iny
        sta (p),y
        inc ri
        lda ri
        cmp #5
        beq +
        jmp rowlp
+       rts

; one newly pressed key per call: A = screen code A-Z (1-26), $80 del, $81 return, 0 none. Compares the whole
; matrix with the last call's, so a key still held doesn't hide the next one.
getkey: lda #$fe
        sta t2
        ldx #0
gk1:    lda t2
        sta $dc00
        jsr keyin
        sta t1
        lda kmp,x
        eor #$ff
        and t1
        sta knw,x
        lda t1
        sta kmp,x
        sec
        rol t2
        inx
        cpx #8
        bne gk1
        lda #$ff
        sta $dc00
        ldx #0
gk2:    lda knw,x
        bne gk3
        inx
        cpx #8
        bne gk2
        lda #0
        beq gk5
gk3:    ldy #0
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
gk5:    ora #0                  ; flags for the caller
        rts

; ---------------------------------------------------------------- input
; joy = port 2 joystick | W/A/S/D keys, joy+1 = port 1 joystick | I/J/K/L keys, fire = any fire or space
; The KERNAL's NMI stop test reads $DC01 without selecting a column, so it needs $DC00 = $7F (column 7, as its
; own IRQ scan leaves it). Our scans end with $FF, so RUN/STOP+RESTORE did nothing.
nmi:    pha
        lda #$7f
        sta $dc00
        pla
        jmp $fe47

readin: lda #$ff
        sta $dc00
        lda $dc01               ; no column selected: port 1 joystick only
        eor #$ff
        sta t3                  ; all lines pulled low (VICE's joyport sim device also pulls rows 5-7)
        and #$1f
        sta joy+1
        lda $dc00               ; port 2 joystick
        eor #$ff
        and #$1f
        sta joy
        lda #%11111101          ; column 1: W A S
        sta $dc00
        jsr keyrow
        ora joy
        sta joy
        lda #%11111011          ; column 2: D
        sta $dc00
        jsr keyrowr
        ora joy
        sta joy
        lda #%11101111          ; column 4: I J K (same rows as W A S)
        sta $dc00
        jsr keyrow
        ora joy+1
        sta joy+1
        lda #%11011111          ; column 5: L (same row as D)
        sta $dc00
        jsr keyrowr
        ora joy+1
        sta joy+1
        lda #%01111111          ; column 7: space on row 4
        sta $dc00
        lda $dc01
        eor #$ff
        ora joy
        ora joy+1
        and #$10
        sta fire
        lda #$ff
        sta $dc00
        rts

; selected column's rows -> joystick bits (row 1 up, 2 left, 5 down); rows port 1 is
; pulling low are dropped. ponytail: a port-2 joystick held while scanning also selects
; its columns, so P1 fire + P2 keys can ghost; fire is unused in play, so left as is.
keyin:  lda t3
        eor #$ff
        sta t1
        lda $dc01
        eor #$ff
        and t1
        rts

keyrow: jsr keyin
        sta t1
        lda #0
        lsr t1
        lsr t1
        bcc +
        ora #1
+       lsr t1
        bcc +
        ora #4
+       lsr t1
        lsr t1
        lsr t1
        bcc +
        ora #2
+       rts

; column of D / L: row 2 -> right
keyrowr: jsr keyin
        and #4
        beq +
        lda #8
+       rts

; pick a pressed direction perpendicular to the last move (no reversing)
steer:  lda joy,x
        sta t1
        ldy #0
-       lda dmask,y
        and t1
        beq +
        tya
        eor dir,x
        and #1
        beq +
        tya
        sta nd,x
+       iny
        cpy #4
        bne -
        rts

; ---------------------------------------------------------------- game
; A = ring index -> Y = slot of player X
slot:   and #$7f
        ora pbase,x
        tay
        rts

step:   lda players
        cmp #1
        bne +
        ldx #1
        jsr ai
+       ldx last
-       jsr tailmove
        jsr newhead
        dex
        bpl -
        lda last
        beq +
        lda nhl
        cmp nhl+1
        bne +
        lda nhh
        cmp nhh+1
        bne +
        lda #1                  ; head-on into the same cell
        sta dead
        sta dead+1
+       ldx last
-       jsr probe
        dex
        bpl -
        lda dead
        ora dead+1
        bne +
        ldx last
-       jsr advance
        dex
        bpl -
+       rts

; drop the tail cell (unless growing) and redraw the new tail
tailmove:
        lda grow,x
        beq +
        dec grow,x
        rts
+       lda tl,x
        jsr slot
        lda rlo,y
        sta p
        lda rhi,y
        sta p+1
        lda #FLOORCOL
        sta t2
        lda #CH_FLOOR
        jsr putc
        inc tl,x
        lda tl,x
        clc
        adc #1
        jsr slot
        lda rdir,y
        pha
        lda tl,x
        jsr slot
        lda rlo,y
        sta p
        lda rhi,y
        sta p+1
        pla
        clc
        adc #CH_TAIL
        ldy #0
        sta (p),y
        rts

newhead:
        lda hd,x
        jsr slot
        lda rlo,y
        sta t1
        lda rhi,y
        sta t2
        ldy nd,x
        lda t1
        clc
        adc dlo,y
        sta nhl,x
        lda t2
        adc dhi,y
        sta nhh,x
        rts

probe:  lda #0
        sta eat,x
        lda nhl,x
        sta p
        lda nhh,x
        sta p+1
        ldy #0
        lda (p),y
        cmp #CH_FLOOR
        beq ++
        cmp #CH_APPLE
        bne +
        inc eat,x
        rts
+       lda #1
        sta dead,x
++      rts

; old head becomes a body tile, new head drawn; eating grows, scores, respawns
advance:
        lda hd,x
        jsr slot
        lda rlo,y
        sta p
        lda rhi,y
        sta p+1
        lda rdir,y
        asl
        asl
        ora nd,x
        tay
        lda bodych,y
        pha
        txa
        asl
        sta t1
        lda hd,x
        and #1
        ora t1
        tay
        lda stripe,y
        sta t2
        pla
        jsr putc
        ldy nd,x
        tya
        sta dir,x
        lda hx,x
        clc
        adc dxt,y
        sta hx,x
        lda hy,x
        clc
        adc dyt,y
        sta hy,x
        inc hd,x
        lda hd,x
        jsr slot
        lda nhl,x
        sta rlo,y
        sta p
        lda nhh,x
        sta rhi,y
        sta p+1
        lda nd,x
        sta rdir,y
        lda #CH_HID
        jsr putc
        lda eat,x
        beq ++
        lda hd,x                ; ponytail: ring holds 128 cells, so stop growing near that
        sec
        sbc tl,x
        clc
        adc grow,x
        cmp #118
        bcs +
        lda grow,x
        adc #3
        sta grow,x
+       sed
        lda score,x
        clc
        adc #1
        bcc +
        lda #$99                ; ponytail: saturate, the board holds 2 digits
+       sta score,x
        cld
        lda players
        bne lvdone
        inc lapples
        lda lapples
        cmp #LEVAPPLES
        bne lvdone
        sta lvlup
lvdone: dec ecnt
        bne +
        lda #5
        sta ecnt
        lda speed
        cmp #4
        bcc +
        dec speed
+       ldy #0                  ; refill the apple slot that was eaten
        lda hx,x
        cmp ax+1
        bne +
        lda hy,x
        cmp ay+1
        bne +
        iny
+       sty aslot
        txa
        pha
        jsr spawn
        jsr sfxeat
        jsr hud
        pla
        tax
++      rts

; recolour every cell of snake X with t2
paint:  lda t2
        sta $d027,x
        lda tl,x
        sta t3
-       lda t3
        jsr slot
        lda rlo,y
        sta q
        lda rhi,y
        clc
        adc #>(COL-SCR)
        sta q+1
        ldy #0
        lda t2
        sta (q),y
        lda t3
        cmp hd,x
        beq +
        inc t3
        jmp -
+       rts

; solo level layouts (level mod NLEVELS; 0 = open): rects col, row, w, h, $ff ends
drawlevel:
        lda players
        bne dlend
        lda level
-       cmp #NLEVELS
        bcc +
        sbc #NLEVELS            ; carry set
        bne -
+       cmp #0
        beq dlend
        asl
        tax
        lda lvltab-2,x
        sta s
        lda lvltab-1,x
        sta s+1
dlrect: ldy #0
        lda (s),y
        cmp #$ff
        beq dlend
        sta rc
        iny
        lda (s),y
        sta rr
        iny
        lda (s),y
        sta rw
        iny
        lda (s),y
        sta rh
        lda s
        clc
        adc #4
        sta s
        bcc dlrow
        inc s+1
dlrow:  ldy rr
        lda rowlo,y
        clc
        adc rc
        sta p
        lda rowhi,y
        adc #0
        sta p+1
        lda #14
        sta t2
        ldx rw
-       lda #CH_BLK
        jsr putc
        inc p
        bne +
        inc p+1
+       dex
        bne -
        inc rr
        dec rh
        bne dlrow
        jmp dlrect
dlend:  rts

lvltab: !word lv0, lv1, lv2, lv3, lv4, lv5, lv6
lv0:    !byte 20, 4, 1, 18, $ff                                 ; bar
lv1:    !byte 12, 6, 16, 1, 12, 18, 16, 1, $ff
lv2:    !byte 9, 5, 2, 2, 29, 5, 2, 2, 9, 18, 2, 2, 29, 18, 2, 2, $ff
lv3:    !byte 20, 3, 1, 7, 20, 15, 1, 8, 7, 12, 7, 1, 27, 12, 7, 1, $ff
lv4:    !byte 20, 5, 1, 16, 11, 12, 19, 1, $ff                  ; plus
lv5:    !for r, 4, 21 { !byte 32-r, r, 2, 1 }                   ; slash
        !byte $ff
lv6:    !for r, 4, 21 { !byte 32-r, r, 2, 1, r+7, r, 2, 1 }     ; X
        !byte $ff

; apple on a random free cell (cols 1-38, rows 2-23); voice 3 noise is the RNG
spawn:
-       jsr rand
        and #63
        cmp #38
        bcs -
        adc #1
        sta t1
-       jsr rand
        and #31
        cmp #22
        bcs -
        adc #2
        sta sy
        tay
        lda rowlo,y
        clc
        adc t1
        sta p
        lda rowhi,y
        adc #0
        sta p+1
        ldy #0
        lda (p),y
        cmp #CH_FLOOR
        bne spawn
        ldy aslot
        lda t1
        sta ax,y
        lda sy
        sta ay,y
        lda #APPLECOL
        sta t2
        lda #CH_APPLE
        jmp putc

initsnakes:
        lda #0
        sta dead+1
        ldx last
isnake: lda #0
        sta dead,x
        sta grow,x
        sta tl,x
        sta score,x
        lda #3
        sta hd,x
        lda sdir,x
        sta dir,x
        sta nd,x
        lda shx,x
        sta hx,x
        lda shy,x
        sta hy,x
        lda spl,x
        sta p
        lda sph,x
        sta p+1
        lda #0
        sta t3
--      lda t3
        jsr slot
        lda p
        sta rlo,y
        lda p+1
        sta rhi,y
        lda dir,x
        sta rdir,y
        txa
        asl
        sta t1
        lda t3
        and #1
        ora t1
        tay
        lda stripe,y
        sta t2
        lda #CH_H
        ldy t3
        bne +
        lda dir,x
        clc
        adc #CH_TAIL
+       cpy #3
        bne +
        lda #CH_HID
+       jsr putc
        ldy dir,x
        lda p
        clc
        adc dlo,y
        sta p
        lda p+1
        adc dhi,y
        sta p+1
        inc t3
        lda t3
        cmp #4
        bne --
        dex
        bmi +
        jmp isnake
+       rts

; computer steers player X: safe moves only, towards the nearer apple, straight on ties,
; avoiding cells with no free neighbour. ponytail: one step of lookahead, so it can coil itself in.
ai:     ldy #0
        jsr adist
        sta best
        iny
        jsr adist
        cmp best
        bcc +
        ldy #0
+       lda ax,y
        sta tx
        lda ay,y
        sta ty
        lda #$ff
        sta best
        lda dir,x
        sta bdir
        lda #0
        sta kk
ai_c:   ldy kk
        lda turns,y
        clc
        adc dir,x
        and #3
        sta cand
        lda hd,x
        jsr slot
        lda rlo,y
        sta p
        lda rhi,y
        sta p+1
        ldy cand
        lda p
        clc
        adc dlo,y
        sta p
        lda p+1
        adc dhi,y
        sta p+1
        ldy #0
        lda (p),y
        jsr free
        bcc ai_n
        ldy cand
        lda hx,x
        clc
        adc dxt,y
        sec
        sbc tx
        jsr absa
        sta t1
        lda hy,x
        clc
        adc dyt,y
        sec
        sbc ty
        jsr absa
        clc
        adc t1
        sta t1
        lda p                   ; neighbours of the new cell at q+1/40/42/81
        sec
        sbc #41
        sta q
        lda p+1
        sbc #0
        sta q+1
        lda #0
        sta t2
        ldy #1
        jsr nfree
        ldy #40
        jsr nfree
        ldy #42
        jsr nfree
        ldy #81
        jsr nfree
        lda t2
        bne +
        lda t1
        clc
        adc #100
        sta t1
+       lda t1
        cmp best
        bcs ai_n
        sta best
        lda cand
        sta bdir
ai_n:   inc kk
        lda kk
        cmp #3
        beq +
        jmp ai_c
+       lda bdir
        sta nd,x
        rts

nfree:  lda (q),y
        jsr free
        bcc +
        inc t2
+       rts

; C = cell char A is enterable
free:   cmp #CH_FLOOR
        beq +
        cmp #CH_APPLE
        beq +
        clc
        rts
+       sec
        rts

absa:   bpl +
        eor #$ff
        clc
        adc #1
+       rts

; A = distance from apple Y to head of player X
adist:  lda ax,y
        sec
        sbc hx,x
        jsr absa
        sta t1
        lda ay,y
        sec
        sbc hy,x
        jsr absa
        clc
        adc t1
        rts

; ---------------------------------------------------------------- drawing
; A = char at p, t2 = colour
putc:   ldy #0
        sta (p),y
        lda p
        sta q
        lda p+1
        clc
        adc #>(COL-SCR)
        sta q+1
        lda t2
        sta (q),y
        rts

; zero-terminated string s at column t1, row Y, colour t2
print:  lda rowlo,y
        clc
        adc t1
        sta p
        sta q
        lda rowhi,y
        adc #0
        sta p+1
        adc #>(COL-SCR)
        sta q+1
        ldy #0
-       lda (s),y
        beq +
        sta (p),y
        lda t2
        sta (q),y
        iny
        bne -
+       rts

; dotted floor in a neon frame (rows 1-24), blank HUD row
drawfield:
        ldx #0
-       lda #CH_FLOOR
        sta SCR,x
        sta SCR+$100,x
        sta SCR+$200,x
        sta SCR+$2e8,x
        lda #FLOORCOL
        sta COL,x
        sta COL+$100,x
        sta COL+$200,x
        sta COL+$2e8,x
        inx
        bne -
        ldx #39
-       lda #32
        sta SCR,x
        lda #CH_WH
        sta SCR+40,x
        sta SCR+24*40,x
        lda #WALLCOL
        sta COL+40,x
        sta COL+24*40,x
        dex
        bpl -
        ldx #23
-       lda rowlo,x
        sta p
        sta q
        lda rowhi,x
        sta p+1
        clc
        adc #>(COL-SCR)
        sta q+1
        lda #CH_WV
        ldy #0
        sta (p),y
        ldy #39
        sta (p),y
        lda #WALLCOL
        sta (q),y
        ldy #0
        sta (q),y
        dex
        cpx #1
        bne -
        lda #CH_WTL
        sta SCR+40
        lda #CH_WTR
        sta SCR+40+39
        lda #CH_WBL
        sta SCR+24*40
        lda #CH_WBR
        sta SCR+24*40+39
        rts

; row 0: P1 score + win pips, title, P2 win pips + score
hud:    +text 1, 0, 13, t_p1
        +text 16, 0, 3, t_title
        lda #13
        sta t2
        lda score
        ldy #4
        jsr bcd
        lda players
        bne +
        +text 37, 0, 7, t_hi
        lda #7
        sta t2
        lda hi
        ldy #34
        jsr bcd
        ldy #0                  ; lives as pips
livp:   lda #CH_PIPE
        ldx #11
        cpy lives
        bcs livq
        lda #CH_PIP
        ldx #13
livq:   sta SCR+7,y
        txa
        sta COL+7,y
        iny
        cpy #3
        bne livp
        rts
+       cmp #2
        beq +
        +text 37, 0, 3, t_cp
        jmp ++
+       +text 37, 0, 3, t_p2
++      lda #3
        sta t2
        lda score+1
        ldy #34
        jsr bcd
        lda #WINS               ; P2 pips fill from the right
        sec
        sbc wins+1
        sta t1
        ldy #0
-       lda #CH_PIPE
        ldx #11
        cpy wins
        bcs +
        lda #CH_PIP
        ldx #13
+       sta SCR+7,y
        txa
        sta COL+7,y
        lda #CH_PIPE
        ldx #11
        cpy t1
        bcc +
        lda #CH_PIP
        ldx #3
+       sta SCR+28,y
        txa
        sta COL+28,y
        iny
        cpy #WINS
        bne -
        rts

; A = BCD at row 0 column Y, colour t2
bcd:    pha
        lsr
        lsr
        lsr
        lsr
        ora #$30
        sta SCR,y
        pla
        and #15
        ora #$30
        sta SCR+1,y
        lda t2
        sta COL,y
        sta COL+1,y
        rts

; ---------------------------------------------------------------- sound
sfxeat: lda #$10
        sta $d412
        lda #$18
        ldx #6
        ldy #6
        jsr sfxgo
        lda #$11                ; triangle, rising
        sta $d412
        rts

sfxcrash:
        lda #$80
        sta $d412
        lda #$30
        ldx #40
        ldy #$ff
        jsr sfxgo
        lda #$81                ; noise, falling
        sta $d412
        rts

; A = pitch, X = frames, Y = per-frame delta
sfxgo:  sta shi
        sta $d40f
        stx sfx
        sty sdel
        rts

sfxtick:
        lda sfx
        beq ++
        dec sfx
        bne +
        lda #0
        sta $d412
        rts
+       lda shi
        clc
        adc sdel
        sta shi
        sta $d40f
++      rts

; one step every TEMPO frames: melody (64 steps, 0 = rest) on voice 1, root/octave bass on voice 2
; F1 (column 0, row 4) toggles the music on a new press. Port-1 fire pulls the same row, so a row 4
; already low with no column selected doesn't count.
f1key:  ldx #0
        lda #$ff
        sta $dc00
        lda $dc01
        and #$10
        beq +
        lda #%11111110
        sta $dc00
        lda $dc01
        and #$10
        bne +
        inx
+       lda #$ff
        sta $dc00
        txa
        cmp prevf1
        stx prevf1
        bcc +
        beq +
        lda mon
        eor #1
        sta mon
        lda #$40                ; silence melody and bass
        sta $d404
        lda #$20
        sta $d40b
+       rts

music:  lda mon
        bne +
        rts
+       dec mcnt
        beq +
        lda mcnt
        cmp #2                  ; release before the next step: staccato
        bne ++
        lda #$40
        sta $d404
        lda #$20
        sta $d40b
++      rts
+       lda #TEMPO
        sta mcnt
        ldx mi
        ldy mel,x
        beq +
        lda ntlo,y
        sta $d400
        lda nthi,y
        sta $d401
        lda #$41
        sta $d404
+       txa
        lsr
        lsr
        lsr
        tay
        lda broot,y
        tay
        txa
        and #1                  ; odd steps an octave up
        beq +
        tya
        clc
        adc #12
        tay
+       lda ntlo,y
        sta $d407
        lda nthi,y
        sta $d408
        lda #$21
        sta $d40b
        inx
        txa
        and #63
        sta mi
        rts

; 8-bit LFSR, mixed with the raster line
rand:   lda rnd
        asl
        bcc +
        eor #$1d
+       sta rnd
        eor $d012
        rts

; head sprites at their cells, minus the part of the step not yet travelled: back = 8*tick/speed
sprpos: lda #0
        sta t3
        lda glide
        beq +
        lda speed
        cmp #8
        bcs +
        asl
        asl
        asl
        adc tick
        tay
        lda btab-8,y
        sta t3
+       ldx last
sp_l:   lda #0
        sta t2
        lda hx,x
        asl
        asl
        asl
        rol t2
        clc
        adc #24
        sta t1
        lda t2
        adc #0
        sta t2
        ldy dir,x
        lda dxt,y
        beq sp_y
        bmi +
        lda t1                  ; moving right: not there yet
        sec
        sbc t3
        sta t1
        lda t2
        sbc #0
        sta t2
        jmp sp_y
+       lda t1
        clc
        adc t3
        sta t1
        lda t2
        adc #0
        sta t2
sp_y:   lda hy,x
        asl
        asl
        asl
        clc
        adc #50
        sta spry
        lda dyt,y
        beq sp_w
        bmi +
        lda spry
        sec
        sbc t3
        sta spry
        jmp sp_w
+       lda spry
        clc
        adc t3
        sta spry
sp_w:   lda dir,x
        clc
        adc #SPR/64
        sta SCR+$3f8,x
        txa
        asl
        tay
        lda t1
        sta $d000,y
        lda spry
        sta $d001,y
        lda $d010
        and msbclr,x
        ldy t2
        beq +
        ora msbset,x
+       sta $d010
        dex
        bmi +
        jmp sp_l
+       rts

; ---------------------------------------------------------------- data
pbase:  !byte 0, $80
dmask:  !byte 1, 8, 2, 4        ; joystick bit for dir up/right/down/left
dlo:    !byte $d8, $01, $28, $ff ; screen offset per dir: -40, +1, +40, -1
dhi:    !byte $ff, $00, $00, $ff
; body tile for [arrival dir * 4 + leaving dir]
bodych: !byte CH_V,  CH_RD, CH_V, CH_LD
        !byte CH_LU, CH_H,  CH_LD, CH_H
        !byte CH_V,  CH_RU, CH_V, CH_LU
        !byte CH_RU, CH_H,  CH_RD, CH_H
headcol: !byte 13, 3
msbset: !byte 1, 2
msbclr: !byte $fe, $fd
btab:   !for sp, 1, 7 { !for k, 0, 7 { !byte int(8.0*k/sp) } }    ; [speed-1][tick]
FQ = 17.0284                    ; Hz -> SID freq (PAL clock)
ntlo:   !for n, 0, 42 { !byte <int(FQ*82.407*2.0^((n-1)/12.0)+0.5) }   ; 1 = E2 .. 42 = A5
nthi:   !for n, 0, 42 { !byte >int(FQ*82.407*2.0^((n-1)/12.0)+0.5) }
N_E2 = 1
N_F2 = 2
N_G2 = 4
N_A2 = 6
N_E4 = 25
N_F4 = 26
N_G4 = 28
N_GS4 = 29
N_A4 = 30
N_B4 = 32
N_C5 = 33
N_D5 = 35
N_E5 = 37
N_F5 = 38
N_G5 = 40
N_A5 = 42
broot:  !byte N_A2, N_A2, N_F2, N_G2, N_A2, N_A2, N_F2, N_E2    ; Am Am F G Am Am F E
mel:    !byte N_A4,0,N_C5,0,N_E5,0,N_D5,N_C5, N_B4,0,N_A4,0,N_E4,0,0,0
        !byte N_F4,0,N_A4,0,N_C5,0,N_A4,N_C5, N_D5,0,N_C5,0,N_B4,0,N_G4,0
        !byte N_A4,0,N_C5,0,N_E5,0,N_A5,N_G5, N_E5,0,N_D5,0,N_C5,0,0,0
        !byte N_F5,0,N_E5,0,N_D5,0,N_C5,0,    N_B4,0,N_GS4,0,N_E4,0,0,0
rankcol: !byte 7, 1, 13, 3, 14
; keyboard matrix (column * 8 + row) -> A-Z screen codes, $80 del, $81 return
ktab:   !byte $80, $81, 0, 0, 0, 0, 0, 0
        !byte 0, 23, 1, 0, 26, 19, 5, 0
        !byte 0, 18, 4, 0, 3, 6, 20, 24
        !byte 0, 25, 7, 0, 2, 8, 21, 22
        !byte 0, 9, 10, 0, 13, 11, 15, 14
        !byte 0, 16, 12, 0, 0, 0, 0, 0
        !byte 0, 0, 0, 0, 0, 0, 0, 0
        !byte 0, 0, 0, 0, 0, 0, 17, 0
dxt:    !byte 0, 1, 0, $ff
dyt:    !byte $ff, 0, 1, 0
turns:  !byte 0, 1, 3           ; straight, right, left
shx:    !byte 6, 33             ; start head col/row
shy:    !byte 8, 17
stripe: !byte 5, 13, 14, 3      ; body stripes P1 green, P2 blue/cyan
sdir:   !byte 1, 3
spl:    !byte <(SCR+8*40+3), <(SCR+17*40+36)
sph:    !byte >(SCR+8*40+3), >(SCR+17*40+36)
rowlo:  !for r, 0, 24 { !byte <(SCR+r*40) }
rowhi:  !for r, 0, 24 { !byte >(SCR+r*40) }
wave:   !byte 5, 13, 7, 1, 7, 13, 5, 5
rowoff: !byte 0, 40, 80, 120, 160
demo1:  !byte CH_TAIL+1, CH_H, CH_H, CH_H, CH_H, CH_H, CH_HEAD+1
democ1: !byte 13, 5, 13, 5, 13, 5, 13
demo2:  !byte CH_HEAD+3, CH_H, CH_H, CH_H, CH_H, CH_H, CH_TAIL+3
democ2: !byte 3, 3, 14, 3, 14, 3, 14
logo:   !text ".####.#...#..###..#...#.#####"
        !text "#.....##..#.#...#.#..#..#...."
        !text ".###..#.#.#.#####.###...####."
        !text "....#.#..##.#...#.#..#..#...."
        !text "####..#...#.#...#.#...#.#####"
t_p1:   !scr "p1", 0
t_p2:   !scr "p2", 0
t_hi:   !scr "hi", 0
t_m0:   !scr "<      solo       >", 0
t_m1:   !scr "<   vs computer   >", 0
t_rule0: !scr "3 lives. level up at 10 ", 0
t_life: !scr "        life lost!        ", 0
t_lvl:  !scr "       next level!        ", 0
t_over: !scr "        game over!        ", 0
t_hs:   !scr "- high scores -", 0
t_ent:  !scr "type initials, then return", 0
t_cp:   !scr "cp", 0
t_cpu:  !scr "player 2  computer        ", 0
t_2p:   !scr "<    2 players    >", 0
t_winc: !scr "   computer wins round!   ", 0
t_matchc: !scr " computer wins the match! ", 0
t_title: !scr "s n a k e", 0
t_ctl1: !scr "player 1  port 2 / w a s d", 0
t_ctl2: !scr "player 2  port 1 / i j k l", 0
t_rule: !scr "first to five round wins", 0
t_start: !scr "press fire or space", 0
t_f1:   !scr "f1 music on/off  h scores", 0
t_ready: !scr "get ready!", 0
t_blank: !scr "                          ", 0
t_fire: !scr "        press fire        ", 0
t_win1: !scr "   player 1 wins round!   ", 0
t_win2: !scr "   player 2 wins round!   ", 0
t_draw: !scr "   head-on crash! draw.   ", 0
t_match1: !scr " player 1 wins the match! ", 0
t_match2: !scr " player 2 wins the match! ", 0

; apple bob frames (up, down)
apple:  !byte %00001100, %00011000, %01101100, %11111110, %11111110, %11111110, %01111100, %00101000
        !byte %00000000, %00001100, %00011000, %01101100, %11111110, %11111110, %11111110, %01111100

tiles:  ; heads: up, right, down, left
        !byte %00011000, %00111100, %01111110, %01011010, %11111111, %11111111, %11111111, %11111111
        !byte %11110000, %11111100, %11110110, %11111111, %11111111, %11110110, %11111100, %11110000
        !byte %11111111, %11111111, %11111111, %11111111, %01011010, %01111110, %00111100, %00011000
        !byte %00001111, %00111111, %01101111, %11111111, %11111111, %01101111, %00111111, %00001111
        ; tails joining up, right, down, left
        !byte %01111110, %01111110, %01111110, %00111100, %00111100, %00011000, %00011000, %00000000
        !byte %00000000, %00000111, %00011111, %01111111, %01111111, %00011111, %00000111, %00000000
        !byte %00000000, %00011000, %00011000, %00111100, %00111100, %01111110, %01111110, %01111110
        !byte %00000000, %11100000, %11111000, %11111110, %11111110, %11111000, %11100000, %00000000
        ; body: H, V, LD, RD, LU, RU
        !byte %00000000, %11111111, %11111111, %11111111, %11111111, %11111111, %11111111, %00000000
        !byte %01111110, %01111110, %01111110, %01111110, %01111110, %01111110, %01111110, %01111110
        !byte %00000000, %11111000, %11111100, %11111110, %11111110, %11111110, %11111110, %01111110
        !byte %00000000, %00011111, %00111111, %01111111, %01111111, %01111111, %01111111, %01111110
        !byte %01111110, %11111110, %11111110, %11111110, %11111110, %11111100, %11111000, %00000000
        !byte %01111110, %01111111, %01111111, %01111111, %01111111, %00111111, %00011111, %00000000
        ; apple (overwritten by the bob animation), floor dot
        !byte %00001100, %00011000, %01101100, %11111110, %11111110, %11111110, %01111100, %00101000
        !byte %00000000, %00000000, %00000000, %00010000, %00000000, %00000000, %00000000, %00000000
        ; neon double-rail walls: H, V, corners TL, TR, BL, BR
        !byte %00000000, %00000000, %11111111, %00000000, %00000000, %11111111, %00000000, %00000000
        !byte %00100100, %00100100, %00100100, %00100100, %00100100, %00100100, %00100100, %00100100
        !byte %00000000, %00000000, %00001111, %00010000, %00100000, %00100111, %00100100, %00100100
        !byte %00000000, %00000000, %11110000, %00001000, %00000100, %11100100, %00100100, %00100100
        !byte %00100100, %00100100, %00100111, %00100000, %00010000, %00001111, %00000000, %00000000
        !byte %00100100, %00100100, %11100100, %00000100, %00001000, %11110000, %00000000, %00000000
        ; win pip, empty pip, logo block
        !byte %00111100, %01111110, %11111111, %11111111, %11111111, %11111111, %01111110, %00111100
        !byte %00111100, %01000010, %10000001, %10000001, %10000001, %10000001, %01000010, %00111100
        !byte %11111111, %11111111, %11111111, %11111111, %11111111, %11111111, %11111111, %00000000
        ; hidden head (cell under the head sprite)
        !byte 0, 0, 0, 0, 0, 0, 0, 0
