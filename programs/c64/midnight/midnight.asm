; Midnight Hollow - C64 Halloween platformer (ACME). Assets come from gen.py (build/c64/midnight_gen.asm).
; Pick Pip or Dr. Nova, collect 20 pumpkins per level (plus the golden key in the mansion), reach the exit
; before the clock runs out, light the lantern in the Moon Chamber. Joystick port 2 (or 1): left/right walk,
; up jumps, fire throws candy. F1 toggles the music.
;
; KERNAL and BASIC are banked out ($01 = $35); our raster IRQ at $FFFE splits the screen:
;   line 40   top HUD row: no scroll, 40 columns, HUD colours
;   line 57   playfield: 38 columns, fine scroll, level $D021/$D023
;   bands     extra $D021 changes (sky colours) at map rows
;   line 242  bottom HUD row; ends the frame (vsync, music)
; Playfield = map rows 0-22 on screen rows 1-23. Two screen buffers ($4000/$4400): the hidden one is pre-shifted by
; one column in the direction the camera moves ("prep"), and on a coarse step the buffers swap and colour RAM is
; shifted racing the beam (commit, right after the bottom split). Colour of a map char = CTAB[char].
; Sprites: 0 player overlay (hires), 1 player body, 2 candy (or falling hat), 3-7 enemies / moving platforms.

SCRA   = $4000
SCRB   = $4400
CHARS  = $4800
MAP    = $e000          ; level map, column-major, 23 bytes per column (RAM under the KERNAL)
FONT   = $f000          ; ROM letters, 64 chars
CTAB   = $f200          ; colour RAM value per char code
FTAB   = $f300          ; tile flags per char code
CBLO   = $f400          ; map column address per column (160)
CBHI   = $f4a0
ROWS   = 23
F_SOLID = 1
F_PLAT = 2
F_HAZ  = 3
NSLOT  = 5              ; enemy sprite slots (sprites 3-7)
D018A  = $02            ; screen $4000, chars $4800
D018B  = $12            ; screen $4400
GRAV   = 4              ; 1/16 px per frame^2
MAXFALL = 64
O_PUMP = 1
O_CANDY = 2
O_KEY  = 3
O_EXIT = 4
O_LAMP = 5
O_SLOT = 6
E_BAT  = 1
E_GHOST = 2
E_ZOMBIE = 3
E_SKEL = 4
E_SPIDER = 5
E_CROW = 6
E_GARG = 7
E_GEAR = 8
E_BOB  = 9
E_BOSS = 10

; ---------------------------------------------------------------- zero page
p0     = $02
p1     = $04
p2     = $06
t0     = $08
t1     = $09
t2     = $0a
t3     = $0b
t4     = $0c
t5     = $0d
t6     = $0e
t7     = $0f
vsync  = $10
frame  = $11
cxl    = $12            ; camera x (map pixels)
cxh    = $13
coarse = $14            ; map column shown in screen column 0 of the front buffer
curxs  = $15            ; fine scroll used by the IRQ
nxs    = $16            ; fine scroll for the next frame
front  = $17            ; 0 = $4000 shown, 1 = $4400
prepdir = $18           ; back buffer pre-shifted: 0 no, 1 for a right step, $ff for a left step
swap   = $19            ; pending coarse step for the next commit: 0, 1, $ff
d018v  = $1a
pxl    = $1b            ; player x (map pixels, sprite left edge)
pxh    = $1c
pxf    = $1d
py     = $1e            ; player sprite top (map pixels)
pyf    = $1f            ; 1/16 px
vy     = $20            ; signed, 1/16 px per frame
onground = $21
facing = $22            ; 0 right, 1 left
pstate = $23            ; 0 play, 1 dying
joy    = $24            ; up 1 down 2 left 4 right 8 fire 16
joyp   = $25            ; last frame's
spi    = $26            ; IRQ split index
nsplit = $27
level  = $28            ; 0-4
hero   = $29            ; 0 Pip, 1 Nova
lvw    = $2a            ; map width in columns
rnd    = $2b
inv    = $2c            ; invulnerable frames
dtimer = $2d
mstep  = $2e            ; music step
mcnt   = $2f
mon    = $30            ; music on
sfxf   = $31            ; voice 3 effect: frames left, pitch hi, delta
sfxp   = $32
sfxd   = $33
pc0    = $34            ; player box in cells: columns, rows
pc1    = $35
pr0    = $36
pr1    = $37
anim   = $38
carry  = $39            ; L5: carrying a pumpkin
cxmaxl = $3a
cxmaxh = $3b
f1p    = $3c
irq16  = $3d
swapped = $3f
mcur   = $40                ; tune playing
mpend  = $41                ; tune+1 waiting for the fade-out to finish
vol    = $42
irq21  = $3e

; ---------------------------------------------------------------- other variables
sp_line = $0200         ; split table (8 entries)
sp_016 = $0208          ; $ff = playfield (38 columns + fine scroll)
sp_021 = $0210
sp_023 = $0218
shx    = $0220          ; sprite shadows, copied to the VIC at commit
shy    = $0228
shp    = $0230
shc    = $0238
shxh   = $0240
shen   = $0241
shxe   = $0242
shmc   = $0243
score  = $0244          ; BCD, 3 bytes, low first
hisc   = $0247
lives  = $024a
ammo   = $024b
pumps  = $024c          ; pumpkins collected (binary)
npump  = $024d
haskey = $024e
needkey = $024f
exitopen = $0250
chkc   = $0251          ; respawn cell (column, feet row)
chkr   = $0252
hour   = $0253
minute = $0254          ; BCD
endh   = $0255
endm   = $0256
fpm    = $0257          ; frames per game minute
tfr    = $0258
msgt   = $0259          ; frames the message stays on the bottom row
lvfill = $025a
nobj   = $025b
nen    = $025c
placed = $025d
hudd   = $025e          ; HUD needs redraw: bit 0 top, bit 1 bottom
state  = $025f          ; 0 playing, 1 level done, 2 game over, 3 won
dir    = $0260          ; camera moved last frame: 0, 1, $ff
oldcxl = $0261
oldcxh = $0262
hatx   = $0263          ; falling hat (death): x lo/hi, y, active
hatxh  = $0264
haty   = $0265
cact   = $0266          ; candy projectile: active, x lo/hi, y, dir, life
cxl_   = $0267
cxh_   = $0268
cy_    = $0269
cdir   = $026a
clife  = $026b
hatact = $026f
eidx   = $0270
lvwl   = $026d          ; map width in pixels
lvwh   = $026e
otype  = $0300          ; objects (48): type, column, row, state
ocol   = $0330
orow   = $0360
ostat  = $0390
ow     = $03c0          ; per object type 1..6 (index type-1)
oh     = $03c6
altlo  = $03cc
althi  = $03d2
; enemies: spawn list (32) and active slots (5)
sptyp  = $f600
spcol  = $f620
sprow  = $f640
spact  = $f660          ; 1 = in a slot
spdead = $f680
etype  = $f6a0          ; slot arrays (NSLOT)
exl    = $f6a8
exh    = $f6b0
ey     = $f6b8
edx    = $f6c0          ; signed px/frame (or direction)
est    = $f6c8          ; state
etim   = $f6d0
esp    = $f6d8          ; spawn index
ex0l   = $f6e0
ex0h   = $f6e8
ey0    = $f6f0
estun  = $f6f8
eyf    = $f700          ; sub-pixel / phase
evy    = $f708

!macro mov16 .src, .dst {
        lda .src
        sta .dst
        lda .src+1
        sta .dst+1
}

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064
* = $0810
        sei
        cld
        ldx #$ff
        txs
        lda #$7f
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        ; ROM font copy (char ROM visible with $01 = $33)
        lda #$33
        sta $01
        ldx #0
-       lda $d000,x
        sta FONT,x
        lda $d100,x
        sta FONT+$100,x
        inx
        bne -
        lda #$35                ; RAM everywhere but I/O
        sta $01
        lda #<irq
        sta $fffe
        lda #>irq
        sta $ffff
        lda #<nmi
        sta $fffa
        lda #>nmi
        sta $fffb
        lda $dd02
        ora #3
        sta $dd02
        lda $dd00
        and #$fc
        ora #2                  ; VIC bank 1 ($4000)
        sta $dd00
        lda #$ff
        sta $dc02               ; CIA1 port A out (keyboard columns)
        lda #0
        sta $dc03
        lda #$ff
        sta $dc00
        lda #14
        sta $d020
        lda #8
        sta $d022
        lda #0
        sta $d025
        lda #7
        sta $d026
        lda #0
        sta $d01b               ; sprites in front
        sta $d017
        ; SID
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #$08
        sta $d405               ; v1 melody: pulse
        lda #$a6
        sta $d406
        lda #$00
        sta $d40c
        lda #$a8
        sta $d40d
        lda #$09
        sta $d413
        lda #$00
        sta $d414
        lda #8
        sta $d403
        lda #$0f
        sta $d418
        lda #1
        sta mon
        jsr setmusic            ; the intro tune from the start
        lda #15
        sta vol
        lda #0
        sta mpend
        lda #$5a
        sta rnd
        lda #0
        sta hisc
        sta hisc+1
        sta hisc+2
        lda #2
        sta hisc+2              ; HI 020000
        ; raster IRQ
        jsr uisplits
        lda #0
        sta spi
        lda sp_line
        sta $d012
        lda $d011
        and #$7f
        sta $d011
        lda #1
        sta $d01a
        sta $d019
        cli
        jmp intro

nmi:    rti

; ---------------------------------------------------------------- raster IRQ
irq:    pha
        txa
        pha
        tya
        pha
        ; fires on the last line before the change; the writes land in its right border
        ldx spi
        lda sp_016,x
        bpl +
        lda curxs
        ora #$10
+       sta irq16
        lda sp_021,x
        sta irq21
        ldy sp_023,x
        lda irq16
        sta $d016
        lda irq21
        sta $d021
        sty $d023
        ldx spi
        bne +
        lda d018v
        sta $d018
+       inx
        cpx nsplit
        bne +
        ldx #0
        inc vsync
        inc frame
        stx spi
        lda sp_line
        sta $d012
        lda #1
        sta $d019
        jsr sound
        jmp ++
+       stx spi
        lda sp_line,x
        sta $d012
        lda #1
        sta $d019
++      pla
        tay
        pla
        tax
        pla
        rti

; split tables: UI screens (black, no scroll) and levels
uisplits:
        lda #40
        sta sp_line
        lda #242
        sta sp_line+1
        lda #$18
        sta sp_016
        sta sp_016+1
        lda #0
        sta sp_021
        sta sp_021+1
        lda #12
        sta sp_023
        lda #5
        sta sp_023+1
        lda #2
        sta nsplit
        rts

; ui with a $D021 band from screen row A (incl) to row X (excl): colour Y
uiband: sta t0
        stx t1
        sty t2
        lda #40
        sta sp_line
        lda #$18
        sta sp_016
        sta sp_016+1
        sta sp_016+2
        sta sp_016+3
        lda #0
        sta sp_021
        sta sp_021+2
        sta sp_021+3
        lda t2
        sta sp_021+1
        lda #11
        sta sp_023
        sta sp_023+1
        sta sp_023+2
        lda #5
        sta sp_023+3
        lda t0
        jsr rowline
        sta sp_line+1
        lda t1
        jsr rowline
        sta sp_line+2
        lda #242
        sta sp_line+3
        lda #4
        sta nsplit
        rts

rowline:                        ; A = screen row -> raster line just before it
        asl
        asl
        asl
        clc
        adc #50
        rts

; level splits from the level tables (p0 = colours: d021, d023, nbands; p1 = bands: row, colour ...)
lvsplits:
        lda #40
        sta sp_line
        lda #$18
        sta sp_016
        lda #0
        sta sp_021
        lda #5
        sta sp_023
        lda #58
        sta sp_line+1
        lda #$ff
        sta sp_016+1
        ldy #0
        lda (p0),y
        sta sp_021+1
        iny
        lda (p0),y
        sta sp_023+1
        sta t1
        iny
        lda (p0),y
        sta t0                  ; band count
        ldx #2
        ldy #0
-       lda t0
        beq +
        lda (p1),y              ; map row -> screen row+1
        clc
        adc #1
        jsr rowline
        sta sp_line,x
        iny
        lda (p1),y
        sta sp_021,x
        iny
        lda #$ff
        sta sp_016,x
        lda t1
        sta sp_023,x
        inx
        dec t0
        jmp -
+       lda #242
        sta sp_line,x
        lda #$18
        sta sp_016,x
        lda #0
        sta sp_021,x
        lda #5
        sta sp_023,x
        inx
        stx nsplit
        rts

; ---------------------------------------------------------------- frame sync
; wait for the end of the frame, then commit what the last frame's logic decided
waitframe:
        lda #0
        sta vsync
-       lda vsync
        beq -
        rts

commit: ; sprites
        !for i, 0, 7 {
        lda shx+i
        sta $d000+2*i
        lda shy+i
        sta $d001+2*i
        lda shc+i
        sta $d027+i
        lda shp+i
        sta SCRA+$3f8+i
        sta SCRB+$3f8+i
        }
        lda shxh
        sta $d010
        lda shen
        sta $d015
        lda shxe
        sta $d01d
        lda shmc
        sta $d01c
        lda nxs
        sta curxs
        lda #0
        sta swapped
        lda swap
        bne +
        rts
