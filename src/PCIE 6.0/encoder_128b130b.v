// =============================================================================
// Module: 128b/130b Encoder
// PCIe Gen3 / Gen4 / Gen5 Physical Layer
// Description: Prepends 2-bit synchronization header to 128-bit data block.
//              SH=01 → data block, SH=10 → ordered set block.
//              Scrambling is assumed handled upstream (LFSR).
//              Zero DC-balance overhead (vs 20% for 8b/10b).
// =============================================================================
module encoder_128b130b (
    input  wire         clk,
    input  wire         rst_n,

    // Input 128-bit data or ordered-set block
    input  wire [127:0] data_in,
    input  wire         is_ordered_set, // 0=data block, 1=ordered set block
    input  wire         data_valid,

    // Output 130-bit encoded block
    output reg  [129:0] data_out,      // [129:128]=sync header, [127:0]=data
    output reg          data_out_valid,
    output reg          enc_err        // Invalid sync header combination
);

// ---------------------------------------------------------------------------
// Sync Header encoding
// PCIe spec: SH[1:0]
//   2'b01 → Data block
//   2'b10 → Ordered set block
//   2'b00, 2'b11 → Invalid (should never occur on TX)
// ---------------------------------------------------------------------------
localparam SH_DATA        = 2'b01;
localparam SH_ORDERED_SET = 2'b10;

// Block counter (for monitoring purposes)
reg [31:0] block_cnt;

// ---------------------------------------------------------------------------
// Encoding logic (combinational + registered output)
// ---------------------------------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        data_out       <= 130'h0;
        data_out_valid <= 1'b0;
        enc_err        <= 1'b0;
        block_cnt      <= 32'h0;
    end else begin
        data_out_valid <= 1'b0;
        enc_err        <= 1'b0;

        if (data_valid) begin
            // Prepend sync header
            if (!is_ordered_set) begin
                // Data block: SH = 01
                data_out       <= {SH_DATA, data_in};
                data_out_valid <= 1'b1;
            end else begin
                // Ordered set block: SH = 10
                data_out       <= {SH_ORDERED_SET, data_in};
                data_out_valid <= 1'b1;
            end
            block_cnt <= block_cnt + 1'b1;
        end
    end
end

endmodule
