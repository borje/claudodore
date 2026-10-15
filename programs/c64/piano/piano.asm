; Piano: tracker layout on SID voice 1 (PAL tuning). C4..E5. Screen shows the keyboard;
; the key being played is lit red.
;  W E   T Y U   O P
; A S D F G H J K L ;
; Chords: Z X C V B N M = I ii iii IV V vi V7/vi of the current key, as an arpeggio
; on voice 2 (green keys). Cursor up/down changes key, left/right tempo; space stops the arpeggio.
; $033c/d = last freq, $033e = gate frames left, $033f = lit melody note,
; $0340 = lit arp note ($ff none) (for tests)
CHROUT = $ffd2
GETIN  = $ffe4
FRQ    = $033c
GATE   = $033e
HL     = $033f
HL2    = $0340
PTR    = $fb

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        lda #0
        sta $d020
        sta $d021
        sta GATE
        sta tonic
        sta arpon
        lda #1
        sta $cc                 ; no cursor blink
        lda #14
        jsr CHROUT              ; lowercase charset (has flats)
        lda #147
        jsr CHROUT
        ldx #0
-       lda title,x
        beq +
        jsr CHROUT
        inx
        bne -
+       ldx #0
-       lda stat,x              ; static text rows 19-23
        sta $06f8,x
        inx
        cpx #200
        bne -
        lda #5
        sta tempo
        jsr showbpm
        jsr names
        lda #$04
        sta base                ; screen RAM: key faces
        lda #0
        sta idx
-       ldx idx
        ldy order,x
        sty cur
        ldx cur
        lda #$a0
        jsr fill
        inc idx
        lda idx
        cmp #17
        bne -
        ldx #17                 ; key labels (1x1 rects), reverse letters
-       lda lab-17,x
        jsr fill
        inx
        cpx #34
        bne -
        lda #$ff
        sta HL
        sta HL2
        jsr draw
        lda #15
        sta $d418               ; volume
        lda #$09
        sta $d405               ; attack 0, decay 9
        lda #$a8
        sta $d406               ; sustain 10, release 8
        lda #$00
        sta $d40c               ; voice 2 (arp): instant attack, no decay,
        lda #$f4
        sta $d40d               ; full sustain: each note hangs until the next
        lda #0
        sta $d402
        sta $d409
        lda #8
        sta $d403               ; pulse width $800
        sta $d40a
frame:  lda $d012
        cmp #255
        bne frame
        lda GATE
        beq arp
        dec GATE
        bne arp
        lda #$40
        sta $d404               ; gate off after hold time
        lda #$ff
        sta HL
        jsr draw
arp:    lda arpon
        beq key
        dec arpcnt
        bne key
        ldy tempo
        lda frames,y
        sta arpcnt
        jsr arpnext
key:    jsr GETIN
        cmp #0
        beq wait
        ldx #16
find:   cmp keys,x
        beq play
        dex
        bpl find
        ldx #6
cfind:  cmp ckeys,x
        beq chord
        dex
        bpl cfind
        cmp #$91
        bne +
        jmp kup
+       cmp #$11
        bne +
        jmp kdown
+       cmp #$1d
        bne +
        jmp tfast
+       cmp #$9d
        bne +
        jmp tslow
+       cmp #$20
        beq stop
        jmp wait
stop:   lda #0                  ; space: stop arpeggio
        sta arpon
        lda #$40
        sta $d40b
        lda #$ff
        sta HL2
        jsr draw
        jmp wait
play:   lda flo,x
        sta $d400
        sta FRQ
        lda fhi,x
        sta $d401
        sta FRQ+1
        lda #$40
        sta $d404
        lda #$41
        sta $d404               ; gate on (pulse)
        lda #50
        sta GATE
        stx HL
        jsr draw
wait:   lda $d012
        cmp #255
        beq wait
        jmp frame

chord:  lda coff,x              ; start arpeggio of chord X in the current key
        clc
        adc tonic
        cmp #12
        bcc +
        sbc #12