+       bmi cmleft
        ; right step: show the back buffer, shift colour RAM left, colour the new column 39
        inc coarse
        lda front
        eor #1
        sta front
        tax
        lda d018tab,x
        sta d018v
        jsr colright
        lda coarse
        clc
        adc #39
        tax
        jsr colnewR
        jmp cmdone
cmleft: dec coarse
        lda front
        eor #1
        sta front
        tax
        lda d018tab,x
        sta d018v
        jsr colleft
        ldx coarse
        jsr colnewL
cmdone: lda #0
        sta swap
        sta prepdir
        lda #1
        sta swapped
        rts

d018tab: !byte D018A, D018B

; colour RAM shifts, in two halves so the top rows are done before the beam gets there
colright:
        ldx #0
-       !for r, 1, 11 {
        lda $d800+r*40+1,x
        sta $d800+r*40,x
        }
        inx
        cpx #39
        beq +
        jmp -
+       ldx #0
-       !for r, 12, 23 {
        lda $d800+r*40+1,x
        sta $d800+r*40,x
        }
        inx
        cpx #39
        beq +
        jmp -
+       rts

colleft:
        ldx #39
-       !for r, 1, 11 {
        lda $d800+r*40-1,x
        sta $d800+r*40,x
        }
        dex
        beq +
        jmp -
+       ldx #39
-       !for r, 12, 23 {
        lda $d800+r*40-1,x
        sta $d800+r*40,x
        }
        dex
        beq +
        jmp -
+       rts

; colour of a whole screen column from map column X
!macro colnew .sc {
        lda CBLO,x
        sta p2
        lda CBHI,x
        sta p2+1
        !for r, 0, 22 {
        ldy #r
        lda (p2),y
        tax
        lda CTAB,x
        sta $d800+(r+1)*40+.sc
        }
        rts
}
colnewR: +colnew 39
colnewL: +colnew 0

; ---------------------------------------------------------------- back buffer prep
; prep for a right step: back[x] = front[x+1], column 39 = map column coarse+40
!macro prepr .src, .dst {
        ldx #0
-       !for r, 1, 23 {
        lda .src+r*40+1,x
        sta .dst+r*40,x
        }
        inx
        cpx #39
        beq +
        jmp -
+       lda coarse
        clc
        adc #40
        tax
        lda CBLO,x
        sta p2
        lda CBHI,x
        sta p2+1
        !for r, 0, 22 {
        ldy #r
        lda (p2),y
        sta .dst+(r+1)*40+39
        }
        rts
}
!macro prepl .src, .dst {
        ldx #39
-       !for r, 1, 23 {
        lda .src+r*40-1,x
        sta .dst+r*40,x
        }
        dex
        beq +
        jmp -
+       ldx coarse
        dex
        lda CBLO,x
        sta p2
        lda CBHI,x
        sta p2+1
        !for r, 0, 22 {
        ldy #r
        lda (p2),y
        sta .dst+(r+1)*40
        }
        rts
}
prepRAB: +prepr SCRA, SCRB
prepRBA: +prepr SCRB, SCRA
prepLAB: +prepl SCRA, SCRB
prepLBA: +prepl SCRB, SCRA

; prepare the back buffer for direction A (1 right, $ff left), if possible
prep:   cmp prepdir
        beq ++
        cmp #1
        bne +
        lda coarse              ; right: needs map column coarse+40
        clc
        adc #40
        cmp lvw
        bcs ++
        lda #1
        sta prepdir
        lda front
        bne +++
        jmp prepRAB
+++     jmp prepRBA
+       lda coarse              ; left: needs coarse-1
        beq ++
        lda #$ff
        sta prepdir
        lda front
        bne +++
        jmp prepLAB
+++     jmp prepLBA
++      rts

; ---------------------------------------------------------------- map
; screen row (map row+1) offsets
rowlo:  !for r, 1, 23 { !byte <(r*40) }
rowhi:  !for r, 1, 23 { !byte >(r*40) }

; A = map char at column X, row Y (preserves X, Y)
getcell:
        lda CBLO,x
        sta p2
        lda CBHI,x
        sta p2+1
        lda (p2),y
        rts

; set map cell column t5, row t6 to A; updates the front buffer (and the prepped back buffer) if visible
setcell:
        sta t7
        ldx t5
        ldy t6
        lda CBLO,x
        sta p2
        lda CBHI,x
        sta p2+1
        lda t7
        sta (p2),y
        ; front
        lda t5
        sec
        sbc coarse
        cmp #40
        bcs +
        ldx front
        jsr putscr
        jsr putcol
+       lda prepdir
        beq +
        lda coarse
        clc
        adc prepdir
        sta t4
        lda t5
        sec
        sbc t4
        cmp #40
        bcs +
        ldx front
        lda front
        eor #1
        tax
        lda t5
        sec
        sbc t4
        jsr putscr
+       rts

; screen column A, row t6, buffer X: store t7 (leaves p2 = screen address)
putscr: ldy t6
        clc
        adc rowlo,y
        sta p2
        lda rowhi,y
        adc bufhi,x
        sta p2+1
        ldy #0
        lda t7
        sta (p2),y
        rts
bufhi:  !byte >SCRA, >SCRB

putcol: lda p2+1                ; same offset in colour RAM
        and #3
        ora #$d8
        sta p2+1
        ldx t7
        lda CTAB,x
        ldy #0
        sta (p2),y
        rts

; draw the whole playfield into the front buffer (and colour RAM)
drawall:
        lda front
        tax
        lda bufhi,x
        sta p1+1
        lda #40
        sta p1                  ; p1 = row 1 of the buffer
        lda #$d8
        sta t3                  ; colour hi
        lda #0
        sta t0                  ; screen column
dacol:  lda coarse
        clc
        adc t0
        tax
        lda CBLO,x
        sta p0
        lda CBHI,x
        sta p0+1
        lda p1
        clc
        adc t0
        sta p2
        lda p1+1
        adc #0
        sta p2+1
        ldy #0
darow:  sty t1
        lda (p0),y
        ldy #0
        sta (p2),y
        tax
        lda p2+1
        pha
        and #3
        ora #$d8
        sta p2+1
        lda CTAB,x
        sta (p2),y
        pla
        sta p2+1
        lda p2
        clc
        adc #40
        sta p2
        bcc +
        inc p2+1
+       ldy t1
        iny
        cpy #ROWS
        bne darow
        inc t0
        lda t0
        cmp #40
        bne dacol
        lda #0
        sta prepdir
        rts

; ---------------------------------------------------------------- charsets
; install tileset A (0 ui, 1-5 levels): font + tiles into CHARS, colour and flag tables
setcs:  tax
        lda cs_tab_lo,x
        sta p0
        lda cs_tab_hi,x
        sta p0+1
        lda cs_col_lo,x
        sta p1
        lda cs_col_hi,x
        sta p1+1
        lda cs_flg_lo,x
        sta t2
        lda cs_flg_hi,x
        sta t3
        lda cs_n,x
        sta t0
        ldx #0
-       lda FONT,x
        sta CHARS,x
        lda FONT+$100,x
        sta CHARS+$100,x
        lda #1
        sta CTAB,x
        lda #0
        sta FTAB,x
        inx
        bne -
        ; tiles: t0 chars of 8 bytes from p0
        lda #<(CHARS+$200)
        sta p2
        lda #>(CHARS+$200)
        sta p2+1
        lda t0
        sta t1
--      ldy #7
-       lda (p0),y
        sta (p2),y
        dey
        bpl -
        lda p0
        clc
        adc #8
        sta p0
        bcc +
        inc p0+1
+       lda p2
        clc
        adc #8
        sta p2
        bcc +
        inc p2+1
+       dec t1
        bne --
        ldy #0
-       lda (p1),y
        sta CTAB+64,y
        iny
        cpy t0
        bne -
        lda t2
        sta p1
        lda t3
        sta p1+1
        ldy #0
-       lda (p1),y
        sta FTAB+64,y
        iny
        cpy t0
        bne -
        rts

; ---------------------------------------------------------------- text helpers
; print zero-terminated screen codes at (p0) to buffer A row Y column X colour A (to both buffers)
print:  sta t2
        stx t0
        sty t1
        ldy #0
-       lda (p0),y
        beq +
        sta t3
        tya
        pha
        clc
        adc t0
        tax
        ldy t1
        lda t3
        jsr putxy
        pla
        tay
        iny
        bne -
+       rts

; put char A at column X row Y with colour t2, both buffers
putxy:  pha
        lda scrlo,y
        sta p2
        lda scrhi,y
        sta p2+1
        txa
        tay
        pla
        sta (p2),y
        pha
        lda p2+1
        eor #4                  ; SCRA <-> SCRB
        sta p2+1
        pla
        sta (p2),y
        lda p2+1
        and #3
        ora #$d8
        sta p2+1
        lda t2
        sta (p2),y
        rts
scrlo:  !for r, 0, 24 { !byte <(SCRA+r*40) }
scrhi:  !for r, 0, 24 { !byte >(SCRA+r*40) }

!macro print .c, .r, .col, .str {
        lda #<.str
        sta p0
        lda #>.str
        sta p0+1
        ldx #.c
        ldy #.r
        lda #.col
        jsr print
}

; clear both buffers to spaces, colour RAM to A
cls:    sta t0
        ldx #0
-       lda #32
        sta SCRA,x
        sta SCRA+$100,x
        sta SCRA+$200,x
        sta SCRA+$2e8,x
        sta SCRB,x
        sta SCRB+$100,x
        sta SCRB+$200,x
        sta SCRB+$2e8,x
        lda t0
        sta $d800,x
        sta $d900,x
        sta $da00,x
        sta $dae8,x
        inx
        bne -
        rts

; stamp at column X row Y from ui stamp table p0 (w, h, codes...), colours from CTAB
stamp:  stx t4
        sty t5
        ldy #0
        lda (p0),y
        sta t6                  ; w
        iny
        lda (p0),y
        sta t7                  ; h
        lda #2
        sta t3                  ; index into codes
--      ldx #0
-       stx t1
        ldy t3
        lda (p0),y
        pha
        tay
        lda CTAB,y
        sta t2
        txa
        clc
        adc t4
        tax
        ldy t5
        pla
        jsr putxy
        inc t3
        ldx t1
        inx
        cpx t6
        bne -
        inc t5
        dec t7
        bne --
        rts

; ---------------------------------------------------------------- input
readjoy:
        lda joy
        sta joyp
        lda $dc00
        and $dc01
        eor #$ff
        and #$1f
        sta joy
        ; F1: column 0, row 4 - unless row 4 is already low with no column selected (port 1 fire)
        lda $dc01
        and #$10
        beq +
        lda #$fe
        sta $dc00
        lda $dc01
        ldx #$ff
        stx $dc00
        and #$10
        bne +
        lda f1p
        bne ++
        lda #1
        sta f1p
        jsr togglemusic
        rts
+       lda #0
        sta f1p
++      rts

; fire pressed this frame (Z clear = yes)
firenew:
        lda joyp
        eor #$ff
        and joy
        and #$10
        rts

rand:   lda rnd
        asl
        bcc +
        eor #$1d
+       sta rnd
        eor $d012
        rts


; ================================================================ game
newgame:
        lda #0
        sta score
        sta score+1
        sta score+2
        sta level
        lda #3
        sta lives
        lda #5
        sta ammo
nextlevel:
        jsr levelcard
        jsr startlevel
play:   jsr waitframe
        jsr commit
        jsr gameframe
        lda state
        beq play
        cmp #1
        bne +
        jsr leveldone
        inc level
        lda level
        cmp #NLEVELS
        bcc nextlevel
        jmp ending
+       cmp #2
        bne +
        jmp gameover
+       jsr leveldone
        jmp ending

gameframe:
        jsr readjoy
        lda pstate
        bne +
        jsr player
        jsr throw
        jsr objects
        jsr clock
        jmp ++
+       jsr dying
++      jsr enemies
        jsr candy
        jsr camera
        jsr sprites
        jsr hud
        inc anim
        rts

; ---------------------------------------------------------------- level start
startlevel:
        jsr blank
        ldx level
        lda lt_set,x
        jsr setcs
        ldx level
        lda lt_w,x
        sta lvw
        ; map width in pixels and the camera limit
        lda #0
        sta lvwh
        lda lvw
        asl
        rol lvwh
        asl
        rol lvwh
        asl
        rol lvwh
        sta lvwl
        sec
        sbc #<320
        sta cxmaxl
        lda lvwh
        sbc #>320
        sta cxmaxh
        ; column addresses: MAP + c*23
        lda #<MAP
        sta p0
        lda #>MAP
        sta p0+1
        ldx #0
-       lda p0
        sta CBLO,x
        lda p0+1
        sta CBHI,x
        lda p0
        clc
        adc #ROWS
        sta p0
        bcc +
        inc p0+1
+       inx
        cpx #160
        bne -
        ; unpack the map (RLE: $ff count value)
        ldx level
        lda lt_map_lo,x
        sta p0
        lda lt_map_hi,x
        sta p0+1
        lda #<MAP
        sta p1
        lda #>MAP
        sta p1+1
        ldx lvw                 ; bytes left = lvw*23: count columns of 23
        stx t4
        lda #ROWS
        sta t5
        ldy #0
unp:    lda (p0),y
        jsr inc0
        cmp #$ff
        bne +
        lda (p0),y
        sta t6
        jsr inc0
        lda (p0),y
        jsr inc0
        sta t7
-       lda t7
        jsr unput
        bcs unpd
        dec t6
        bne -
        jmp unp
+       jsr unput
        bcc unp
