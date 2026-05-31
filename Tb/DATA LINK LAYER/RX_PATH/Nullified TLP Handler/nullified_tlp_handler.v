
module nullified_tlp_handler (
    input  wire          clk,
    input  wire          rst_n,

    input  wire          flit_null,
    input  wire [1023:0] flit_slot_data,
    input  wire          flit_slot_valid,

    output reg           null_drop,
    output reg  [7:0]    null_count
);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            null_drop  <= 1'b0;
            null_count <= 8'h00;
        end else begin
            null_drop <= 1'b0;

            if (flit_slot_valid && flit_null) begin
                null_drop <= 1'b1;

                if (null_count != 8'hFF)
                    null_count <= null_count + 8'h01;
            end
        end
    end

    `ifdef SIMULATION
    always @(posedge clk) begin
        if (flit_slot_valid && flit_null) begin
            if (flit_slot_data !== {1024{1'b1}} && flit_slot_data !== 1024'b0) begin
                $display("[NULL_HDL] WARNING @%0t: null slot data is neither all-ones nor all-zeros", $time);
            end
        end
    end
    `endif

endmodule
