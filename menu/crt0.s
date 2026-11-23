; startup of the menu (10 KB at $D800, no interrupts)
.export _exit, __STARTUP__ : absolute = 1
.import _main, zerobss, __STACKTOP__
.importzp sp
.segment "STARTUP"
reset:
  sei
  cld
  ldx #$ff
  txs
  inx
  txa
:  sta $00,x
  inx
  bne :-
  lda #<__STACKTOP__
  sta sp
  lda #>__STACKTOP__
  sta sp+1
  jsr zerobss
  jsr _main
_exit:
  jmp _exit
irq:
  rti
.segment "VECTORS"
  .word irq, reset, irq