unpd:   ; level parameters
        ldx level
        lda lt_fill,x
        sta lvfill
        lda lt_npump,x
        sta npump
        lda lt_colors_lo,x
        sta p0
        lda lt_colors_hi,x
        sta p0+1
        lda lt_bands_lo,x
        sta p1
        lda lt_bands_hi,x
        sta p1+1
        jsr blank               ; splits change: keep the screen off meanwhile
        sei
        jsr lvsplits
        lda #0
        sta spi
        lda sp_line
        sta $d012
        cli
        ; objects
        ldx level
        lda lt_nobj,x
        sta nobj
        lda lt_obj_lo,x
        sta p0
        lda lt_obj_hi,x
        sta p0+1
        ldx #0
        ldy #0
        lda #0
        sta needkey
-       cpx nobj
        beq +
        lda (p0),y
        sta otype,x
        cmp #O_KEY
        bne ++
        sta needkey
++      iny
        lda (p0),y
        sta ocol,x
        iny
        lda (p0),y
        sta orow,x
        iny
        lda #0
        sta ostat,x
        inx
        bne -
+       ldx level
        lda lt_ow_lo,x
        sta p0
        lda lt_ow_hi,x
        sta p0+1
        lda lt_oh_lo,x
        sta p1
        lda lt_oh_hi,x
        sta p1+1
        ldy #5
-       lda (p0),y
        sta ow,y
        lda (p1),y
        sta oh,y
        dey
        bpl -
        lda lt_alt_lo,x
        sta p0
        lda lt_alt_hi,x
        sta p0+1
        ldy #0
        ldx #0
-       lda (p0),y
        sta altlo,x
        iny
        lda (p0),y
        sta althi,x
        iny
        inx
        cpx #6
        bne -
        ; enemy spawns
        ldx level
        lda lt_nen,x
        sta nen
        lda lt_en_lo,x
        sta p0
        lda lt_en_hi,x
        sta p0+1
        ldx #0
        ldy #0
-       cpx nen
        beq +
        lda (p0),y
        sta sptyp,x
        iny
        lda (p0),y
        sta spcol,x
        iny
        lda (p0),y
        sta sprow,x
        iny
        inx
        bne -
+       ; start cell, clock
        ldx level
        lda lt_start_lo,x
        sta p0
        lda lt_start_hi,x
        sta p0+1
        ldy #0
        lda (p0),y
        sta chkc
        iny
        lda (p0),y
        sta chkr
        jsr resettime
        lda #0
        sta pumps
        sta haskey
        sta exitopen
        sta placed
        sta carry
        sta state
        sta msgt
        jsr respawn
        rts

inc0:   inc p0
        bne +
        inc p0+1
+       rts

; store A at (p1), advance; C set when the map is full
unput:  ldy #0
        sta (p1),y
        inc p1
        bne +
        inc p1+1
+       dec t5
        bne +
        lda #ROWS
        sta t5
        dec t4
        bne +
        sec
        rts
+       clc
        rts

resettime:
        ldx level
        lda lt_time_lo,x
        sta p0
        lda lt_time_hi,x
        sta p0+1
        ldy #0
        lda (p0),y
        sta hour
        iny
        lda (p0),y
        sta minute
        iny
        lda (p0),y
        sta endh
        iny
        lda (p0),y
        sta endm
        iny
        lda (p0),y
        sta fpm
        lda #0
        sta tfr
        lda #2
        ora hudd
        sta hudd
        rts

blank:  jsr waitframe
        lda $d011
        and #$ef
        sta $d011
        lda #0
        sta $d015
        sta shen
        rts

unblank:
        jsr waitframe
        lda $d011
        ora #$10
        and #$7f
        sta $d011
        rts

; put the player at the checkpoint, reset enemies and the camera, redraw everything
respawn:
        jsr blank
        lda chkc
        sta pxl
        lda #0
        sta pxh
        asl pxl
        rol pxh
        asl pxl
        rol pxh
        asl pxl
        rol pxh
        lda pxl
        sec
        sbc #4
        sta pxl
        bcs +
        dec pxh
+       lda chkr
        asl
        asl
        asl
        sec
        sbc #13
        sta py
        lda #0
        sta pyf
        sta vy
        sta pxf
        sta pstate
        sta onground
        sta facing
        sta cact
        sta hatact
        sta dir
        lda #90
        sta inv
        ldx #NSLOT-1
-       lda #0
        sta etype,x
        dex
        bpl -
        ldx #31
-       lda #0
        sta spact,x
        sta spdead,x
        dex
        bpl -
        jsr camx                ; camera on the player, coarse/fine from it
        lda t0
        sta cxl
        lda t1
        sta cxh
        jsr coarseof
        sta coarse
        lda nxs
        sta curxs
        lda #0
        sta swap
        sta front
        lda #D018A
        sta d018v
        jsr drawall
        lda #3
        sta hudd
        jsr hud
        jsr sprites
        jsr commit
        jsr unblank
        rts

; t0/t1 = camera x for the player position, clamped to 0..cxmax
camx:   lda pxl
        sec
        sbc #148
        sta t0
        lda pxh
        sbc #0
        sta t1
        bpl +
        lda #0
        sta t0
        sta t1
        rts
+       lda t0
        cmp cxmaxl
        lda t1
        sbc cxmaxh
        bcc +
        lda cxmaxl
        sta t0
        lda cxmaxh
        sta t1
+       rts

; coarse column (A) and nxs for camera cxl/cxh: coarse = (cx+7)>>3, xs = (-cx)&7
coarseof:
        lda cxl
        eor #$ff
        clc
        adc #1
        and #7
        sta nxs
        lda cxl
        clc
        adc #7
        sta t2
        lda cxh
        adc #0
        lsr
        ror t2
        lsr
        ror t2
        lsr
        ror t2
        lda t2
        rts

; ---------------------------------------------------------------- camera
camera: lda cxl
        sta oldcxl
        lda cxh
        sta oldcxh
        jsr camx
        lda t0
        sta cxl
        lda t1
        sta cxh
        ; direction
        lda #0
        sta dir
        lda cxl
        cmp oldcxl
        bne +
        lda cxh
        cmp oldcxh
        beq ++
+       lda cxl
        cmp oldcxl
        lda cxh
        sbc oldcxh
        lda #1
        bcs +
        lda #$ff
+       sta dir
++      jsr coarseof
        cmp coarse
        beq camnop
        bcc +
        lda #1
        bne ++
+       lda #$ff
++      sta swap
        jmp prep                ; no-op when already prepped that way
camnop: lda dir                 ; prep ahead, but not in the frame that already shifted colour RAM
        beq +
        ldx swapped
        bne +
        jmp prep
+       rts

; ---------------------------------------------------------------- tiles under a point
; A = tile flag at map pixel (t0/t1, Y=t2). 0 outside the map (sides, above, below).
tflag:  lda t1
        bmi tf0
        lda t2
        cmp #ROWS*8
        bcs tf0
        lsr
        lsr
        lsr
        tay
        lda t1
        sta t3
        lda t0
        lsr t3
        ror
        lsr t3
        ror
        lsr t3
        ror
        cmp lvw
        bcs tf0
        tax
        jsr getcell
        tax
        lda FTAB,x
        rts
tf0:    lda #0
        rts

; t0/t1 = px + A
pxplus: clc
        adc pxl
        sta t0
        lda pxh
        adc #0
        sta t1
        rts

; flag at (px+A, row Y*8) - used for feet probes: A = x offset, t2 = y
probe:  jsr pxplus
        jmp tflag

; ---------------------------------------------------------------- player
spdlo:  !byte $80, $c0      ; walk speed 1.5 / 1.75 px (SPD 3 / 4)
jmpv:   !byte 90, 82        ; jump velocity (JMP 4 / 3): 63 / 52 px
lucky:  !byte 77, 102       ; hit survival chance /256 (LUK 3 / 4, 30% / 40%)

player: lda joy
        and #4
        beq +
        lda #1
        sta facing
        lda pxf
        sec
        ldx hero
        sbc spdlo,x
        sta t4
        lda pxl
        sbc #1
        sta t5
        lda pxh
        sbc #0
        sta t6
        bmi pnox                ; left edge
        lda t5                  ; wall at the left side of the box
        clc
        adc #6
        sta t0
        lda t6
        adc #0
        sta t1
        jsr wallat
        bne pnox
        jmp pmovex
+       lda joy
        and #8
        beq pnox
        lda #0
        sta facing
        lda pxf
        clc
        ldx hero
        adc spdlo,x
        sta t4
        lda pxl
        adc #1
        sta t5
        lda pxh
        adc #0
        sta t6
        ; right edge: px <= width*8 - 24
        lda t5
        clc
        adc #24
        sta t0
        lda t6
        adc #0
        sta t1
        lda t0
        cmp lvwl
        lda t1
        sbc lvwh
        bcs pnox
        lda t5
        clc
        adc #17
        sta t0
        lda t6
        adc #0
        sta t1
        jsr wallat
        bne pnox
pmovex: lda t4
        sta pxf
        lda t5
        sta pxl
        lda t6
        sta pxh
pnox:   ; ---- vertical
        lda onground
        beq pair
        lda joy
        and #1
        beq +
        ldx hero
        lda #0
        sec
        sbc jmpv,x
        sta vy
        lda #0
        sta onground
        sta onplat
        lda #SFX_JUMP
        jsr sfx
        jmp pair
+       lda onplat
        bne pdj
        jsr support
        bne pdj
        lda #0
        sta onground
        jmp pair
pdj:    jmp pdone
pair:   lda vy
        clc
        adc #GRAV
        bmi +
        cmp #MAXFALL
        bcc +
        lda #MAXFALL
+       sta vy
        lda py
        clc
        adc #20
        sta t7                  ; old feet
        lda vy
        clc
        adc pyf
        sta t0
        and #15
        sta pyf
        lda t0
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        sta t0
        clc
        adc py
        ldx vy
        bpl pfall
        ; rising
        cmp py
        bcc +
        beq +
        lda #0                  ; above the top of the map
        sta vy
+       sta py
        clc
        adc #2                  ; head
        sta t2
        cmp #ROWS*8
        bcs pdone
        lda #8
        jsr probe
        cmp #F_SOLID
        beq +
        lda #15
        jsr probe
        cmp #F_SOLID
        bne pdone
+       lda t2                  ; bump: head just under the tile
        and #$f8
        clc
        adc #8-2
        sta py
        lda #0
        sta vy
        sta pyf
        jmp pdone
pfall:  sta py
        jsr platland
        bcs pdone
        lda py
        clc
        adc #20
        sta t2                  ; new feet
        cmp #ROWS*8+8
        bcs pdone
        eor t7
        and #$f8
        beq pdone               ; same row as before
        lda t7
        cmp #ROWS*8+8
        bcs pdone
        jsr landok
        beq pdone
        lda t2                  ; land on top of that row
        and #$f8
        sec
        sbc #21
        sta py
        lda #0
        sta vy
        sta pyf
        lda #1
        sta onground
pdone:  ; ---- fell out of the map or into a hazard
        lda py
        cmp #ROWS*8+4
        bcc +
        cmp #$e0
        bcs +
        jmp kill
+       lda #11
        sta t2
        lda py
        clc
        adc #12
        sta t2
        lda #12
        jsr probe
        cmp #F_HAZ
        bne +
        jmp kill
+       lda py
        clc
        adc #20
        sta t2
        lda #12
        jsr probe
        cmp #F_HAZ
        bne +
        jmp kill
+       rts

; Z clear when a solid tile is at x t0/t1 for the body rows (py+3, py+11, py+19)
wallat: lda t0
        pha
        lda t1
        pha
        lda py
        clc
        adc #3
        sta t2
        jsr tflag
        cmp #F_SOLID
        beq wyes
        pla
        sta t1
        pla
        sta t0
        pha
        lda t1
        pha
        lda py
        clc
        adc #11
        sta t2
        jsr tflag
        cmp #F_SOLID
        beq wyes
        pla
        sta t1
        pla
        sta t0
        lda py
        clc
        adc #19
        sta t2
        jsr tflag
        cmp #F_SOLID
        beq +
        lda #0
        rts
wyes:   pla
        pla
+       lda #1
        rts

; standing: Z clear when ground (solid/plat) is right under the feet
support:
        lda py
        clc
        adc #21
        sta t2
; t2 = row pixel to test under both feet
support2:
        lda #7
        jsr probe
        cmp #F_SOLID
        beq +
        cmp #F_PLAT
        beq +
        lda #16
        jsr probe
        cmp #F_SOLID
        beq +
        cmp #F_PLAT
        beq +
        lda #0
        rts
+       lda #1
        rts

; landing: Z clear when a foot is over a solid/platform tile at row pixel t2 with nothing standable on top
; (so a jump up through a 2-row platform lands on its top row, not inside it)
landok: lda #7
        jsr landfoot
        bne +
        lda #16
        jsr landfoot
+       rts
landfoot:
        sta t5
        jsr probe
        cmp #F_SOLID
        beq +
        cmp #F_PLAT
        bne ++
+       lda t2
        pha
        sec
        sbc #8
        sta t2
        lda t5
        jsr probe
        tax
        pla
        sta t2
        cpx #F_SOLID
        beq ++
        cpx #F_PLAT
        beq ++
        lda #1
        rts
++      lda #0
        rts

; player dies (unless lucky, see hurt)
kill:   lda pstate
        bne +
        lda #1
        sta pstate
        lda #100
        sta dtimer
        lda #$c0
        sta vy
        lda #0
        sta onplat
        lda pxl
        clc
        adc #2
        sta hatx
        lda pxh
        adc #0
        sta hatxh
        lda py
        sta haty
        lda #1
        sta hatact
        lda #SFX_DIE
        jsr sfx
