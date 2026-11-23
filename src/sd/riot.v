// riot.v : 6532 (RAM, ports, timer). Every CPU cycle: tick, then cpu_en.
module riot(
  input            clk, reset, tick,
  input            cpu_en,          // end of an executed CPU cycle
  input            cs, rs, we,      // rs: 1 = ports and timer, 0 = RAM
  input      [6:0] a,
  input      [7:0] d,
  output reg [7:0] q,
  input      [7:0] pa_in, pb_in
);
  // 128 bytes of LUT RAM, cleared during reset
  reg [7:0] ram[0:127] /* synthesis syn_ramstyle = "distributed_ram" */;
  reg [6:0] ca;
  always @(posedge clk) ca <= ca + 1'b1;
  wire [6:0] wa = reset ? ca : a;
  wire [7:0] wd = reset ? 8'd0 : d;
  wire       ram_we = reset || (cpu_en && cs && !rs && we);
  always @(posedge clk) if (ram_we) ram[wa] <= wd;
  wire [7:0] rq = ram[wa];

  reg [7:0] pao, pad, pbo, pbd;
  wire [7:0] pa = pa_in & (pao | ~pad);
  wire [7:0] pb = (pb_in & ~pbd) | (pbo & pbd);

  // The first step after a write comes one cycle later, then every interval.
  // After the wrap it counts every cycle until INTIM is read (or written).
  reg [7:0] tm;
  reg [1:0] iv;
  reg [9:0] sub;
  reg       irq, now;               // now: it wrapped in this very cycle
  reg       pa7, pf, pol;
  wire [9:0] dm = iv == 0 ? 10'd0 : iv == 2'd1 ? 10'd7 : iv == 2'd2 ? 10'd63 : 10'd1023;

  always @* begin
    if (!rs) q = rq;
    else if (a[2]) q = a[0] ? {irq, pf, 6'd0} : tm;
    else case (a[1:0])
      2'd0: q = pa;
      2'd1: q = pad;
      2'd2: q = pb;
      default: q = pbd;
    endcase
  end

  always @(posedge clk) begin
    if (tick) begin
      now <= 0;
      sub <= sub == 0 ? dm : sub - 1'b1;
      if (irq || sub == 0) tm <= tm - 1'b1;
      if (!irq && sub == 0 && tm == 0) begin irq <= 1; now <= 1; end
      pa7 <= pa[7];
      if (pa[7] != pa7 && pa[7] == pol) pf <= 1;
    end
    if (cpu_en && cs && rs) begin
      if (!we) begin
        if (a[2]) begin
          if (a[0]) pf <= 0;
          else if (!now) irq <= 0;
        end
      end else if (!a[2]) case (a[1:0])
        2'd0: pao <= d;
        2'd1: pad <= d;
        2'd2: pbo <= d;
        default: pbd <= d;
      endcase
      else if (a[4]) begin tm <= d; iv <= a[1:0]; irq <= 0; sub <= 0; end
      else pol <= a[0];
    end
    if (reset) begin
      pao <= 0; pad <= 0; pbo <= 0; pbd <= 0; tm <= 8'hA5; iv <= 2'd3; sub <= 10'd1023;
      irq <= 0; now <= 0; pf <= 0; pol <= 0; pa7 <= 1;
    end
  end
endmodule