+       sta aroot
        lda cq,x
        sta arpq
        lda arpon
        bne +                   ; already running: keep step position and tempo phase
        sta astep               ; (A = 0)
        lda #1
        sta arpcnt              ; first step next frame
        sta arpon
        lda #$41
        sta $d40b               ; gate on (pulse); stays on, only the pitch changes
+       jmp wait
kup:    ldx tonic
        inx
        cpx #12
        bne +
        ldx #0
+       stx tonic
        jsr names
        jmp wait
kdown:  ldx tonic
        bne +
        ldx #12
+       dex
        stx tonic
        jsr names
        jmp wait

tfast:  ldx tempo               ; cursor right: faster
        cpx #8
        beq +
        inx
+       stx tempo
        jsr showbpm
        jmp wait
tslow:  ldx tempo               ; cursor left: slower
        beq +
        dex
+       stx tempo
        jsr showbpm
        jmp wait

; bpm (arp step = 16th note) as 3 screen codes at row 19 col 18
showbpm: lda tempo
        asl
        clc
        adc tempo
        tax
        ldy #0
-       lda bpms,x
        sta $070a,y
        inx
        iny
        cpy #3
        bne -
        rts

; play next arpeggio note on voice 2, fold into C4..E5 so it shows on the piano
arpnext: lda arpq
        clc
        adc astep
        tax
        lda pats,x
        clc
        adc aroot
fold:   cmp #17
        bcc +
        sbc #12
        bcs fold
+       tax
        lda flo,x
        sta $d407
        lda fhi,x
        sta $d408
        stx HL2
        jsr draw
        lda astep
        clc
        adc #1
        and #3
        sta astep
        rts

; key name (row 19) and the 7 chord names (row 21)
names:  lda #$06
        sta PTR+1
        lda #$ff
        sta PTR                 ; $06ff = row 19 col 7
        lda #$20
        sta sfxv
        lda tonic
        jsr wname
        lda #$07
        sta PTR+1
        lda #$4a
        sta PTR                 ; $074a = row 21 col 2
        ldx #0
-       stx ni
        lda sfx,x
        sta sfxv
        lda coff,x
        clc
        adc tonic
        cmp #12
        bcc +
        sbc #12
+       jsr wname
        lda PTR
        clc
        adc #5
        sta PTR
        ldx ni
        inx
        cpx #7
        bne -
        rts

; write root name of pitch class A + suffix sfxv at (PTR), pad to 4 cells
wname:  asl
        tax
        ldy #0
        lda rnames,x
        sta (PTR),y
        iny
        lda rnames+1,x
        cmp #$20
        beq +
        sta (PTR),y
        iny
+       lda sfxv
        sta (PTR),y
        iny
-       cpy #4
        bcs +
        lda #$20
        sta (PTR),y
        iny
        bne -
+       rts

; colour RAM: white keys first, then black keys on top; melody note red, arp note green
draw:   lda #$d8
        sta base
        lda #0
        sta idx
-       ldx idx
        ldy order,x
        lda basecol,y
        cpy HL2
        bne +
        lda #5
+       cpy HL
        bne +
        lda #2
+       sty cur
        ldx cur
        jsr fill
        inc idx
        lda idx
        cmp #17
        bne -
        rts

; fill rect X (cols/rows/size tables) at base-page $base00 + 40*row + col with A
fill:   sta val
        ldy nrow,x
        lda rowlo,y
        clc
        adc ncol,x
        sta PTR
        lda rowhi,y
        adc base
        sta PTR+1
        lda nh,x
        sta cnt
nextrow: ldy nw,x
        dey
        lda val
-       sta (PTR),y
        dey
        bpl -
        lda PTR
        clc
        adc #40
        sta PTR
        bcc +
        inc PTR+1
+       dec cnt
        bne nextrow
        rts

