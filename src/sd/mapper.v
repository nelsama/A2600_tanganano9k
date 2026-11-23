// mapper.v : cartridge bank switching. cpu_en = end of an executed CPU cycle,
// so the access to a hotspot still reads the old bank, as in the cartridge.
// pa = PSRAM byte address: ROM at 0, cartridge RAM at $80000.
module mapper(
  input             clk, reset, cpu_en, we,
  input      [12:0] a,
  input      [7:0]  d,          // data bus (read or written)
  input      [3:0]  map,
  input      [7:0]  last,       // 3F / 3E: number of 2 KB banks - 1
  input             sc,         // 128 bytes of RAM (Superchip)
  output reg [19:0] pa,
  output reg        ram_w       // this address is a RAM write port
);
  localparam M4K = 4'd0, M2K = 4'd1, F8 = 4'd2, F6 = 4'd3, F4 = 4'd4, E0 = 4'd5, FE = 4'd6,
             T3F = 4'd7, FA = 4'd8, E7 = 4'd9, CV = 4'd10, UA = 4'd11, M0840 = 4'd12,
             F0 = 4'd13, EF = 4'd14, T3E = 4'd15;
  reg [7:0] b, b1, b2;          // main bank, slices
  reg       fe, e3;
  wire        c = a[12];
  wire [11:0] o = a[11:0];
  always @* begin
    pa = {8'd0, o};
    ram_w = 0;
    case (map)
      M4K: if (sc) pa = {7'd0, b[0], o};          // DPC: F8
      M2K: pa = {9'd0, o[10:0]};
      F8, FE, UA, M0840: pa = {7'd0, b[0], o};
      F6:  pa = {6'd0, b[1:0], o};
      F4:  pa = {5'd0, b[2:0], o};
      F0, EF: pa = {4'd0, b[3:0], o};
      E0:  pa = {7'd0, o[11:10] == 2'd0 ? b[2:0] : o[11:10] == 2'd1 ? b1[2:0] :
                       o[11:10] == 2'd2 ? b2[2:0] : 3'd7, o[9:0]};
      T3F: pa = {1'b0, o[11] ? last : b, o[10:0]};
      T3E: if (o[11]) pa = {1'b0, last, o[10:0]};
           else if (!e3) pa = {1'b0, b, o[10:0]};
           else begin pa = {5'b10000, b[4:0], o[9:0]}; ram_w = o[10]; end
      FA:  if (o[11:9] == 0) begin pa = {12'h800, o[7:0]}; ram_w = !o[8]; end
           else pa = {6'd0, b[1:0], o};
      E7:  if (!o[11]) begin
             if (b[2:0] == 3'd7) begin pa = {10'h200, o[9:0]}; ram_w = !o[10]; end
             else pa = {6'd0, b[2:0], o[10:0]};
           end else if (o[10:9] == 0) begin
             pa = {10'h201, b1[1:0], o[7:0]}; ram_w = !o[8];
           end else pa = {6'd0, 3'd7, o[10:0]};
      CV:  if (!o[11]) begin pa = {10'h200, o[9:0]}; ram_w = o[10]; end
           else pa = {9'd0, o[10:0]};
      default: ;
    endcase
    if (sc && map != M4K && o[11:8] == 0) begin pa = {13'h1000, o[6:0]}; ram_w = !o[7]; end
    if (!c) ram_w = 0;
  end
  always @(posedge clk) begin
    if (reset) begin
      b  <= map == F8 || (map == M4K && sc) || map == EF ? 8'd1 : map == FA ? 8'd2 : map == E0 ? 8'd4 : 8'd0;
      b1 <= map == E0 ? 8'd5 : 8'd0;
      b2 <= 8'd6;
      fe <= 0;
      e3 <= 0;
    end else if (cpu_en) begin
      fe <= a == 13'h01FE;
      case (map)
        F8, M4K: if (c && o[11:1] == 11'h7FC) b <= {7'd0, o[0]};
        F6: if (c && o >= 12'hFF6 && o <= 12'hFF9) b <= {6'd0, o[1:0] - 2'd2};
        F4: if (c && o >= 12'hFF4 && o <= 12'hFFB) b <= {5'd0, o[2:0] - 3'd4};
        FA: if (c && o >= 12'hFF8 && o <= 12'hFFA) b <= {6'd0, o[1:0]};
        EF: if (c && o[11:4] == 8'hFE) b <= {4'd0, o[3:0]};
        F0: if (c && o == 12'hFF0) b <= {4'd0, b[3:0] + 4'd1};
        E0: if (c && o[11:5] == 7'h7F) case (o[4:3])
              2'd0: b  <= {5'd0, o[2:0]};
              2'd1: b1 <= {5'd0, o[2:0]};
              2'd2: b2 <= {5'd0, o[2:0]};
              default: ;
            endcase
        E7: if (c && o[11:4] == 8'hFE) begin
              if (!o[3]) b <= {5'd0, o[2:0]};
              else if (!o[2]) b1 <= {6'd0, o[1:0]};
            end
        FE: if (fe) b <= {7'd0, ~d[5]};
        UA: if ((a & 13'h1260) == 13'h0220) b <= 0;
            else if ((a & 13'h1260) == 13'h0240) b <= 8'd1;
        M0840: if ((a & 13'h1840) == 13'h0800) b <= 0;
               else if ((a & 13'h1840) == 13'h0840) b <= 8'd1;
        T3F: if (we && a <= 13'h003F) b <= d & last;
        T3E: if (we && a == 13'h003F) begin b <= d & last; e3 <= 0; end
             else if (we && a == 13'h003E) begin b <= d; e3 <= 1; end
        default: ;
      endcase
    end
  end
endmodule
