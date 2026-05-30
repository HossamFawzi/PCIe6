// ============================================================
// Module 44 : FTS Generator / Detector (FTS)
// PCIe Gen6 Physical Layer
// Fast Training Sequence for L0s exit.
// TX sends N FTS symbols. RX detects FTS for re-lock.
// ============================================================
module fts (
    input  wire        clk,
    input  wire        rst_n,

    // TX control
    input  wire        fts_send,           // Request to send FTS
    input  wire [7:0]  fts_count,          // Number of FTS symbols to send

    // RX input
    input  wire [255:0] rx_data,
    input  wire         rx_valid,

    // TX outputs
    output reg  [255:0] fts_data,          // FTS ordered set data
    output reg          fts_tx_valid,      // FTS data valid for TX

    // RX detection outputs
    output reg          fts_detected,      // FTS detected on RX
    output reg  [7:0]   fts_count_rx       // Count of consecutive FTS detected
);

// FTS symbol = K28.1 = 0x3C (per PCIe spec)
// Each 256-bit word carries 32 symbols; a single FTS OS is 4 symbols
// For simplicity: one 256-bit word = one FTS OS transmission
localparam [7:0] FTS_SYMBOL = 8'h3C;  // K28.1
localparam [7:0] COM_SYMBOL = 8'hBC;  // K28.5
localparam [7:0] FTS_ID     = 8'hF7;  // PAD (used as filler after FTS header)

// Build FTS pattern: 4 x FTS_SYMBOL followed by PAD to fill 256 bits
// FTS OS = FTS FTS FTS FTS (4 symbols) × fts_count times
// We pack one 32-symbol FTS frame per tx word (8 FTS ordered sets per word)
wire [255:0] fts_word;
genvar gi;
generate
    for (gi = 0; gi < 32; gi = gi + 1) begin : FTS_FILL
        assign fts_word[gi*8 +: 8] = FTS_SYMBOL;
    end
endgenerate

// TX FSM
reg [1:0] tx_state;
localparam TX_IDLE  = 2'd0;
localparam TX_SEND  = 2'd1;
localparam TX_DONE  = 2'd2;

reg [7:0] tx_cnt;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fts_data     <= 256'd0;
        fts_tx_valid <= 1'b0;
        tx_state     <= TX_IDLE;
        tx_cnt       <= 8'd0;
    end else begin
        case (tx_state)
            TX_IDLE: begin
                fts_tx_valid <= 1'b0;
                if (fts_send && fts_count > 8'd0) begin
                    tx_cnt   <= fts_count - 8'd1;
                    fts_data <= fts_word;
                    tx_state <= TX_SEND;
                end
            end

            TX_SEND: begin
                fts_tx_valid <= 1'b1;
                fts_data     <= fts_word;
                if (tx_cnt == 8'd0) begin
                    tx_state <= TX_DONE;
                end else begin
                    tx_cnt <= tx_cnt - 8'd1;
                end
            end

            TX_DONE: begin
                fts_tx_valid <= 1'b0;
                tx_state     <= TX_IDLE;
            end

            default: tx_state <= TX_IDLE;
        endcase
    end
end

// RX detection: detect FTS_SYMBOL in all byte positions
wire [31:0] sym_is_fts;
genvar ri;
generate
    for (ri = 0; ri < 32; ri = ri + 1) begin : RX_CHECK
        assign sym_is_fts[ri] = (rx_data[ri*8 +: 8] == FTS_SYMBOL);
    end
endgenerate

wire all_fts = (&sym_is_fts);  // All 32 symbols are FTS

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        fts_detected  <= 1'b0;
        fts_count_rx  <= 8'd0;
    end else begin
        fts_detected <= 1'b0;
        if (rx_valid) begin
            if (all_fts) begin
                fts_detected <= 1'b1;
                if (fts_count_rx < 8'hFF)
                    fts_count_rx <= fts_count_rx + 8'd1;
            end else begin
                fts_count_rx <= 8'd0;
            end
        end
    end
end

endmodule