base:   !byte 0
val:    !byte 0
cnt:    !byte 0
cur:    !byte 0
idx:    !byte 0
ni:     !byte 0
sfxv:   !byte 0
tonic:  !byte 0
arpon:  !byte 0
arpcnt: !byte 0
arpq:   !byte 0
astep:  !byte 0
tempo:  !byte 0
aroot:  !byte 0
keys:   !pet "awsedftgyhujkolp;"
ckeys:  !pet "zxcvbnm"
coff:   !byte 0,2,4,5,7,9,4     ; I ii iii IV V vi V7/vi (semitones above key)
cq:     !byte 0,4,4,0,0,4,8     ; quality: 0 major, 4 minor, 8 dom7 (offset into pats)
sfx:    !byte $20,$0d,$0d,$20,$20,$0d,$37  ; screen codes: ' ' m m ' ' ' ' m 7
frames: !byte 20,16,12,10,8,6,5,4,3   ; frames per arp step, by tempo level
bpms:   !byte $20,$33,$38,$20,$34,$37,$20,$36,$32,$20,$37,$35,$20,$39,$34,$31,$32,$35,$31,$35,$30,$31,$38,$38,$32,$35,$30
pats:   !byte 0,4,7,4, 0,3,7,3, 0,4,7,10
rnames: !byte $43,$20,$44,$02,$44,$20,$45,$02,$45,$20,$46,$20,$47,$02,$47,$20,$41,$02,$41,$20,$42,$02,$42,$20
flo:    !byte $67,$70,$89,$b2,$ed,$3b,$9c,$13,$a0,$45,$02,$da,$ce,$e0,$11,$64,$da
fhi:    !byte $11,$12,$13,$14,$15,$17,$18,$1a,$1b,$1d,$1f,$20,$22,$24,$27,$29,$2b
ncol:   !byte $00,$02,$04,$06,$08,$0c,$0e,$10,$12,$14,$16,$18,$1c,$1e,$20,$22,$24,$01,$03,$05,$07,$09,$0d,$0f,$11,$13,$15,$17,$19,$1d,$1f,$21,$23,$25
nrow:   !byte $06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$06,$10,$0a,$10,$0a,$10,$10,$0a,$10,$0a,$10,$0a,$10,$10,$0a,$10,$0a,$10
nw:     !byte $03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$03,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
nh:     !byte $0c,$06,$0c,$06,$0c,$0c,$06,$0c,$06,$0c,$06,$0c,$0c,$06,$0c,$06,$0c,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01,$01
order:  !byte $00,$02,$04,$05,$07,$09,$0b,$0c,$0e,$10,$01,$03,$06,$08,$0a,$0d,$0f
basecol: !byte $01,$0b,$01,$0b,$01,$01,$0b,$01,$0b,$01,$0b,$01,$01,$0b,$01,$0b,$01
lab:    !byte $c1,$d7,$d3,$c5,$c4,$c6,$d4,$c7,$d9,$c8,$d5,$ca,$cb,$cf,$cc,$d0,$bb
rowlo:  !byte $00,$28,$50,$78,$a0,$c8,$f0,$18,$40,$68,$90,$b8,$e0,$08,$30,$58,$80,$a8,$d0,$f8,$20,$48,$70,$98,$c0
rowhi:  !byte $00,$00,$00,$00,$00,$00,$00,$01,$01,$01,$01,$01,$01,$02,$02,$02,$02,$02,$02,$02,$03,$03,$03,$03,$03
stat:   !byte $20,$20,$0b,$05,$19,$3a,$20,$20,$20,$20,$20,$20,$20,$02,$10,$0d,$3a,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$1a,$20,$20,$20,$20,$18,$20,$20,$20,$20,$03,$20,$20,$20,$20,$16,$20,$20,$20,$20,$02,$20,$20,$20,$20,$0e,$20,$20,$20,$20,$0d,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$15,$10,$2f,$04,$0f,$17,$0e,$3a,$20,$0b,$05,$19,$20,$20,$0c,$05,$06,$14,$2f,$12,$09,$07,$08,$14,$3a,$20,$14,$05,$0d,$10,$0f,$20,$20,$20,$20,$20,$20,$20,$20,$20,$13,$10,$01,$03,$05,$3a,$20,$13,$14,$0f,$10,$20,$20,$1a,$2d,$0d,$3a,$20,$03,$08,$0f,$12,$04,$13,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20,$20
title:  !pet "piano - press the key shown on the key", 0