+       rts

; enemy touched the player
hurt:   lda inv
        ora pstate
        bne +
        jsr rand
        ldx hero
        cmp lucky,x
        bcs kill
        lda #90                 ; lucky: blink and lose a candy
        sta inv
        lda ammo
        beq ++
        dec ammo
        lda hudd
        ora #1
        sta hudd
++      lda #SFX_LUCK
        jsr sfx
+       rts

dying:  dec dtimer
        bne +
        jmp died
+       lda dtimer
        cmp #88
        bcc +
        and #2                  ; flash
        beq ++
        lda #1
        !byte $2c
++      lda #14
        sta $d020
        jmp dmove
+       lda #14
        sta $d020
dmove:  lda vy                  ; fall through everything
        clc
        adc #2
        bmi +
        cmp #$40
        bcc +
        lda #$40
+       sta vy
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        cmp #$80
        ror
        clc
        adc py
        ldx py
        cpx #$f0
        bcs +
        sta py
+       ; hat floats down, swaying
        lda anim
        and #1
        beq +
        inc haty
+       lda anim
        and #16
        beq +
        inc hatx
        bne ++
        inc hatxh
        jmp ++
+       lda hatx
        bne +
        dec hatxh
+       dec hatx
++      rts

died:   dec lives
        bne +
        lda #2
        sta state
        rts
+       lda pstate
        cmp #2
        bne +
        jsr resettime           ; out of time: the clock starts over
+       jmp respawn

; ---------------------------------------------------------------- moving platforms (L4)
onplat: !byte 0
; called while falling: land on a gear/pendulum sprite whose top the feet just passed. C set if landed.
platland:
        ldx #NSLOT-1
-       lda etype,x
        cmp #E_GEAR
        beq +
        cmp #E_BOB
        bne pln
+       lda ey,x                ; top
        sec
        sbc #1
        cmp t7                  ; old feet below the top: no
        bcc pln
        lda py
        clc
        adc #20
        cmp ey,x
        bcc pln
        ; x overlap: ex-12 <= px <= ex + width - 12
        lda pxl
        sec
        sbc exl,x
        sta t0
        lda pxh
        sbc exh,x
        sta t1
        lda t0
        clc
        adc #12
        sta t0
        lda t1
        adc #0
        bne pln
        lda platw-E_GEAR,x
        lda etype,x
        tay
        lda t0
        cmp platw-E_GEAR,y
        bcs pln
        lda ey,x
        sec
        sbc #21
        sta py
        lda #0
        sta vy
        sta pyf
        lda #1
        sta onground
        inx
        stx onplat
        sec
        rts
pln:    dex
        bpl -
        clc
        rts
platw:  !byte 48+12, 24+12   ; gear (x-expanded), pendulum bob

; keep the player on the platform it stands on (after the platforms moved): t0 = dx of slot onplat-1
ride:   ldx onplat
        beq +++
        dex
        lda pstate
        bne ++
        lda onground
        beq ++
        lda edxl,x              ; platform moved this frame
        clc
        adc pxl
        sta pxl
        lda edxl,x
        and #$80
        beq +
        lda #$ff
+       adc pxh
        sta pxh
        lda ey,x
        sec
        sbc #21
        sta py
        ; walked off? same test as platland: 0 <= px - ex + 12 < width
        lda pxl
        sec
        sbc exl,x
        sta t0
        lda pxh
        sbc exh,x
        sta t1
        lda t0
        clc
        adc #12
        sta t0
        lda t1
        adc #0
        bne ++
        lda etype,x
        tay
        lda t0
        cmp platw-E_GEAR,y
        bcc +++
++      lda #0
        sta onplat
        sta onground
+++     rts
edxl:   !fill NSLOT, 0

; ---------------------------------------------------------------- candy throw
throw:  jsr firenew
        beq +
        lda cact
        bne +
        lda ammo
        beq +
        dec ammo
        lda hudd
        ora #1
        sta hudd
        lda #1
        sta cact
        lda #60
        sta clife
        lda py
        clc
        adc #9
        sta cy_
        ldx facing
        lda pxl
        clc
        adc cthrowx,x
        sta cxl_
        lda pxh
        adc cthrowxh,x
        sta cxh_
        lda cthrowd,x
        sta cdir
        lda #SFX_THROW
        jsr sfx
+       rts
cthrowx: !byte 14, <-6
cthrowxh: !byte 0, $ff
cthrowd: !byte 3, <-3

candy:  lda cact
        beq ++
        dec clife
        beq +
        lda cdir
        clc
        adc cxl_
        sta cxl_
        lda cdir
        and #$80
        beq ++++
        lda #$ff
++++    adc cxh_
        sta cxh_
        ; hit a wall?
        lda cxl_
        clc
        adc #6
        sta t0
        lda cxh_
        adc #0
        sta t1
        lda cy_
        clc
        adc #2
        sta t2
        jsr tflag
        cmp #F_SOLID
        beq +
        jsr candyhit
        rts
+       lda #0
        sta cact
++      rts

; ---------------------------------------------------------------- objects
objects:
        ; player box in cells
        lda #6
        jsr pxplus
        jsr t0col
        sta pc0
        lda #17
        jsr pxplus
        jsr t0col
        sta pc1
        lda py
        clc
        adc #2
        lsr
        lsr
        lsr
        sta pr0
        lda py
        clc
        adc #20
        bcc +
        lda #$ff
+       lsr
        lsr
        lsr
        sta pr1
        ldx #0
oblp:   cpx nobj
        bne +
        rts
+       lda ostat,x
        bne obnext
        ldy otype,x
        lda ocol,x
        cmp pc1
        beq +
        bcs obnext              ; starts right of the player
+       clc
        adc ow-1,y
        sec
        sbc #1
        cmp pc0
        bcc obnext              ; ends left of the player
        lda orow,x
        cmp pr1
        beq +
        bcs obnext
+       clc
        adc oh-1,y
        sec
        sbc #1
        cmp pr0
        bcc obnext
        stx oidx
        tya
        asl
        tay
        lda objtab-2,y
        sta p1
        lda objtab-1,y
        sta p1+1
        jsr jp1
        ldx oidx
obnext: inx
        jmp oblp
jp1:    jmp (p1)
objtab: !word getpump, getcandy, getkey, atexit, getlamp, atslot

t0col:  lda t1
        lsr
        sta t3
        lda t0
        ror
        lsr t3
        ror
        lsr t3
        ror
        rts

getpump:
        lda level
        cmp #4
        bne +
        lda carry               ; Moon Chamber: carry one at a time
        bne ++
        lda #1
        sta carry
        jmp gp1
+       inc pumps
        lda #2
        ora hudd
        sta hudd
gp1:    jsr erase
        lda #<$0100             ; 100 points
        ldx #1
        jsr addscore
        lda #SFX_CHIME
        jsr sfx
        jsr checkopen
++      rts

getcandy:
        lda ammo
        cmp #5
        bcs +
        clc
        adc #3
        cmp #5
        bcc ++
        lda #5
++      sta ammo
        jsr erase
        lda #1
        ora hudd
        sta hudd
        lda #SFX_CANDY
        jsr sfx
+       rts

getkey: lda #1
        sta haskey
        jsr erase
        lda #$00
        ldx #5
        jsr addscore
        lda #2
        ora hudd
        sta hudd
        lda #SFX_KEY
        jsr sfx
        jsr checkopen
        lda #<msgkey
        ldx #>msgkey
        jmp message

; all pumpkins (and the key if the level has one): open the exit
checkopen:
        lda oidx
        pha
        jsr chkopen
        pla
        sta oidx
        rts
chkopen:
        lda exitopen
        bne +
        lda pumps
        cmp npump
        bcc +
        lda needkey
        beq ++
        lda haskey
        beq +
++      lda #1
        sta exitopen
        ldx #0                  ; swap every exit to its open stamp
-       cpx nobj
        beq ++
        lda otype,x
        cmp #O_EXIT
        bne +++
        stx oidx
        jsr altstamp
        ldx oidx
+++     inx
        bne -
++      lda #<msgopen
        ldx #>msgopen
        jsr message
        lda #SFX_KEY
        jsr sfx
+       rts

atexit: lda exitopen
        beq +
        lda #1
        sta state
+       rts

getlamp:
        lda #1
        sta ostat,x
        lda ocol,x
        sta chkc
        lda orow,x
        clc
        adc #2
        sta chkr
        jsr altstamp
        lda #SFX_CANDY
        jsr sfx
        lda #<msglamp
        ldx #>msglamp
        jmp message

atslot: lda carry
        beq +
        lda #0
        sta carry
        lda #1
        ldx oidx
        sta ostat,x
        jsr altstamp
        inc placed
        inc pumps
        lda #2
        ora hudd
        sta hudd
        lda #$00
        ldx #5
        jsr addscore
        lda #SFX_KEY
        jsr sfx
        lda placed
        cmp npump
        bcc +
        lda #3
        sta state
+       rts

; object t7: mark taken, fill its cells with the level's empty char
erase:  ldx oidx
        lda #1
        sta ostat,x
        lda #0
        sta p1+1                ; no alt: fill
        jmp ostamp
; object t7: stamp its type's alt chars (open exit, lit lamp, filled slot)
altstamp:
        ldx oidx
        ldy otype,x
        lda altlo-1,y
        sta p1
        lda althi-1,y
        sta p1+1
ostamp: ldx oidx
        ldy otype,x
        lda ow-1,y
        sta t0
        lda oh-1,y
        sta t1
        lda ocol,x
        sta t2
        lda orow,x
        sta t6
        lda #0
        sta t3                  ; alt index
--      lda t2
        sta t5
        lda t0
        sta t4
-       lda p1+1
        beq +
        ldy t3
        lda (p1),y
        jmp ++++
+       lda lvfill
++++
        ldx t4                  ; setcell clobbers t4
        stx otmp
        jsr setcell
        ldx otmp
        stx t4
        inc t3
        inc t5
        dec t4
        bne -
        inc t6
        dec t1
        bne --
        rts
otmp:   !byte 0
oidx:   !byte 0

; ---------------------------------------------------------------- score / hud
; add A (low BCD byte) + X (hundreds BCD) to the score
addscore:
        sed
        clc
        adc score
        sta score
        txa
        adc score+1
        sta score+1
        lda score+2
        adc #0
        sta score+2
        cld
        lda hudd
        ora #1
        sta hudd
        rts

clock:  lda fpm
        beq ++
        inc tfr
        lda tfr
        cmp fpm
        bcc ++
        lda #0
        sta tfr
        sed
        lda minute
        clc
        adc #1
        sta minute
        cld
        cmp #$60
        bne +
        lda #0
        sta minute
        inc hour
+       lda hudd
        ora #2
        sta hudd
        lda hour
        cmp endh
        bne ++
        lda minute
        cmp endm
        bne ++
        jsr kill                ; out of time
        lda #2
        sta pstate
        lda #<msgtime
        ldx #>msgtime
        jsr message
++      rts

; A/X = zero-terminated message for the bottom row (3 s)
message:
        sta p0
        stx p0+1
        lda #150
        sta msgt
        jsr clrbottom
        ldy #0
-       lda (p0),y
        beq +
        iny
        bne -
+       tya                     ; centre
        eor #$ff
        sec
        adc #40
        lsr
        tax
        ldy #24
        lda #1
        jmp print

clrbottom:
        ldx #39
-       lda #32
        sta SCRA+24*40,x
        sta SCRB+24*40,x
        dex
        bpl -
        rts

hud:    lda msgt
        beq +
        dec msgt
        bne +
        lda hudd
        ora #2
        sta hudd
+       lda hudd
        and #1
        beq +
        jsr hudtop
+       lda hudd
        and #2
        beq +
        lda msgt
        bne +
        jsr hudbot
+       lda #0
        sta hudd
        rts

hudtop: +print 0, 0, 3, txscore
        +print 12, 0, 5, txhi
        lda #<score
        ldx #6
        jsr bcd6
        lda #<hisc
        ldx #16
        jsr bcd6
        ; lives: 3 pumpkins from column 23, candy: 5 from column 30
        ldx #0
-       stx t5
        txa
        asl
        adc #23
        tax
        lda #32
        sta t6
        sta t7
        lda t5
        cmp lives
        bcs +
        lda #T_LIFE
        sta t6
        lda #T_LIFE+1
        sta t7
+       lda CTAB+T_LIFE
        sta t2
        ldy #0
        lda t6
        jsr putxy
        inx
        ldy #0
        lda t7
        jsr putxy
        ldx t5
        inx
        cpx #3
        bne -
        ldx #0
-       stx t5
        lda #32
        cpx ammo
        bcs +
        lda #T_C
+       pha
        txa
        clc
        adc #30
        tax
        lda CTAB+T_C
        sta t2
        ldy #0
        pla
        jsr putxy
        ldx t5
        inx
        cpx #5
        bne -
        rts

; 3 BCD bytes at $02xx (A = low byte address) printed as 6 digits at column X of row 0, white
bcd6:   sta p0
        lda #$02
        sta p0+1
        stx t5
        lda #1
        sta t2
        ldy #2
-       sty t6
        lda (p0),y
        lsr
        lsr
        lsr
        lsr
        ora #$30
        ldx t5
        ldy #0
        jsr putxy
        inc t5
        ldy t6
        lda (p0),y
        and #15
        ora #$30
        ldx t5
        ldy #0
        jsr putxy
        inc t5
        ldy t6
        dey
        bpl -
        rts

