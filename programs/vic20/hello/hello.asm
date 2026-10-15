; VIC-20 test program: prints a banner, then echoes each key pressed as "KEY: x"
; Assemble with -DEXP=0 (unexpanded, BASIC at $1001) or -DEXP=8 / 16 (BASIC at $1201).
CHROUT = $ffd2
GETIN  = $ffe4

!if EXP = 0 {
* = $1001
        !byte $0d,$10,$0a,$00,$9e
        !text "4112"            ; 10 SYS 4112
} else {
* = $1201
        !byte $0d,$12,$0a,$00,$9e
        !text "4624"            ; 10 SYS 4624
}
        !byte 0,0,0

!if EXP = 0 { * = $1010 } else { * = $1210 }
start:
        lda #$93                ; clear screen
        jsr CHROUT
        ldx #0
-       lda banner,x
        beq loop
        jsr CHROUT
        inx
        bne -
loop:
        jsr GETIN
        beq loop
        pha
        ldx #0
-       lda keymsg,x
        beq +
        jsr CHROUT
        inx
        bne -
+       pla
        jsr CHROUT
        lda #13
        jsr CHROUT
        jmp loop

banner: !pet "hello from asm!", 13, "press a key", 13, 0
keymsg: !pet "key: ", 0
