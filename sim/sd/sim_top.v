// simulation top: atari_sys with PIX = 5 (faster), short reset, and a way to
// start a game directly (tmode) with the given mapper configuration
module sim_top(
  input         clk, reset_in, to_menu, tmode,
  input  [5:0]  tcfg,
  input  [7:0]  tlast,
  output        menu, vsync_o, pal,
  input  [4:0]  joy0, joy1,
  input         sw_select, sw_reset, sw_bw,
  input  [1:0]  sw_diff,
  output [4:0]  audio,
  output        fb_we,
  output [15:0] fb_a,
  output [7:0]  fb_d,
  output [4:0]  hl_row,
  input         vblank_in,
  output        mt, mwe,
  output [21:0] ma,
  output [7:0]  md,
  input  [7:0]  mq,
  output        sd_sck, sd_cmd, sd_cs,
  input         sd_dat0
);
  atari_sys #(.PIX(5), .REQ(3), .DREQ(8), .SIM(1)) u(.clk(clk), .reset_in(reset_in), .to_menu(to_menu),
    .menu(menu), .reset(), .joy0(joy0), .joy1(joy1), .sw_select(sw_select), .sw_reset(sw_reset),
    .sw_bw(sw_bw), .sw_diff(sw_diff), .audio(audio), .fb_we(fb_we), .fb_a(fb_a), .fb_d(fb_d),
    .pal(pal), .hl_row(hl_row), .vblank_in(vblank_in), .mt(mt), .mwe(mwe), .ma(ma), .md(md), .mq(mq),
    .sd_active(), .sd_sck(sd_sck), .sd_cmd(sd_cmd), .sd_cs(sd_cs), .sd_dat0(sd_dat0),
    .vsync_o(vsync_o), .tmode(tmode), .tcfg(tcfg), .tlast(tlast));
endmodule