hudbot: jsr clrbottom
        ldx level
        lda lt_name_lo,x
        sta p0
        lda lt_name_hi,x
        sta p0+1
        ldy #0
-       sty t6
        lda (p0),y
        ldx #7                  ; "LEVEL n" yellow
        cpy #7
        bcc +
        ldx #1
+       stx t2
        tax
        tya
        pha
        txa
        pha
        tya
        tax
        ldy #24
        pla
        jsr putxy
        pla
        tay
        iny
        cpy #21
        bne -
        +print 22, 24, 5, txcandy
        ; pumpkins nn/20
        lda #1
        sta t2
        lda pumps
        jsr dec2
        ldx #28
        jsr put2
        lda #'/'
        ldx #30
        ldy #24
        jsr putxy
        lda npump
        jsr dec2
        ldx #31
        jsr put2
        ; key
        lda needkey
        beq +
        lda #6+8                ; dim until found
        ldx haskey
        beq ++
        lda CTAB+T_K
++      sta t2
        lda #T_K
        ldx #33
        ldy #24
        jsr putxy
        lda #T_K+1
        ldx #34
        ldy #24
        jsr putxy
+       ; clock " H:MM" / "HH:MM"
        lda #1
        sta t2
        lda hour
        jsr dec2
        lda t0
        cmp #'0'
        bne ++
        lda #32
        sta t0
++      ldx #35
        jsr put2
        lda #':'
        ldx #37
        ldy #24
        jsr putxy
        lda minute
        lsr
        lsr
        lsr
        lsr
        ora #$30
        ldx #38
        ldy #24
        jsr putxy
        lda minute
        and #15
        ora #$30
        ldx #39
        ldy #24
        jsr putxy
+       rts

; A (0-99) -> t0/t1 digit screen codes
dec2:   ldx #$30
-       cmp #10
        bcc +
        sbc #10
        inx
        bne -
+       ora #$30
        sta t1
        stx t0
        rts
put2:   stx t5
        lda t0
        ldy #24
        jsr putxy
        ldx t5
        inx
        lda t1
        ldy #24
        jmp putxy

txscore: !scr "score", 0
txhi:   !scr " hi ", 0
txcandy: !scr "candy", 0
msgkey: !scr "golden key! the tower door opens.", 0
msgopen: !scr "the way is open", 0
msglamp: !scr "checkpoint", 0
msgtime: !scr "midnight is coming... too slow!", 0

; ================================================================ enemies
; spawn table -> sprite slots when they come near the camera
spawns: lda #4                  ; a few spawn points per frame
        sta spcnt
spl:    ldy spnext
        iny
        cpy nen
        bcc +
        ldy #0
+       sty spnext
        dec spcnt
        bpl +
        rts
+       lda nen
        beq spn3
        lda spact,y
        ora spdead,y
        bne spn3
        jsr spawnx              ; t0/t1 = spawn x - camera x + 48
        lda cxmaxl              ; single screen (L5), gears, pendulums: anywhere at x -32..327
        ora cxmaxh
        beq spany
        lda sptyp,y
        cmp #E_GEAR
        beq spany
        cmp #E_BOB
        beq spany
        ; monsters only just off screen (x -48..-17 or 312..343): they come in from an edge
        lda t1
        bne +
        lda t0
        cmp #32
        bcc spon
        bcs spn3
+       cmp #1
        bne spn3
        lda t0
        sec
        sbc #104
        cmp #32
        bcc spon
        bcs spn3
spany:  lda t1
        bne +
        lda t0
        cmp #16
        bcs spon
        bcc spn3
+       cmp #1
        bne spn3
        lda t0
        cmp #120
        bcs spn3
spon:   jsr activate
spn3:   jmp spl
spcnt:  !byte 0
spnext: !byte 0

; t0/t1 = spcol(y)*8 - cx + 48
spawnx: lda #0
        sta t1
        lda spcol,y
        asl
        rol t1
        asl
        rol t1
        asl
        rol t1
        clc
        adc #48
        sta t0
        lda t1
        adc #0
        sta t1
        lda t0
        sec
        sbc cxl
        sta t0
        lda t1
        sbc cxh
        sta t1
        rts

; put spawn Y into a free slot
activate:
        ldx #NSLOT-1
-       lda etype,x
        beq +
        dex
        bpl -
        ; all slots busy: a gear/pendulum (needed to cross a gap) takes a slot from a plain enemy
        lda sptyp,y
        cmp #E_GEAR
        beq ++
        cmp #E_BOB
        bne +++
++      ldx #NSLOT-1
-       lda etype,x
        cmp #E_GEAR
        beq ++
        cmp #E_BOB
        bne +
++      dex
        bpl -
+++     rts
+       lda etype,x
        beq +
        tya                     ; evict: its spawn point can come back later
        pha
        ldy esp,x
        lda #0
        sta spact,y
        pla
        tay
+       lda #1
        sta spact,y
        tya
        sta esp,x
        lda sptyp,y
        sta etype,x
        lda #0
        sta exh,x
        sta est,x
        sta etim,x
        sta estun,x
        sta eyf,x
        sta evy,x
        lda spcol,y
        asl
        rol exh,x
        asl
        rol exh,x
        asl
        rol exh,x
        sta exl,x
        sta ex0l,x
        lda exh,x
        sta ex0h,x
        lda sprow,y
        asl
        asl
        asl
        sta ey,x
        sta ey0,x
        lda #1                  ; face the player
        sta edx,x
        lda pxl
        cmp exl,x
        lda pxh
        sbc exh,x
        bcs +
        lda #$ff
        sta edx,x
+       lda etype,x
        cmp #E_ZOMBIE
        beq +
        cmp #E_SKEL
        bne ++
+       lda ey,x                ; walkers: feet on the bottom of the spawn cell
        sec
        sbc #13
        sta ey,x
        sta ey0,x
++      lda etype,x
        cmp #E_BAT
        beq +
        cmp #E_GEAR
        bne ++
+       lda #40
        sta etim,x
++      txa                     ; pendulums and the swarm start out of phase
        asl
        asl
        asl
        asl
        sta eyf,x
        rts

enemies:
        jsr spawns
        ldx #NSLOT-1
enlp:   stx eidx
        lda #0
        sta edxl,x
        lda etype,x
        beq ennext
        ; gone far from the camera: free the slot (it can spawn again)
        lda exl,x
        sec
        sbc cxl
        sta t0
        lda exh,x
        sbc cxh
        sta t1
        lda t0
        clc
        adc #80
        sta t0
        lda t1
        adc #0
        beq +
        cmp #1
        bne efree
        lda t0
        cmp #224                ; 480: right edge + 80
        bcs efree
+       lda etype,x
        asl
        tay
        lda etab-2,y
        sta p1
        lda etab-1,y
        sta p1+1
        jsr jp1
        ldx eidx
        lda etype,x
        cmp #E_GEAR
        beq ennext
        cmp #E_BOB
        beq ennext
        jsr ecoll
        jmp ennext
efree:  lda #0
        sta etype,x
        ldy esp,x
        sta spact,y
ennext: ldx eidx
        dex
        bpl enlp
        jmp ride

etab:   !word ebat, eghost, ezomb, eskel, espider, ecrow, egarg, egear, ebob, eboss

; ex += A (signed); remembered in edxl for riders
movex:  sta edxl,x
        clc
        adc exl,x
        sta exl,x
        lda edxl,x
        and #$80
        beq +
        lda #$ff
+       adc exh,x
        sta exh,x
        rts

; signed sin, 64 steps, amplitude 31
sin64:  !for i, 0, 63 { !byte <int(31.5*sin(float(i)*3.14159265/32.0)) }

; A = sin64[A & 63]
sin:    and #63
        tay
        lda sin64,y
        rts

ebat:   lda edx,x
        jsr movex
        inc etim,x
        lda etim,x
        cmp #80
        bcc +
        lda #0
        sta etim,x
        jsr turn
+       inc eyf,x
        lda eyf,x
        lsr
        jsr sin
        cmp #$80
        ror
        cmp #$80
        ror
        clc
        adc ey0,x
        sta ey,x
        rts

turn:   lda edx,x
        eor #$ff
        clc
        adc #1
        sta edx,x
        rts

eghost: lda estun,x
        beq +
        dec estun,x
        rts
+       lda frame
        and #1
        beq ++
        lda pxl
        cmp exl,x
        lda pxh
        sbc exh,x
        lda #1
        bcs +
        lda #$ff
+       sta edx,x
        jsr movex
        lda py
        cmp ey,x
        beq ++
        bcc +
        inc ey,x
        rts
+       dec ey,x
++      rts

ezomb:  lda frame
        and #1
        bne +
        rts
+       jsr walkok
        bcc +
        jsr turn
        rts
+       lda edx,x
        jmp movex

; C set when the walker at slot X must not step on: no floor ahead or a wall
walkok: lda edx,x
        bmi +
        lda #19
        !byte $2c
+       lda #4
        sta t4
        lda ey,x
        clc
        adc #21
        jsr eprobe
        cmp #F_SOLID
        beq +
        cmp #F_PLAT
        bne wno
+       lda ey,x
        clc
        adc #10
        jsr eprobe
        cmp #F_SOLID
        beq wno
        clc
        rts
wno:    sec
        rts

; flag at (ex + t4, A) for slot eidx; X restored
eprobe: sta t2
        ldx eidx
        lda exl,x
        clc
        adc t4
        sta t0
        lda exh,x
        adc #0
        sta t1
        lda t4
        bpl +
        dec t1
+       jsr tflag
        ldx eidx
        rts

eskel:  lda est,x
        beq eswalk
        ; hopping over a gap: evy in 1/4 px
        lda edx,x
        jsr movex
        inc evy,x
        lda evy,x
        cmp #$80
        ror
        cmp #$80
        ror
        clc
        adc ey,x
        sta ey,x
        lda evy,x
        bmi +
        lda ey,x
        cmp ey0,x
        bcc +
        lda ey0,x
        sta ey,x
        lda #0
        sta est,x
+       rts
eswalk: jsr walkok
        bcc ++
        ; floor 3 cells ahead? hop, else turn
        lda edx,x
        bmi +
        lda #19+24
        !byte $2c
+       lda #<(4-24)
        sta t4
        lda ey,x
        clc
        adc #21
        jsr eprobe
        cmp #F_SOLID
        beq +
        cmp #F_PLAT
        beq +
        jmp turn
+       lda #1
        sta est,x
        lda #<-14
        sta evy,x
        rts
++      lda edx,x
        jmp movex

espider:
        lda etim,x
        beq +
        dec etim,x
        rts
+       lda est,x
        bne ++
        inc ey,x
        lda ey,x
        sec
        sbc ey0,x
        cmp #40
        bcc +
        lda #1
        sta est,x
        lda #30
        sta etim,x
+       rts
++      dec ey,x
        lda ey,x
        cmp ey0,x
        bne +
        lda #0
        sta est,x
        lda #50
        sta etim,x
+       rts

; |px - ex| (low byte, saturated) in A
pdist:  lda pxl
        sec
        sbc exl,x
        sta t0
        lda pxh
        sbc exh,x
        beq +
        cmp #$ff
        bne pfar
        lda t0
        eor #$ff
        clc
        adc #1
        rts
pfar:   lda #$ff
        rts
+       lda t0
        bmi pfar
        rts

ecrow:  lda est,x
        bne ++
        lda etim,x
        beq +
        dec etim,x
        rts
+       jsr pdist
        cmp #72
        bcs +
        lda py
        cmp ey,x
        bcc +
        lda #1
        sta est,x
        lda pxl
        cmp exl,x
        lda pxh
        sbc exh,x
        lda #2
        bcs ++++
        lda #<-2
++++    sta edx,x
+       rts
++      cmp #1
        bne ++
        lda edx,x
        jsr movex
        inc ey,x
        inc ey,x
        lda ey,x
        cmp #160
        bcs +
        sec
        sbc ey0,x
        cmp #96
        bcs +
        lda ey,x
        sec
        sbc #4
        cmp py
        bcc +++
+       lda #2
        sta est,x
+++     rts
++      lda edx,x
        cmp #$80
        ror
        jsr movex
        dec ey,x
        lda ey,x
        cmp ey0,x
        bne +
        lda #0
        sta est,x
        lda #90
        sta etim,x
        jsr turn
+       rts

egarg:  lda est,x
        bne ++
        lda etim,x
        beq +
        dec etim,x
        rts
+       jsr pdist
        cmp #20
        bcs +
        lda py
        cmp ey,x
        bcc +
        lda #1
        sta est,x
+       rts
++      cmp #1
        bne ++
        lda ey,x
        clc
        adc #3
        sta ey,x
        cmp #160
        bcs +
        lda #4
        sta t4
        lda ey,x
        clc
        adc #17
        jsr eprobe
        cmp #F_SOLID
        beq +
        cmp #F_PLAT
        bne +++
+       lda #2
        sta est,x
+++     rts
++      dec ey,x
        lda ey,x
        cmp ey0,x
        bne +
        lda #0
        sta est,x
        lda #60
        sta etim,x
+       rts

egear:  lda edx,x
        jsr movex
        inc etim,x
        lda etim,x
        cmp #80
        bcc +
        lda #0
        sta etim,x
        jsr turn
+       rts

; pendulum bob: x = ex0 + sin, y lowest in the middle of the swing
ebob:   inc eyf,x
        lda eyf,x
        lsr
        jsr sin
        sta t0
        clc
        adc ex0l,x
        sta t1
        lda t0
        and #$80
        beq +
        lda #$ff
