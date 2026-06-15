// ============================================================
// Module 41 : TS1 Ordered Set Generator (TS1_GEN)
// PCIe Gen6 Physical Layer
// Generates TS1 Ordered Sets for link training.
// Used in Polling, Configuration, and Recovery states.
// ============================================================
module ts1_gen (
    input  wire        clk,
    input  wire        rst_n,

    // Control inputs
    input  wire [7:0]  link_num,       // Link number (0xFF = PAD)
    input  wire [7:0]  lane_num,       // Lane number (0xFF = PAD)
    input  wire [7:0]  speed_cap,      // Speed capability bits
    input  wire [7:0]  fts_count,      // FTS count field
    input  wire        ts1_send,       // Request to send TS1
    input  wire        compliance_mode,// Set compliance bit in TS1

    // Outputs
    output reg  [255:0] ts1_data,      // 256-bit TS1 ordered set
    output reg          ts1_valid,     // ts1_data is valid
    output reg          ts1_done       // One-shot: TS1 fully generated
);

// TS1 Ordered Set constants (PCIe spec)
// Symbol 0: COM (K28.5) = 0xBC
// Symbol 1: Link Number
// Symbol 2: Lane Number
// Symbol 3: FTS Count
// Symbol 4: Speed Cap
// Symbols 5-15: Training Control / reserved
// Symbols 16-31: Scrambled PAD (0xF7)

localparam [7:0] COM_SYMBOL  = 8'hBC;  // K28.5
localparam [7:0] PAD_SYMBOL  = 8'hF7;  // K23.7
localparam [7:0] TS1_ID      = 8'h4A;  // TS1 identifier symbol

// Compliance bit position in training control byte (symbol 5)
localparam COMPLIANCE_BIT = 4;

reg [1:0] state;
localparam S_IDLE  = 2'd0;
localparam S_BUILD = 2'd1;
localparam S_VALID = 2'd2;
localparam S_DONE  = 2'd3;

reg [7:0] training_ctrl;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ts1_data     <= 256'd0;
        ts1_valid    <= 1'b0;
        ts1_done     <= 1'b0;
        state        <= S_IDLE;
        training_ctrl<= 8'h00;
    end else begin
        ts1_done  <= 1'b0; // default pulse off

        case (state)
            S_IDLE: begin
                ts1_valid <= 1'b0;
                if (ts1_send) begin
                    training_ctrl <= {3'b000, compliance_mode, 4'b0000};
                    state <= S_BUILD;
                end
            end

            S_BUILD: begin
                // Build 32-byte (256-bit) TS1 ordered set
                // Byte 0 (bits 7:0)   = COM
                // Byte 1 (bits 15:8)  = Link Number
                // Byte 2 (bits 23:16) = Lane Number
                // Byte 3 (bits 31:24) = FTS Count
                // Byte 4 (bits 39:32) = Speed Capability
                // Byte 5 (bits 47:40) = Training Control
                // Byte 6 (bits 55:48) = TS1 ID
                // Bytes 7-31          = PAD
                ts1_data[  7:  0] <= COM_SYMBOL;
                ts1_data[ 15:  8] <= link_num;
                ts1_data[ 23: 16] <= lane_num;
                ts1_data[ 31: 24] <= fts_count;
                ts1_data[ 39: 32] <= speed_cap;
                ts1_data[ 47: 40] <= training_ctrl;
                ts1_data[ 55: 48] <= TS1_ID;
                ts1_data[ 63: 56] <= PAD_SYMBOL;
                ts1_data[ 71: 64] <= PAD_SYMBOL;
                ts1_data[ 79: 72] <= PAD_SYMBOL;
                ts1_data[ 87: 80] <= PAD_SYMBOL;
                ts1_data[ 95: 88] <= PAD_SYMBOL;
                ts1_data[103: 96] <= PAD_SYMBOL;
                ts1_data[111:104] <= PAD_SYMBOL;
                ts1_data[119:112] <= PAD_SYMBOL;
                ts1_data[127:120] <= PAD_SYMBOL;
                ts1_data[135:128] <= PAD_SYMBOL;
                ts1_data[143:136] <= PAD_SYMBOL;
                ts1_data[151:144] <= PAD_SYMBOL;
                ts1_data[159:152] <= PAD_SYMBOL;
                ts1_data[167:160] <= PAD_SYMBOL;
                ts1_data[175:168] <= PAD_SYMBOL;
                ts1_data[183:176] <= PAD_SYMBOL;
                ts1_data[191:184] <= PAD_SYMBOL;
                ts1_data[199:192] <= PAD_SYMBOL;
                ts1_data[207:200] <= PAD_SYMBOL;
                ts1_data[215:208] <= PAD_SYMBOL;
                ts1_data[223:216] <= PAD_SYMBOL;
                ts1_data[231:224] <= PAD_SYMBOL;
                ts1_data[239:232] <= PAD_SYMBOL;
                ts1_data[247:240] <= PAD_SYMBOL;
                ts1_data[255:248] <= PAD_SYMBOL;
                state <= S_VALID;
            end

            S_VALID: begin
                ts1_valid <= 1'b1;
                state     <= S_DONE;
            end

            S_DONE: begin
                ts1_done  <= 1'b1;
                ts1_valid <= 1'b0;
                state     <= S_IDLE;
            end

            default: state <= S_IDLE;
        endcase
    end
end

endmodule
