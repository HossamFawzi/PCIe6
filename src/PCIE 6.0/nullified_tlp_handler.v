
module nullified_tlp_handler (
    input  wire          clk,
    input  wire          rst_n,

    // ?? From FLIT Rx Deframer ?????????????????????????????????????????????????
    input  wire          flit_null,            // this FLIT slot is a null slot
    input  wire [1023:0] flit_slot_data,       // raw slot data (used for assert checks only)
    input  wire          flit_slot_valid,      // FLIT slot present this cycle

    // ?? To DLL Error Aggregator / diagnostics ???????????????????????????????
    output reg           null_drop,            // 1-cycle pulse per null slot dropped
    output reg  [7:0]    null_count            // saturating counter (wraps at 8'hFF)
);

    // ?? Null slot detection and counting ??????????????????????????????????????
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            null_drop  <= 1'b0;
            null_count <= 8'h00;
        end else begin
            null_drop <= 1'b0;   // default: no drop this cycle

            if (flit_slot_valid && flit_null) begin
                null_drop <= 1'b1;

                // Saturating increment
                if (null_count != 8'hFF)
                    null_count <= null_count + 8'h01;
            end
        end
    end

    // ?? Assertion: null slots must carry the PCIe-defined null pattern ????????
    // (Null TLP slot payload should be all-ones per spec; this is a simulation
    //  check only ? synthesis tools ignore initial/assert blocks.)
    // FIX-SYNTH-3: Wrapped $display with `ifdef SIMULATION
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
