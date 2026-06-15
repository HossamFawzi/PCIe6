// ============================================================
//  PCIe Gen6 - FEC Syndrome Calculator
//  Tag : FEC_SYN  |  Group : gen6  |  Gen : Gen6
// ============================================================
//
//  INTERFACE (from HTML reference):
//    Inputs :
//      flit_rx[2303:0]  - Received FLIT + FEC parity (2304 bits)
//                         [2303:256] = 2048-bit FLIT data
//                         [255:0]    = 256-bit RS parity (30 used, 2 padded)
//      flit_valid       - input valid strobe
//      clk              - system clock (rising-edge)
//      rst_n            - active-low synchronous reset
//
//    Outputs:
//      syndrome[255:0]  - 256-bit RS syndrome (30 x 8b syndromes + 2B pad)
//      syndrome_valid   - syndrome output valid
//      zero_syndrome    - 1 when syndrome == 0 (no error)
//
//  RS(544,514) over GF(2^8):
//    Primitive poly: p(x) = x^8 + x^4 + x^3 + x^2 + 1  (0x11D)
//    Generator root: alpha = 0x02
//    30 parity symbols, 514 data symbols, 544 total
//
//  Syndrome S_j = R(alpha^j) evaluated via Horner's method.
//  Input treated as 288 x 8-bit symbols (2304 / 8 = 288).
// ============================================================

module fec_syndrome_calculator (
    input  wire          clk,
    input  wire          rst_n,

    // Inputs
    input  wire [2303:0] flit_rx,
    input  wire          flit_valid,

    // Outputs
    output reg  [255:0]  syndrome,
    output reg           syndrome_valid,
    output reg           zero_syndrome
);

    // ----------------------------------------------------------
    // Parameters
    // ----------------------------------------------------------
    localparam NUM_PARITY_SYMS = 30;
    localparam TOTAL_BYTES     = 288;   // 2304 / 8

    // ----------------------------------------------------------
    // GF(2^8) multiply function
    //   Primitive poly: x^8+x^4+x^3+x^2+1  -> reduce byte = 0x1D
    // ----------------------------------------------------------
    function [7:0] gf_mul;
        input [7:0] a;
        input [7:0] b;
        reg   [7:0] result;
        reg   [7:0] fa;
        reg   [7:0] fb;
        integer     bit_i;
        begin
            result = 8'h00;
            fa     = a;
            fb     = b;
            for (bit_i = 0; bit_i < 8; bit_i = bit_i + 1) begin
                if (fb[0])
                    result = result ^ fa;
                if (fa[7])
                    fa = (fa << 1) ^ 8'h1D;
                else
                    fa = fa << 1;
                fb = fb >> 1;
            end
            gf_mul = result;
        end
    endfunction

    // ----------------------------------------------------------
    // Alpha power: returns alpha^exp in GF(2^8), alpha = 0x02
    // ----------------------------------------------------------
    function [7:0] alpha_pow;
        input [4:0] exp;
        reg   [7:0] val;
        integer     p;
        begin
            val = 8'h01;
            for (p = 0; p < exp; p = p + 1)
                val = gf_mul(val, 8'h02);
            alpha_pow = val;
        end
    endfunction

    // ----------------------------------------------------------
    // Combinatorial syndrome computation
    //   syn_comb[j] = S_j = R(alpha^j)  for j = 0..29
    //   Horner's method over all 288 received symbols.
    // ----------------------------------------------------------
    reg [7:0] syn_comb [0:NUM_PARITY_SYMS-1];

    // Loop variables at module scope (QuestaSim Verilog-2001)
    integer    j_s;
    integer    i_s;
    reg [7:0]  horner_sym;
    reg [7:0]  horner_alpha;

    always @(*) begin : SYNDROME_COMB
        for (j_s = 0; j_s < NUM_PARITY_SYMS; j_s = j_s + 1) begin
            syn_comb[j_s] = 8'h00;
            horner_alpha  = alpha_pow(j_s[4:0]);

            for (i_s = 0; i_s < TOTAL_BYTES; i_s = i_s + 1) begin
                // Extract byte i_s (MSB-first packing)
                horner_sym    = flit_rx[(TOTAL_BYTES - 1 - i_s)*8 +: 8];
                // Horner step: acc = sym XOR (alpha^j * acc)
                syn_comb[j_s] = horner_sym ^ gf_mul(horner_alpha, syn_comb[j_s]);
            end
        end
    end

    // ----------------------------------------------------------
    // Pack 30 syndromes into 256-bit output
    //   Bits [239:0]  = 30 x 8-bit syndromes
    //   Bits [255:240] = 0 (pad)
    // ----------------------------------------------------------
    wire [255:0] syndrome_comb;
    genvar gi;
    generate
        for (gi = 0; gi < NUM_PARITY_SYMS; gi = gi + 1) begin : PACK_SYN
            assign syndrome_comb[gi*8 +: 8] = syn_comb[gi];
        end
        assign syndrome_comb[255:240] = 16'h0000;
    endgenerate

    // ----------------------------------------------------------
    // Output register
    // ----------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            syndrome       <= 256'b0;
            syndrome_valid <= 1'b0;
            zero_syndrome  <= 1'b0;
        end else begin
            syndrome_valid <= flit_valid;
            if (flit_valid) begin
                syndrome      <= syndrome_comb;
                zero_syndrome <= (syndrome_comb == 256'b0) ? 1'b1 : 1'b0;
            end else begin
                syndrome      <= 256'b0;
                zero_syndrome <= 1'b0;
            end
        end
    end

endmodule
