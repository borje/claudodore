; Agent input demo: shows the edge-triggered byte at $033C in screen cell 0
; (and clears it, as games should) and the held byte at $033E in cell 1.
PRESS = $033c
HOLD  = $033e

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        lda #0
        sta PRESS
        sta HOLD
loop:   lda PRESS
        beq +
        sta $0400               ; last pressed bits
        lda #0
        sta PRESS               ; edge-triggered: clear after reading
+       lda HOLD
        sta $0401               ; currently held bits
        jmp loop
