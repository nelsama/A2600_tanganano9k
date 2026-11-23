// atari_top.v : Atari 2600 on the Sipeed Tang Nano 9K, games from a microSD.
//   PLL sys : 27 / 8 x 17 = 57.375 MHz, + 90 degrees (PSRAM),
//             CLKOUTD /2 = 28.6875 MHz (console)
//   PLL hdmi: 27 x 5 = 135 MHz, CLKDIV /5 = 27 MHz pixel clock
// S1 = reset, S2 = back to the menu. Pins 85 / 86: Select / Game Reset.
// LEDs: 0 heartbeat, 1 menu, 2 loading, 3 PAL, 4 any joystick input.
module atari_top(
  input        clk27,
  input        btn_s1_n, btn_s2_n, game_select_n, game_reset_n,
  output [5:0] led_n,
  output       tmds_ck_p, tmds_ck_n,
  output [2:0] tmds_d_p, tmds_d_n,
  input        joy_up, joy_down, joy_left, joy_right, joy_fire,
  output       audio_l, audio_r,
  output       sd_sck, sd_cmd, sd_cs,
  input        sd_dat0,
  output [1:0]  O_psram_ck,
  output [1:0]  O_psram_ck_n,
  inout  [1:0]  IO_psram_rwds,
  inout  [15:0] IO_psram_dq,
  output [1:0]  O_psram_reset_n,
  output [1:0]  O_psram_cs_n
);
  wire clk, memclk, memclk_p, clk135, clk_pix, lock_s, lock_h;

  rPLL u_pll_sys(.CLKIN(clk27), .CLKOUT(memclk), .CLKOUTD(clk), .LOCK(lock_s),
    .CLKOUTP(memclk_p), .CLKOUTD3(), .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111));
  defparam u_pll_sys.FCLKIN = "27";
  defparam u_pll_sys.DEVICE = "GW1NR-9C";
  defparam u_pll_sys.IDIV_SEL = 7;
  defparam u_pll_sys.FBDIV_SEL = 16;
  defparam u_pll_sys.ODIV_SEL = 8;
  defparam u_pll_sys.DYN_SDIV_SEL = 2;
  defparam u_pll_sys.PSDA_SEL = "0100";

  rPLL u_pll_hdmi(.CLKIN(clk27), .CLKOUT(clk135), .CLKOUTD(), .LOCK(lock_h),
    .CLKOUTP(), .CLKOUTD3(), .RESET(1'b0), .RESET_P(1'b0), .CLKFB(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b1111));
  defparam u_pll_hdmi.FCLKIN = "27";
  defparam u_pll_hdmi.DEVICE = "GW1NR-9C";
  defparam u_pll_hdmi.IDIV_SEL = 0;
  defparam u_pll_hdmi.FBDIV_SEL = 4;
  defparam u_pll_hdmi.ODIV_SEL = 4;

  CLKDIV u_div_pix(.CLKOUT(clk_pix), .HCLKIN(clk135), .RESETN(lock_h), .CALIB(1'b0));
  defparam u_div_pix.DIV_MODE = "5";
  defparam u_div_pix.GSREN = "false";

  // reset: power-on, S1, ~9 ms
  reg [1:0]  rs = 0;
  reg [18:0] por = 0;
  wire reset = !por[18];
  always @(posedge clk) begin
    rs <= {rs[0], btn_s1_n};
    if (!lock_s || !rs[1]) por <= 0;
    else if (reset) por <= por + 1'b1;
  end
  reg [3:0] prst = 4'hF;
  always @(posedge clk_pix or negedge lock_h)
    if (!lock_h) prst <= 4'hF; else prst <= {prst[2:0], 1'b0};

  // S2, debounced (~2 ms)
  reg [1:0]  m2 = 2'b11;
  reg [15:0] md = 0;
  reg        to_menu = 0;
  always @(posedge clk) begin
    m2 <= {m2[0], btn_s2_n};
    if (m2[1]) md <= 0; else if (!(&md)) md <= md + 1'b1;
    to_menu <= &md;
  end

  // joystick, active low pins; opposite directions together are ignored
  reg [6:0] j0 = 0, j1 = 0;
  always @(posedge clk) begin
    j0 <= ~{game_select_n, game_reset_n, joy_fire, joy_right, joy_left, joy_down, joy_up};
    j1 <= j0;
  end
  wire [4:0] joy = {j1[4], j1[3] & ~j1[2], j1[2] & ~j1[3], j1[1] & ~j1[0], j1[0] & ~j1[1]};

  wire [4:0]  audio;
  wire        fb_we, pal, menu, sd_active, vbl, mt, mwe;
  wire [15:0] fb_a;
  wire [7:0]  fb_d, mdo, mq;
  wire [4:0]  hl_row;
  wire [21:0] ma;
  reg  [1:0]  vb = 0;
  always @(posedge clk) vb <= {vb[0], vbl};
  atari_sys u_sys(.clk(clk), .reset_in(reset), .to_menu(to_menu), .menu(menu), .reset(),
    .joy0(joy), .joy1(5'd0), .sw_select(j1[6]), .sw_reset(j1[5]), .sw_bw(1'b0), .sw_diff(2'b00),
    .audio(audio), .fb_we(fb_we), .fb_a(fb_a), .fb_d(fb_d), .pal(pal), .hl_row(hl_row),
    .vblank_in(vb[1]), .mt(mt), .mwe(mwe), .ma(ma), .md(mdo), .mq(mq), .sd_active(sd_active),
    .sd_sck(sd_sck), .sd_cmd(sd_cmd), .sd_cs(sd_cs), .sd_dat0(sd_dat0),
    .tmode(1'b0), .tcfg(6'd0), .tlast(8'd0), .vsync_o());

  // --- PSRAM, die 0 -----------------------------------------------------------
  reg  ts = 0, td = 0, rd = 0, wr = 0;
  wire [15:0] w0;
  always @(posedge memclk) begin
    ts <= mt;
    td <= ts;
    rd <= (ts != td) && !mwe;
    wr <= (ts != td) && mwe;
  end
  psram_chan u_ram(.clk(memclk), .clk_p(memclk_p), .resetn(lock_s), .read(rd), .write(wr),
    .addr(ma), .din({mdo, mdo}), .byte_write(1'b1), .dout(w0), .busy(),
    .psram_ck(O_psram_ck[0]), .psram_cs_n(O_psram_cs_n[0]),
    .psram_rwds(IO_psram_rwds[0]), .psram_dq(IO_psram_dq[7:0]));
  assign mq = ma[0] ? w0[15:8] : w0[7:0];
  assign O_psram_ck[1] = 1'b0;
  assign O_psram_cs_n[1] = 1'b1;
  assign O_psram_ck_n = 2'b00;
  assign O_psram_reset_n = {2{lock_s}};
  assign IO_psram_rwds[1] = 1'bz;
  assign IO_psram_dq[15:8] = 8'hzz;

  // --- video ------------------------------------------------------------------
  wire [7:0] r, g, b;
  wire hs, vs, de;
  atari_video u_vid(.clk(clk), .we(fb_we), .wa(fb_a), .wd(fb_d), .clk_pix(clk_pix), .menu(menu),
    .pal(pal), .hl_row(hl_row), .vblank(vbl), .r(r), .g(g), .b(b), .hs(hs), .vs(vs), .de(de));
  hdmi_module u_hdmi(.vga_clk_x5(clk135), .vga_clk(clk_pix), .rst(prst[3]),
    .vga_red_in(r), .vga_green_in(g), .vga_blue_in(b),
    .vga_hsync_in(hs), .vga_vsync_in(vs), .vga_disp_ena_in(de),
    .tmds_c0_p_out(tmds_d_p[0]), .tmds_c0_n_out(tmds_d_n[0]),
    .tmds_c1_p_out(tmds_d_p[1]), .tmds_c1_n_out(tmds_d_n[1]),
    .tmds_c2_p_out(tmds_d_p[2]), .tmds_c2_n_out(tmds_d_n[2]),
    .tmds_ck_p_out(tmds_ck_p), .tmds_ck_n_out(tmds_ck_n));

  // first-order sigma-delta DAC
  reg [5:0] acc = 0;
  always @(posedge clk) acc <= {1'b0, acc[4:0]} + {1'b0, audio};
  assign audio_l = acc[5];
  assign audio_r = acc[5];

  reg [23:0] beat = 0;
  always @(posedge clk) beat <= beat + 1'b1;
  assign led_n = ~{1'b0, |joy, pal, sd_active, menu, beat[23]};
endmodule
