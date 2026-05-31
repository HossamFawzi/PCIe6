
`timescale 1ns / 1ps

module pcie6_phy_tx (

    input  wire         clk,
    input  wire         rst_n,

    input  wire [255:0] tx_data,
    input  wire         tx_valid,
    input  wire         tx_sop,
    input  wire         tx_eop,

    input  wire         tx_elec_idle_req,
    input  wire         tx_compliance_req,

    output reg  [255:0] phy_txd,
    output reg          phy_tx_valid,
    output reg          phy_tx_elec_idle,
    output reg          phy_tx_compliance
);

    reg [255:0] pipe1_data;
    reg         pipe1_valid;
    reg         pipe1_sop;
    reg         pipe1_eop;
    reg         pipe1_elec_idle;
    reg         pipe1_compliance;

    localparam ST_IDLE     = 2'b00;
    localparam ST_SOP      = 2'b01;
    localparam ST_PAYLOAD  = 2'b10;
    localparam ST_EOP      = 2'b11;

    reg [1:0] flit_state;
    reg [1:0] flit_state_nxt;

    wire elec_idle_active;
    wire compliance_active;

    assign elec_idle_active  = tx_elec_idle_req;
    assign compliance_active = tx_compliance_req & ~tx_elec_idle_req;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe1_data       <= 256'b0;
            pipe1_valid      <= 1'b0;
            pipe1_sop        <= 1'b0;
            pipe1_eop        <= 1'b0;
            pipe1_elec_idle  <= 1'b0;
            pipe1_compliance <= 1'b0;
        end else begin
            pipe1_data       <= tx_data;
            pipe1_valid      <= tx_valid & ~elec_idle_active & ~compliance_active;
            pipe1_sop        <= tx_sop;
            pipe1_eop        <= tx_eop;
            pipe1_elec_idle  <= elec_idle_active;
            pipe1_compliance <= compliance_active;
        end
    end

    always @(*) begin
        flit_state_nxt = flit_state;
        case (flit_state)
            ST_IDLE: begin
                if (pipe1_valid && pipe1_sop && !pipe1_eop)
                    flit_state_nxt = ST_PAYLOAD;
                else if (pipe1_valid && pipe1_sop && pipe1_eop)
                    flit_state_nxt = ST_IDLE;
            end
            ST_PAYLOAD: begin
                if (pipe1_valid && pipe1_eop)
                    flit_state_nxt = ST_IDLE;
            end
            ST_SOP: begin
                flit_state_nxt = ST_PAYLOAD;
            end
            ST_EOP: begin
                flit_state_nxt = ST_IDLE;
            end
            default: flit_state_nxt = ST_IDLE;
        endcase

        if (pipe1_elec_idle || pipe1_compliance)
            flit_state_nxt = ST_IDLE;
    end

    always @(posedge clk) begin
        if (!rst_n)
            flit_state <= ST_IDLE;
        else
            flit_state <= flit_state_nxt;
    end

    localparam [255:0] COMPLIANCE_PATTERN = {
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5,
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5,
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5,
        32'hBC_D5_BC_D5, 32'hBC_D5_BC_D5
    };

    wire flit_data_valid;
    assign flit_data_valid = pipe1_valid &&
                             (flit_state == ST_PAYLOAD ||
                              (flit_state == ST_IDLE && pipe1_sop));

    always @(posedge clk) begin
        if (!rst_n) begin
            phy_txd           <= 256'b0;
            phy_tx_valid      <= 1'b0;
            phy_tx_elec_idle  <= 1'b1;
            phy_tx_compliance <= 1'b0;
        end else begin

            if (pipe1_elec_idle) begin
                phy_txd           <= 256'b0;
                phy_tx_valid      <= 1'b0;
                phy_tx_elec_idle  <= 1'b1;
                phy_tx_compliance <= 1'b0;

            end else if (pipe1_compliance) begin
                phy_txd           <= COMPLIANCE_PATTERN;
                phy_tx_valid      <= 1'b1;
                phy_tx_elec_idle  <= 1'b0;
                phy_tx_compliance <= 1'b1;

            end else if (flit_data_valid) begin
                phy_txd           <= pipe1_data;
                phy_tx_valid      <= 1'b1;
                phy_tx_elec_idle  <= 1'b0;
                phy_tx_compliance <= 1'b0;

            end else begin
                phy_txd           <= 256'b0;
                phy_tx_valid      <= 1'b0;
                phy_tx_elec_idle  <= 1'b0;
                phy_tx_compliance <= 1'b0;
            end
        end
    end

endmodule
