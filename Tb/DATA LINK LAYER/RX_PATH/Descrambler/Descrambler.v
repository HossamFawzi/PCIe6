
`timescale 1ns/1ps

module Descrambler (

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

            assign keystream[i] = lfsr_next[i][0];
        end
    endgenerate

    wire seed_mismatch;
    assign seed_mismatch = (lfsr_seed !== lfsr_state) && !link_reset && data_valid_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_state     <= 23'h7FFFFF;
            data_out       <= 256'b0;
            data_valid_out <= 1'b0;
            lfsr_sync_err  <= 1'b0;
        end
        else begin

            if (link_reset) begin
                lfsr_state     <= lfsr_seed;
                data_out       <= 256'b0;
                data_valid_out <= 1'b0;
                lfsr_sync_err  <= 1'b0;
            end
            else if (data_valid_in) begin

                lfsr_state <= lfsr_next[256];

                if (scramble_en)
                    data_out <= data_in ^ keystream;
                else
                    data_out <= data_in;

                data_valid_out <= 1'b1;

                lfsr_sync_err  <= seed_mismatch;
            end
            else begin
                data_valid_out <= 1'b0;
                lfsr_sync_err  <= 1'b0;
            end
        end
    end

endmodule
