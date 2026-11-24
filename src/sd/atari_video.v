// atari_video.v : framebuffer -> 720x480p (858 x 525 at 27 MHz).
// Game: 160 x 240 pixels, each 4 x 2. Menu: text, 80 x 30 characters of
// 8 x 16; the same memory holds the characters (0..2399) and, at 4096, the
// font (8 bytes per character, every row shown twice).
module atari_video(
  input             clk,            // write side
  input             we,
  input      [15:0] wa,
  input      [7:0]  wd,
  input             clk_pix,
  input             menu, pal,
  input      [4:0]  hl_row,
  output reg        vblank,
  output reg [7:0]  r, g, b,
  output reg        hs, vs, de,     // like r, g, b, 2 clk after h and v
  output reg [9:0]  h, v
);
  localparam X0 = 40, W = 640;
  reg [7:0] fb[0:38911] /* synthesis syn_ramstyle = "block_ram" */;
  reg [7:0] q;
  reg [15:0] ra;
  always @(posedge clk) if (we) fb[wa] <= wd;
  always @(posedge clk_pix) q <= fb[ra];

  reg [1:0] ms, ps;
  always @(posedge clk_pix) begin ms <= {ms[0], menu}; ps <= {ps[0], pal}; end

  reg [15:0] base;                  // start of this line's 160 or 80 bytes
  initial begin h = 0; v = 0; base = 0; end
  wire last = h == 10'd857;
  always @(posedge clk_pix) begin
    h <= last ? 10'd0 : h + 1'b1;
    if (last) begin
      v <= v == 10'd524 ? 10'd0 : v + 1'b1;
      if (v == 10'd524) base <= 0;
      else if (ms[1]) begin if (v[3:0] == 4'd15) base <= base + 16'd80; end
      else if (v[0]) base <= base + 16'd160;
      vblank <= v >= 10'd479 && v < 10'd524;
    end
  end

  // x = h - (X0 - 8): the fetch of a group of 8 pixels happens in the 8
  // pixels before it. game: two bytes per group, menu: character, font row.
  wire [9:0] x = h - (X0 - 8);
  wire       act = x < W;           // fetching
  reg  [6:0] ch;
  reg  [7:0] p0, p1, fr, sh;
  reg  [7:0] c0, c1;
  reg        inv;
  always @(posedge clk_pix) begin
    case (x[2:0])
      3'd0: ra <= ms[1] ? base + {9'd0, x[9:3]} : base + {8'd0, x[9:3], 1'b0};
      3'd2: ;
      3'd3: begin
        p0 <= q;
        ra <= ms[1] ? {6'b000100, q[6:0], v[3:1]} : {ra[15:1], 1'b1};
      end
      3'd6: p1 <= q;
      3'd7: begin
        c0 <= p0; c1 <= p1;
        sh <= p1; inv <= p0[7];
      end
      default: ;
    endcase
    if (x[2:0] != 3'd7) sh <= {sh[6:0], 1'b0};
  end

  // stage A: after the edge with x[2:0] = 7, h is at pixel 0 of the group
  wire       vis = h >= X0 && h < X0 + W && v < 10'd480;
  wire [7:0] gp = x[2] ? c1 : c0;
  wire       hl = v[8:4] == hl_row;
  wire       dot = sh[7] ^ hl ^ inv;
  // colour of the game from the palette ROM, 1 clk later
  wire [17:0] rgb;
  atari_palette u_pal(.clk(clk_pix), .a({ps[1], gp[6:0]}), .q(rgb));
  reg vis1, dot1, m1, de1, hs1, vs1, top1;
  always @(posedge clk_pix) begin
    vis1 <= vis; dot1 <= dot; m1 <= ms[1];
    top1 <= v < 10'd32 || v >= 10'd448;
    de1 <= h < 10'd720 && v < 10'd480;
    hs1 <= !(h >= 10'd736 && h < 10'd798);
    // 6 lines, aligned with the start of hs
    vs1 <= !((v > 10'd489 || (v == 10'd489 && h >= 10'd736)) &&
             (v < 10'd495 || (v == 10'd495 && h < 10'd736)));
    {de, hs, vs} <= {de1, hs1, vs1};
    if (m1) {r, g, b} <= !de1 ? 24'd0 : (vis1 && dot1) ? (top1 ? 24'hFFC040 : 24'hE8F0FF) : 24'h101838;
    else    {r, g, b} <= !vis1 ? 24'd0 :
              {rgb[17:12], rgb[17:16], rgb[11:6], rgb[11:10], rgb[5:0], rgb[5:4]};
  end
endmodule
