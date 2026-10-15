; Real joystick-port demo: mirrors CIA1 port registers (joystick 2 = $DC00, joystick 1 = $DC01)
; into screen cells 0 and 1. Joystick lines are active low (0 = pressed) in bits 0-4.
* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
loop:   lda $dc00
        sta $0400
        lda $dc01
        sta $0401
        jmp loop
