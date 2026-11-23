#!/usr/bin/env bash
# tools/build.sh : synthesis, P&R and bitstream (impl/pnr/Atari2600_SD.fs)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -W); mkdir -p "$ROOT/build"; cd "$ROOT/build"
GW=${GOWIN:-/c/Gowin/Gowin_V1.9.12.03_x64/IDE/bin}
printf '%s\n' "open_project $ROOT/Atari2600_SD.gprj" "set_option -top_module atari_top" \
  "set_option -verilog_std sysv2017" "set_option -output_base_name Atari2600_SD" \
  "set_option -timing_driven 1" "run all" > syn.tcl
"$GW/gw_sh.exe" syn.tcl > syn.log 2>&1 || { tail -20 syn.log; exit 1; }
grep -E "ERROR|WARN" syn.log || true
grep -E "  Logic  |BSRAM" ../impl/pnr/Atari2600_SD.rpt.txt
