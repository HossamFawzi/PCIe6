
`timescale 1ns/1ps

module phy_interface_rx (

    input  wire          clk,
    input  wire          rst_n,

    input  wire [255:0]  phy_rxd,
    input  wire          phy_rx_valid,
    input  wire [2:0]    phy_rx_status,

    input  wire [15:0]   fec_syndrome,
    input  wire          fec_corrected,

    input  wire          ltssm_dl_up,

    output reg  [255:0]  rx_data,
    output reg           rx_valid,

    output reg  [2047:0] rx_flit,
    output reg           rx_flit_valid
);

    localparam BEATS_PER_FLIT   = 3'd7;
    localparam RX_STATUS_OK     = 3'b000;
    localparam RX_STATUS_TS     = 3'b010;

    reg [2047:0] flit_buf;

    reg [2:0]    beat_cnt;

    reg          flit_has_ue;
    reg          flit_has_ce;

    wire beat_ok;
    wire fec_ue;
    wire phy_status_ok;

    assign phy_status_ok = (phy_rx_status == RX_STATUS_OK);

    assign fec_ue = (fec_syndrome != 16'h0000) && !fec_corrected;

    assign beat_ok = ltssm_dl_up && phy_rx_valid && phy_status_ok;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            beat_cnt      <= 3'd0;
            flit_buf      <= {2048{1'b0}};
            flit_has_ue   <= 1'b0;
            flit_has_ce   <= 1'b0;
            rx_data       <= {256{1'b0}};
            rx_valid      <= 1'b0;
            rx_flit       <= {2048{1'b0}};
            rx_flit_valid <= 1'b0;
        end else begin

            rx_flit_valid <= 1'b0;
            rx_valid      <= 1'b0;

            if (!ltssm_dl_up) begin

                beat_cnt    <= 3'd0;
                flit_has_ue <= 1'b0;
                flit_has_ce <= 1'b0;
            end else if (beat_ok) begin

                rx_data  <= phy_rxd;
                rx_valid <= 1'b1;

                if (fec_ue)
                    flit_has_ue <= 1'b1;

                if (fec_corrected && (fec_syndrome != 16'h0000))
                    flit_has_ce <= 1'b1;

                case (beat_cnt)
                    3'd0: flit_buf[255:0]    <= phy_rxd;
                    3'd1: flit_buf[511:256]   <= phy_rxd;
                    3'd2: flit_buf[767:512]   <= phy_rxd;
                    3'd3: flit_buf[1023:768]  <= phy_rxd;
                    3'd4: flit_buf[1279:1024] <= phy_rxd;
                    3'd5: flit_buf[1535:1280] <= phy_rxd;
                    3'd6: flit_buf[1791:1536] <= phy_rxd;
                    3'd7: flit_buf[2047:1792] <= phy_rxd;
                    default: ;
                endcase

                if (beat_cnt == BEATS_PER_FLIT) begin

                    if (!flit_has_ue && !fec_ue) begin
                        rx_flit       <= {phy_rxd, flit_buf[1791:0]};
                        rx_flit_valid <= 1'b1;
                    end else begin

                        rx_flit_valid <= 1'b0;
                    end

                    beat_cnt    <= 3'd0;
                    flit_has_ue <= 1'b0;
                    flit_has_ce <= 1'b0;

                end else begin
                    beat_cnt <= beat_cnt + 3'd1;
                end

            end

        end
    end

`ifdef FORMAL

    always @(posedge clk) begin
        if (rst_n)
            assert (beat_cnt <= 3'd7);
    end

    reg flit_valid_prev;
    always @(posedge clk) flit_valid_prev <= rx_flit_valid;
    always @(posedge clk) begin
        if (rst_n && flit_valid_prev)
            assert (!rx_flit_valid || (beat_cnt == 3'd0));
    end
`endif

endmodule
