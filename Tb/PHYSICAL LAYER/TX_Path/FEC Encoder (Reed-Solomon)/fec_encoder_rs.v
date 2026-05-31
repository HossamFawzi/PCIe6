
module fec_encoder_rs (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [2047:0] flit_in,
    input  wire          flit_valid,
    input  wire          fec_en,

    output reg  [2347:0] flit_fec_out,
    output reg  [299:0]  fec_parity,
    output reg           fec_valid
);

function [9:0] gf_mul2;
    input [9:0] a;
    begin
        if (a[9])
            gf_mul2 = {a[8:0], 1'b0} ^ 10'h009;
        else
            gf_mul2 = {a[8:0], 1'b0};
    end
endfunction

function [9:0] gf_mul;
    input [9:0] a, b;
    reg [9:0] result, aa;
    reg [9:0] bb;
    integer   i;
    begin
        result = 10'h0;
        aa     = a;
        bb     = b;
        for (i = 0; i < 10; i = i+1) begin
            if (bb[0])
                result = result ^ aa;
            aa = gf_mul2(aa);
            bb = {1'b0, bb[9:1]};
        end
        gf_mul = result;
    end
endfunction

reg [9:0] gen_poly [0:29];
integer   gi;

initial begin
    gen_poly[ 0] = 10'h20B;  gen_poly[ 1] = 10'h342;
    gen_poly[ 2] = 10'h080;  gen_poly[ 3] = 10'h09E;
    gen_poly[ 4] = 10'h0B9;  gen_poly[ 5] = 10'h07F;
    gen_poly[ 6] = 10'h188;  gen_poly[ 7] = 10'h0C1;
    gen_poly[ 8] = 10'h262;  gen_poly[ 9] = 10'h314;
    gen_poly[10] = 10'h169;  gen_poly[11] = 10'h373;
    gen_poly[12] = 10'h1F7;  gen_poly[13] = 10'h3AE;
    gen_poly[14] = 10'h181;  gen_poly[15] = 10'h1EF;
    gen_poly[16] = 10'h2D0;  gen_poly[17] = 10'h05E;
    gen_poly[18] = 10'h084;  gen_poly[19] = 10'h251;
    gen_poly[20] = 10'h0F9;  gen_poly[21] = 10'h11A;
    gen_poly[22] = 10'h235;  gen_poly[23] = 10'h06C;
    gen_poly[24] = 10'h001;  gen_poly[25] = 10'h228;
    gen_poly[26] = 10'h0E6;  gen_poly[27] = 10'h0BB;
    gen_poly[28] = 10'h228;  gen_poly[29] = 10'h23F;
end

localparam N_SYM = 9'd205;

reg [9:0]    parity [0:29];
reg [8:0]    sym_cnt;
reg          enc_busy;
reg [2047:0] flit_buf;
integer      pi;

reg [9:0]  sym_r;
reg [9:0]  fb_r;
integer    pj;

function [9:0] extract_sym;
    input [2047:0] flit;
    input [8:0]    idx;
    reg [9:0] s;
    begin
        if (idx < 9'd204)

            s = flit[2047 - idx*10 -: 10];
        else

            s = {2'b00, flit[7:0]};
        extract_sym = s;
    end
endfunction

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        flit_fec_out <= {2348{1'b0}};
        fec_parity   <= {300{1'b0}};
        fec_valid    <= 1'b0;
        enc_busy     <= 1'b0;
        sym_cnt      <= 9'h0;
        flit_buf     <= {2048{1'b0}};
        for (pi = 0; pi < 30; pi = pi+1)
            parity[pi] <= 10'h0;
    end else begin
        fec_valid <= 1'b0;

        if (flit_valid && fec_en && !enc_busy) begin
            flit_buf <= flit_in;
            enc_busy <= 1'b1;
            sym_cnt  <= 9'h0;
            for (pi = 0; pi < 30; pi = pi+1)
                parity[pi] <= 10'h0;

        end else if (enc_busy) begin
            if (sym_cnt < N_SYM) begin

                sym_r = extract_sym(flit_buf, sym_cnt);
                fb_r  = sym_r ^ parity[29];

                for (pj = 29; pj > 0; pj = pj-1)
                    parity[pj] <= parity[pj-1] ^ gf_mul(fb_r, gen_poly[pj]);
                parity[0] <= gf_mul(fb_r, gen_poly[0]);
                sym_cnt   <= sym_cnt + 1'b1;

            end else begin

                enc_busy <= 1'b0;

                fec_parity <= {
                    parity[29], parity[28], parity[27], parity[26],
                    parity[25], parity[24], parity[23], parity[22],
                    parity[21], parity[20], parity[19], parity[18],
                    parity[17], parity[16], parity[15], parity[14],
                    parity[13], parity[12], parity[11], parity[10],
                    parity[9],  parity[8],  parity[7],  parity[6],
                    parity[5],  parity[4],  parity[3],  parity[2],
                    parity[1],  parity[0]
                };

                flit_fec_out <= {flit_buf,
                    parity[29], parity[28], parity[27], parity[26],
                    parity[25], parity[24], parity[23], parity[22],
                    parity[21], parity[20], parity[19], parity[18],
                    parity[17], parity[16], parity[15], parity[14],
                    parity[13], parity[12], parity[11], parity[10],
                    parity[9],  parity[8],  parity[7],  parity[6],
                    parity[5],  parity[4],  parity[3],  parity[2],
                    parity[1],  parity[0]
                };

                fec_valid <= 1'b1;
            end
        end
    end
end

endmodule
