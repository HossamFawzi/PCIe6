// ============================================================
//  PCIe Gen6 - PAM4 Gray Code Decoder
//  Tag : PAM4_DEC  |  Group : gen6  |  Gen : Gen6
// ============================================================
//
//  INTERFACE (from HTML reference):
//    Inputs :
//      pam4_symbols_in[127:0]  - 128-bit packed PAM4 Gray-coded symbols
//                                (64 symbols x 2 bits each)
//      pam4_valid              - input valid strobe
//      pam4_en                 - enable PAM4 decode (bypass when 0)
//      clk                     - system clock (rising-edge)
//      rst_n                   - active-low synchronous reset
//
//    Outputs:
//      data_out[255:0]         - 256-bit decoded binary data
//                                (lower 128 b = decoded; upper 128 b = 0)
//      data_valid              - output valid strobe (1 cycle after input)
//      decode_err              - any invalid Gray code detected this cycle
//
//  ENCODING TABLE (2-bit Gray -> 2-bit binary):
//      Gray   Binary   PAM4 level
//      00  ->   00      ( 0 )
//      01  ->   01      (+1 )
//      11  ->   10      (+2 )
//      10  ->   11      (+3 )
// ============================================================

module pam4_gray_code_decoder (
    input  wire         clk,
    input  wire         rst_n,

    // Inputs
    input  wire [127:0] pam4_symbols_in,
    input  wire         pam4_valid,
    input  wire         pam4_en,

    // Outputs
    output reg  [255:0] data_out,
    output reg          data_valid,
    output reg          decode_err
);

    localparam NUM_SYMBOLS = 64;

    // Combinatorial decode results
    reg [127:0] decoded_128;
    reg         any_err;

    // Gray-to-binary decode - fully combinatorial
    // All variables declared at module scope for Verilog-2001 compatibility
    integer     dec_idx;
    reg [1:0]   gray_sym;
    reg [1:0]   bin_sym;
    reg         sym_err;

    always @(*) begin
        decoded_128 = 128'b0;
        any_err     = 1'b0;

        for (dec_idx = 0; dec_idx < NUM_SYMBOLS; dec_idx = dec_idx + 1) begin
            gray_sym = pam4_symbols_in[dec_idx*2 +: 2];

            case (gray_sym)
                2'b00: begin bin_sym = 2'b00; sym_err = 1'b0; end
                2'b01: begin bin_sym = 2'b01; sym_err = 1'b0; end
                2'b11: begin bin_sym = 2'b10; sym_err = 1'b0; end
                2'b10: begin bin_sym = 2'b11; sym_err = 1'b0; end
                // All 4 two-bit Gray codes are valid; default guards X/Z
                default: begin bin_sym = 2'b00; sym_err = 1'b1; end
            endcase

            decoded_128[dec_idx*2 +: 2] = bin_sym;
            any_err = any_err | sym_err;
        end
    end

    // Output pipeline register - 1 clock latency
    always @(posedge clk) begin
        if (!rst_n) begin
            data_out   <= 256'b0;
            data_valid <= 1'b0;
            decode_err <= 1'b0;
        end else begin
            data_valid <= pam4_valid;

            if (pam4_valid) begin
                if (pam4_en) begin
                    // PAM4 decode mode
                    data_out   <= {128'b0, decoded_128};
                    decode_err <= any_err;
                end else begin
                    // Bypass mode: raw symbols forwarded unchanged
                    data_out   <= {128'b0, pam4_symbols_in};
                    decode_err <= 1'b0;
                end
            end else begin
                data_out   <= 256'b0;
                decode_err <= 1'b0;
            end
        end
    end

endmodule
