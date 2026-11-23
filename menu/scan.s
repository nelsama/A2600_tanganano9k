; find_at: next byte of the window page with tab[byte] != 0, from offset A.
; _found = 0 when there is none.
.export _find_at, _found, _scan_pg
.importzp ptr1
tab = $2F00
.segment "BSS"
_found:   .res 1
_scan_pg: .res 1
.segment "CODE"
_find_at:
  tay
  lda #0
  sta ptr1
  lda _scan_pg
  sta ptr1+1
loop:
  lda (ptr1),y
  tax
  lda tab,x
  bne hit
  iny
  bne loop
hit:
  sta _found
  tya
  ldx #0
  rts
