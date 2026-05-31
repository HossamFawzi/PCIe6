
`timescale 1ns / 1ps

module scrambler (

    input  wire          clk,
    input  wire          rst_n,

    input  wire [255:0]  data_in,
    input  wire          data_valid_in,

    input  wire [22:0]   lfsr_seed,
    input  wire          scramble_en,
    input  wire          link_reset,

    output reg  [255:0]  data_out,
    output reg           data_valid_out,
    output reg  [22:0]   lfsr_state
);

    reg  [22:0] lfsr_reg;

    wire [278:0] seq;

    genvar gi;
    generate
        for (gi = 0; gi < 23; gi = gi + 1) begin : seed_bits
            assign seq[gi] = lfsr_reg[22 - gi];
        end
    endgenerate

    generate
        for (gi = 23; gi < 279; gi = gi + 1) begin : extend_bits
            assign seq[gi] = seq[gi-23] ^ seq[gi-21] ^ seq[gi-16] ^ seq[gi-8]
                           ^ seq[gi-5]  ^ seq[gi-2]  ^ seq[gi-1];
        end
    endgenerate

    wire [255:0] scramble_word;
    generate
        for (gi = 0; gi < 256; gi = gi + 1) begin : build_word

            assign scramble_word[255 - gi] = seq[gi];
        end
    endgenerate

    wire [22:0] lfsr_next;
    generate
        for (gi = 0; gi < 23; gi = gi + 1) begin : next_state
            assign lfsr_next[22 - gi] = seq[256 + gi];
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lfsr_reg       <= 23'h7FFFFF;
            data_out       <= 256'h0;
            data_valid_out <= 1'b0;
            lfsr_state     <= 23'h7FFFFF;
        end
        else begin

            if (link_reset) begin

                lfsr_reg   <= lfsr_seed;
                lfsr_state <= lfsr_seed;
            end
            else if (data_valid_in && scramble_en) begin

                lfsr_reg   <= lfsr_next;
                lfsr_state <= lfsr_next;
            end
            else begin

                lfsr_state <= lfsr_reg;
            end

            data_valid_out <= data_valid_in;

            if (data_valid_in) begin
                if (scramble_en)
                    data_out <= data_in ^ scramble_word;
                else
                    data_out <= data_in;
            end
            else begin
                data_out <= 256'h0;
            end
        end
    end

endmodule
