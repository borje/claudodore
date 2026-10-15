; Test program: prints a banner, then echoes each key pressed as "KEY: x"
CHROUT = $ffd2
GETIN  = $ffe4

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
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