+       adc ex0h,x
        sta t2
        lda t1                  ; edxl = new - old
        sec
        sbc exl,x
        sta edxl,x
        lda t1
        sta exl,x
        lda t2
        sta exh,x
        lda t0
        bpl +
        eor #$ff
        clc
        adc #1
+       lsr
        eor #$ff
        sec
        adc #16
        clc
        adc ey0,x
        sta ey,x
        rts

; the Count's bat swarm circles the lantern, faster with every pumpkin placed
eboss:  lda estun,x
        beq +
        dec estun,x
        rts
+       lda placed
        lsr
        clc
        adc #1
        adc eyf,x
        sta eyf,x
        lsr
        lsr
        jsr sin                 ; x: ex0 + 3*sin
        sta t0
        asl
        clc
        adc t0
        sta t0
        clc
        adc ex0l,x
        sta exl,x
        lda t0
        and #$80
        beq +
        lda #$ff
+       adc ex0h,x
        sta exh,x
        lda eyf,x
        lsr
        lsr
        clc
        adc #16
        jsr sin                 ; y: ey0 + 1.5*cos
        sta t0
        cmp #$80
        ror
        clc
        adc t0
        clc
        adc ey0,x
        sta ey,x
        rts

; per type (1..10): box half width/height, box centre y offset in the sprite, points (BCD lo, hundreds)
ehw:    !byte 9, 8, 5, 5, 6, 7, 8, 0, 0, 9
ehh:    !byte 3, 7, 8, 8, 3, 3, 5, 0, 0, 3
ecy:    !byte 3, 10, 12, 12, 3, 4, 11, 0, 0, 3
eplo:   !byte $00, $00, $00, $00, $50, $00, $00, 0, 0, 0
ephi:   !byte $01, $00, $02, $03, $01, $02, $03, 0, 0, 0
ecol:   !byte 4, 1, 5, 1, 2, 11, 12, 12, 7, 2
eptr:   !byte SP_BAT1, SP_BAT2, SP_BAT1, SP_BAT2
        !byte SP_GHOST1, SP_GHOST2, SP_GHOST1, SP_GHOST2
        !byte SP_ZOMBIE1, SP_ZOMBIE2, SP_ZOMBIE1_L, SP_ZOMBIE2_L
        !byte SP_SKEL1, SP_SKEL2, SP_SKEL1_L, SP_SKEL2_L
        !byte SP_SPIDER, SP_SPIDER, SP_SPIDER, SP_SPIDER
        !byte SP_CROW1, SP_CROW2, SP_CROW1_L, SP_CROW2_L
        !byte SP_GARG1, SP_GARG1, SP_GARG1, SP_GARG1
        !byte SP_GEAR, SP_GEAR, SP_GEAR, SP_GEAR
        !byte SP_BOB, SP_BOB, SP_BOB, SP_BOB
        !byte SP_BAT1, SP_BAT2, SP_BAT1, SP_BAT2

; t0 = |(ex,ey+ecy) - (point t4/t5, t6)| test: C set when within (ehw+A, ehh+t7)
; point x 16-bit in t4/t5, y in t6; A = extra half width, t7 = extra half height
boxhit: sta t3
        ldy etype,x
        lda exl,x
        clc
        adc #12
        sta t0
        lda exh,x
        adc #0
        sta t1
        lda t0
        sec
        sbc t4
        sta t0
        lda t1
        sbc t5
        beq +
        cmp #$ff
        bne bmiss
        lda t0
        eor #$ff
        clc
        adc #1
        bmi bmiss
        sta t0
        jmp ++
+       lda t0
        bmi bmiss
++      lda ehw-1,y
        clc
        adc t3
        cmp t0
        bcc bmiss
        beq bmiss
        lda ey,x
        clc
        adc ecy-1,y
        sec
        sbc t6
        bcs +
        eor #$ff
        adc #1
+       sta t0
        lda ehh-1,y
        clc
        adc t7
        cmp t0
        bcc bmiss
        beq bmiss
        sec
        rts
bmiss:  clc
        rts

; enemy slot X vs the player
ecoll:  lda inv
        ora pstate
        bne +
        lda pxl
        clc
        adc #12
        sta t4
        lda pxh
        adc #0
        sta t5
        lda py
        clc
        adc #11
        sta t6
        lda #9
        sta t7
        lda #5
        jsr boxhit
        bcc +
        jmp hurt
+       rts

; the candy vs every enemy slot
candyhit:
        lda cxl_
        clc
        adc #6
        sta t4
        lda cxh_
        adc #0
        sta t5
        lda cy_
        clc
        adc #2
        sta t6
        ldx #NSLOT-1
-       lda etype,x
        beq +
        cmp #E_GEAR
        beq +
        cmp #E_BOB
        beq +
        lda #2
        sta t7
        lda #3
        jsr boxhit
        bcs chit
+       dex
        bpl -
        rts
chit:   lda #0
        sta cact
        lda etype,x
        cmp #E_GHOST
        bne +
        lda #150
        sta estun,x
        lda #SFX_STUN
        jmp sfx
+       cmp #E_BOSS
        bne +
        lda #120
        sta estun,x
        lda #SFX_STUN
        jmp sfx
+       tay
        lda #0
        sta etype,x
        lda eplo-1,y
        pha
        lda ephi-1,y
        pha
        ldy esp,x
        lda #1
        sta spdead,y
        lda #0
        sta spact,y
        pla
        tax
        pla
        jsr addscore
        lda #SFX_HIT
        jmp sfx

; ================================================================ sprite shadows
pptr:   !byte SP_PIP_STAND, SP_PIP_STAND_L, SP_PIP_RUN1, SP_PIP_RUN1_L, SP_PIP_RUN2, SP_PIP_RUN2_L
        !byte SP_PIP_JUMP, SP_PIP_JUMP_L, SP_PIP_HURT, SP_PIP_HURT_L
        !byte SP_NOVA_STAND, SP_NOVA_STAND_L, SP_NOVA_RUN1, SP_NOVA_RUN1_L, SP_NOVA_RUN2, SP_NOVA_RUN2_L
        !byte SP_NOVA_JUMP, SP_NOVA_JUMP_L, SP_NOVA_HURT, SP_NOVA_HURT_L
herobody: !byte 3, 1    ; cyan cape / white coat
heroovl: !byte 10, 14   ; pink face / light blue mask
bits:   !byte 1, 2, 4, 8, 16, 32, 64, 128

; sprite X at map position t0/t1 (x), A (y): shadow x/y/msb/enable; C set if off screen
place:  clc
        adc #59
        bcs poff
        cmp #250
        bcs poff
        sta shy,x
        lda t0
        sec
        sbc cxl
        sta t0
        lda t1
        sbc cxh
        sta t1
        lda t0
        clc
        adc #24
        sta t0
        lda t1
        adc #0
        bmi poff
        beq +
        cmp #1
        bne poff
        lda t0
        cmp #88                 ; 344
        bcs poff
        lda shxh
        ora bits,x
        sta shxh
+       lda t0
        sta shx,x
        lda shen
        ora bits,x
        sta shen
        clc
        rts
poff:   sec
        rts

sprites:
        lda #0
        sta shen
        sta shxh
        sta shxe
        lda #$fe
        sta shmc
        lda inv
        beq +
        dec inv
        and #4
        bne spr2                ; blinking
+       ; player frame: 0 stand, 1/2 run, 3 jump, 4 hurt
        ldy #4
        lda pstate
        bne +
        ldy #3
        lda onground
        beq +
        ldy #0
        lda joy
        and #12
        beq +
        lda anim
        lsr
        lsr
        lsr
        and #1
        tay
        iny
+       tya
        asl
        ora facing
        sta t2
        lda hero
        beq +
        lda #10
+       clc
        adc t2
        tay
        lda pptr,y
        sta shp+1
        clc
        adc #1
        sta shp
        ldx hero
        lda herobody,x
        sta shc+1
        lda heroovl,x
        sta shc
        ldx #0
        jsr placeplayer
        ldx #1
        jsr placeplayer
spr2:   ; sprite 2: candy or the falling hat
        lda cact
        beq +
        lda #SP_CANDY
        sta shp+2
        lda #2
        sta shc+2
        lda cxl_
        sta t0
        lda cxh_
        sta t1
        lda cy_
        ldx #2
        jsr place
        jmp spr3
+       lda hatact
        beq spr3
        lda #SP_HAT
        sta shp+2
        lda hatx
        sta t0
        lda hatxh
        sta t1
        lda haty
        ldx #2
        jsr place
spr3:   ldx #NSLOT-1
-       stx eidx
        lda etype,x
        beq +
        jsr placeenemy
+       ldx eidx
        dex
        bpl -
        rts

placeplayer:
        lda pxl
        sta t0
        lda pxh
        sta t1
        lda py
        jmp place

placeenemy:
        tay
        lda ecol-1,y
        sta shc+3,x
        ; frame: animation bit, facing from edx
        lda anim
        lsr
        lsr
        lsr
        and #1
        cpy #E_GARG
        bne +
        lda est,x
        beq +
        lda #1
+       sta t2
        lda edx,x
        bpl +
        lda t2
        ora #2
        sta t2
+       tya
        asl
        asl
        clc
        adc t2
        tay
        lda eptr-4,y
        sta shp+3,x
        lda estun,x             ; stunned: flicker
        beq +
        lda anim
        and #2
        beq ++
+       lda exl,x
        sta t0
        lda exh,x
        sta t1
        lda ey,x
        pha
        txa
        clc
        adc #3
        tax
        pla
        jsr place
        ldx eidx
        lda etype,x
        cmp #E_GEAR
        bne ++
        lda shxe
        ora bits+3,x
        sta shxe
++      rts

!if * > $4000 { !error "code runs into the screens" }
; ================================================================ screens (second code block, under the BASIC ROM)
* = $a000
; switch to a UI screen: blank, ui charset, clear, sprites off. A = 0 plain black, else select-screen band
uiscreen:
        pha
        jsr blank
        lda #0
        jsr setcs
        lda #1
        jsr cls
        lda #0
        sta front
        sta curxs
        sta nxs
        sta swap
        sta $d017
        lda #D018A
        sta d018v
        sei
        pla
        beq +
        lda #5
        ldx #23
        ldy #6
        jsr uiband
        lda #12
        sta sp_023+1
        jmp ++
+       jsr uisplits
++      lda #0
        sta spi
        lda sp_line
        sta $d012
        cli
        rts

; big text: zero-terminated ASCII at (p0), column X, row Y (2x2 letters, space = 2 blank columns)
bigtext:
        stx t4
        sty t5
        ldy #0
-       sty bgi
        lda (p0),y
        beq +++
        cmp #' '
        beq ++
        sec
        sbc #'A'
        tax
        lda bigtab,x
        beq ++
        tay
        lda ui_stamps_lo-1,y
        sta p1
        lda ui_stamps_hi-1,y
        sta p1+1
        lda p0                  ; stamp takes p0
        pha
        lda p0+1
        pha
        lda p1
        sta p0
        lda p1+1
        sta p0+1
        ldx t4
        ldy t5
        lda t4
        pha
        lda t5
        pha
        jsr stamp
        pla
        sta t5
        pla
        sta t4
        pla
        sta p0+1
        pla
        sta p0
++      inc t4
        inc t4
        ldy bgi
        iny
        bne -
+++     rts
bgi:    !byte 0

; letter -> index+1 into the big-letter stamp list (0 = none)
bigtab: !byte 1,2,3,4,5,0,6,7,8,0,0,9,10,11,12,0,0,13,14,15,16,17,18,0,19,0
ui_stamps_lo: !byte <ui_bigA,<ui_bigB,<ui_bigC,<ui_bigD,<ui_bigE,<ui_bigG,<ui_bigH,<ui_bigI,<ui_bigL,<ui_bigM
        !byte <ui_bigN,<ui_bigO,<ui_bigR,<ui_bigS,<ui_bigT,<ui_bigU,<ui_bigV,<ui_bigW,<ui_bigY
ui_stamps_hi: !byte >ui_bigA,>ui_bigB,>ui_bigC,>ui_bigD,>ui_bigE,>ui_bigG,>ui_bigH,>ui_bigI,>ui_bigL,>ui_bigM
        !byte >ui_bigN,>ui_bigO,>ui_bigR,>ui_bigS,>ui_bigT,>ui_bigU,>ui_bigV,>ui_bigW,>ui_bigY

!macro big .c, .r, .str {
        lda #<.str
        sta p0
        lda #>.str
        sta p0+1
        ldx #.c
        ldy #.r
        jsr bigtext
}
!macro stamp .c, .r, .st {
        lda #<.st
        sta p0
        lda #>.st
        sta p0+1
        ldx #.c
        ldy #.r
        jsr stamp
}

; wait for fire (released first); C set if it came, clear on timeout after A frames (0 = never)
waitfire:
        sta t7
-       jsr waitframe
        jsr commit
        jsr readjoy
        lda joy
        and #$10
        bne -                   ; release first
-       jsr waitframe
        jsr commit
        jsr readjoy
        jsr firenew
        bne +
        lda t7
        beq -
        dec t7
        bne -
        clc
        rts
+       sec
        rts


