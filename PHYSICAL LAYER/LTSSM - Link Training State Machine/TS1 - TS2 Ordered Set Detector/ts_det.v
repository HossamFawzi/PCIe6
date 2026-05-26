// ============================================================
// Module 43 : TS1/TS2 Ordered Set Detector (TS_DET)
// PCIe Gen6 Physical Layer
// Detects and decodes incoming TS1/TS2 ordered sets.
// Feeds LTSSM state machines directly.
// ============================================================
module ts_det (
    input  wire        clk,
    input  wire        rst_n,

    // RX data input
    input  wire [255:0] rx_data,       // 256-bit RX data word
    input  wire         rx_valid,      // RX data valid
    input  wire         block_lock,    // Block/symbol lock achieved

    // Detected outputs
    output reg          ts1_detected,      // TS1 was detected
    output reg          ts2_detected,      // TS2 was detected
    output reg  [7:0]   ts1_link_num,      // Link number from TS1
    output reg  [7:0]   ts1_lane_num,      // Lane number from TS1
    output reg  [7:0]   ts2_speed_cap,     // Speed capability from TS2
    output reg          ts_decode_err      // Malformed OS detected
);

// Constants
localparam [7:0] COM_SYMBOL = 8'hBC;   // K28.5
localparam [7:0] TS1_ID     = 8'h4A;
localparam [7:0] TS2_ID     = 8'h45;

// Internal wires — extract fields from rx_data
wire [7:0] sym0  = rx_data[ 7:  0];   // Should be COM
wire [7:0] sym1  = rx_data[15:  8];   // Link number
wire [7:0] sym2  = rx_data[23: 16];   // Lane number
wire [7:0] sym4  = rx_data[39: 32];   // Speed capability
wire [7:0] sym6  = rx_data[55: 48];   // TS1/TS2 ID

wire is_com      = (sym0 == COM_SYMBOL);
wire is_ts1_id   = (sym6 == TS1_ID);
wire is_ts2_id   = (sym6 == TS2_ID);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ts1_detected  <= 1'b0;
        ts2_detected  <= 1'b0;
        ts1_link_num  <= 8'h00;
        ts1_lane_num  <= 8'h00;
        ts2_speed_cap <= 8'h00;
        ts_decode_err <= 1'b0;
    end else begin
        // Defaults — pulse outputs
        ts1_detected  <= 1'b0;
        ts2_detected  <= 1'b0;
        ts_decode_err <= 1'b0;

        if (rx_valid && block_lock) begin
            if (is_com) begin
                if (is_ts1_id) begin
                    // Valid TS1
                    ts1_detected <= 1'b1;
                    ts1_link_num <= sym1;
                    ts1_lane_num <= sym2;
                end else if (is_ts2_id) begin
                    // Valid TS2
                    ts2_detected  <= 1'b1;
                    ts2_speed_cap <= sym4;
                end else begin
                    // COM present but unknown OS ID
                    ts_decode_err <= 1'b1;
                end
            end
            // No COM = not a TS1/TS2 (could be data, SKP, etc.) — ignore
        end
    end
end

endmodule
