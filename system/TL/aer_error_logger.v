// =============================================================
//  MODULE : aer_error_logger
//  TAG    : AER
//  LAYER  : Transaction Layer — Support Group (Gen6 NEW)
//  DESC   : Advanced Error Reporting aggregator.
//           Collects errors from all TL + DLL sources,
//           classifies them (COR/NONFATAL/FATAL),
//           generates ERR_* Message TLPs upstream, and
//           raises aer_int to host software.
//  SPEC   : PCIe 6.0 Base Spec §6.2 (AER Capability)
// =============================================================
module aer_error_logger (
    input  wire        clk,
    input  wire        rst_n,

    // ── Error inputs from TL blocks ──────────────────────────
    input  wire [3:0]  err_from_tmo,   // Timeout/Error Manager
    input  wire [3:0]  err_from_cpl,   // Completion Handler
    input  wire        err_from_mal,   // Malformed TLP Checker
    input  wire        err_from_psnd,  // Poisoned TLP Handler
    input  wire        err_from_msg,   // Message Handler
    input  wire        err_from_ur,    // FIX-AER: UR completion status from completion handler
    input  wire        err_from_flit,  // FLIT Mode Controller

    // ── Error inputs from DLL ────────────────────────────────
    input  wire [3:0]  dll_err,        // DLL error codes
    input  wire        dll_err_valid,  // FIX-AER: gate — only log when DLL err is a new pulse

    // ── Error severity override ──────────────────────────────
    input  wire [1:0]  err_severity,   // 00=COR 01=NONFATAL 10=FATAL

    // ── AER Status outputs ───────────────────────────────────
    output reg  [31:0] aer_status,     // AER Uncorrectable Status reg
    output reg  [31:0] aer_mask,       // AER Uncorrectable Mask (RW)
    output reg         aer_int,        // Interrupt to host

    // ── Error Message TLP ────────────────────────────────────
    output reg  [255:0] err_msg_tlp,   // ERR_COR / NONFATAL / FATAL TLP
    output reg          err_msg_valid  // Pulse
);

    // ── AER Uncorrectable Status bit positions ────────────────
    localparam BIT_DLPE   = 4;  // Data Link Protocol Error
    localparam BIT_PTLP   = 12; // Poisoned TLP Received
    localparam BIT_FCP    = 13; // Flow Control Protocol Error
    localparam BIT_CT     = 14; // Completion Timeout
    localparam BIT_CA     = 15; // Completer Abort
    localparam BIT_UC     = 16; // Unexpected Completion
    localparam BIT_RO     = 17; // Receiver Overflow
    localparam BIT_MTLP   = 18; // Malformed TLP
    localparam BIT_ECRC   = 19; // ECRC Error
    localparam BIT_UR     = 20; // Unsupported Request
    localparam BIT_FLIT   = 24; // FLIT CRC Error (Gen6 new)

    // ── Message TLP type codes ─────────────────────────────────
    localparam [7:0] MSG_ERR_COR      = 8'h30;
    localparam [7:0] MSG_ERR_NONFATAL = 8'h31;
    localparam [7:0] MSG_ERR_FATAL    = 8'h33;

    // ── Internal signals ─────────────────────────────────────
    // new_status: blocking-assigned each cycle so message-gen
    // sees the UPDATED value in the same always evaluation.
    reg [31:0] new_status;
    reg        any_error;
    reg [7:0]  msg_type;

    // ── Default mask (all zeros = nothing masked) ────────────
    // FIX-SYNTH-1: Removed non-synthesizable 'initial' block.
    // aer_mask is now reset synchronously in the always block below.

    // ── AER display de-bounce: only print when status changes ─
    reg [31:0] aer_status_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aer_status    <= 32'h0;
            aer_mask      <= 32'h0;
            aer_int       <= 1'b0;
            err_msg_tlp   <= 256'h0;
            err_msg_valid <= 1'b0;
            aer_status_prev <= 32'h0;
        end
        else begin
            // ── Default: de-assert pulses ─────────────────────
            err_msg_valid = 1'b0;   // blocking — visible below
            aer_int       = 1'b0;
            any_error     = 1'b0;

            // Start with current sticky status (blocking copy)
            new_status = aer_status;

            // ── Map incoming errors → new_status bits ─────────
            if (err_from_tmo[0])  begin new_status[BIT_CT]   = 1'b1; any_error = 1'b1; end
            if (err_from_cpl[0])  begin new_status[BIT_UC]   = 1'b1; any_error = 1'b1; end
            if (err_from_cpl[1])  begin new_status[BIT_CA]   = 1'b1; any_error = 1'b1; end
            if (err_from_mal)     begin new_status[BIT_MTLP] = 1'b1; any_error = 1'b1; end
            if (err_from_psnd)    begin new_status[BIT_PTLP] = 1'b1; any_error = 1'b1; end
            if (err_from_msg)     begin new_status[BIT_UR]   = 1'b1; any_error = 1'b1; end
            if (err_from_ur)      begin new_status[BIT_UR]   = 1'b1; any_error = 1'b1; end  // FIX-AER: UR cpl
            if (err_from_flit)    begin new_status[BIT_FLIT] = 1'b1; any_error = 1'b1; end
            // FIX-AER: gated by dll_err_valid — dll_err bits are level signals
            // (replay_rollover stays high in LINK_DOWN state), so without this gate
            // BIT_DLPE fires every cycle causing the AER $display storm.
            if (dll_err_valid && dll_err[0]) begin new_status[BIT_DLPE] = 1'b1; any_error = 1'b1; end
            if (dll_err_valid && dll_err[1]) begin new_status[BIT_FCP]  = 1'b1; any_error = 1'b1; end

            // ── Latch updated sticky status ───────────────────
            aer_status <= new_status;

            // ── Classify and generate message TLP ────────────
            // Uses new_status (blocking) so it sees THIS cycle's errors
            if (any_error && |(new_status & ~aer_mask)) begin
                case (err_severity)
                    2'b00:   msg_type = MSG_ERR_COR;
                    2'b01:   msg_type = MSG_ERR_NONFATAL;
                    default: msg_type = MSG_ERR_FATAL;
                endcase

                err_msg_tlp[255:248] = 8'h34;
                err_msg_tlp[247:240] = 8'h00;
                err_msg_tlp[239:232] = 8'h00;
                err_msg_tlp[231:224] = msg_type;   // Message Code
                err_msg_tlp[223:208] = 16'h0001;   // Requester ID
                err_msg_tlp[207:200] = 8'h00;
                err_msg_tlp[199:192] = 8'h00;
                err_msg_tlp[191:160] = new_status;
                err_msg_tlp[159:0]   = 160'h0;
                err_msg_valid = 1'b1;
                aer_int       = 1'b1;
            end

            // ── Commit all blocking → register outputs ────────
            aer_int       <= aer_int;
            err_msg_valid <= err_msg_valid;
            err_msg_tlp   <= err_msg_tlp;

            // FIX-AER-DISPLAY: Only print when aer_status value changes,
            // not every clock cycle (eliminates the display storm).
            aer_status_prev <= aer_status;
            `ifdef SIMULATION
            if (new_status != aer_status_prev)
                $display("  [AER] status=%08h @%0t ns", new_status, $time/1000);
            `endif
        end
    end

endmodule
