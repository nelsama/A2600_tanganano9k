// tia.v : Television Interface Adapter, synchronous, one clock.
//
// A colour clock takes several clk. The steps s[0]..s[3] are one-clk pulses,
// in this order; the CPU access (cpu_en) comes between s[3] of the third
// colour clock of a CPU cycle and the next s[0].
//   s[0] delayed register writes     s[1] HMOVE, HBLANK, playfield
//   s[2] sprites (counters, pixels)  s[3] collisions, colour, line counter
// The register-write delays are those measured by the emulator community.
module tia(
  input            clk, reset,
  input      [3:0] s,
  input            cpu_en,          // end of a CPU cycle (stalled ones too)
  input            wr,              // register write, with cpu_en
  input      [5:0] a,
  input      [7:0] d,
  output reg [1:0] q,               // read data, bits 7:6
  output reg       rdy,
  input      [1:0] fire_n,          // INPT4/5
  input      [3:0] pot,             // INPT0..3: paddle charged
  output           dump,            // paddle capacitors grounded
  output reg       pix_we,
  output reg [7:0] pix_x,           // 0..159
  output reg [6:0] pix_c,
  output reg       line_t,          // pulse: a new line starts
  output reg       vsync,
  output     [4:0] audio
);
  reg [7:0] hc;                     // 0..227
  reg       frame, fr_next, ext;    // not HBLANK; extended HBLANK (comb)
  reg       vblank, vb_dump, vb_lat;
  assign dump = vb_dump;

  // --- write registers ------------------------------------------------------
  reg [6:0] cp0, cp1, cpf, cbk;
  reg       pf_ref, pf_score, pf_pri, pf_refl;
  reg [1:0] bl_size, m0_size, m1_size;
  reg [2:0] nus0, nus1;
  reg [19:0] pf;                    // bit 0 = leftmost
  reg [7:0] g0n, g0o, g1n, g1o;
  reg       ref0, ref1, vd0, vd1, vdb, enm0, enm1, enbn, enbo, rm0, rm1;
  reg [3:0] hp0, hp1, hm0, hm1, hb;
  reg [3:0] audc0, audc1, audv0, audv1;
  reg [4:0] audf0, audf1;
  // one delayed write (1 or 2 colour clocks: done before the next CPU cycle)
  reg [5:0] da;
  reg [7:0] dd;
  reg [1:0] dn;
  reg       dp;
  reg [2:0] hm_n;                   // HMOVE strobe, delay 6
  reg       hm_p;

  // --- movement ---------------------------------------------------------------
  reg       mov;                    // HMOVE in progress
  reg [4:0] mclk;
  wire [3:0] mcnt = mclk[4] ? 4'd0 : mclk[3:0];
  wire      mtick = mov && hc[1:0] == 2'd0;
  reg [4:0] moving;                 // bl m1 m0 p1 p0
  wire [4:0] hit = {mcnt == (hb ^ 4'd8), mcnt == (hm1 ^ 4'd8), mcnt == (hm0 ^ 4'd8),
                    mcnt == (hp1 ^ 4'd8), mcnt == (hp0 ^ 4'd8)};
  wire [4:0] still = moving & ~hit;
  reg [4:0] tk;                     // object ticks of this colour clock
  reg       reg_tk;                 // regular clock (visible part)
  reg       cxu;                    // update collisions

  // --- sprites ------------------------------------------------------------------
  wire st = cpu_en && wr;
  wire [7:0] rescnt = frame ? 8'd157 : hc >= 8'd73 ? 8'd158 : 8'd159;
  wire       p0, p1, m0, m1, bl;
  wire [7:0] rp0, rp1;
  tia_player u_p0(.clk(clk), .reset(reset), .tick(s[2] && tk[0]), .res(st && a == 6'h10),
    .rescnt(rescnt), .nusiz(nus0), .refl(ref0), .g(vd0 ? g0o : g0n), .pix(p0), .respc(rp0));
  tia_player u_p1(.clk(clk), .reset(reset), .tick(s[2] && tk[1]), .res(st && a == 6'h11),
    .rescnt(rescnt), .nusiz(nus1), .refl(ref1), .g(vd1 ? g1o : g1n), .pix(p1), .respc(rp1));
  tia_mb #(.BALL(0)) u_m0(.clk(clk), .reset(reset), .tick(s[2] && tk[2]), .regular(reg_tk),
    .moving(moving[2]), .res(st && a == 6'h12), .rescnt(rescnt), .nusiz(nus0), .size(m0_size),
    .en(enm0 && !rm0), .hold(rm0), .load(rm0 && st && a == 6'h28 && !d[1]), .loadv(rp0), .pix(m0));
  tia_mb #(.BALL(0)) u_m1(.clk(clk), .reset(reset), .tick(s[2] && tk[3]), .regular(reg_tk),
    .moving(moving[3]), .res(st && a == 6'h13), .rescnt(rescnt), .nusiz(nus1), .size(m1_size),
    .en(enm1 && !rm1), .hold(rm1), .load(rm1 && st && a == 6'h29 && !d[1]), .loadv(rp1), .pix(m1));
  tia_mb #(.BALL(1)) u_bl(.clk(clk), .reset(reset), .tick(s[2] && tk[4]), .regular(reg_tk),
    .moving(moving[4]), .res(st && a == 6'h14), .rescnt(rescnt), .nusiz(3'd0), .size(bl_size),
    .en(vdb ? enbo : enbn), .hold(1'b0), .load(1'b0), .loadv(8'd0), .pix(bl));

  // --- playfield ------------------------------------------------------------------
  wire [7:0] x = hc - 8'd68;
  reg        pfp;
  wire       refl_now = (x == 8'd80) ? pf_ref : pf_refl;
  wire [5:0] xi = x[7:2];
  wire [5:0] xr = refl_now ? 6'd39 - xi : xi - 6'd20;
  wire [4:0] pidx = (x < 8'd80) ? xi[4:0] : xr[4:0];
  wire       pf_on = frame || (ext && hc > 8'd67);

  // --- collisions, colour -----------------------------------------------------------
  reg [14:0] cx;
  wire [14:0] cxn = {p0 & p1, m0 & m1, bl & pfp, m1 & pfp, m1 & bl, m0 & pfp, m0 & bl,
                     p1 & pfp, p1 & bl, p0 & pfp, p0 & bl, m1 & p0, m1 & p1, m0 & p1, m0 & p0};
  wire o0 = p0 | m0, o1 = p1 | m1;
  wire left = x < 8'd80;
  wire [6:0] col =
    pf_pri   ? ((pfp | bl) ? cpf : o0 ? cp0 : o1 ? cp1 : cbk) :
    pf_score ? (o0 ? cp0 : (pfp && left) ? cp0 : o1 ? cp1 : pfp ? cp1 : bl ? cpf : cbk) :
               (o0 ? cp0 : o1 ? cp1 : (pfp | bl) ? cpf : cbk);

  // --- reads ----------------------------------------------------------------------
  reg  [1:0] lat;
  wire [1:0] fi = vb_lat ? (lat & fire_n) : fire_n;
  always @* case (a[3:0])
    4'h0: q = cx[1:0];
    4'h1: q = cx[3:2];
    4'h2: q = cx[5:4];
    4'h3: q = cx[7:6];
    4'h4: q = cx[9:8];
    4'h5: q = cx[11:10];
    4'h6: q = {cx[12], 1'b0};
    4'h7: q = cx[14:13];
    4'h8: q = {pot[0], 1'b0};
    4'h9: q = {pot[1], 1'b0};
    4'hA: q = {pot[2], 1'b0};
    4'hB: q = {pot[3], 1'b0};
    4'hC: q = {fi[0], 1'b0};
    4'hD: q = {fi[1], 1'b0};
    default: q = 2'b00;
  endcase

  always @(posedge clk) begin
    pix_we <= 0;
    line_t <= 0;
    if (cpu_en) begin
      if (hc == 0) rdy <= 1;                   // the stall ends with the line
      else if (st && a == 6'h02) rdy <= 0;
    end
    lat <= vb_lat ? (lat & fire_n) : 2'b11;

    if (s[0]) begin
      if (dp) begin
        if (dn != 0) dn <= dn - 1'b1;
        else begin
          dp <= 0;
          case (da)
            6'h01: begin vb_dump <= dd[7]; vb_lat <= dd[6]; vblank <= dd[1]; end
            6'h0B: ref0 <= dd[3];
            6'h0C: ref1 <= dd[3];
            6'h0D: pf[3:0] <= dd[7:4];
            6'h0E: pf[11:4] <= {dd[0], dd[1], dd[2], dd[3], dd[4], dd[5], dd[6], dd[7]};
            6'h0F: pf[19:12] <= dd;
            6'h1B: begin g0n <= dd; g1o <= g1n; end
            6'h1C: begin g1n <= dd; g0o <= g0n; enbo <= enbn; end
            6'h1D: enm0 <= dd[1];
            6'h1E: enm1 <= dd[1];
            6'h1F: enbn <= dd[1];
            6'h20: hp0 <= dd[7:4];
            6'h21: hp1 <= dd[7:4];
            6'h22: hm0 <= dd[7:4];
            6'h23: hm1 <= dd[7:4];
            6'h24: hb <= dd[7:4];
            6'h2B: begin hp0 <= 0; hp1 <= 0; hm0 <= 0; hm1 <= 0; hb <= 0; end
            default: ;
          endcase
        end
      end
      if (hm_p) begin
        if (hm_n != 0) hm_n <= hm_n - 1'b1;
        else begin hm_p <= 0; mov <= 1; mclk <= 0; moving <= 5'h1F; ext <= 1; end
      end
    end

    if (s[1]) begin
      reg_tk <= frame;
      cxu <= frame;
      tk <= {5{frame}};
      if (mtick) begin
        moving <= still;
        mov <= |still;
        if (|still) cxu <= 1;
        if (!mclk[4]) mclk <= mclk + 1'b1;
        if (!frame) tk <= still;
      end
      if (!frame) begin
        if (hc == 0) ext <= 0;
        if ((hc == 8'd67 && !ext) || hc == 8'd75) fr_next <= 1;
      end
      if (pf_on) begin
        if (x[1:0] == 0) pfp <= pf[pidx];
        if (x == 8'd80) pf_refl <= pf_ref;
      end
    end

    if (s[3]) begin
      if (cxu && !vblank) cx <= cx | cxn;
      if (hc >= 8'd68) begin
        pix_we <= 1;
        pix_x <= x;
        pix_c <= (!frame || vblank) ? 7'd0 : col;
      end
      if (fr_next) begin frame <= 1; fr_next <= 0; end
      if (hc == 8'd227) begin hc <= 0; frame <= 0; fr_next <= 0; line_t <= 1; end
      else hc <= hc + 1'b1;
    end

    if (st) begin
      da <= a;
      dd <= d;
      case (a)
        6'h00: vsync <= d[1];
        6'h03: hc <= 8'd225;
        6'h04: begin nus0 <= d[2:0]; m0_size <= d[5:4]; end
        6'h05: begin nus1 <= d[2:0]; m1_size <= d[5:4]; end
        6'h06: cp0 <= d[7:1];
        6'h07: cp1 <= d[7:1];
        6'h08: cpf <= d[7:1];
        6'h09: cbk <= d[7:1];
        6'h0A: begin pf_ref <= d[0]; pf_score <= d[1]; pf_pri <= d[2]; bl_size <= d[5:4]; end
        6'h15: audc0 <= d[3:0];
        6'h16: audc1 <= d[3:0];
        6'h17: audf0 <= d[4:0];
        6'h18: audf1 <= d[4:0];
        6'h19: audv0 <= d[3:0];
        6'h1A: audv1 <= d[3:0];
        6'h25: vd0 <= d[0];
        6'h26: vd1 <= d[0];
        6'h27: vdb <= d[0];
        6'h28: rm0 <= d[1];
        6'h29: rm1 <= d[1];
        6'h2A: begin hm_p <= 1; hm_n <= 3'd6; end
        6'h2C: cx <= 0;
        6'h01, 6'h0B, 6'h0C, 6'h1B, 6'h1C, 6'h1D, 6'h1E, 6'h1F:
          begin dp <= 1; dn <= 2'd1; end
        6'h0D, 6'h0E, 6'h0F, 6'h20, 6'h21, 6'h22, 6'h23, 6'h24, 6'h2B:
          begin dp <= 1; dn <= 2'd2; end
        default: ;
      endcase
    end

    if (reset) begin
      hc <= 0; frame <= 0; ext <= 0; fr_next <= 0; rdy <= 1; vsync <= 0; vblank <= 0;
      vb_dump <= 0; vb_lat <= 0; dp <= 0; hm_p <= 0; mov <= 0; moving <= 0; cx <= 0;
      tk <= 0; cxu <= 0; mclk <= 0; reg_tk <= 0; pfp <= 0; lat <= 2'b11;
      rm0 <= 0; rm1 <= 0; vd0 <= 0; vd1 <= 0; vdb <= 0; nus0 <= 0; nus1 <= 0; pf <= 0;
      g0n <= 0; g0o <= 0; g1n <= 0; g1o <= 0; enm0 <= 0; enm1 <= 0; enbn <= 0; enbo <= 0;
      ref0 <= 0; ref1 <= 0; pf_ref <= 0; pf_refl <= 0; pf_score <= 0; pf_pri <= 0;
      bl_size <= 0; m0_size <= 0; m1_size <= 0;
      hp0 <= 0; hp1 <= 0; hm0 <= 0; hm1 <= 0; hb <= 0; cp0 <= 0; cp1 <= 0; cpf <= 0; cbk <= 0;
      audc0 <= 0; audc1 <= 0; audf0 <= 0; audf1 <= 0; audv0 <= 0; audv1 <= 0;
    end
  end

  // --- audio: two phases, each twice per line -----------------------------------
  wire ap0 = s[3] && (hc == 8'd9 || hc == 8'd81);
  wire ap1 = s[3] && (hc == 8'd37 || hc == 8'd149);
  wire ao0, ao1;
  tia_audio u_a0(.clk(clk), .reset(reset), .ph0(ap0), .ph1(ap1), .c(audc0), .f(audf0), .o(ao0));
  tia_audio u_a1(.clk(clk), .reset(reset), .ph0(ap0), .ph1(ap1), .c(audc1), .f(audf1), .o(ao1));
  assign audio = {1'b0, ao0 ? audv0 : 4'd0} + {1'b0, ao1 ? audv1 : 4'd0};
endmodule

module tia_player(
  input            clk, reset, tick, res,
  input      [7:0] rescnt,
  input      [2:0] nusiz,
  input            refl,
  input      [7:0] g,
  output reg       pix,
  output     [7:0] respc            // counter for a missile leaving RESMP
);
  reg [7:0] cnt;                    // 0..159
  reg       run;
  reg [6:0] rc;                     // render counter + 5 (0 = -5)
  reg [2:0] smp;
  reg [1:0] div;                    // 0: x1, 1: x2, 2: x4
  wire [1:0] divp = nusiz == 3'd5 ? 2'd1 : nusiz == 3'd7 ? 2'd2 : 2'd0;
  wire dec = cnt == 8'd156 ||
    (cnt == 8'd12 && (nusiz == 3'd1 || nusiz == 3'd3)) ||
    (cnt == 8'd28 && (nusiz == 3'd2 || nusiz == 3'd3 || nusiz == 3'd6)) ||
    (cnt == 8'd60 && (nusiz == 3'd4 || nusiz == 3'd6));
  wire [6:0] rc1 = rc + 1'b1;
  wire [6:0] k = rc - 7'd5;         // new counter - 1
  wire adv = div == 0 ? rc1 > 7'd5 :
             rc1 > 7'd6 && (div == 2'd1 ? !k[0] : k[1:0] == 2'd0);
  wire [7:0] lag = div == 0 ? 8'd5 : div == 2'd1 ? 8'd9 : 8'd12;
  wire [1:0] ro = rescnt[1:0] - 2'd1;                // 157 158 159 -> 0 1 2
  assign respc = cnt >= lag ? cnt - lag : cnt + (8'd160 - lag);
  always @(posedge clk) begin
    if (tick) begin
      pix <= run && (div == 0 ? rc >= 7'd5 : rc >= 7'd6) && g[refl ? smp : ~smp];
      if (dec) begin run <= 1; smp <= 0; rc <= 0; div <= divp; end
      else if (run) begin
        rc <= rc1;
        if (adv) begin
          smp <= smp + 1'b1;
          div <= divp;
          if (smp == 3'd7) run <= 0;
        end
      end
      cnt <= cnt == 8'd159 ? 8'd0 : cnt + 1'b1;
    end else if (!run || rc < 7'd5) div <= divp;
    if (res) begin
      cnt <= rescnt;
      if (run && rc < 7'd4) rc <= {5'd0, ro};
    end
    if (reset) begin cnt <= 0; run <= 0; pix <= 0; div <= 0; rc <= 0; smp <= 0; end
  end
endmodule

// missile or ball
module tia_mb #(parameter BALL = 0)(
  input            clk, reset, tick, regular, moving, res,
  input      [7:0] rescnt,
  input      [2:0] nusiz,
  input      [1:0] size,
  input            en, hold, load,
  input      [7:0] loadv,
  output reg       pix
);
  reg [7:0] cnt;
  reg       run;
  reg [4:0] rc;                     // render counter + 4
  reg [3:0] eff;
  wire [3:0] w = 4'd1 << size;
  wire dec = cnt == 8'd156 || (BALL == 0 && (
    (cnt == 8'd12 && (nusiz == 3'd1 || nusiz == 3'd3)) ||
    (cnt == 8'd28 && (nusiz == 3'd2 || nusiz == 3'd3 || nusiz == 3'd6)) ||
    (cnt == 8'd60 && (nusiz == 3'd4 || nusiz == 3'd6))));
  // clocked by HMOVE and by the regular clock at once ("starfield")
  wire       star = moving && regular;
  wire [1:0] c1 = cnt[1:0] + 2'd1;
  wire       pre = rc == 5'd3;
  wire       early = pre && star && c1 == 2'd3 && w < 4'd4;
  wire [3:0] effn = !star ? w : c1 == 2'd3 ? (w == 4'd1 ? 4'd2 : w) : c1 == 2'd2 ? 4'd0 : w;
  wire [3:0] lim = !moving ? w : pre ? effn : eff;
  wire [4:0] rc1 = rc + (early ? 5'd2 : 5'd1);
  wire [1:0] ro = rescnt[1:0] - 2'd1;
  always @(posedge clk) begin
    if (tick) begin
      pix <= run && en && (rc >= 5'd4 || early);
      if (dec && !hold) begin run <= 1; rc <= 0; eff <= w; end
      else if (run) begin
        if (pre) eff <= effn;
        rc <= rc1;
        if (rc1 >= {1'b0, lim} + 5'd4) run <= 0;
      end
      cnt <= cnt == 8'd159 ? 8'd0 : cnt + 1'b1;
    end
    if (res) begin
      cnt <= rescnt;
      if (BALL != 0) run <= 1;
      if (BALL != 0 || (run && rc < 5'd4)) rc <= {3'd0, ro};
    end
    if (load) cnt <= loadv;
    if (reset) begin cnt <= 0; run <= 0; pix <= 0; rc <= 0; eff <= 0; end
  end
endmodule

module tia_audio(
  input       clk, reset, ph0, ph1,
  input [3:0] c,
  input [4:0] f,
  output      o
);
  reg [4:0] nc, dv;
  reg [3:0] pc;
  reg       ce, hold, fb, nb4;
  reg       pf;
  assign o = pc[0];
  always @* case (c[3:2])
    2'd0: pf = (pc[1] ^ pc[0]) && pc != 4'hA && c[1:0] != 0;
    2'd1: pf = !pc[3];
    2'd2: pf = !nb4;
    2'd3: pf = !(pc[1] || pc[3:1] == 0);
  endcase
  always @(posedge clk) begin
    if (ph0) begin
      if (ce) begin
        nb4 <= nc[0];
        hold <= c[1:0] == 2'd2 ? nc[4:1] != 4'b0001 : c[1:0] == 2'd3 ? !nc[0] : 1'b0;
        fb <= c[1:0] == 0 ? ((pc[0] ^ nc[0]) || !(nc != 0 || pc != 4'hA) || c[3:2] == 0)
                          : ((nc[2] ^ nc[0]) || nc == 0);
      end
      ce <= dv == f;
      dv <= (dv == f || dv == 5'd31) ? 5'd0 : dv + 1'b1;
    end
    if (ph1 && ce) begin
      nc <= {fb, nc[4:1]};
      if (!hold) pc <= {pf, ~pc[3:1]};
    end
    if (reset) begin nc <= 0; dv <= 0; pc <= 0; ce <= 0; hold <= 0; fb <= 0; nb4 <= 0; end
  end
endmodule
