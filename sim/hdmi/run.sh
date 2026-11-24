#!/usr/bin/env bash
# Simula hdmi_tx con GHDL y lo decodifica con receptor.js (Node)
set -e
export PATH=$PATH:/c/msys64/ucrt64/bin
cd "$(dirname "$0")"; mkdir -p ../../build/hdmi; cd ../../build/hdmi
F="--std=08 -frelaxed"
for s in ../../src/hdmi/tmds_encoder_2.vhd ../../src/hdmi/hdmi_tx.vhd ../../sim/hdmi/tb_hdmi.vhd; do ghdl -a $F $s; done
ghdl -e $F tb
ghdl -r $F tb --ieee-asserts=disable --stop-time=12ms > /dev/null 2>&1 || true
node ../../sim/hdmi/receptor.js
