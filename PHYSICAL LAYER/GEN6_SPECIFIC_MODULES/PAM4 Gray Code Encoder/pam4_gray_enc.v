// =============================================================================
// Module  : pam4_gray_enc
// Block   : PAM4 Gray Code Encoder  (tag: PAM4_ENC)
// Spec    : PCIe Gen6 PHY ? Gen6 Group
//
// Purpose : Maps each pair of binary bits from the 256-bit input data word
//           to a PAM4 Gray-coded 2-bit symbol before it is handed to the DAC.
//           Gray coding ensures that adjacent PAM4 levels differ by only one
//           bit, minimising the bit-error rate impact of a single symbol error.
//
// PAM4 Gray Code Mapping  (standard reflected binary)
//   Binary 00 ? Gray 00 (level 0)
//   Binary 01 ? Gray 01 (level 1)
//   Binary 10 ? Gray 11 (level 3)
//   Binary 11 ? Gray 10 (level 2)
//
// Data Layout
//   data_in[255:0]  ? 256-bit wide input: 128 two-bit binary symbols
//   pam4_symbols[127:0] ? 128-bit output: 128 two-bit Gray-coded symbols
//   Each symbol occupies two adjacent bits: symbol[k] = data_in[2k+1 : 2k]
//
// Interfaces (from HTML reference):
//   Inputs  : data_in[255:0], data_valid, pam4_en, clk, rst_n
//   Outputs : pam4_symbols[127:0], pam4_valid
// =============================================================================

module pam4_gray_enc (
    // ?? Clock & Reset ????????????????????????????????????????????????????????
    input  wire          clk,               // PIPE / core clock
    input  wire          rst_n,             // Active-low synchronous reset

    // ?? Inputs ???????????????????????????????????????????????????????????????
    input  wire [255:0]  data_in,           // 256-bit binary input data
    input  wire          data_valid,        // Input data valid strobe
    input  wire          pam4_en,           // Enable PAM4 encoding (Gen6 mode)

    // ?? Outputs ??????????????????????????????????????????????????????????????
    output reg  [127:0]  pam4_symbols,      // 128 two-bit Gray-coded PAM4 symbols
    output reg           pam4_valid         // Output valid (registered 1-cycle latency)
);

    // =========================================================================
    // Gray Code Encoder Function
    // Standard 2-bit binary-to-Gray:
    //   gray[1] = bin[1]
    //   gray[0] = bin[1] ^ bin[0]
    // =========================================================================
    function [1:0] bin2gray;
        input [1:0] bin;
        begin
            bin2gray[1] = bin[1];
            bin2gray[0] = bin[1] ^ bin[0];
        end
    endfunction

    // =========================================================================
    // Encode all 128 two-bit symbols in a single registered stage
    // When pam4_en = 0 the data passes through unencoded (bypass mode).
    // =========================================================================
    integer k;

    always @(posedge clk) begin
        if (!rst_n) begin
            pam4_symbols <= 128'b0;
            pam4_valid   <= 1'b0;
        end else begin
            // Register valid one cycle after data arrives
            pam4_valid <= data_valid;

            if (data_valid) begin
                if (pam4_en) begin
                    // Gray-encode every 2-bit symbol
                    for (k = 0; k < 128; k = k + 1) begin
                        pam4_symbols[2*k +: 2] <=
                            bin2gray(data_in[2*k +: 2]);
                    end
                end else begin
                    // Bypass: pass binary data straight through
                    // (used during Gen1-5 operation or calibration)
                    pam4_symbols <= data_in[127:0];
                end
            end else begin
                // Hold last value when not valid (no flush to zero)
                pam4_symbols <= pam4_symbols;
            end
        end
    end

endmodule
