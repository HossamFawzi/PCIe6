// =============================================================================
// tlp_assembler.v
// PCIe Gen6 ? TLP Assembler / Packet Builder
// =============================================================================

`timescale 1ns/1ps

module tlp_assembler (
    input  wire          clk,
    input  wire          rst_n,

    // ?? From TX Arbiter ???????????????????????????????????????????????????????
    input  wire [575:0]  arb_tlp_in,
    input  wire          arb_tlp_valid,

    // ?? From TLP Prefix Handler / ECRC / Credit Mgr ???????????????????????????
    input  wire [127:0]  prefix_in,
    input  wire          prefix_valid,
    input  wire [31:0]   ecrc_in,
    input  wire          credit_ok,
    input  wire [2:0]    max_payload,

    // ?? Outputs to Downstream (DLL Interface) ?????????????????????????????????
    output reg  [1023:0] tlp_out,
    output reg           tlp_valid,
    output reg           tlp_sop,
    output reg           tlp_eop,
    output reg  [127:0]  tlp_hdr,
    output reg  [127:0]  tlp_be
);

    // =========================================================================
    // FIELD EXTRACTION
    // =========================================================================
    wire [63:0]  raw_hdr_info  = arb_tlp_in[575:512];
    wire [511:0] raw_data      = arb_tlp_in[511:0];

    wire [9:0]   tlp_length_dw = raw_hdr_info[9:0];
    wire [3:0]   tlp_first_be  = raw_hdr_info[13:10];
    wire [3:0]   tlp_last_be   = raw_hdr_info[17:14];
    wire         tlp_has_data  = raw_hdr_info[18];
    wire         tlp_4dw_hdr   = raw_hdr_info[19];

    // =========================================================================
    // HEADER CONSTRUCTION (Combinational)
    // =========================================================================
    reg [127:0] hdr_dws;
    always @(*) begin
        hdr_dws = 128'd0;
        
        // DW0: {Type/Fmt[31:20], has_data, 4dw, Length[9:0], 2'b00}
        hdr_dws[31:0]   = {raw_hdr_info[31:20], tlp_has_data, tlp_4dw_hdr, tlp_length_dw, 2'b00};
        
        // DW1: {ReqID[47:32], Tag[55:48], Last_BE, First_BE}
        hdr_dws[63:32]  = {raw_hdr_info[47:32], raw_hdr_info[55:48], tlp_last_be, tlp_first_be};
        
        // DW2: Address[63:32]
        hdr_dws[95:64]  = raw_hdr_info[63:32];
        
        // DW3: Lower Address or Placeholder
        hdr_dws[127:96] = tlp_4dw_hdr ? 32'hDEAD_C0DE : 32'h0;
    end

    // =========================================================================
    // BYTE ENABLE MASK (Combinational)
    // =========================================================================
    reg [127:0] be_mask;
    always @(*) begin
        be_mask = {128{1'b1}}; // Default: all bytes valid
        be_mask[127:124] = tlp_last_be;
    end

    // =========================================================================
    // REGISTERED OUTPUT STAGE
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_out   <= 1024'd0;
            tlp_valid <= 1'b0;
            tlp_sop   <= 1'b0;
            tlp_eop   <= 1'b0;
            tlp_hdr   <= 128'd0;
            tlp_be    <= 128'd0;
        end else begin
            // Default inactive state
            tlp_valid <= 1'b0;
            tlp_sop   <= 1'b0;
            tlp_eop   <= 1'b0;

            // Only forward if Arbiter has data AND credits are available
            if (arb_tlp_valid && credit_ok) begin
                tlp_out[1023:896] <= prefix_valid ? prefix_in : 128'd0;
                tlp_out[895:768]  <= hdr_dws;
                tlp_out[767:256]  <= tlp_has_data ? raw_data : 512'd0;
                tlp_out[255:224]  <= ecrc_in;
                tlp_out[223:0]    <= 224'd0; // Padding
                
                tlp_hdr           <= hdr_dws;
                tlp_be            <= be_mask;
                
                tlp_valid         <= 1'b1;
                tlp_sop           <= 1'b1; // Gen6 FLIT packets are typically single-beat here
                tlp_eop           <= 1'b1;
            end
        end
    end

endmodule