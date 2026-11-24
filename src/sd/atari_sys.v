// atari_sys.v : Atari 2600 + flash-cart ("EverDrive" style) logic.
//
// Timing (clk = 28.6875 MHz): a colour clock = PIX clk (8, so 3.586 MHz),
//   a CPU cycle = 3 colour clocks. The CPU moves at ph 0; the request to the
//   PSRAM goes out at ph REQ and its data is used at the next ph 0.
//
// Memory: cartridge ROM and RAM in PSRAM (byte address = mapper address).
//
// Menu mode (after power-on or the menu button): the same CPU runs the menu
// program; TIA and RIOT are disconnected.
//   $0000-$5FFF RAM (PSRAM $200000)      $6000-$7FFF window, PSRAM bank $C009
//   $8000-$9FFF W text screen: 80 x 30 characters, font (8 x 8) at $9000
//   $D800-$FFFF menu program (10 KB BSRAM)
//   $C000 W send SPI byte     R last byte received
//   $C001 W bit 0 CS (1 = high), bit 1 fast clock    R bit 7 SPI or DMA busy
//   $C002/3/4 W PSRAM byte address, low / mid / high
//   $C005 W copy 512 SPI bytes to the PSRAM; the address increments
//   $C006 W mapper (0-3), superchip (4), paddles (5)   $C007 W last 2K bank
//   R $C006 buttons: 0 up 1 down 2 left 3 right 4 fire 5 select 6 reset
//   R $C007 bit 7: vertical blanking of the screen
//   $C008 W leave the menu: reset and run the game
//   $C009 W window bank (8 KB)   $C00A W highlighted text row
module atari_sys #(parameter PIX = 8, parameter REQ = 3, parameter DREQ = 14, parameter SIM = 0)(
  input             clk,
  input             reset_in,
  input             to_menu,
  output reg        menu,
  output            reset,
  input      [4:0]  joy0, joy1,    // 0 up 1 down 2 left 3 right 4 fire, 1 = pressed
  input             sw_select, sw_reset, sw_bw,
  input      [1:0]  sw_diff,       // {right, left}, 1 = A
  output     [4:0]  audio,
  // framebuffer
  output reg        fb_we,
  output reg [15:0] fb_a,
  output reg [7:0]  fb_d,
  output reg        pal,
  output reg [4:0]  hl_row,
  input             vblank_in,
  // PSRAM port: an access starts when mt changes
  output reg        mt, mwe,
  output reg [21:0] ma,
  output reg [7:0]  md,
  input      [7:0]  mq,
  output            sd_active,
  output            sd_sck, sd_cmd, sd_cs,
  input             sd_dat0,
  // simulation only: start in a game
  input             tmode,
  input      [5:0]  tcfg,
  input      [7:0]  tlast,
  output            vsync_o
);
`include "menu_cfg.vh"
  // --- reset / menu ---------------------------------------------------------
  wire       vsync;
  reg [16:0] rcnt;
  reg        launch;
  assign reset = !rcnt[16];
  assign vsync_o = vsync;
  initial begin rcnt = 0; menu = 1; launch = 0; end
  always @(posedge clk) begin
    if (to_menu) menu <= 1;
    else if (launch || (SIM != 0 && tmode && reset_in)) menu <= 0;
    if (reset_in || to_menu || launch) rcnt <= 0;
    else if (reset) rcnt <= rcnt + 1'b1;
  end

  // --- sequencer ------------------------------------------------------------
  reg [5:0] ph;
  reg [2:0] sub;
  initial begin ph = 0; sub = 0; end
  always @(posedge clk) begin
    // after the reset the first CPU cycle is complete (it reads the vector)
    ph <= reset ? 6'd1 : ph == 3 * PIX - 1 ? 6'd0 : ph + 1'b1;
    sub <= reset ? 3'd1 : sub == PIX - 1 ? 3'd0 : sub + 1'b1;
  end
  wire       run = !reset;
  wire       ce = run && ph == 0;                 // end of a CPU cycle
  wire [3:0] s = {4{run && !menu}} & {sub == 4, sub == 3, sub == 2, sub == 1};
  wire       rtick = run && !menu && ph == 3 * PIX - 1;

  // --- CPU --------------------------------------------------------------------
  wire [15:0] ca;
  wire [7:0]  cdo;
  wire        cwe, tia_rdy;
  wire        ok = menu || tia_rdy || cwe;
  wire        cen = ce && ok;
  reg  [7:0]  cdi;
  cpu6507 u_cpu(.clk(clk), .enable(reset || cen), .reset(reset), .di(cdi),
    .dq(cdo), .addr(ca), .we(cwe));

  // --- decoding ---------------------------------------------------------------
  wire s_cart = !menu && ca[12];
  wire s_tia  = !menu && !ca[12] && !ca[7];
  wire s_riot = !menu && !ca[12] && ca[7];
  wire s_rom  = menu && ca[15:12] >= 4'hD;
  wire s_reg  = menu && ca[15:12] == 4'hC;
  wire s_fb   = menu && ca[15:13] == 3'b100;
  wire s_ram  = menu && !ca[15];

  wire [1:0] tq;
  wire [7:0] rq;
  reg  [7:0] bus;                                 // last value on the data bus
  reg  [7:0] q_rom, q_reg, q_mem;
  wire       dpc_sel, dpc_rd;
  wire [7:0] dpc_q;
  wire [19:0] dpa;
  always @* begin
    if (s_tia) cdi = {tq, bus[5:0]};
    else if (s_riot) cdi = rq;
    else if (s_rom) cdi = q_rom;
    else if (s_reg) cdi = q_reg;
    else if (dpc_sel) cdi = dpc_q;
    else cdi = q_mem;
  end
  wire [7:0] dnow = cwe ? cdo : cdi;
  always @(posedge clk) if (cen) bus <= dnow;

  // --- menu program -------------------------------------------------------------
  // 8 KB at $E000 and 2 KB at $D800 (as one array it would take 8 blocks)
  reg [7:0] rom_h[0:8191] /* synthesis syn_romstyle = "block_rom" */;
  reg [7:0] rom_l[0:2047] /* synthesis syn_romstyle = "block_rom" */;
  initial begin $readmemh(`MENU_HEX, rom_h); $readmemh(`MENU_HEX_L, rom_l); end
  reg [7:0] q_h, q_l;
  always @(posedge clk) begin q_h <= rom_h[ca[12:0]]; q_l <= rom_l[ca[10:0]]; end
  always @* q_rom = ca[13] ? q_h : q_l;

  // --- cartridge ------------------------------------------------------------------
  reg [5:0]  cfg;
  reg [7:0]  lastb, pbank;
  wire [19:0] cpa;
  wire       cram_w;
  mapper u_map(.clk(clk), .reset(reset), .cpu_en(cen && !menu), .we(cwe), .a(ca[12:0]), .d(dnow),
    .map(cfg[3:0]), .last(lastb), .sc(cfg[4]), .pa(cpa), .ram_w(cram_w));

  // 4K + superchip does not exist: that code is the DPC
  wire dpc_on = !menu && cfg[4:0] == 5'h10;
  reg  [10:0] oc;
  wire osc = oc == 11'd1433;                      // 20 kHz
  always @(posedge clk) oc <= osc ? 11'd0 : oc + 1'b1;
  // applied at ph 1: the DPC registers are then stable when the CPU reads them
  // (multicycle paths of atari_sd.sdc)
  reg  osc_p;
  wire osc_t = osc_p && ph == 6'd1 && !reset;
  always @(posedge clk) osc_p <= !reset && (osc || (osc_p && !osc_t));
  dpc u_dpc(.clk(clk), .reset(reset), .en(dpc_on), .cpu_en(cen), .we(cwe), .osc(osc_t), .a(ca[12:0]),
    .d(dnow), .sel(dpc_sel), .rd_data(dpc_rd), .dpa(dpa), .q(dpc_q), .mem(q_mem));

  // --- PSRAM ------------------------------------------------------------------------
  reg        dma, dma_wr;
  reg [21:0] dma_a;
  reg [7:0]  dma_d;
  wire       m_go = run && ph == REQ && !dma &&
                    (s_cart ? (!cwe || cram_w) : s_ram);
  initial begin mt = 0; mwe = 0; ma = 0; md = 0; dma_wr = 0; dma = 0; end
  always @(posedge clk) begin
    if (m_go) begin
      mt <= !mt;
      mwe <= cwe;
      md <= cdo;
      ma <= dpc_rd ? {2'b00, dpa} : s_cart ? {2'b00, cpa} : (ca[14:13] == 2'b11) ? {1'b0, pbank, ca[12:0]} : {7'b1000000, ca[14:0]};
    end else if (dma_wr && ph == DREQ) begin
      mt <= !mt; mwe <= 1; md <= dma_d; ma <= dma_a;
    end
    if (ph == 3 * PIX - 1) q_mem <= mq;
  end

  // --- flash-cart registers ----------------------------------------------------------
  wire       reg_w = cen && cwe && s_reg;
  reg        cs, fast, spi_go;
  reg [7:0]  spi_tx;
  reg [9:0]  dcnt;
  wire       spi_busy, spi_done;
  wire [7:0] spi_rx;
  assign sd_cs = cs;
  assign sd_active = dma;
  initial begin cs = 1; fast = 0; spi_go = 0; cfg = 0; lastb = 0; pbank = 0; hl_row = 31; end
  always @(posedge clk) begin
    spi_go <= 0;
    launch <= 0;
    if (dma_wr && ph == DREQ) begin
      dma_wr <= 0;
      dma_a <= dma_a + 1'b1;
      dcnt <= dcnt + 1'b1;
      if (dcnt == 10'd511) dma <= 0; else spi_go <= 1;
    end
    if (dma && spi_done) begin dma_wr <= 1; dma_d <= spi_rx; end
    if (reg_w) case (ca[3:0])
      4'h0: begin spi_tx <= cdo; spi_go <= 1; end
      4'h1: {fast, cs} <= cdo[1:0];
      4'h2: dma_a[7:0] <= cdo;
      4'h3: dma_a[15:8] <= cdo;
      4'h4: dma_a[21:16] <= cdo[5:0];
      4'h5: begin dma <= 1; dcnt <= 0; spi_tx <= 8'hFF; spi_go <= 1; end
      4'h6: cfg <= cdo[5:0];
      4'h7: lastb <= cdo;
      4'h8: launch <= 1;
      4'h9: pbank <= cdo;
      4'hA: hl_row <= cdo[4:0];
      default: ;
    endcase
    if (SIM != 0 && tmode && reset_in) begin cfg <= tcfg; lastb <= tlast; end
    if (reset) begin cs <= 1; fast <= 0; dma <= 0; dma_wr <= 0; end
    q_reg <= ca[2:0] == 0 ? spi_rx :
             ca[2:0] == 3'd1 ? {spi_busy | spi_go | dma, 7'd0} :
             ca[2:0] == 3'd6 ? {1'b0, sw_reset, sw_select, joy0} : {vblank_in, 7'd0};
  end
  spi_byte u_spi(.clk(clk), .go(spi_go), .fast(fast), .tx(spi_tx), .rx(spi_rx),
    .busy(spi_busy), .done(spi_done), .sck(sd_sck), .mosi(sd_cmd), .miso(sd_dat0));

  // --- paddles: moved with the joystick ---------------------------------------------
  wire       pad_mode = cfg[5];
  wire       dump, line_t;
  reg  [8:0] charge;
  reg  [8:0] pos;                                 // 0..240, in lines
  reg  [3:0] spd;
  reg        vs_q;
  wire       fr_tick = vsync && !vs_q;
  wire [8:0] step = {6'd0, spd[3:1]} + 9'd1;
  always @(posedge clk) begin
    vs_q <= vsync;
    if (dump) charge <= 0;
    else if (line_t && charge != 9'd511) charge <= charge + 1'b1;
    if (fr_tick) begin
      if (!joy0[2] && !joy0[3]) spd <= 0; else if (spd != 4'd7) spd <= spd + 1'b1;
      if (joy0[2]) pos <= (pos < 9'd235) ? pos + step : pos;
      else if (joy0[3]) pos <= (pos > 9'd8) ? pos - step : pos;
    end
    if (reset) begin pos <= 9'd120; spd <= 0; end
  end
  wire [3:0] pot = pad_mode ? {3'b000, !dump && charge >= pos} : 4'b0000;

  // --- TIA, RIOT ------------------------------------------------------------------------
  wire       pix_we;
  wire [7:0] pix_x;
  wire [6:0] pix_c;
  tia u_tia(.clk(clk), .reset(reset || menu), .s(s), .cpu_en(ce), .wr(s_tia && cwe), .a(ca[5:0]), .d(cdo),
    .q(tq), .rdy(tia_rdy), .fire_n(pad_mode ? 2'b11 : ~{joy1[4], joy0[4]}), .pot(pot), .dump(dump),
    .pix_we(pix_we), .pix_x(pix_x), .pix_c(pix_c), .line_t(line_t), .vsync(vsync), .audio(audio));
  wire [7:0] pa_in = pad_mode ? {~joy0[4], 7'h7F} :
    ~{joy0[3], joy0[2], joy0[1], joy0[0], joy1[3], joy1[2], joy1[1], joy1[0]};
  wire [7:0] pb_in = {sw_diff[1], sw_diff[0], 2'b11, !sw_bw, 1'b1, !sw_select, !sw_reset};
  riot u_riot(.clk(clk), .reset(reset), .tick(rtick), .cpu_en(cen), .cs(s_riot), .rs(ca[9]), .we(cwe),
    .a(ca[6:0]), .d(cdo), .q(rq), .pa_in(pa_in), .pb_in(pb_in));

  // --- framebuffer writes: 160 x 240, or the text screen in the menu --------------------
  // PAL when the frames are long; the top lines (vertical blank) are skipped.
  reg  [8:0] ln, row;
  reg  [15:0] base;
  reg  [2:0] palc;
  reg        vq;
  wire [8:0] skip = pal ? 9'd42 : 9'd20;
  initial begin pal = 0; palc = 0; end
  always @(posedge clk) begin
    vq <= vsync;
    if (reset) begin
      ln <= 9'd511; row <= 9'd511; palc <= 0; pal <= 0;
    end else if (vq && !vsync) begin
      ln <= 0; row <= 9'd511;
      if (ln > 9'd60) begin
        if (ln >= 9'd286) begin
          if (palc == 3'd7) pal <= 1; else palc <= palc + 1'b1;
        end else begin
          if (palc == 3'd0) pal <= 0; else palc <= palc - 1'b1;
        end
      end
    end else if (line_t) begin
      if (ln != 9'd511) ln <= ln + 1'b1;
      if (ln == skip) begin row <= 0; base <= 0; end
      else if (row < 9'd240) begin row <= row + 1'b1; base <= base + 16'd160; end
    end
  end
  always @(posedge clk) begin
    fb_we <= 0;
    if (reset) begin                              // clear the screen
      fb_we <= rcnt < 17'd38400; fb_a <= rcnt[15:0]; fb_d <= 0;
    end else if (menu) begin
      fb_we <= cen && cwe && s_fb; fb_a <= {3'b000, ca[12:0]}; fb_d <= cdo;
    end else begin
      fb_we <= pix_we && row < 9'd240; fb_a <= base + {8'd0, pix_x}; fb_d <= {1'b0, pix_c};
    end
  end
endmodule

// SPI mode 0 byte: slow = clk/128 (224 kHz), fast = clk/4 (7.2 MHz)
module spi_byte(
  input            clk, go, fast,
  input      [7:0] tx,
  output     [7:0] rx,
  output reg       busy, done, sck,
  output           mosi,
  input            miso
);
  reg [7:0] sr;
  reg [5:0] div;
  reg [2:0] n;
  reg       bitin;
  initial begin busy = 0; done = 0; sck = 0; sr = 8'hFF; end
  assign mosi = busy ? sr[7] : 1'b1;
  assign rx = sr;
  wire tick = fast ? div[0] : &div;
  always @(posedge clk) begin
    done <= 0;
    if (!busy) begin
      sck <= 0; div <= 0; n <= 0;
      if (go) begin busy <= 1; sr <= tx; end
    end else begin
      div <= tick ? 6'd0 : div + 1'b1;
      if (tick) begin
        sck <= !sck;
        if (!sck) bitin <= miso;
        else begin
          sr <= {sr[6:0], bitin};
          n <= n + 1'b1;
          if (n == 3'd7) begin busy <= 0; done <= 1; end
        end
      end
    end
  end
endmodule
