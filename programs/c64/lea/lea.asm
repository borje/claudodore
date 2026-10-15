; LEA: three 2x-expanded sprites scroll right->left, sine wave, rainbow colours,
; raster bars, 3-voice SID tune (arpeggio + bass + hat). PAL.
SPRPTR = $07f8
VIC    = $d000
SID    = $d400

bxl    = $c000          ; scroll base X (signed 16-bit)
bxh    = $c001
phase  = $c002          ; frame counter
fc     = $c003          ; music frame divider
tick   = $c004          ; music step
idx    = $c005
tl     = $c006
th     = $c007
en     = $c008          ; sprite enable mask being built
msb    = $c009          ; X bit 8 mask being built
last   = $c00a
t      = $c00b

!macro n .hz { !word .hz * 17.0284 }   ; Hz -> SID freq (PAL)

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        jsr $e544               ; clear screen
        lda #$58                ; start at X=344 (just off right edge)
        sta bxl
        lda #1
        sta bxh
        lda #6
        sta fc
        lda #0
        sta phase
        sta tick
        ldx #2
-       lda #128
        stx t
        clc
        adc t
        sta SPRPTR,x
        dex
        bpl -
        lda #7
        sta VIC+$17             ; Y expand
        sta VIC+$1d             ; X expand
        ldx #$18                ; clear SID
        lda #0
-       sta SID,x
        dex
        bpl -
        lda #$02                ; V1 pulse: sustain high, gated off mid-step
        sta SID+5
        lda #$c4
        sta SID+6
        lda #$0a                ; V2 saw bass
        sta SID+$0c
        lda #$a8
        sta SID+$0d
        lda #$01                ; V3 noise hat
        sta SID+$13
        lda #$50
        sta SID+$0f
        lda #$0f
        sta SID+$18
        lda #$00
        sta SID+2

loop:   lda VIC+$12             ; raster bars: one colour per line
        cmp last
        beq loop
        sta last
        clc
        adc phase
        and #$1f
        tay
        lda bars,y
        sta VIC+$20
        sta VIC+$21
        lda last
        cmp #250
        bne loop

        inc phase
        ; ---- music (every 6 frames)
        dec fc
        lda fc
        cmp #3
        bne +
        lda #$40                ; lead gate off halfway through the step
        sta SID+4
+       lda fc
        bne nomus
        lda #6
        sta fc
        inc tick
        lda tick
        lsr
        lsr
        lsr
        lsr
        and #3
        sta idx                 ; chord
        asl
        asl
        sta t
        lda tick
        and #3
        ora t
        asl
        tax
        lda #$40
        sta SID+4
        lda arp,x
        sta SID
        lda arp+1,x
        sta SID+1
        lda #$41
        sta SID+4
        lda phase               ; pulse-width wobble
        lsr
        lsr
        lsr
        and #7
        ora #4
        sta SID+3
        lda tick
        and #3
        bne nobass
        lda idx
        asl
        tax
        lda #$20
        sta SID+$0b
        lda bass,x
        sta SID+7
        lda bass+1,x
        sta SID+8
        lda #$21
        sta SID+$0b
nobass: lda #$80
        sta SID+$12
        lda tick
        and #1
        beq nomus
        lda #$81
        sta SID+$12
nomus:
        ; ---- sprites
        lda #0
        sta en
        sta msb
        sta idx
sl:     ldx idx
        lda off,x
        clc
        adc bxl
        sta tl
        lda bxh
        adc #0
        sta th
        bmi neg
        cmp #2
        bcs next
        cmp #1
        bne show
        lda tl
        cmp #$58
        bcs next
        bcc show
neg:    cmp #$ff
        bne next
        lda tl
        cmp #$d0
        bcc next
        sbc #8                  ; wrap at 504 (PAL): -n -> 504-n
        sta tl
        lda #1
        sta th
show:   txa
        asl
        tay
        lda tl
        sta VIC,y
        lda msk,x
        ora en
        sta en
        lda th
        beq nomsb
        lda msk,x
        ora msb
        sta msb
nomsb:  lda phase               ; sine Y
        asl
        clc
        adc yoff,x
        tax
        lda sine,x
        sta VIC+1,y
        ldx idx
        lda phase               ; rainbow
        lsr
        clc
        adc coff,x
        and #$0f
        tay
        lda rainbow,y
        sta VIC+$27,x
next:   inc idx
        lda idx
        cmp #3
        beq done
        jmp sl
done:
        lda en
        sta VIC+$15
        lda msb
        sta VIC+$10
        ; ---- scroll left 2px/frame, wrap after all letters are gone
        lda bxl
        sec
        sbc #2
        sta bxl
        lda bxh
        sbc #0
        sta bxh
        cmp #$ff
        bne +
        lda bxl
        cmp #$60                ; -160
        bcs +
        lda #$58
        sta bxl
        lda #1
        sta bxh
+       jmp loop

off:    !byte 0,52,104
msk:    !byte 1,2,4
yoff:   !byte 0,28,56
coff:   !byte 0,5,10
bars:   !byte 0,6,6,14,14,3,3,1,1,3,3,14,14,6,6,0
        !byte 0,9,9,2,2,10,10,7,7,10,10,2,2,9,9,0
rainbow:!byte 2,10,8,7,1,7,13,5,3,14,4,6,4,14,3,5
sine:   !for i,0,255 { !byte 118 + 45*sin(i*3.14159265/128) }

; Am F C G, 4-note arpeggio each
arp:    +n 440
        +n 523.25
        +n 659.26
        +n 880
        +n 349.23
        +n 440
        +n 523.25
        +n 698.46
        +n 523.25
        +n 659.26
        +n 783.99
        +n 1046.5
        +n 392
        +n 493.88
        +n 587.33
        +n 783.99
bass:   +n 110
        +n 87.31
        +n 130.81
        +n 98

* = $2000                       ; L
        !byte 0,0,0
        !for i,1,15 { !byte %00111111,0,0 }
        !for i,16,19 { !byte %00111111,%11111111,%11111100 }
        !byte 0,0,0
* = $2040                       ; E
        !byte 0,0,0
        !for i,1,4 { !byte %00111111,%11111111,%11111100 }
        !for i,5,8 { !byte %00111111,0,0 }
        !for i,9,12 { !byte %00111111,%11111111,%11000000 }
        !for i,13,15 { !byte %00111111,0,0 }
        !for i,16,19 { !byte %00111111,%11111111,%11111100 }
        !byte 0,0,0
* = $2080                       ; A
        !byte 0,0,0
        !byte %00000011,%11111111,%11000000
        !for i,2,4 { !byte %00001111,%11111111,%11110000 }
        !for i,5,8 { !byte %00111111,0,%11111100 }
        !for i,9,12 { !byte %00111111,%11111111,%11111100 }
        !for i,13,19 { !byte %00111111,0,%11111100 }
        !byte 0,0,0
