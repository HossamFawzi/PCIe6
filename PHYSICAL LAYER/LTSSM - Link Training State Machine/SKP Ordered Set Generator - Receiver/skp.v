// ============================================================
// Module 46 : SKP Ordered Set Generator / Receiver (SKP)
// PCIe Gen6 Physical Layer
// SKP ordered sets compensate for spread-spectrum clock
// differences between TX and RX.
// Insert/remove every 1180-1538 symbols.
// ============================================================
module skp (
    input  wire        clk,
    input  wire        rst_n,

    // TX side
    input  wire        skp_send_req,       // Request to insert SKP OS
    input  wire [11:0] skp_interval,       // SKP interval (symbols between inserts)

    // RX side
    input  wire [255:0] rx_data,
    input  wire         rx_valid,

    // TX outputs
    output reg  [255:0] skp_data,          // SKP OS data
    output reg          skp_tx_valid,      // SKP data valid

    // RX outputs
    output reg          skp_detected,      // SKP OS detected in RX
    output reg          skp_removed,       // SKP has been stripped (pulse)
    output reg          skp_err            // SKP format error
);

// SKP symbol = K28.0 = 0x1C per PCIe spec
// SKP OS: COM SKP SKP SKP (4 symbols), can appear multiple times
localparam [7:0] COM_SYMBOL = 8'hBC;  // K28.5
localparam [7:0] SKP_SYMBOL = 8'h1C;  // K28.0

// Build SKP TX word: 4-symbol pattern repeated
// COM SKP SKP SKP | COM SKP SKP SKP | ...  (32 symbols total)
wire [255:0] skp_tx_word;
genvar gi;
generate
    for (gi = 0; gi < 8; gi = gi + 1) begin : SKP_BUILD
        assign skp_tx_word[gi*32 +  0 +: 8] = COM_SYMBOL;
        assign skp_tx_word[gi*32 +  8 +: 8] = SKP_SYMBOL;
        assign skp_tx_word[gi*32 + 16 +: 8] = SKP_SYMBOL;
        assign skp_tx_word[gi*32 + 24 +: 8] = SKP_SYMBOL;
    end
endgenerate

// TX interval counter
reg [11:0] interval_cnt;
reg        auto_send;

// TX FSM
reg [1:0] tx_state;
localparam TX_IDLE = 2'd0;
localparam TX_SEND = 2'd1;
localparam TX_DONE = 2'd2;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        skp_data      <= 256'd0;
        skp_tx_valid  <= 1'b0;
        tx_state      <= TX_IDLE;
        interval_cnt  <= 12'd0;
        auto_send     <= 1'b0;
    end else begin
        auto_send <= 1'b0;

        // Interval counter — auto SKP generation
        if (skp_interval > 12'd0) begin
            if (interval_cnt >= skp_interval - 12'd1) begin
                interval_cnt <= 12'd0;
                auto_send    <= 1'b1;
            end else begin
                interval_cnt <= interval_cnt + 12'd1;
            end
        end

        case (tx_state)
            TX_IDLE: begin
                skp_tx_valid <= 1'b0;
                if (skp_send_req || auto_send) begin
                    skp_data <= skp_tx_word;
                    tx_state <= TX_SEND;
                end
            end

            TX_SEND: begin
                skp_tx_valid <= 1'b1;
                tx_state     <= TX_DONE;
            end

            TX_DONE: begin
                skp_tx_valid <= 1'b0;
                tx_state     <= TX_IDLE;
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

// RX: detect SKP OS
// SKP OS starts with COM then SKP symbols
// Check first 4 bytes: BC 1C 1C 1C
wire is_skp_os = (rx_data[ 7: 0] == COM_SYMBOL) &&
                 (rx_data[15: 8] == SKP_SYMBOL) &&
                 (rx_data[23:16] == SKP_SYMBOL) &&
                 (rx_data[31:24] == SKP_SYMBOL);

// Error: COM is present but followed by wrong pattern (not FTS/SKP/TS)
// Simplified: COM byte present but second byte is not SKP, IDL, or known OS
wire is_bad_com = (rx_data[7:0] == COM_SYMBOL) &&
                  (rx_data[15:8] != SKP_SYMBOL) &&
                  (rx_data[15:8] != 8'h7C)  &&   // IDL
                  (rx_data[55:48] != 8'h4A) &&   // TS1
                  (rx_data[55:48] != 8'h45) &&   // TS2
                  (rx_data[7:0]  != 8'h3C);      // FTS

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        skp_detected <= 1'b0;
        skp_removed  <= 1'b0;
        skp_err      <= 1'b0;
    end else begin
        skp_detected <= 1'b0;
        skp_removed  <= 1'b0;
        skp_err      <= 1'b0;

        if (rx_valid) begin
            if (is_skp_os) begin
                skp_detected <= 1'b1;
                skp_removed  <= 1'b1;   // Indicate removal from data stream
            end
        end
    end
end

endmodule
