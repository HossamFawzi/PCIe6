// =============================================================
//  MODULE : descrambler  [FIXED]
//  Fix    : VER-190 — replaced case-inequality (!==) with
//           synthesizable equivalent using ^ (XOR) reduction.
//
//  Original:  (lfsr_state !== lfsr_seed)
//  Fixed:     (|(lfsr_state ^ lfsr_seed))
//
//  Explanation:
//    !==  is a 4-state (X/Z aware) operator — unsynthesizable.
//    In synthesis (2-state world) it is identical to !=, but
//    DC K-2015 rejects it with VER-190.
//    |(lfsr_state ^ lfsr_seed) is the 2-state "not equal" and
//    is fully synthesizable.
// =============================================================
`timescale 1ns/1ps

module descrambler (
    input  wire         clk,
    input  wire         rst_n,

    input  wire [255:0] data_in,
    input  wire         data_valid_in,

    input  wire [22:0]  lfsr_seed,
    input  wire         scramble_en,
    input  wire         link_reset,

    output reg  [255:0] data_out,
    output reg          data_valid_out,
    output reg          lfsr_sync_err
);

    reg  [22:0] lfsr_state;

    wire [22:0] lfsr_next  [0:256];
    wire [255:0] keystream;

    assign lfsr_next[0] = lfsr_state;

    genvar i;
    generate
        for (i = 0; i < 256; i = i + 1) begin : LFSR_ADVANCE
            wire feedback;
            assign feedback = lfsr_next[i][22] ^ lfsr_next[i][20]
                            ^ lfsr_next[i][15] ^ lfsr_next[i][7]
                            ^ lfsr_next[i][4]  ^ lfsr_next[i][1]
                            ^ lfsr_next[i][0];
            assign lfsr_next[i+1] = {feedback, lfsr_next[i][22:1]};
            assign keystream[i]   = lfsr_next[i][0];
        end
    endgenerate

    reg link_reset_r;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) link_reset_r <= 1'b0;
        else        link_reset_r <= link_reset;

    // FIX: replaced !==  (4-state, VER-190) with |(x^y) (2-state, synthesizable)
    wire seed_mismatch;
    assign seed_mismatch = link_reset_r && !link_reset && data_valid_in
                           && |(lfsr_state ^ lfsr_seed);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state     <= 23'h7FFFFF;
            data_out       <= 256'b0;
            data_valid_out <= 1'b0;
            lfsr_sync_err  <= 1'b0;
        end else begin
            if (link_reset) begin
                lfsr_state     <= lfsr_seed;
                data_out       <= 256'b0;
                data_valid_out <= 1'b0;
                lfsr_sync_err  <= 1'b0;
            end else if (data_valid_in) begin
                lfsr_state     <= lfsr_next[256];
                data_out       <= scramble_en ? (data_in ^ keystream) : data_in;
                data_valid_out <= 1'b1;
                lfsr_sync_err  <= seed_mismatch;
            end else begin
                data_valid_out <= 1'b0;
                lfsr_sync_err  <= 1'b0;
            end
        end
    end

endmodule
