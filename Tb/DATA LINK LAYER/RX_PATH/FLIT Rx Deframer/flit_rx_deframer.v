
module flit_rx_deframer (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [2047:0] rx_flit,
    input  wire          rx_flit_valid,
    input  wire [15:0]   fec_syndrome,
    input  wire          fec_corrected,

    output reg  [1023:0] flit_tlp,
    output reg           flit_tlp_valid,
    output reg  [63:0]   flit_dllp,
    output reg           flit_dllp_valid,
    output reg  [11:0]   flit_seq,
    output reg           flit_crc_err,
    output reg           flit_null,
    output reg           flit_uncorr_err
);

    localparam FLIT_TYPE_NULL  = 4'h0;
    localparam FLIT_TYPE_TLP   = 4'h1;
    localparam FLIT_TYPE_DLLP  = 4'h2;
    localparam FLIT_TYPE_MIXED = 4'h3;

    wire [23:0] rx_crc      = rx_flit[2047:2024];
    wire [11:0] rx_seq      = rx_flit[2023:2012];
    wire [3:0]  rx_type     = rx_flit[2011:2008];
    wire [63:0] rx_dllp_raw = rx_flit[2007:1944];
    wire [1023:0] rx_tlp_raw= rx_flit[1023:0];

    wire [23:0] computed_crc;

    flit_crc24 u_crc24 (
        .data  (rx_flit[2023:0]),
        .crc   (computed_crc)
    );

    wire uncorr = (fec_syndrome != 16'h0) && !fec_corrected;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_tlp        <= 1024'b0;
            flit_tlp_valid  <= 1'b0;
            flit_dllp       <= 64'b0;
            flit_dllp_valid <= 1'b0;
            flit_seq        <= 12'b0;
            flit_crc_err    <= 1'b0;
            flit_null       <= 1'b0;
            flit_uncorr_err <= 1'b0;
        end else begin

            flit_tlp_valid  <= 1'b0;
            flit_dllp_valid <= 1'b0;
            flit_crc_err    <= 1'b0;
            flit_null       <= 1'b0;
            flit_uncorr_err <= 1'b0;

            if (rx_flit_valid) begin
                flit_seq        <= rx_seq;
                flit_uncorr_err <= uncorr;

                if (computed_crc != rx_crc) begin
                    flit_crc_err <= 1'b1;
                end else if (!uncorr) begin

                    case (rx_type)
                        FLIT_TYPE_NULL: begin
                            flit_null <= 1'b1;
                        end

                        FLIT_TYPE_TLP: begin
                            flit_tlp       <= rx_tlp_raw;
                            flit_tlp_valid <= 1'b1;
                        end

                        FLIT_TYPE_DLLP: begin
                            flit_dllp       <= rx_dllp_raw;
                            flit_dllp_valid <= 1'b1;
                        end

                        FLIT_TYPE_MIXED: begin
                            flit_tlp        <= rx_tlp_raw;
                            flit_tlp_valid  <= 1'b1;
                            flit_dllp       <= rx_dllp_raw;
                            flit_dllp_valid <= 1'b1;
                        end

                        default: begin

                            flit_crc_err <= 1'b1;
                        end
                    endcase
                end
            end
        end
    end

endmodule

module flit_crc24 (
    input  wire [2023:0] data,
    output wire [23:0]   crc
);

    function [23:0] crc24_byte;
        input [23:0] crc_in;
        input [7:0]  byte_in;
        integer i;
        reg [23:0] c;
        begin
            c = crc_in ^ {byte_in, 16'h0};
            for (i = 0; i < 8; i = i + 1) begin
                if (c[23])
                    c = (c << 1) ^ 24'hC60001;
                else
                    c = c << 1;
            end
            crc24_byte = c;
        end
    endfunction

    integer j;
    reg [23:0] crc_reg;
    always @(*) begin
        crc_reg = 24'hFFFFFF;
        for (j = 0; j < 253; j = j + 1)
            crc_reg = crc24_byte(crc_reg, data[j*8 +: 8]);
    end

    assign crc = crc_reg;
endmodule