; ---------------------------------------------------------------- intro (fire skips to the title screen)
; dark, eyes, lightning shows the Count's portrait; MIDNIGHT HOLLOW crawls out of the ground letter by letter
; (dark red), lightning turns it gold; the story is typed (the Count, then Grandma Hazel), then the rules;
; it ends on the title screen. The intro tune plays from boot through the title and the hero select.
intro:  lda #0
        jsr uiscreen
        jsr unblank
        lda #40
        jsr iwait
        bcc *+5
        jmp introx
        jsr eyeson
        lda #60
        jsr iwait
        bcc *+5
        jmp introx
        jsr eyesoff
        lda #12
        jsr iwait
        bcc *+5
        jmp introx
        jsr eyeson
        lda #60
        jsr iwait
        bcc *+5
        jmp introx
        jsr flash
        bcc *+5
        jmp introx
        jsr portrait
        jsr ground
        lda #30
        jsr iwait
        bcc *+5
        jmp introx
        jsr risetitle
        bcc *+5
        jmp introx
        jsr flash
        bcc *+5
        jmp introx
        lda #7
        jsr titlecol
        +stamp 18, 8, ui_portwink
        lda #12
        jsr iwait
        bcc *+5
        jmp introx
        jsr portrait
        lda #60
        jsr iwait
        bcc *+5
        jmp introx
        ; the story: the Count's deed in white, Grandma Hazel's plea in yellow
        lda #7
        jsr clrfrom
        jsr batson
        lda #7
        sta t6
        lda #<pg1
        ldx #>pg1
        jsr typepage
        bcc *+5
        jmp introx
        +stamp 33, 17, ui_hazel
        +print 14, 18, 7, txhazel
        lda #200
        jsr iwait
        bcc *+5
        jmp introx
        jsr flash
        bcc *+5
        jmp introx
        ; the rules, with icons
        lda #7
        jsr clrfrom
        lda #8
        sta t6
        lda #<pg2
        ldx #>pg2
        jsr typepage
        bcc *+5
        jmp introx
        +stamp 2, 8, ui_P
        +stamp 2, 10, ui_K
        +stamp 3, 12, ui_C
        +stamp 2, 16, ui_P
        lda #250
        jsr iwait
        bcc *+5
        jmp introx
        jsr flash
introx: jmp title

; the title screen (end of the intro, and after a game): gold title on the ground, the portrait, press fire
title:  lda #1
        jsr musicto
        lda #0
        jsr uiscreen
        lda #4
        jsr stars
        jsr ground
        +big 5, 2, txmh
        lda #7
        jsr titlecol
        jsr portrait
        +print 10, 18, 5, txfire
        +print 12, 21, 15&7, txcopy
        +stamp 1, 1, ui_P
        +stamp 37, 1, ui_P
        jsr batson
        jsr unblank
        lda #0
        jsr iwait
        lda #0
        sta shen
        jmp select

portrait:
        +stamp 18, 8, ui_port
        rts
eyeson: +stamp 19, 8, ui_eyes
        rts
eyesoff:
        lda #32
        ldx #19
        ldy #8
        jsr putxy
        lda #32
        ldx #20
        ldy #8
        jmp putxy

; graveyard ground under the title: grass row 4, dirt row 5
ground: ldx #39
-       lda ui_G+2
        ldy #4
        jsr putc
        lda ui_D+2
        ldy #5
        jsr putc
        dex
        bpl -
        rts

; MIDNIGHT HOLLOW (row 2-3, column 5) rises out of the ground one letter at a time, dark red. C set: skipped
risetitle:
        lda #0
        sta rti_
rtnext: ldx rti_
        lda txmh,x
        bne +
        clc
        rts
+       cmp #' '
        beq rtskip
        sec
        sbc #'A'
        tax
        ldy bigtab,x
        lda ui_stamps_lo-1,y
        sta p1
        lda ui_stamps_hi-1,y
        sta p1+1
        lda #2+8                ; dark red until the lightning
        sta t2
        lda rti_
        asl
        adc #5
        sta rtc
        ; half out: top half on row 3
        ldy #2
        jsr rtput3
        lda #SFX_THUD
        jsr sfx
        lda #7
        jsr iwait
        bcs rtx
        ; all the way: top on row 2, bottom on row 3
        ldy #2
        lda (p1),y
        ldx rtc
        ldy #2
        jsr putxy
        ldy #3
        lda (p1),y
        ldx rtc
        inx
        ldy #2
        jsr putxy
        ldy #4
        jsr rtput3
        lda #SFX_THUD
        jsr sfx
        lda #9
        jsr iwait
        bcs rtx
rtskip: inc rti_
        jmp rtnext
rtx:    rts
; codes (p1),y and (p1),y+1 to row 3 at columns rtc, rtc+1
rtput3: sty rty
        lda (p1),y
        ldx rtc
        ldy #3
        jsr putxy
        ldy rty
        iny
        lda (p1),y
        ldx rtc
        inx
        ldy #3
        jmp putxy
rti_:   !byte 0
rtc:    !byte 0
rty:    !byte 0

; title rows 2-3, columns 5-34: colour RAM of every non-blank cell to A (+8: multicolour)
titlecol:
        ora #8
        ldx #29
-       ldy SCRA+2*40+5,x
        cpy #32
        beq +
        sta $d800+2*40+5,x
+       ldy SCRA+3*40+5,x
        cpy #32
        beq +
        sta $d800+3*40+5,x
+       dex
        bpl -
        rts

; lightning: two white flashes with thunder. C set if fire skipped
flash:  lda #SFX_THUNDER
        jsr sfx
        lda #1
        jsr flashc
        lda #3
        jsr iwait
        bcs +
        lda #0
        jsr flashc
        lda #5
        jsr iwait
        bcs +
        lda #1
        jsr flashc
        lda #2
        jsr iwait
        bcs +
        lda #0
        jsr flashc
        lda #20
        jmp iwait
+       lda #0
        jmp flashc
flashc: sta sp_021
        sta sp_021+1
        sta $d020
        cmp #0
        bne +
        lda #14
        sta $d020
+       rts

; clear rows A-24
clrfrom:
        sta t6
--      ldx #39
-       lda #32
        ldy t6                  ; putxy leaves the column in Y
        jsr putxy
        dex
        bpl -
        inc t6
        lda t6
        cmp #25
        bne --
        rts

; type the page at A/X from row t6, centred: lines of screen codes ending in 0, $fe c = colour c, $ff = end.
; C set if fire skipped
typepage:
        sta p1
        stx p1+1
        lda #1
        sta tcol
tpline: ldy #0
        lda (p1),y
        cmp #$ff
        bne +
        clc
        rts
+       cmp #$fe
        bne +
        iny
        lda (p1),y
        sta tcol
        lda #2
        jsr tpadv
        jmp tpline
+       ldy #0                  ; length -> start column
-       lda (p1),y
        beq +
        iny
        bne -
+       tya
        eor #$ff
        sec
        adc #40
        lsr
        sta t5                  ; column
        ldy #0
tpch:   lda (p1),y
        beq tpeol
        sty t7
        sta pcch
        lda tcol
        sta t2
        lda pcch
        cmp #'.'
        bne +
        lda #2                  ; full stops red
        sta t2
+       lda pcch
        ldx t5
        ldy t6
        jsr putxy
        lda pcch
        cmp #32
        beq +
        lda #SFX_TICK
        jsr sfx
+       inc t5
        lda #2
        jsr iwait
        bcs tpx
        ldy t7
        iny
        bne tpch
tpeol:  iny                     ; next line
        tya
        jsr tpadv
        inc t6
        lda #12
        jsr iwait
        bcc tpline
tpx:    rts
tpadv:  clc
        adc p1
        sta p1
        bcc +
        inc p1+1
+       rts
tcol:   !byte 1

; bats: sprites 3-5 flap left to right at different heights
batson: lda #$38
        sta shen
        lda #$38
        sta shmc
        lda #0
        sta shxh
        sta $d017
        sta shxe
        ldx #3
-       lda #4
        sta shc,x
        lda battop-3,x
        sta shy,x
        lda batstart-3,x
        sta batx-3,x
        inx
        cpx #6
        bne -
        rts
battop: !byte 60, 120, 205
batstart: !byte 0, 120, 60
batx:   !fill 3, 0

; per frame while bats are out
bats:   lda shen
        and #$38
        beq +++
        ldx #3
-       lda batx-3,x
        clc
        adc #2
        sta batx-3,x
        asl                     ; screen x = batx*2 (0..510)
        sta shx,x
        lda shxh
        and bitsoff,x
        bcc +
        ora bits,x
+       sta shxh
        lda frame
        and #8
        beq +
        lda #SP_BAT2
        !byte $2c
+       lda #SP_BAT1
        sta shp,x
        lda frame
        clc
        adc batstart-3,x
        lsr
        jsr sin
        cmp #$80
        ror
        clc
        adc battop-3,x
        sta shy,x
        inx
        cpx #6
        bne -
+++     rts
bitsoff: !byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f

; A frames (0 = until fire) of commit/bats; C set when fire was pressed
iwait:  sta t4
-       jsr waitframe
        jsr commit
        jsr bats
        jsr readjoy
        jsr firenew
        bne +
        lda t4
        beq -
        dec t4
        bne -
        clc
        rts
+       sec
        rts

txmh:   !text "MIDNIGHT HOLLOW", 0
txhazel: !scr "- grandma hazel", 0
txfire: !scr "press fire to start", 0
txcopy: !scr "f1 music on/off", 0
; the story: the Count (white), then Grandma Hazel (yellow)
pg1:    !scr "hollow's eve. the clock strikes nine.", 0
        !scr "count vesper morrow has stolen", 0
        !scr "the harvest moon lantern.", 0
        !scr "if it is not lit again by midnight,", 0
        !scr "the night will never end...", 0
        !byte $fe, 7
        !scr " ", 0
        !scr "take my pail, child. find the", 0
        !scr "glowing pumpkins and light", 0
        !scr "the lantern again. hurry!", 0
        !byte $ff
; how to play (icons are stamped at columns 2-3 afterwards)
pg2:    !scr "collect 20 glowing pumpkins   ", 0
        !scr "in each haunted place.        ", 0
        !scr "the mansion hides a golden key", 0
        !scr " ", 0
        !scr "fire throws candy. up jumps.  ", 0
        !scr "ghosts only freeze - run!     ", 0
        !scr " ", 0
        !scr "beat the clock, then carry the", 0
        !scr "pumpkins to the moon lantern. ", 0
        !byte $ff

; ---------------------------------------------------------------- character select
select: lda #1
        jsr uiscreen
        lda #5
        jsr stars
        +big 4, 1, txchoose
        +stamp 0, 1, ui_P
        +stamp 38, 1, ui_P
        ; black sides of the blue band, with a few grey stars
        ldy #5
--      sty t6
        ldx #0
-       jsr sidefill
        inx
        cpx #40
        bne -
        ldy t6
        iny
        cpy #23
        bne --
        +print 9, 16, 1, txpip
        +print 4, 17, 3, txpip2
        +print 25, 16, 1, txnova
        +print 22, 17, 3, txnova2
        ldx #0
        jsr statcard
        ldx #1
        jsr statcard
        ldx #4                  ; green lines under the portraits
-       lda ui_green+2
        ldy #14
        jsr putc
        txa
        clc
        adc #18
        tax
        lda ui_green+2
        ldy #14
        jsr putc
        txa
        sec
        sbc #17
        tax
        cpx #18
        bne -
        ldx #0
-       lda #T_HLINE
        ldy #23
        jsr putc
        inx
        cpx #40
        bne -
        +print 5, 24, 5, txlr
        +print 16, 24, 1, txchoose2
        +print 24, 24, 5, txfire2
        +print 29, 24, 1, txstart
        lda #0
        sta hero
        jsr cards
        ; portraits: double size sprites (0/2 hires overlays, 1/3 bodies)
        lda #$0f
        sta shxe
        sta $d017
        sta shen
        lda #$fa
        sta shmc
        lda #0
        sta shxh
        lda #SP_PIP_STAND
        sta shp+1
        lda #SP_PIP_STAND+1
        sta shp
        lda #SP_NOVA_STAND
        sta shp+3
        lda #SP_NOVA_STAND+1
        sta shp+2
        lda #3
        sta shc+1
        lda #10
        sta shc
        lda #1
        sta shc+3
        lda #14
        sta shc+2
        lda #84
        sta shx
        sta shx+1
        lda #228
        sta shx+2
        sta shx+3
        lda #104
        sta shy
        sta shy+1
        sta shy+2
        sta shy+3
        jsr unblank
selp:   jsr waitframe
        jsr commit
        jsr readjoy
        lda joyp
        eor #$ff
        and joy
        sta t0
        and #4
        beq +
        lda #0
        jmp ++
+       lda t0
        and #8
        beq +
        lda #1
++      cmp hero
        beq +
        sta hero
        jsr cards
        lda #SFX_CANDY
        jsr sfx
+       lda t0
        and #$10
        beq selp
        lda #0
        sta $d017
        sta shxe
        jmp newgame

; char A at column X, row Y in its CTAB colour (X kept)
putc:   sta pcch
        stx pcx
        tax
        lda CTAB,x
        sta t2
        ldx pcx
        lda pcch
        jmp putxy
pcch:   !byte 0
pcx:    !byte 0

; column X of row t6: black fill outside the cards (columns 0-2, 19-20, 37-39)
sidefill:
        cpx #3
        bcc +
        cpx #19
        bcc ++
        cpx #21
        bcc +
        cpx #37
        bcc ++
+       jsr rand
        and #15
        bne +
        lda ui_blkstar+2
        jmp ++++
+       lda ui_blk+2
++++    ldy t6
        jmp putc
++      rts

; rows 0..A-1: some hires stars on blank cells
stars:  sta t6
        lda #50
        sta t5
