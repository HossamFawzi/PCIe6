// =============================================================================
// PCIe Gen6 DLL Support Block: DLLP Generator (DLLP_GEN)
// =============================================================================
module dllp_gen (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [71:0] fc_update,
    input  wire        fc_update_valid,
    input  wire        fc_update_req,
    input  wire [2:0]  pm_type,
    input  wire        pm_send,
    input  wire        nop_send,
    input  wire [63:0] bw_notif,
    input  wire        bw_notif_valid,
    output reg  [63:0] fc_dllp,
    output reg         fc_dllp_valid,
    output reg  [63:0] pm_dllp,
    output reg         pm_dllp_valid,
    output reg  [63:0] nop_dllp,
    output reg         nop_valid
);
    localparam DLLP_NOP_TYPE = 8'h31; // BUG FIX: NOP=0x31 per spec (not 0x00=ACK)
    localparam DLLP_PM_BASE  = 8'h20;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_dllp       <= 64'd0;
            fc_dllp_valid <= 1'b0;
            pm_dllp       <= 64'd0;
            pm_dllp_valid <= 1'b0;
            nop_dllp      <= 64'd0;
            nop_valid     <= 1'b0;
        end else begin
            // Default: clear all valids every cycle (pulse outputs)
            fc_dllp_valid <= 1'b0;
            pm_dllp_valid <= 1'b0;
            nop_valid     <= 1'b0;

            // BW notification overrides FC (higher priority)
            if (bw_notif_valid) begin
                fc_dllp       <= bw_notif;
                fc_dllp_valid <= 1'b1;
            end else if (fc_update_valid || fc_update_req) begin
                fc_dllp       <= {fc_update[71:8], fc_update[7:0]};
                fc_dllp_valid <= 1'b1;
            end

            if (pm_send) begin
                pm_dllp       <= {DLLP_PM_BASE | {5'd0, pm_type}, 56'd0};
                pm_dllp_valid <= 1'b1;
            end

            if (nop_send) begin
                nop_dllp  <= {DLLP_NOP_TYPE, 56'd0};
                nop_valid <= 1'b1;
            end
        end
    end
endmodule
