// dpc.v : the display processor of one 10 KB cartridge (8 KB F8 + 2 KB of
// display data at $2000 of the image). Registers at $1000-$107F.
module dpc(
  input             clk, reset, en, cpu_en, we, osc,   // osc: ~20 kHz pulse
  input      [12:0] a,
  input      [7:0]  d,
  output            sel,        // the read data is q, not the memory
  output            rd_data,    // display data read: PSRAM address dpa
  output     [19:0] dpa,
  output reg [7:0]  q,
  input      [7:0]  mem
);
  reg [7:0]  top[0:7] /* synthesis syn_ramstyle = "registers" */, bot[0:7] /* synthesis syn_ramstyle = "registers" */;
  reg [10:0] cnt[0:7] /* synthesis syn_ramstyle = "registers" */;
  reg [7:0]  flag;
  reg [2:0]  mus;
  reg [7:0]  rng;
  wire       hit = en && a[12] && a[11:7] == 0;
  wire       rd = hit && !a[6];
  wire [2:0] i = a[2:0], fn = a[5:3];
  assign sel = rd;
  assign rd_data = rd && fn != 0;
  wire [10:0] c = cnt[i];
  assign dpa = {9'b000000100, ~c};               // $2000 + 2047 - c
  wire       fl = c[7:0] == top[i] ? 1'b1 : c[7:0] == bot[i] ? 1'b0 : flag[i];
  wire       music = i >= 3'd5 && mus[i - 3'd5];
  wire [2:0] mf = {flag[7] & mus[2], flag[6] & mus[1], flag[5] & mus[0]};
  reg  [3:0] amp;
  always @* case (mf)
    3'd0: amp = 4'd0;  3'd1: amp = 4'd4;  3'd2: amp = 4'd5;  3'd3: amp = 4'd9;
    3'd4: amp = 4'd6;  3'd5: amp = 4'd10; 3'd6: amp = 4'd11; default: amp = 4'd15;
  endcase
  always @* case (fn)
    3'd0: q = !a[2] ? rng : {4'd0, amp};
    3'd1: q = mem;
    3'd2: q = mem & {8{fl}};
    3'd7: q = {8{fl}};
    default: q = 8'd0;
  endcase
  integer k;
  always @(posedge clk) begin
    for (k = 5; k < 8; k = k + 1) if (osc && mus[k - 5]) begin
      cnt[k][7:0] <= cnt[k][7:0] == 0 ? top[k] : cnt[k][7:0] - 1'b1;
      if (top[k] == 0) flag[k] <= 0;
      else if (cnt[k][7:0] <= bot[k]) flag[k] <= 0;
      else if (cnt[k][7:0] <= top[k]) flag[k] <= 1;
    end
    if (cpu_en && rd) begin
      if (fn == 0 && !a[2])
        rng <= {rng[6:0], ~(rng[7] ^ rng[5] ^ rng[4] ^ rng[3])};
      if (!music) begin
        flag[i] <= fl;
        if (fn != 0) cnt[i] <= c - 1'b1;
      end
    end
    if (cpu_en && hit && a[6] && we) case (fn)
      3'd0: begin top[i] <= d; flag[i] <= 0; end
      3'd1: bot[i] <= d;
      3'd2: cnt[i][7:0] <= music ? top[i] : d;
      3'd3: begin cnt[i][10:8] <= d[2:0]; if (i >= 3'd5) mus[i - 3'd5] <= d[4]; end
      3'd6: rng <= 8'd1;
      default: ;
    endcase
    if (reset) begin
      rng <= 8'd1; mus <= 0; flag <= 0;
      for (k = 0; k < 8; k = k + 1) begin top[k] <= 0; bot[k] <= 0; cnt[k] <= 0; end
    end
  end
endmodule
