#!/usr/bin/env bash
# synthesizes sim_top, turns the netlist into C++ and builds build/sim/sim
set -euo pipefail
export PATH=/c/msys64/ucrt64/bin:$PATH
ROOT=$(cd "$(dirname "$0")/../.." && pwd -W); O=$ROOT/build/sim; mkdir -p "$O"; cd "$O"
GW=${GOWIN:-/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin}
{ echo "set_device GW1NR-LV9QN88PC6/I5 -device_version C"
  for f in tia riot mapper dpc atari_sys; do echo "add_file -type verilog {$ROOT/src/sd/$f.v}"; done
  echo "add_file -type verilog {$ROOT/sim/sd/sim_top.v}"
  echo "add_file -type vhdl {$ROOT/src/sd/cpu6507.vhd}"
  echo "add_file -type vhdl {$ROOT/src/cpu_6502/cpu65xx_fast.vhd}"
  echo "set_option -verilog_std sysv2017"; echo "set_option -include_path {$ROOT/src/sd}"
  echo "set_option -top_module sim_top"; echo "set_option -output_base_name sim_top"
  echo "set_option -disable_io_insertion 1"; echo "run syn"; } > b.tcl
"$GW/gw_sh.exe" b.tcl > syn.log 2>&1 || { tail -20 syn.log; exit 1; }
grep -E "ERROR|WARN" syn.log || true
python "$ROOT/sim/sd/netlist2cpp.py" impl/gwsynthesis/sim_top.vg sim_top netlist.h
{ echo 'static const unsigned pal[256]={'; grep -oE "18'h[0-9a-f]+" "$ROOT/src/sd/atari_palette.v" | sed "s/18'h/0x/;s/$/,/"; echo '};'; } > pal.h
g++ -O2 -march=native -I. -o sim "$ROOT/sim/sd/sim.cpp"
