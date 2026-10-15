; VIC-20 joystick demo: shows VIA1 $9111 (up b2, down b3, left b4, fire b5) and
; VIA2 $9120 (right b7) as hex, active low. Unexpanded build ($1001); runs fine on 8K/16K via -DEXP.
CHROUT = $ffd2

!if EXP = 0 {
* = $1001
        !byte $0d,$10,$0a,$00,$9e
        !text "4112"
} else {
* = $1201
        !byte $0d,$12,$0a,$00,$9e
        !text "4624"
}
        !byte 0,0,0

!if EXP = 0 { * = $1010 } else { * = $1210 }
        lda #$93
        jsr CHROUT
loop:
        lda #$13                ; home
        jsr CHROUT
        lda $9111
        jsr hex
        lda #32
        jsr CHROUT
        sei
        ldx $9122               ; VIA2 DDRB: bit 7 must be input to read right
        lda #$7f
        sta $9122
        lda $9120
        stx $9122
        cli
        jsr hex
        jmp loop

hex:    pha
        lsr
        lsr
        lsr
        lsr
        jsr nib
        pla
        and #$0f
nib:    cmp #10
        bcc +
        adc #6                  ; carry set: +7 -> 'A'..'F' after +$30
+       adc #$30
        jmp CHROUT
