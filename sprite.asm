; Sprite demo: a yellow ball bouncing around the screen on a cleared screen
SPRPTR = $07f8
VIC    = $d000

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        jsr $e544               ; clear screen
        lda #128                ; sprite data at 128*64 = $2000
        sta SPRPTR
        lda #7                  ; yellow
        sta VIC+$27
        lda #1
        sta VIC+$15             ; enable sprite 0
        lda #100
        sta VIC+1               ; Y
        lda #24
        sta x
frame:
-       lda VIC+$12             ; wait for raster line 255 (once per frame)
        cmp #$ff
        bne -
-       lda VIC+$12
        cmp #$ff
        beq -
        lda x
        clc
        adc dx
        sta x
        sta VIC                 ; X (low 8 bits only, so range stays < 256)
        cmp #24
        beq flipx
        cmp #250
        bne movey
flipx:  lda dx
        eor #$fe                ; +1 <-> -1
        sta dx
movey:  lda y
        clc
        adc dy
        sta y
        sta VIC+1
        cmp #50
        beq flipy
        cmp #208                ; 229 (last visible line) - 21 (sprite height) + 1
        bne frame
flipy:  lda dy
        eor #$fe
        sta dy
        jmp frame

x:      !byte 24
y:      !byte 100
dx:     !byte 1
dy:     !byte 1

* = $2000
        !byte %00000000,%00000000,%00000000
        !byte %00000000,%00111100,%00000000
        !byte %00000000,%11111111,%00000000
        !byte %00000011,%11111111,%11000000
        !byte %00000111,%11111111,%11100000
        !byte %00001111,%11111111,%11110000
        !byte %00001111,%11111111,%11110000
        !byte %00011111,%10011001,%11111000   ; eyes
        !byte %00011111,%10011001,%11111000
        !byte %00011111,%11111111,%11111000
        !byte %00011111,%11111111,%11111000
        !byte %00011111,%10111101,%11111000   ; mouth
        !byte %00011111,%11000011,%11111000
        !byte %00001111,%11111111,%11110000
        !byte %00001111,%11111111,%11110000
        !byte %00000111,%11111111,%11100000
        !byte %00000011,%11111111,%11000000
        !byte %00000000,%11111111,%00000000
        !byte %00000000,%00111100,%00000000
        !byte %00000000,%00000000,%00000000
        !byte %00000000,%00000000,%00000000
