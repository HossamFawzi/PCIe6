
`timescale 1ns / 1ps

module flit_null_slot_inserter (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [2047:0] flit_in,
    input  wire          flit_valid,
    input  wire [1:0]    flit_slot_used,

    input  wire [1023:0] null_pattern,

    output reg  [2047:0] flit_out,
    output reg           flit_out_valid,
    output reg           null_inserted,
    output reg  [7:0]    null_count
);

    wire [1023:0] slot0_mux = flit_slot_used[0] ? flit_in[1023:0]    : null_pattern;
    wire [1023:0] slot1_mux = flit_slot_used[1] ? flit_in[2047:1024] : null_pattern;

    wire any_null = flit_valid & (~flit_slot_used[0] | ~flit_slot_used[1]);

    always @(posedge clk) begin
        if (!rst_n) begin
            flit_out       <= {2048{1'b0}};
            flit_out_valid <= 1'b0;
            null_inserted  <= 1'b0;
            null_count     <= 8'h00;
        end else begin

            flit_out_valid <= flit_valid;

            null_inserted  <= any_null;

            if (flit_valid)
                flit_out <= {slot1_mux, slot0_mux};

            if (any_null)
                null_count <= (null_count == 8'hFF) ? 8'hFF : null_count + 8'h01;
        end
    end

endmodule
