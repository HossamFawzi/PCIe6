
module fec_syndrome_calculator (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [2303:0] flit_rx,
    input  wire          flit_valid,

    output reg  [255:0]  syndrome,
    output reg           syndrome_valid,
    output reg           zero_syndrome
);

    localparam NUM_PARITY_SYMS = 30;
    localparam TOTAL_BYTES     = 288;

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

    reg [7:0] syn_comb [0:NUM_PARITY_SYMS-1];

    integer    j_s;
    integer    i_s;
    reg [7:0]  horner_sym;
    reg [7:0]  horner_alpha;

    always @(*) begin : SYNDROME_COMB
        for (j_s = 0; j_s < NUM_PARITY_SYMS; j_s = j_s + 1) begin
            syn_comb[j_s] = 8'h00;
            horner_alpha  = alpha_pow(j_s[4:0]);

            for (i_s = 0; i_s < TOTAL_BYTES; i_s = i_s + 1) begin

                horner_sym    = flit_rx[(TOTAL_BYTES - 1 - i_s)*8 +: 8];

                syn_comb[j_s] = horner_sym ^ gf_mul(horner_alpha, syn_comb[j_s]);
            end
        end
    end

    wire [255:0] syndrome_comb;
    genvar gi;
    generate
        for (gi = 0; gi < NUM_PARITY_SYMS; gi = gi + 1) begin : PACK_SYN
            assign syndrome_comb[gi*8 +: 8] = syn_comb[gi];
        end
        assign syndrome_comb[255:240] = 16'h0000;
    endgenerate

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
