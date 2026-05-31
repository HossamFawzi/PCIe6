
module rx_datapath_demux (
    input  wire          clk,
    input  wire          rst_n,

    input  wire [255:0]  rx_data,
    input  wire          rx_valid,

    input  wire [1023:0] flit_tlp,
    input  wire          flit_tlp_valid,
    input  wire [63:0]   flit_dllp,
    input  wire          flit_dllp_valid,

    input  wire          flit_mode_en,

    output reg  [1055:0] tlp_rx,
    output reg           tlp_rx_valid,
    output reg  [63:0]   dllp_raw,
    output reg           dllp_rx_valid,
    output reg           rx_parse_err
);

    localparam STP = 8'hFB;
    localparam SDP = 8'hFC;

    reg [1055:0] tlp_accum;
    reg [63:0]   dllp_accum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_rx        <= 1056'b0;
            tlp_rx_valid  <= 1'b0;
            dllp_raw      <= 64'b0;
            dllp_rx_valid <= 1'b0;
            rx_parse_err  <= 1'b0;
            tlp_accum     <= 1056'b0;
            dllp_accum    <= 64'b0;
        end else begin

            tlp_rx_valid  <= 1'b0;
            dllp_rx_valid <= 1'b0;
            rx_parse_err  <= 1'b0;

            if (flit_mode_en) begin

                if (flit_tlp_valid) begin
                    tlp_rx       <= {32'b0, flit_tlp};
                    tlp_rx_valid <= 1'b1;
                end
                if (flit_dllp_valid) begin
                    dllp_raw      <= flit_dllp;
                    dllp_rx_valid <= 1'b1;
                end
            end else begin

                if (rx_valid) begin
                    case (rx_data[7:0])
                        STP: begin

                            tlp_rx       <= {rx_data[255:8], 32'b0};
                            tlp_rx_valid <= 1'b1;
                        end
                        SDP: begin

                            dllp_raw      <= rx_data[71:8];
                            dllp_rx_valid <= 1'b1;
                        end

                        default: begin

                            if (rx_data[7:0] != 8'hBC && rx_data[7:0] != 8'hFC) begin
                                tlp_rx       <= rx_data[255:0];
                                tlp_rx_valid <= 1'b1;
                            end

                        end
                    endcase
                end
            end
        end
    end

endmodule
