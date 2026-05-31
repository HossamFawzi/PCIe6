
`timescale 1ns/1ps

module pipe_tx (

    input  wire         pipe_clk,
    input  wire         clk,
    input  wire         rst_n,

    input  wire [255:0] tx_data,
    input  wire         tx_valid,
    input  wire [31:0]  tx_datak,
    input  wire         tx_elec_idle,
    input  wire         tx_compliance,

    output reg  [255:0] pipe_txd,
    output reg  [31:0]  pipe_txdatak,
    output reg          pipe_tx_elec_idle,
    output reg          pipe_tx_compliance,
    output reg  [1:0]   pipe_power_down,
    output reg          pipe_tx_swing
);

localparam [1:0] PIPE_P0 = 2'b00;
localparam [1:0] PIPE_P1 = 2'b01;
localparam [1:0] PIPE_P2 = 2'b10;
localparam [1:0] PIPE_P3 = 2'b11;

reg         tx_elec_idle_s1, tx_elec_idle_s2;
reg         tx_compliance_s1, tx_compliance_s2;
reg         tx_valid_s1,      tx_valid_s2;

reg [255:0] txd_reg;
reg [31:0]  txdatak_reg;
reg         txd_valid_reg;

always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        tx_elec_idle_s1  <= 1'b0;
        tx_elec_idle_s2  <= 1'b0;
        tx_compliance_s1 <= 1'b0;
        tx_compliance_s2 <= 1'b0;
        tx_valid_s1      <= 1'b0;
        tx_valid_s2      <= 1'b0;
    end else begin
        tx_elec_idle_s1  <= tx_elec_idle;
        tx_elec_idle_s2  <= tx_elec_idle_s1;
        tx_compliance_s1 <= tx_compliance;
        tx_compliance_s2 <= tx_compliance_s1;
        tx_valid_s1      <= tx_valid;
        tx_valid_s2      <= tx_valid_s1;
    end
end

always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        txd_reg       <= 256'h0;
        txdatak_reg   <= 32'h0;
        txd_valid_reg <= 1'b0;
    end else begin
        if (tx_valid_s2) begin
            txd_reg       <= tx_data;
            txdatak_reg   <= tx_datak;
            txd_valid_reg <= 1'b1;
        end else begin
            txd_valid_reg <= 1'b0;
        end
    end
end

always @(posedge pipe_clk or negedge rst_n) begin
    if (!rst_n) begin
        pipe_txd            <= 256'h0;
        pipe_txdatak        <= 32'h0;
        pipe_tx_elec_idle   <= 1'b1;
        pipe_tx_compliance  <= 1'b0;
        pipe_power_down     <= PIPE_P2;
        pipe_tx_swing       <= 1'b1;
    end else begin

        if (tx_elec_idle_s2) begin

            pipe_txd     <= 256'h0;
            pipe_txdatak <= 32'hFFFF_FFFF;

        end else if (txd_valid_reg) begin
            pipe_txd     <= txd_reg;
            pipe_txdatak <= txdatak_reg;
        end

        pipe_tx_elec_idle  <= tx_elec_idle_s2;

        pipe_tx_compliance <= tx_compliance_s2;

        pipe_tx_swing <= tx_compliance_s2 ? 1'b0 : 1'b1;

        if (tx_compliance_s2) begin
            pipe_power_down <= PIPE_P0;
        end else if (tx_elec_idle_s2) begin
            pipe_power_down <= PIPE_P1;
        end else begin
            pipe_power_down <= PIPE_P0;
        end
    end
end

endmodule
