create_clock -name clk27    -period 37.037 -waveform {0 18.518} [get_ports {clk27}]
create_clock -name memclk   -period 17.429 -waveform {0 8.715}     [get_nets {memclk}]
create_clock -name memclk_p -period 17.429 -waveform {4.357 13.072} [get_nets {memclk_p}]
create_clock -name clk      -period 34.858 -waveform {0 17.429} [get_nets {clk}]
create_clock -name clk_pix  -period 37.037 -waveform {0 18.518} [get_nets {clk_pix_Z}]
set_clock_groups -asynchronous -group [get_clocks {clk27}] -group [get_clocks {clk memclk memclk_p}] -group [get_clocks {clk_pix}]
set_false_path -from [get_ports {btn_s1_n btn_s2_n game_select_n game_reset_n joy_up joy_down joy_left joy_right joy_fire sd_dat0}]
// The CPU registers only move with enable, every 24 clk, and the DPC ones then or one
// clk later: 2 clk for CPU -> CPU and DPC -> CPU are safe
set_multicycle_path 2 -setup -end -from [get_regs {u_sys/u_cpu/cpu/*}] -to [get_regs {u_sys/u_cpu/cpu/*}]
set_multicycle_path 1 -hold -end -from [get_regs {u_sys/u_cpu/cpu/*}] -to [get_regs {u_sys/u_cpu/cpu/*}]
set_multicycle_path 2 -setup -end -from [get_regs {u_sys/u_dpc/*}] -to [get_regs {u_sys/u_cpu/cpu/*}]
set_multicycle_path 1 -hold -end -from [get_regs {u_sys/u_dpc/*}] -to [get_regs {u_sys/u_cpu/cpu/*}]
