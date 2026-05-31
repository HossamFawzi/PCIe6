
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

            sh_invalid   = (sync_hdr[1] == sync_hdr[0]);

            sh_mismatch  = (sync_hdr != data_in[129:128]);

            if (PCIE_GEN < 6)
                sh_err_gated = sh_invalid;
            else
                sh_err_gated = 1'b0;

            case (sync_hdr)
                2'b01:   block_type_next = 1'b0;
                2'b10:   block_type_next = 1'b1;
                default: block_type_next = 1'b0;
            endcase

            data_out     <= data_in[127:0];
            block_type   <= block_type_next;
            sync_hdr_err <= sh_err_gated;
            dec_err      <= sh_err_gated | sh_mismatch;

        end else begin

            dec_err      <= 1'b0;
            sync_hdr_err <= 1'b0;
        end
    end

endmodule
