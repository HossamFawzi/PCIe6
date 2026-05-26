// =============================================================================
// ecrc.v (or ecrc_gen_chk.v)
// PCIe Gen6 ? End-to-End CRC Generator & Checker 
// FIXED: tlp_rx port is now 1184 bits to prevent ECRC truncation
// =============================================================================

`timescale 1ns/1ps

module ecrc_gen_chk (
    input  wire           clk,
    input  wire           rst_n,

    // ?? Global Control ????????????????????????????????????????????????????????
    input  wire           ecrc_en,

    // ?? TX Path (Generator) ???????????????????????????????????????????????????
    input  wire [1151:0]  tlp_tx,         
    input  wire           tlp_tx_valid,
    output reg  [1183:0]  tlp_ecrc_tx,    
    output reg            tlp_ecrc_valid,

    // ?? RX Path (Checker) ?????????????????????????????????????????????????????
    input  wire [1183:0]  tlp_rx,         // <--- FIXED: Must be 1184 bits!
    input  wire           tlp_rx_valid,
    output reg            ecrc_rx_ok,     
    output reg            ecrc_rx_err     
);

    // =========================================================================
    // ISOLATED ECRC FUNCTIONS
    // Defined separately to prevent Verilog static variable collision
    // =========================================================================
    
    // TX ECRC Tree
    function [31:0] calc_ecrc_tx;
        input [1151:0] data;
        integer i;
        reg [31:0] temp_crc;
        begin
            temp_crc = 32'hFFFF_FFFF; 
            for (i = 0; i < 36; i = i + 1) begin
                temp_crc = temp_crc ^ data[(i*32) +: 32];
            end
            calc_ecrc_tx = ~temp_crc; 
        end
    endfunction

    // RX ECRC Tree
    function [31:0] calc_ecrc_rx;
        input [1151:0] data;
        integer j;
        reg [31:0] temp_crc_rx;
        begin
            temp_crc_rx = 32'hFFFF_FFFF; 
            for (j = 0; j < 36; j = j + 1) begin
                temp_crc_rx = temp_crc_rx ^ data[(j*32) +: 32];
            end
            calc_ecrc_rx = ~temp_crc_rx; 
        end
    endfunction

    // =========================================================================
    // TX Path: ECRC Generation
    // =========================================================================
    wire [31:0] generated_ecrc = calc_ecrc_tx(tlp_tx);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_ecrc_tx    <= 1184'd0;
            tlp_ecrc_valid <= 1'b0;
        end else begin
            tlp_ecrc_valid <= tlp_tx_valid;
            
            if (tlp_tx_valid) begin
                if (ecrc_en) begin
                    tlp_ecrc_tx <= {generated_ecrc, tlp_tx};
                end else begin
                    tlp_ecrc_tx <= {32'd0, tlp_tx};
                end
            end else begin
                tlp_ecrc_tx <= 1184'd0;
            end
        end
    end

    // =========================================================================
    // RX Path: ECRC Checking
    // =========================================================================
    wire [1151:0] rx_data_payload = tlp_rx[1151:0];      // Bottom 1152 bits
    wire [31:0]   rx_ecrc_in      = tlp_rx[1183:1152];   // Top 32 bits
    
    wire [31:0]   expected_ecrc   = calc_ecrc_rx(rx_data_payload);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ecrc_rx_ok  <= 1'b0;
            ecrc_rx_err <= 1'b0;
        end else begin
            ecrc_rx_ok  <= 1'b0;
            ecrc_rx_err <= 1'b0;

            if (tlp_rx_valid) begin
                if (ecrc_en) begin
                    if (rx_ecrc_in == expected_ecrc) begin
                        ecrc_rx_ok  <= 1'b1;
                    end else begin
                        ecrc_rx_err <= 1'b1; 
                    end
                end else begin
                    ecrc_rx_ok <= 1'b1;
                end
            end
        end
    end

endmodule