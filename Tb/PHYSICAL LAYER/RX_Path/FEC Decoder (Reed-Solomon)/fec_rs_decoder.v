`timescale 1ns/1ps

module fec_rs_decoder (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [2347:0] flit_fec_in,
    input  wire          flit_valid,
    input  wire          fec_en,

    output reg  [2047:0] flit_corrected,
    output reg           fec_corrected,
    output reg  [299:0]  fec_syndrome,
    output reg           fec_uncorrectable,
    output reg  [7:0]    fec_err_count
);

    localparam S_IDLE  = 3'd0;
    localparam S_SYND  = 3'd1;
    localparam S_BM    = 3'd2;
    localparam S_OMEGA = 3'd3;
    localparam S_CHIEN = 3'd4;
    localparam S_DONE  = 3'd5;

    reg [2:0]  state;
    reg [9:0]  cnt;

    reg [9:0]  recv [0:234];
    reg [9:0]  corr [0:234];
    reg [9:0]  synd [0:29];
    reg [9:0]  sgm  [0:15];
    reg [9:0]  Bpol [0:15];
    reg [9:0]  omg  [0:29];

    reg [4:0]  bm_L;
    reg [9:0]  bm_b;
    reg [9:0]  chx;
    reg [4:0]  nerr;
    reg        uncorr_r;
    reg        synd_nz;

    reg [9:0]  bm_delta;
    reg [9:0]  bm_coeff;
    reg [9:0]  bm_tmp  [0:15];
    reg [9:0]  omg_tmp [0:29];

    reg [9:0]  ch_sv, ch_ov, ch_sp, ch_xpow;
    reg [4:0]  new_bm_L;

    integer    ii, jj;
    integer    bm_L_int;

    function [9:0] gf_mul2;
        input [9:0] a;
        begin
            if (a[9]) gf_mul2 = {a[8:0], 1'b0} ^ 10'h009;
            else      gf_mul2 = {a[8:0], 1'b0};
        end
    endfunction

    function [9:0] gf_mul;
        input [9:0] a, b;
        reg [9:0] result, aa, bb;
        integer k;
        begin
            result = 10'h0; aa = a; bb = b;
            for (k = 0; k < 10; k = k + 1) begin
                if (bb[0]) result = result ^ aa;
                aa = gf_mul2(aa);
                bb = {1'b0, bb[9:1]};
            end
            gf_mul = result;
        end
    endfunction

    function [9:0] gf_inv;
        input [9:0] a;
        reg [9:0] res, base;
        integer k;
        begin
            res = 10'h1; base = a;
            for (k = 0; k < 9; k = k + 1) begin
                base = gf_mul(base, base);
                res = gf_mul(res, base);
            end
            gf_inv = (a == 10'h0) ? 10'h0 : res;
        end
    endfunction

    function [9:0] aroot;
        input [4:0] j;
        reg [9:0] r;
        integer k;
        begin
            r = 10'h1;
            for (k = 0; k < j; k = k + 1) r = gf_mul(r, 10'h2);
            aroot = r;
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            cnt               <= 10'd0;
            flit_corrected    <= {2048{1'b0}};
            fec_corrected     <= 1'b0;
            fec_syndrome      <= {300{1'b0}};
            fec_uncorrectable <= 1'b0;
            fec_err_count     <= 8'd0;
            bm_L <= 5'd0; bm_b <= 10'h1; chx <= 10'h1; nerr <= 5'd0;
            uncorr_r <= 1'b0; synd_nz <= 1'b0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (flit_valid) begin
                        for (ii = 0; ii < 30; ii = ii + 1)
                            recv[ii] <= flit_fec_in[ii*10 +: 10];

                        recv[30] <= {2'b00, flit_fec_in[307:300]};

                        for (ii = 0; ii < 204; ii = ii + 1)
                            recv[ii+31] <= flit_fec_in[308 + ii*10 +: 10];

                        if (!fec_en) begin
                            flit_corrected    <= flit_fec_in[2347:300];
                            fec_corrected     <= 1'b0;
                            fec_uncorrectable <= 1'b0;
                            fec_err_count     <= 8'd0;
                            state             <= S_IDLE;
                        end else begin
                            for (ii = 0; ii < 30; ii = ii + 1) synd[ii] <= 10'h0;
                            cnt   <= 10'd234;
                            state <= S_SYND;
                        end
                    end
                end

                S_SYND: begin
                    for (ii = 0; ii < 30; ii = ii + 1)
                        synd[ii] <= gf_mul(synd[ii], aroot(ii[4:0])) ^ recv[cnt];

                    if (cnt == 10'd0) begin
                        for (ii = 0; ii <= 15; ii = ii + 1) sgm[ii]  <= 10'h0;
                        for (ii = 0; ii <= 15; ii = ii + 1) Bpol[ii] <= 10'h0;
                        sgm[0]  <= 10'h1; Bpol[0] <= 10'h1;
                        bm_L    <= 5'd0;  bm_b    <= 10'h1;
                        cnt     <= 10'd0;
                        state   <= S_BM;
                    end else cnt <= cnt - 1;
                end

                S_BM: begin
                    bm_delta = synd[cnt];
                    for (ii = 1; ii <= 15; ii = ii + 1)
                        if ((ii <= bm_L) && (cnt >= ii))
                            bm_delta = bm_delta ^ gf_mul(sgm[ii], synd[cnt - ii]);

                    new_bm_L = bm_L;
                    if (bm_delta != 10'h0) begin
                        for (ii = 0; ii <= 15; ii = ii + 1) bm_tmp[ii] = sgm[ii];
                        bm_coeff = gf_mul(bm_delta, gf_inv(bm_b));

                        for (ii = 1; ii <= 15; ii = ii + 1)
                            sgm[ii] <= sgm[ii] ^ gf_mul(bm_coeff, Bpol[ii-1]);

                        if (2 * bm_L <= cnt) begin
                            new_bm_L = cnt[4:0] + 5'd1 - bm_L;
                            bm_L <= new_bm_L;
                            for (ii = 0; ii <= 15; ii = ii + 1) Bpol[ii] <= bm_tmp[ii];
                            bm_b <= bm_delta;
                        end else begin
                            for (ii = 15; ii >= 1; ii = ii - 1) Bpol[ii] <= Bpol[ii-1];
                            Bpol[0] <= 10'h0;
                        end
                    end else begin
                        for (ii = 15; ii >= 1; ii = ii - 1) Bpol[ii] <= Bpol[ii-1];
                        Bpol[0] <= 10'h0;
                    end

                    if (cnt == 10'd29) begin
                        uncorr_r <= (new_bm_L > 5'd15);
                        cnt      <= 10'd0;
                        state    <= S_OMEGA;
                    end else cnt <= cnt + 1;
                end

                S_OMEGA: begin
                    for (ii = 0; ii < 30; ii = ii + 1) omg_tmp[ii] = 10'h0;
                    for (ii = 0; ii < 30; ii = ii + 1)
                        for (jj = 0; jj <= 15; jj = jj + 1)
                            if (ii >= jj)
                                omg_tmp[ii] = omg_tmp[ii] ^ gf_mul(synd[ii-jj], sgm[jj]);

                    for (ii = 0; ii < 30; ii = ii + 1) omg[ii] <= omg_tmp[ii];

                    synd_nz = 1'b0;
                    for (ii = 0; ii < 30; ii = ii + 1) if (synd[ii] != 10'h0) synd_nz = 1'b1;

                    chx <= 10'h1; nerr <= 5'd0;
                    for (ii = 0; ii < 235; ii = ii + 1) corr[ii] <= recv[ii];

                    cnt <= 10'd0; state <= S_CHIEN;
                end

                S_CHIEN: begin
                    bm_L_int = bm_L;
                    ch_sv    = sgm[bm_L_int];
                    for (ii = bm_L_int - 1; ii >= 0; ii = ii - 1)
                        ch_sv = gf_mul(ch_sv, chx) ^ sgm[ii];

                    if (ch_sv == 10'h0 && !uncorr_r) begin
                        ch_sp = 10'h0; ch_xpow = 10'h1;
                        for (ii = 1; ii <= 15; ii = ii + 2) begin
                            if (ii <= bm_L_int) ch_sp = ch_sp ^ gf_mul(sgm[ii], ch_xpow);
                            ch_xpow = gf_mul(ch_xpow, gf_mul(chx, chx));
                        end

                        ch_ov = omg[29];
                        for (ii = 28; ii >= 0; ii = ii - 1) ch_ov = gf_mul(ch_ov, chx) ^ omg[ii];

                        if (ch_sp != 10'h0) corr[cnt] <= recv[cnt] ^ gf_mul(ch_ov, gf_inv(gf_mul(ch_sp, chx)));
                        nerr <= nerr + 5'd1;
                    end

                    chx <= gf_mul(chx, 10'h204);

                    if (cnt == 10'd234) state <= S_DONE;
                    else                cnt <= cnt + 1;
                end

                S_DONE: begin
                    flit_corrected[7:0] <= corr[30][7:0];
                    for (ii = 0; ii < 204; ii = ii + 1)
                        flit_corrected[8 + ii*10 +: 10] <= corr[ii+31];

                    for (ii = 0; ii < 30; ii = ii + 1)
                        fec_syndrome[ii*10 +: 10] <= synd[ii];

                    fec_err_count     <= {3'd0, nerr};
                    fec_uncorrectable <= uncorr_r || (nerr != bm_L);
                    fec_corrected     <= synd_nz && !uncorr_r && (nerr == bm_L);

                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule