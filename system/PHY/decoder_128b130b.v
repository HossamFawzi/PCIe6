//============================================================
// PCIe 6.0 Physical Link Layer
// Module: decoder_128b130b
// 128b/130b Decoder
//
// Parameters:
//   PCIE_GEN : PCIe generation (3,4,5,6).
//              Gen3-5: invalid sync header asserts sync_hdr_err.
//              Gen6  : sync header error detection is bypassed
//                      (sync_hdr_err always driven 0).
//
// Sync header encoding (IEEE 802.3 / PCIe Base Spec):
//   2'b01 -> Data Block        (block_type = 0)
//   2'b10 -> Ordered Set Block (block_type = 1)
//   2'b00 / 2'b11 -> Invalid  (sync_hdr_err in Gen3-5)
//
// data_in[129:0] layout:
//   [129:128] = sync header bits (must equal sync_hdr port)
//   [127:0]   = 128-bit payload
//
// dec_err is asserted when:
//   - sync_hdr port disagrees with data_in[129:128], OR
//   - sync_hdr is invalid (00 or 11) AND PCIE_GEN < 6
//============================================================
module decoder_128b130b #(
    parameter integer PCIE_GEN = 6
) (
    input  wire          clk,
    input  wire          rst_n,
    input  wire [129:0]  data_in,
    input  wire [1:0]    sync_hdr,
    input  wire          dec_en,
    output reg  [127:0]  data_out,
    output reg           block_type,
    output reg           dec_err,
    output reg           sync_hdr_err
);

    // Internal combinational signals
    reg        sh_invalid;
    reg        sh_mismatch;
    reg        sh_err_gated;
    reg        block_type_next;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_out      <= 128'h0;
            block_type    <= 1'b0;
            dec_err       <= 1'b0;
            sync_hdr_err  <= 1'b0;
        end else if (dec_en) begin

            // -------------------------------------------------------
            // Sync header validity check
            // Valid: 2'b01 (data) or 2'b10 (ordered set)
            // Invalid: 2'b00 or 2'b11  ->  both bits equal
            // -------------------------------------------------------
            sh_invalid   = (sync_hdr[1] == sync_hdr[0]);

            // Cross-check: sync_hdr port must agree with embedded
            // header in data_in[129:128]
            sh_mismatch  = (sync_hdr != data_in[129:128]);

            // Gate sync header error per generation
            if (PCIE_GEN < 6)
                sh_err_gated = sh_invalid;
            else
                sh_err_gated = 1'b0;   // bypassed in Gen6

            // -------------------------------------------------------
            // Block type decode
            //   sync_hdr == 2'b01  ->  data block       (block_type=0)
            //   sync_hdr == 2'b10  ->  ordered set      (block_type=1)
            //   invalid            ->  hold 0 (don't care, dec_err set)
            // -------------------------------------------------------
            case (sync_hdr)
                2'b01:   block_type_next = 1'b0;
                2'b10:   block_type_next = 1'b1;
                default: block_type_next = 1'b0;
            endcase

            // -------------------------------------------------------
            // Drive outputs
            // -------------------------------------------------------
            data_out     <= data_in[127:0];
            block_type   <= block_type_next;
            sync_hdr_err <= sh_err_gated;
            dec_err      <= sh_err_gated | sh_mismatch;

        end else begin
            // Decoder disabled: clear error flags, hold data
            dec_err      <= 1'b0;
            sync_hdr_err <= 1'b0;
        end
    end

endmodule
