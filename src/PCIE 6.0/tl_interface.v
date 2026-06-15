// =============================================================================
// Module: tl_interface
// Description: TL Interface (From TL) — Hard TL/DLL Boundary
//              Accepts TLPs and FLITs from the Transaction Layer.
//              Forwards FC update values to the DLLP Generator.
//              PCIe Gen6 compliant: supports legacy TLP mode and 256B FLIT mode.
// =============================================================================

module tl_interface (
    input  wire        clk,
    input  wire        rst_n,

    // ── Inputs from TL ──────────────────────────────────────────────────────
    input  wire [1023:0] tlp_in,          // TLP data bus (legacy mode)
    input  wire          tlp_valid_in,    // TLP valid strobe

    input  wire [2047:0] flit_in,         // 256-byte FLIT data (Gen6 mode)
    input  wire          flit_valid_in,   // FLIT valid strobe

    input  wire          flit_mode_en,    // 1 = Gen6 FLIT mode active

    input  wire [7:0]    fc_update_ph,    // FC Posted-Header credit update
    input  wire          fc_update_valid, // FC update strobe

    // ── Outputs to DLL internals ─────────────────────────────────────────────
    output reg  [1023:0] dll_tlp,         // TLP forwarded into DLL TX path
    output reg           dll_tlp_valid,   // DLL TLP valid

    output reg  [2047:0] dll_flit,        // FLIT forwarded into DLL TX path
    output reg           dll_flit_valid,  // DLL FLIT valid

    output reg           tl_ready,        // Back-pressure: TL may send next unit

    // ── FC update to DLLP Generator ──────────────────────────────────────────
    output reg  [71:0]   fc_to_dllp,      // {PD[23:0], PH[7:0], NPD[23:0], NPH[7:0], CPLH[7:0]} packed
    output reg           fc_dllp_send     // Pulse: DLLP Generator should send UpdateFC
);

    // ── Internal state ───────────────────────────────────────────────────────
    // Simple single-entry pipe-register to break combinational paths.

    reg [1023:0] tlp_pipe;
    reg          tlp_vld_pipe;
    reg [2047:0] flit_pipe;
    reg          flit_vld_pipe;

    // FC accumulator – holds the latest credit advertisement per type.
    // In a real design this would be a full credit-type FIFO; here we
    // latch ph credits and forward them whenever fc_update_valid is seen.
    reg [7:0]    fc_ph_lat;

    // ── Pipeline stage ───────────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tlp_pipe      <= {1024{1'b0}};
            tlp_vld_pipe  <= 1'b0;
            flit_pipe     <= {2048{1'b0}};
            flit_vld_pipe <= 1'b0;
        end else begin
            // Gate on mode
            tlp_pipe      <= tlp_in;
            tlp_vld_pipe  <= tlp_valid_in & ~flit_mode_en; // suppress in FLIT mode
            flit_pipe     <= flit_in;
            flit_vld_pipe <= flit_valid_in &  flit_mode_en; // active only in FLIT mode
        end
    end

    // ── Output registration ──────────────────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dll_tlp       <= {1024{1'b0}};
            dll_tlp_valid <= 1'b0;
            dll_flit      <= {2048{1'b0}};
            dll_flit_valid<= 1'b0;
            tl_ready      <= 1'b1;    // Initially ready after reset
            fc_to_dllp    <= 72'h0;
            fc_dllp_send  <= 1'b0;
            fc_ph_lat     <= 8'h0;
        end else begin
            // TLP path
            dll_tlp       <= tlp_pipe;
            dll_tlp_valid <= tlp_vld_pipe;

            // FLIT path
            dll_flit       <= flit_pipe;
            dll_flit_valid <= flit_vld_pipe;

            // Back-pressure: always ready in this pipelined model.
            // A real implementation would gate on downstream FIFO full.
            tl_ready <= 1'b1;

            // FC forwarding
            if (fc_update_valid) begin
                fc_ph_lat    <= fc_update_ph;
                // Pack a simplified UpdateFC DLLP payload:
                //  [71:64] = PH credits, rest set to 0 (extend as needed)
                fc_to_dllp   <= {64'h0, fc_update_ph};
                fc_dllp_send <= 1'b1;
            end else begin
                fc_dllp_send <= 1'b0;
            end
        end
    end

endmodule