-       jsr rand
        and #31
        cmp t6
        bcs ++
        sta t4
        jsr rand
        and #63
        cmp #40
        bcs ++
        tax
        ldy t4
        lda scrlo,y
        sta p2
        lda scrhi,y
        sta p2+1
        txa
        tay
        lda (p2),y
        cmp #32
        bne ++
        jsr rand
        and #1
        beq +
        lda #T_STAR
        !byte $2c
+       lda #T_DOT
        ldy t4
        jsr putc
++      dec t5
        bne -
        rts

; frames: selected card yellow, the other grey; arrow over the selected one
cards:  ldx #0
        lda hero
        beq +
        ldx #16
+       stx t3
        lda #3
        sta t4
        jsr drawframe
        ldx #16
        lda hero
        beq +
        ldx #0
+       stx t3
        lda #21
        sta t4
        jsr drawframe
        ldx #0
-       lda #32
        ldy #4
        jsr putxy
        inx
        cpx #40
        bne -
        ldx hero
        lda arrowx,x
        tax
        lda ui_arrow+2
        ldy #4
        jsr putc
        inx
        lda ui_arrow+3
        ldy #4
        jmp putc
arrowx: !byte 10, 28

; card frame at column t4, rows 5-22, 16 wide; t3 = offset into frtab (TL TR BL BR T B L R)
drawframe:
        lda #0
        sta t5
-       ldx t3
        lda frtab,x
        sta p0
        lda frtab+1,x
        sta p0+1
        ldy #2
        lda (p0),y
        ldx t5
        sta fcodes,x
        inc t3
        inc t3
        inc t5
        lda t5
        cmp #8
        bne -
        ldx t4
        ldy #5
        lda fcodes
        jsr putc
        lda t4
        clc
        adc #15
        tax
        ldy #5
        lda fcodes+1
        jsr putc
        ldx t4
        ldy #22
        lda fcodes+2
        jsr putc
        lda t4
        clc
        adc #15
        tax
        ldy #22
        lda fcodes+3
        jsr putc
        lda #1
        sta t5
-       lda t4
        clc
        adc t5
        tax
        ldy #5
        lda fcodes+4
        jsr putc
        ldy #22
        lda fcodes+5
        jsr putc
        inc t5
        lda t5
        cmp #15
        bne -
        lda #6
        sta t5
-       ldx t4
        ldy t5
        lda fcodes+6
        jsr putc
        lda t4
        clc
        adc #15
        tax
        ldy t5
        lda fcodes+7
        jsr putc
        inc t5
        lda t5
        cmp #22
        bne -
        rts
fcodes: !fill 8, 0
frtab:  !word ui_fsTL, ui_fsTR, ui_fsBL, ui_fsBR, ui_fsT, ui_fsB, ui_fsL, ui_fsR
        !word ui_fuTL, ui_fuTR, ui_fuBL, ui_fuBR, ui_fuT, ui_fuB, ui_fuL, ui_fuR

; labels and 5-square bars for card X (0 Pip, 1 Nova), rows 19-21
statcard:
        stx t6
        lda cardx,x
        clc
        adc #1
        sta t4
        lda #0
        sta t5                  ; stat 0-2
-       lda t5
        asl
        asl
        tax
        lda #<txspd
        clc
        adc t5
        adc t5
        adc t5
        adc t5
        sta p0
        lda #>txspd
        adc #0
        sta p0+1
        lda t5
        clc
        adc #19
        tay
        ldx t4
        lda #3
        jsr print
        ; bars
        lda t5
        asl
        ora t6
        tax
        lda stats,x
        sta t7
        lda #0
        sta t3
--      lda t3
        cmp t7
        lda ui_bar+2
        bcc +
        lda ui_baroff+2
+       pha
        lda t4
        clc
        adc #4
        adc t3
        tax
        lda t5
        clc
        adc #19
        tay
        pla
        jsr putc
        inc t3
        lda t3
        cmp #5
        bne --
        inc t5
        lda t5
        cmp #3
        bne -
        rts
cardx:  !byte 3, 21

txchoose: !text "CHOOSE YOUR HERO", 0
txpip:  !scr "pip", 0
txpip2: !scr "witch-hat kid", 0
txnova: !scr "dr. nova", 0
txnova2: !scr "the mad doctor", 0
txspd:  !scr "spd", 0
txjmp:  !scr "jmp", 0
txluk:  !scr "luk", 0
txlr:   !scr "left/right", 0
txchoose2: !scr "choose", 0
txfire2: !scr "fire", 0
txstart: !scr "start", 0
stats:  !byte 3, 4, 4, 3, 3, 4  ; SPD, JMP, LUK: Pip, Nova

; ---------------------------------------------------------------- level card, level done, game over, ending
levelcard:
        lda #2                  ; levels: the dance of death; the Moon Chamber: the Count's chase
        ldx level
        cpx #4
        bne +
        lda #3
+       jsr musicto
        lda #0
        jsr uiscreen
        lda #8
        jsr stars
        +stamp 19, 5, ui_P
        ldx level
        lda lt_card_lo,x
        sta p0
        lda lt_card_hi,x
        sta p0+1
        lda #10
        sta t6
lcline: ldy #0
        lda (p0),y
        beq +
        ldx #0
-       lda (p0),y
        sta cardline,x
        iny
        inx
        cpx #38
        bne -
        lda #0
        sta cardline,x
        lda p0
        clc
        adc #38
        sta p0
        bcc ++
        inc p0+1
++      lda p0
        pha
        lda p0+1
        pha
        lda #<cardline
        sta p0
        lda #>cardline
        sta p0+1
        ldx #1
        ldy t6
        lda #1
        jsr print
        pla
        sta p0+1
        pla
        sta p0
        inc t6
        jmp lcline
+       +print 10, 20, 5, txfire
        jsr unblank
        lda #250
        jmp waitfire
cardline: !fill 40, 0

leveldone:
        lda #<msgdone
        ldx #>msgdone
        jsr message
        lda #$00
        ldx #$10                ; 1000 bonus
        jsr addscore
        lda #SFX_KEY
        jsr sfx
        lda #0
        sta shen
        lda #100
        sta t6
-       jsr waitframe
        jsr commit
        lda #0
        sta msgt                ; keep the message
        lda #150
        sta msgt
        jsr hud
        dec t6
        bne -
        rts
msgdone: !scr "well done! on to the next place...", 0

; keep the high score
hiscore:
        lda score+2
        cmp hisc+2
        bcc ++
        bne +
        lda score+1
        cmp hisc+1
        bcc ++
        bne +
        lda score
        cmp hisc
        bcc ++
+       lda score
        sta hisc
        lda score+1
        sta hisc+1
        lda score+2
        sta hisc+2
++      rts

gameover:
        lda #1
        jsr musicto
        jsr hiscore
        lda #0
        jsr uiscreen
        lda #6
        jsr stars
        +print 9, 8, 1, txgo1
        +print 5, 11, 15&7, txgo2
        +print 13, 14, 7, txgo3
        jsr hudtop
        jsr unblank
        lda #SFX_DIE
        jsr sfx
        lda #0
        jsr waitfire
        jmp title
txgo1:  !scr "the night never ends...", 0
txgo2:  !scr "the count laughs in the dark.", 0
txgo3:  !scr "try again?", 0

ending: lda #0                  ; the old cheerful tune: the night is over
        jsr musicto
        jsr hiscore
        lda #0
        jsr uiscreen
        +print 1, 3, 1, txe1
        +print 1, 4, 1, txe2
        +print 1, 5, 1, txe3
        +print 1, 6, 1, txe4
        +print 15, 8, 7, txe5
        +stamp 18, 11, ui_port
        jsr hudtop
        lda #22
        jsr stars
        jsr unblank
        lda #SFX_KEY
        jsr sfx
        ; the portrait winks, a bat leaves the frame
        lda #120
        jsr pause
        +stamp 18, 11, ui_portwink
        lda #SFX_STUN
        jsr sfx
        lda #20
        jsr pause
        +stamp 18, 11, ui_port
        lda #SP_BAT1
        sta shp+3
        lda #4
        sta shc+3
        lda #$08
        sta shen
        lda #$fe
        sta shmc
        lda #0
        sta shxh
        lda #176
        sta shx+3
        lda #150
        sta shy+3
        lda #160
        sta t6
-       jsr waitframe
        jsr commit
        inc shx+3
        dec shy+3
        lda frame
        and #4
        beq +
        lda #SP_BAT2
        !byte $2c
+       lda #SP_BAT1
        sta shp+3
        lda shx+3
        bne +
        lda shxh
        ora #8
        sta shxh
+       dec t6
        bne -
        lda #0
        sta shen
        +print 10, 22, 5, txfire
        lda #0
        jsr waitfire
        jmp title
txe1:   !scr "the clock strikes twelve. the lantern", 0
txe2:   !scr "burns bright and the moon rises over", 0
txe3:   !scr "the hollow. the children get their", 0
txe4:   !scr "candy at last.", 0
txe5:   !scr "well done!", 0

; A frames, screen kept up to date
pause:  sta t6
-       jsr waitframe
        jsr commit
        dec t6
        bne -
        rts

; ================================================================ sound
SFX_JUMP = 1
SFX_CHIME = 2
SFX_THROW = 3
SFX_HIT = 4
SFX_DIE = 5
SFX_CANDY = 6
SFX_KEY = 7
SFX_STUN = 8
SFX_LUCK = 9
SFX_THUNDER = 10
SFX_TICK = 11
SFX_THUD = 12
; frames, start pitch (hi byte), pitch delta per frame, waveform
sfxtab: !byte 10, $10, 3, $11
        !byte 14, $38, 2, $11
        !byte 6, $30, <-4, $81
        !byte 10, $18, <-1, $81
        !byte 50, $30, <-1, $21
        !byte 8, $40, 6, $41
        !byte 24, $20, 1, $21
        !byte 14, $50, <-3, $11
        !byte 16, $18, 3, $41
        !byte 40, $0a, 0, $81
        !byte 1, $50, 0, $11
        !byte 8, $0a, <-1, $81
sfxw:   !byte 0

sfx:    asl
        asl
        tax
        lda sfxtab-4,x
        sta sfxf
        lda sfxtab-3,x
        sta sfxp
        lda sfxtab-2,x
        sta sfxd
        lda sfxtab-1,x
        sta sfxw
        lda #0
        sta $d412
        lda sfxp
        sta $d40f
        lda sfxw
        sta $d412
        rts

; per frame from the IRQ: music on voices 1-2, effect on voice 3
sound:  lda sfxf
        beq +
        dec sfxf
        bne ++
        lda sfxw
        and #$fe
        sta $d412
        jmp +
++      lda sfxp
        clc
        adc sfxd
        sta sfxp
        sta $d40f
+       lda mpend               ; fading out before a tune change
        beq +
        dec vol
        lda vol
        sta $d418
        bne +
        lda mpend
        sec
        sbc #1
        jsr setmusic
        lda #0
        sta mpend
        lda #15
        sta vol
        sta $d418
+       lda mon
        bne +
        rts
+       dec mcnt
        beq mstep_
        lda mcnt
        cmp #2                  ; release before the next step, unless it holds the note (1)
        bne ++
        ldx mstep
        lda tune_theme,x
mmel2 = *-2
        cmp #1
        beq +
        lda #$40
        sta $d404
+       lda tune_themeb,x
mbass2 = *-2
        cmp #1
        beq ++
        lda #$20
        sta $d40b
++      rts
mstep_: lda #7
mtempo = *-1
        sta mcnt
        ldx mstep
        ldy tune_theme,x
mmel = *-2
        cpy #2
        bcc +
        lda ntlo,y
        sta $d400
        lda nthi,y
        sta $d401
        lda #$41
        sta $d404
+       ldy tune_themeb,x
mbass = *-2
        cpy #2
        bcc +
        lda ntlo,y
        sta $d407
        lda nthi,y
        sta $d408
        lda #$21
        sta $d40b
+       inx
        cpx #theme_len
mlen = *-1
        bcc +
        ldx #0
+       stx mstep
        rts

; A = tune (0 theme/ending, 1 intro/title, 2 levels, 3 Moon Chamber): patch the player's tables, start it
setmusic:
        sta mcur
        asl
        asl
        asl
        tax
        lda mtab,x
        sta mmel
        sta mmel2
        lda mtab+1,x
        sta mmel+1
        sta mmel2+1
        lda mtab+2,x
        sta mbass
        sta mbass2
        lda mtab+3,x
        sta mbass+1
        sta mbass2+1
        lda mtab+4,x
        sta mlen
        lda mtab+5,x
        sta mtempo
        lda #0
        sta mstep
        lda #1
        sta mcnt
        lda #$40
        sta $d404
        lda #$20
        sta $d40b
        rts
mtab:   !word tune_theme, tune_themeb
        !byte theme_len, 7, 0, 0
        !word tune_intro, tune_introb
        !byte intro_len, 12, 0, 0
        !word tune_dance, tune_danceb
        !byte dance_len, 8, 0, 0
        !word tune_boss, tune_bossb
        !byte boss_len, 5, 0, 0

; change to tune A: the current one fades out over 15 frames first (from the IRQ)
musicto:
        cmp mcur
        beq ++
        ldx mon
        bne +
        sei                     ; music off: switch at once, silently
        jsr setmusic
        cli
        rts
+       sta mcur
        clc
        adc #1
        sta mpend
++      rts

togglemusic:
        lda mon
        eor #1
        sta mon
        lda #$40
        sta $d404
        lda #$20
        sta $d40b
        rts
!if * > $c000 { !error "screen code runs past $c000" }
