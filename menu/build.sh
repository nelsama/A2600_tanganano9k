#!/usr/bin/env bash
# menu/build.sh : menu.c -> menu.hex + src/sd/menu_cfg.vh (cc65)
set -euo pipefail
cd "$(dirname "$0")"; B=${CC65:-/d/cc65/bin}; O=../build/menu; mkdir -p $O
for f in menu fat; do $B/cc65 -t none -Oirs --static-locals -o $O/$f.s $f.c; $B/ca65 -o $O/$f.o $O/$f.s; done
for f in crt0 font scan; do $B/ca65 -o $O/$f.o $f.s; done
$B/ld65 -C menu.cfg -m $O/menu.map -o $O/menu.bin $O/crt0.o $O/menu.o $O/fat.o $O/font.o $O/scan.o $B/../lib/none.lib
python bin2hex.py $O/menu.bin
grep -A12 'Segment list' $O/menu.map
