// ============================================================
// Module 50 : Compliance Pattern Generator (COMPL_GEN)
// PCIe Gen6 Physical Layer
// Generates compliance test patterns for PHY-level electrical
// validation. Required for PCIe compliance testing.
// ============================================================
module compl_gen (
    input  wire        clk,
    input  wire        rst_n,

    // Control
    input  wire        compliance_req,     // Request compliance mode
    input  wire [3:0]  compliance_pattern, // Pattern selector 0-7
    input  wire [2:0]  deemph_req,         // De-emphasis level request

    // Outputs
    output reg  [255:0] compl_data,        // Compliance pattern data
    output reg          compl_valid,       // Pattern data is valid
    output reg          compl_active       // Compliance mode active
);

// Compliance patterns per PCIe spec:
// Pattern 0: Compliance Pattern (1010... alternating)
// Pattern 1: Modified compliance (scrambled)
// Pattern 2: LFSR pattern
// Pattern 3: Fixed pattern (0xBC repeating)
// Pattern 4: De-emphasis verification pattern
// Pattern 5-7: Reserved / vendor-specific

// LFSR for scrambled pattern generation (simple 16-bit LFSR)
reg [15:0] lfsr;
wire        lfsr_fb = lfsr[15] ^ lfsr[14] ^ lfsr[12] ^ lfsr[3];

reg [255:0] pattern_data;
integer i;

always @(*) begin
    case (compliance_pattern)
        4'd0: begin
            // Alternating 1010 pattern
            pattern_data = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
        end
        4'd1: begin
            // 0101 pattern
            pattern_data = 256'h5555555555555555555555555555555555555555555555555555555555555555;
        end
        4'd2: begin
            // LFSR-based (use lfsr value replicated)
            pattern_data = {16{lfsr}};
        end
        4'd3: begin
            // COM repeating
            pattern_data = {32{8'hBC}};
        end
        4'd4: begin
            // De-emphasis: 0xFF bytes
            pattern_data = {32{8'hFF}};
        end
        4'd5: begin
            // Checkerboard 0xCC/0x33
            pattern_data = {16{16'hCC33}};
        end
        4'd6: begin
            // SKP pattern
            pattern_data = {32{8'h1C}};
        end
        4'd7: begin
            // All zeros
            pattern_data = 256'd0;
        end
        default: pattern_data = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
    endcase
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        compl_data   <= 256'd0;
        compl_valid  <= 1'b0;
        compl_active <= 1'b0;
        lfsr         <= 16'hFFFF;
    end else begin
        // Advance LFSR every cycle
        lfsr <= {lfsr[14:0], lfsr_fb};

        if (compliance_req) begin
            compl_active <= 1'b1;
            compl_valid  <= 1'b1;
            compl_data   <= pattern_data;
        end else begin
            compl_active <= 1'b0;
            compl_valid  <= 1'b0;
            compl_data   <= 256'd0;
        end
    end
end

endmodule
