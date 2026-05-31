
`timescale 1ns/1ps

module dllp_arb (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [63:0] ack_dllp,
    input  wire        ack_dllp_valid,

    input  wire [63:0] fc_dllp,
    input  wire        fc_dllp_valid,

    input  wire [63:0] pm_dllp,
    input  wire        pm_dllp_valid,

    input  wire        nop_valid,

    input  wire        bw_dllp_valid,

    output reg  [63:0] dllp_out,
    output reg         dllp_out_valid,
    output reg  [3:0]  dllp_type
);

    localparam [63:0] NOP_DLLP = {8'h31, 56'h00_0000_0000_0000};

    localparam [63:0] BW_DLLP_TEMPLATE = {8'h03, 56'h00_0000_0000_0000};

    reg  [63:0] sel_data;
    reg  [3:0]  sel_type;
    reg         sel_valid;

    wire is_nak = (ack_dllp[63:56] == 8'h10);

    always @(*) begin
        if (ack_dllp_valid) begin
            sel_data  = ack_dllp;
            sel_type  = is_nak ? 4'h1 : 4'h0;
            sel_valid = 1'b1;
        end else if (fc_dllp_valid) begin
            sel_data  = fc_dllp;
            sel_type  = 4'h2;
            sel_valid = 1'b1;
        end else if (pm_dllp_valid) begin
            sel_data  = pm_dllp;
            sel_type  = 4'h3;
            sel_valid = 1'b1;
        end else if (bw_dllp_valid) begin
            sel_data  = BW_DLLP_TEMPLATE;
            sel_type  = 4'h4;
            sel_valid = 1'b1;
        end else if (nop_valid) begin
            sel_data  = NOP_DLLP;
            sel_type  = 4'h5;
            sel_valid = 1'b1;
        end else begin
            sel_data  = 64'h0;
            sel_type  = 4'hF;
            sel_valid = 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dllp_out       <= 64'h0;
            dllp_out_valid <= 1'b0;
            dllp_type      <= 4'hF;
        end else begin
            dllp_out       <= sel_data;
            dllp_out_valid <= sel_valid;
            dllp_type      <= sel_type;
        end
    end

endmodule
