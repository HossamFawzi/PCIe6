// ============================================================
// Module 42 : TS2 Ordered Set Generator (TS2_GEN)
// PCIe Gen6 Physical Layer
// Generates TS2 Ordered Sets for link training.
// Agreement on TS2 marks end of Configuration/Recovery.
// ============================================================
module ts2_gen (
    input  wire        clk,
    input  wire        rst_n,

    // Control inputs
    input  wire [7:0]  link_num,       // Negotiated link number
    input  wire [7:0]  lane_num,       // Negotiated lane number
    input  wire [7:0]  speed_cap,      // Agreed speed capability
    input  wire [7:0]  fts_count,      // FTS count
    input  wire        ts2_send,       // Trigger TS2 generation

    // Outputs
    output reg  [255:0] ts2_data,      // 256-bit TS2 ordered set
    output reg          ts2_valid,     // ts2_data is valid
    output reg          ts2_done       // One-shot done pulse
);

localparam [7:0] COM_SYMBOL = 8'hBC;  // K28.5
localparam [7:0] PAD_SYMBOL = 8'hF7;  // K23.7
localparam [7:0] TS2_ID     = 8'h45;  // TS2 identifier (distinct from TS1 0x4A)

reg [1:0] state;
localparam S_IDLE  = 2'd0;
localparam S_BUILD = 2'd1;
localparam S_VALID = 2'd2;
localparam S_DONE  = 2'd3;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ts2_data  <= 256'd0;
        ts2_valid <= 1'b0;
        ts2_done  <= 1'b0;
        state     <= S_IDLE;
    end else begin
        ts2_done <= 1'b0;

        case (state)
            S_IDLE: begin
                ts2_valid <= 1'b0;
                if (ts2_send)
                    state <= S_BUILD;
            end

            S_BUILD: begin
                // TS2 format mirrors TS1 but with TS2 ID byte
                // Byte 0: COM (K28.5)
                // Byte 1: Link Number
                // Byte 2: Lane Number
                // Byte 3: FTS Count
                // Byte 4: Speed Capability
                // Byte 5: Training Control (0 for TS2)
                // Byte 6: TS2 ID (0x45)
                // Bytes 7-31: PAD
                ts2_data[  7:  0] <= COM_SYMBOL;
                ts2_data[ 15:  8] <= link_num;
                ts2_data[ 23: 16] <= lane_num;
                ts2_data[ 31: 24] <= fts_count;
                ts2_data[ 39: 32] <= speed_cap;
                ts2_data[ 47: 40] <= 8'h00;        // Training ctrl = 0 for TS2
                ts2_data[ 55: 48] <= TS2_ID;
                ts2_data[ 63: 56] <= PAD_SYMBOL;
                ts2_data[ 71: 64] <= PAD_SYMBOL;
                ts2_data[ 79: 72] <= PAD_SYMBOL;
                ts2_data[ 87: 80] <= PAD_SYMBOL;
                ts2_data[ 95: 88] <= PAD_SYMBOL;
                ts2_data[103: 96] <= PAD_SYMBOL;
                ts2_data[111:104] <= PAD_SYMBOL;
                ts2_data[119:112] <= PAD_SYMBOL;
                ts2_data[127:120] <= PAD_SYMBOL;
                ts2_data[135:128] <= PAD_SYMBOL;
                ts2_data[143:136] <= PAD_SYMBOL;
                ts2_data[151:144] <= PAD_SYMBOL;
                ts2_data[159:152] <= PAD_SYMBOL;
                ts2_data[167:160] <= PAD_SYMBOL;
                ts2_data[175:168] <= PAD_SYMBOL;
                ts2_data[183:176] <= PAD_SYMBOL;
                ts2_data[191:184] <= PAD_SYMBOL;
                ts2_data[199:192] <= PAD_SYMBOL;
                ts2_data[207:200] <= PAD_SYMBOL;
                ts2_data[215:208] <= PAD_SYMBOL;
                ts2_data[223:216] <= PAD_SYMBOL;
                ts2_data[231:224] <= PAD_SYMBOL;
                ts2_data[239:232] <= PAD_SYMBOL;
                ts2_data[247:240] <= PAD_SYMBOL;
                ts2_data[255:248] <= PAD_SYMBOL;
                state <= S_VALID;
            end

            S_VALID: begin
                ts2_valid <= 1'b1;
                state     <= S_DONE;
            end

            S_DONE: begin
                ts2_done  <= 1'b1;
                ts2_valid <= 1'b0;
                state     <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
