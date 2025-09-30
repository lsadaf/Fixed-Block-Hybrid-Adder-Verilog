`timescale 1ns/1ps
`default_nettype none

// ============================================================
// Fixed Block Hybrid Adder (FBHA)
// Implements a 32-bit adder using:
// - A 24-bit Carry-Lookahead Adder (CLA) for lower bits
// - An 8-bit Carry-Select Adder (CSLA) for upper bits
// Based on: "Design of Fixed Block Hybrid Adders" (arXiv:2412.01764)
// ============================================================
module fbha_adder #(
  parameter N = 32,         // Total adder width
  parameter K = 24,         // Width of the CLA block (lower bits)
  parameter LSB_HAS_CIN = 1 // If set, CLA accepts an external carry-in
)(
  input  wire         clk,
  input  wire         rst,
  input  wire         start,
  input  wire [N-1:0] A,
  input  wire [N-1:0] B,
  input  wire         Cin,
  output reg  [N-1:0] Sum,
  output reg          Cout,
  output reg          done
);

  // Input registers
  reg [N-1:0] A_r, B_r;
  reg         Cin_r;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      A_r   <= {N{1'b0}};
      B_r   <= {N{1'b0}};
      Cin_r <= 1'b0;
    end else if (start) begin
      A_r   <= A;
      B_r   <= B;
      Cin_r <= Cin;
    end
  end

  // Lower block: K-bit CLA
  wire [K-1:0] sum_lo;
  wire         cK;
  cla24_844422 #(.LSB_HAS_CIN(LSB_HAS_CIN)) u_cla24 (
    .a    (A_r[K-1:0]),
    .b    (B_r[K-1:0]),
    .cin  (Cin_r),
    .sum  (sum_lo),
    .cout (cK)
  );

  // Upper block: (N-K)-bit CSLA
  wire [N-K-1:0] sum_hi;
  wire           cN;
  csla8 u_csla_hi (
    .a    (A_r[N-1:K]),
    .b    (B_r[N-1:K]),
    .sel  (cK),
    .sum  (sum_hi),
    .cout (cN)
  );

  // Combinational outputs
  wire [N-1:0] Sum_comb  = {sum_hi, sum_lo};
  wire         Cout_comb = cN;

  // Registered outputs
  reg start_d;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      Sum     <= {N{1'b0}};
      Cout    <= 1'b0;
      start_d <= 1'b0;
      done    <= 1'b0;
    end else begin
      Sum     <= Sum_comb;
      Cout    <= Cout_comb;
      start_d <= start;
      done    <= start_d;
    end
  end

endmodule

// ============================================================
// Supporting blocks
// ============================================================

// Full Adder
module fa (
  input  wire a, b, cin,
  output wire sum, cout
);
  wire p = a ^ b;
  assign sum  = p ^ cin;
  assign cout = (a & b) | (p & cin);
endmodule

// Ripple-Carry Adder
module rca #(parameter W = 8)(
  input  wire [W-1:0] a,
  input  wire [W-1:0] b,
  input  wire         cin,
  output wire [W-1:0] sum,
  output wire         cout
);
  wire [W:0] c;
  assign c[0] = cin;

  genvar i;
  generate
    for (i=0; i<W; i=i+1) begin : g_fa
      fa u_fa (.a(a[i]), .b(b[i]), .cin(c[i]), .sum(sum[i]), .cout(c[i+1]));
    end
  endgenerate

  assign cout = c[W];
endmodule

// ============================================================
// CLA primitives (2/4/8/24-bit)
// ============================================================

// 2-bit CLA (no carry-in)
module cla2_nocin(
  input  wire [1:0] a, b,
  output wire [1:0] sum,
  output wire       cout
);
  wire [1:0] g = a & b;
  wire [1:0] p = a ^ b;
  wire c1 = g[0];
  wire c2 = g[1] | (p[1] & g[0]);
  assign sum  = {p[1]^c1, p[0]^1'b0};
  assign cout = c2;
endmodule

// 2-bit CLA (with carry-in)
module cla2_cin(
  input  wire [1:0] a, b,
  input  wire       cin,
  output wire [1:0] sum,
  output wire       cout
);
  wire [1:0] g = a & b;
  wire [1:0] p = a ^ b;
  wire c1 = g[0] | (p[0] & cin);
  wire c2 = g[1] | (p[1] & c1);
  assign sum  = {p[1]^c1, p[0]^cin};
  assign cout = c2;
endmodule

// 4-bit CLA
module cla4(
  input  wire [3:0] a, b,
  input  wire       cin,
  output wire [3:0] sum,
  output wire       cout
);
  wire [3:0] g = a & b;
  wire [3:0] p = a ^ b;

  wire c1 = g[0] | (p[0] & cin);
  wire c2 = g[1] | (p[1] & g[0]) | (p[1] & p[0] & cin);
  wire c3 = g[2] | (p[2] & g[1]) | (p[2] & p[1] & g[0])
            | (p[2] & p[1] & p[0] & cin);
  wire c4 = g[3] | (p[3] & g[2]) | (p[3] & p[2] & g[1])
            | (p[3] & p[2] & p[1] & p[0] & cin);

  assign sum  = {p[3]^c3, p[2]^c2, p[1]^c1, p[0]^cin};
  assign cout = c4;
endmodule

// 8-bit CLA (hierarchical, no carry-in)
module cla8_nocin(
  input  wire [7:0] a, b,
  output wire [7:0] sum,
  output wire       cout
);
  wire [3:0] s0, s1; 
  wire c4, c8;
  cla4 u0(.a(a[3:0]), .b(b[3:0]), .cin(1'b0), .sum(s0), .cout(c4));
  cla4 u1(.a(a[7:4]), .b(b[7:4]), .cin(c4),   .sum(s1), .cout(c8));
  assign sum  = {s1, s0};
  assign cout = c8;
endmodule

// 24-bit CLA using 8/4/4/4/2/2 composition
module cla24_844422 #(
  parameter LSB_HAS_CIN = 1
)(
  input  wire [23:0] a, b,
  input  wire        cin,
  output wire [23:0] sum,
  output wire        cout
);
  wire [7:0] s8;  wire c8;
  wire [3:0] s4a; wire c12;
  wire [3:0] s4b; wire c16;
  wire [3:0] s4c; wire c20;
  wire [1:0] s2a; wire c22;
  wire [1:0] s2b; wire c24;

  generate
    if (LSB_HAS_CIN) begin : g_8_with_cin
      wire [3:0] s0; wire c4;
      cla4 u0(.a(a[3:0]), .b(b[3:0]), .cin(cin), .sum(s0), .cout(c4));
      cla4 u1(.a(a[7:4]), .b(b[7:4]), .cin(c4),  .sum(s8[7:4]), .cout(c8));
      assign s8[3:0] = s0;
    end else begin : g_8_nocin
      cla8_nocin u8(.a(a[7:0]), .b(b[7:0]), .sum(s8), .cout(c8));
    end
  endgenerate

  cla4     u4a (.a(a[11:8]),  .b(b[11:8]),  .cin(c8),  .sum(s4a), .cout(c12));
  cla4     u4b (.a(a[15:12]), .b(b[15:12]), .cin(c12), .sum(s4b), .cout(c16));
  cla4     u4c (.a(a[19:16]), .b(b[19:16]), .cin(c16), .sum(s4c), .cout(c20));
  cla2_cin u2a (.a(a[21:20]), .b(b[21:20]), .cin(c20), .sum(s2a), .cout(c22));
  cla2_cin u2b (.a(a[23:22]), .b(b[23:22]), .cin(c22), .sum(s2b), .cout(c24));

  assign sum  = {s2b, s2a, s4c, s4b, s4a, s8};
  assign cout = c24;
endmodule

// ============================================================
// Carry-Select Adder (8-bit)
// ============================================================
module csla8(
  input  wire [7:0] a, b,
  input  wire       sel, // carry from previous block
  output wire [7:0] sum,
  output wire       cout
);
  wire [7:0] sum0, sum1;
  wire c0, c1;
  rca #(.W(8)) r0(.a(a), .b(b), .cin(1'b0), .sum(sum0), .cout(c0));
  rca #(.W(8)) r1(.a(a), .b(b), .cin(1'b1), .sum(sum1), .cout(c1));
  assign {cout, sum} = sel ? {c1, sum1} : {c0, sum0};
endmodule
