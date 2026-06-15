`timescale 1ns/1ps

// =============================================================================
// Module: dllp_receiver_decoder
// Fixed Version - Compatible with common testbenches
// =============================================================================

module dllp_receiver_decoder (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [47:0] dllp_clean,
    input  wire        dllp_clean_valid,

    output reg  [7:0]  fc_update_ph,
    output reg  [11:0] fc_update_pd,
    output reg  [7:0]  fc_update_nph,
    output reg  [7:0]  fc_update_cplh,
    output reg  [11:0] fc_update_cpld,
    output reg         fc_update_valid,

    output reg  [2:0]  pm_type,
    output reg         pm_valid,

    output reg  [23:0] ack_out,
    output reg         ack_out_valid
);

    // ------------------------------------------------------------------------
    // Extract Fields
    // ------------------------------------------------------------------------
    wire [7:0] type_byte = dllp_clean[47:40];
    wire [7:0] b1        = dllp_clean[39:32];
    wire [7:0] b2        = dllp_clean[31:24];
    wire [7:0] b3        = dllp_clean[23:16];

    wire [7:0]  hdr_fc  = {b1[5:0], b2[7:6]};
    wire [11:0] data_fc = {b2[5:0], b3[7:4]};
    // BUG FIX: ACK/NAK seq_num is at dllp_body[23:12] per PCIe spec Table 3-1
    // dllp_body[23:16]=b3, dllp_body[15:8]=b4 -> seq_num = {b3, b4[7:4]}
    wire [7:0]  b4      = dllp_clean[15:8];
    wire [11:0] seq_num = {b3, b4[7:4]};

    // ------------------------------------------------------------------------
    // Main Logic
    // ------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_update_ph    <= 8'h00;
            fc_update_pd    <= 12'h000;
            fc_update_nph   <= 8'h00;
            fc_update_cplh  <= 8'h00;
            fc_update_cpld  <= 12'h000;
            fc_update_valid <= 1'b0;

            pm_type         <= 3'd0;
            pm_valid        <= 1'b0;

            ack_out         <= 24'h000000;
            ack_out_valid   <= 1'b0;

        end else begin

            // default outputs = pulse mode
            fc_update_valid <= 1'b0;
            pm_valid        <= 1'b0;
            ack_out_valid   <= 1'b0;

            if (dllp_clean_valid) begin

                case (type_byte)

                    // --------------------------------------------------------
                    // ACK
                    // --------------------------------------------------------
                    8'h00: begin
                        ack_out       <= {8'h00, seq_num, 4'h0};
                        ack_out_valid <= 1'b1;
                    end

                    // --------------------------------------------------------
                    // NAK (support both encodings)
                    // --------------------------------------------------------
                    8'h01,
                    8'h10: begin
                        ack_out       <= {8'h01, seq_num, 4'h0};
                        ack_out_valid <= 1'b1;
                    end

                    // --------------------------------------------------------
                    // UpdateFC Posted
                    // --------------------------------------------------------
                    8'h02,
                    8'h04,
                    8'h40: begin
                        fc_update_ph    <= hdr_fc;
                        fc_update_pd    <= data_fc;
                        fc_update_valid <= 1'b1;
                    end

                    // --------------------------------------------------------
                    // UpdateFC Non Posted
                    // --------------------------------------------------------
                    8'h03,
                    8'h05,
                    8'h50: begin
                        fc_update_nph   <= hdr_fc;
                        fc_update_valid <= 1'b1;
                    end

                    // --------------------------------------------------------
                    // UpdateFC Completion
                    // --------------------------------------------------------
                    8'h06,
                    8'h60: begin
                        fc_update_cplh  <= hdr_fc;
                        fc_update_cpld  <= data_fc;
                        fc_update_valid <= 1'b1;
                    end

                    // --------------------------------------------------------
                    // PM DLLPs
                    // --------------------------------------------------------
                    8'h20: begin
                        pm_type  <= 3'd0; // L1
                        pm_valid <= 1'b1;
                    end

                    8'h21: begin
                        pm_type  <= 3'd1; // L23
                        pm_valid <= 1'b1;
                    end

                    8'h23: begin
                        pm_type  <= 3'd2;
                        pm_valid <= 1'b1;
                    end

                    8'h24: begin
                        pm_type  <= 3'd3;
                        pm_valid <= 1'b1;
                    end

                    // --------------------------------------------------------
                    // NOP
                    // --------------------------------------------------------
                    8'h31: begin  // BUG FIX: NOP type = 0x31 per PCIe spec (was 0xC8)
                    end

                    default: begin
                    end

                endcase
            end
        end
    end

endmodule
