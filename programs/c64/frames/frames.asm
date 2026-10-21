; Checkpoint test: counts passes of raster line 100 (one per frame) and calls `hook` once per
; frame, so run.py can check run_until() and run_frames() in exact emulated frames.
COUNT = $c000           ; frames seen (16-bit)
HOOKS = $c002           ; times hook ran

* = $0801
        !byte $0c,$08,$0a,$00,$9e,$32,$30,$36,$34,$00,$00,$00   ; 10 SYS 2064

* = $0810
        sei                     ; no KERNAL IRQ: the raster alone paces the loop
        lda #0
        sta COUNT
        sta COUNT+1
        sta HOOKS
loop:
-       lda $d012               ; wait for line 100 (PAL $d012 reads 100 once per frame)
        cmp #100
        bne -
        inc COUNT
        bne +
        inc COUNT+1
+       jsr hook
-       lda $d012               ; leave line 100
        cmp #100
        beq -
        jmp loop

* = $0840                       ; fixed address: run.py breaks on it
hook:   inc HOOKS
        rts
