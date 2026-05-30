// =============================================================
//  MODULE : aer_error_logger  [FIXED]
//  Fix    : VER-134 + LATCH (aer_mask) — removed mixed blocking/nonblocking
//           assignments to aer_int, err_msg_tlp, err_msg_valid.
//  Method : All outputs driven exclusively by nonblocking (<=).
//           Combinational intermediate signals (new_status,
//           any_error, msg_type, nxt_int, nxt_valid, nxt_tlp)
//           computed with blocking = inside the always block,
//           then committed to the registered outputs at the end
//           with a single nonblocking statement each.
// =============================================================
module aer_error_logger (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [3:0]  err_from_tmo,
    input  wire [3:0]  err_from_cpl,
    input  wire        err_from_mal,
    input  wire        err_from_psnd,
    input  wire        err_from_msg,
    input  wire        err_from_ur,
    input  wire        err_from_flit,

    input  wire [3:0]  dll_err,
    input  wire        dll_err_valid,

    input  wire [1:0]  err_severity,

    output reg  [31:0]  aer_status,
    output reg  [31:0]  aer_mask,
    output reg          aer_int,

    output reg  [255:0] err_msg_tlp,
    output reg          err_msg_valid
);

    localparam BIT_DLPE = 4;
    localparam BIT_PTLP = 12;
    localparam BIT_FCP  = 13;
    localparam BIT_CT   = 14;
    localparam BIT_CA   = 15;
    localparam BIT_UC   = 16;
    localparam BIT_RO   = 17;
    localparam BIT_MTLP = 18;
    localparam BIT_ECRC = 19;
    localparam BIT_UR   = 20;
    localparam BIT_FLIT = 24;

    localparam [7:0] MSG_ERR_COR      = 8'h30;
    localparam [7:0] MSG_ERR_NONFATAL = 8'h31;
    localparam [7:0] MSG_ERR_FATAL    = 8'h33;

    // Purely combinational temporaries — blocking only, never appear
    // as register targets, so no VER-134 conflict.
    reg [31:0]  new_status;
    reg         any_error;
    reg [7:0]   msg_type;
    // Registered-output next-values (committed once, nonblocking)
    reg         nxt_int;
    reg         nxt_valid;
    reg [255:0] nxt_tlp;

    reg [31:0] aer_status_prev;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aer_status      <= 32'h0;
            aer_mask        <= 32'h0;
            aer_int         <= 1'b0;
            err_msg_tlp     <= 256'h0;
            err_msg_valid   <= 1'b0;
            aer_status_prev <= 32'h0;
        end else begin
            aer_mask <= aer_mask;  // hold: prevents latch inference on aer_mask_reg
            // ── Combinational computation (blocking = only) ────────────────
            nxt_int   = 1'b0;
            nxt_valid = 1'b0;
            nxt_tlp   = err_msg_tlp;
            any_error = 1'b0;

            new_status = aer_status;   // start from current sticky value

            // Map inputs → status bits
            if (err_from_tmo[0])             begin new_status[BIT_CT]   = 1'b1; any_error = 1'b1; end
            if (err_from_cpl[0])             begin new_status[BIT_UC]   = 1'b1; any_error = 1'b1; end
            if (err_from_cpl[1])             begin new_status[BIT_CA]   = 1'b1; any_error = 1'b1; end
            if (err_from_mal)                begin new_status[BIT_MTLP] = 1'b1; any_error = 1'b1; end
            if (err_from_psnd)               begin new_status[BIT_PTLP] = 1'b1; any_error = 1'b1; end
            if (err_from_msg || err_from_ur) begin new_status[BIT_UR]   = 1'b1; any_error = 1'b1; end
            if (err_from_flit)               begin new_status[BIT_FLIT] = 1'b1; any_error = 1'b1; end
            if (dll_err_valid && dll_err[0]) begin new_status[BIT_DLPE] = 1'b1; any_error = 1'b1; end
            if (dll_err_valid && dll_err[1]) begin new_status[BIT_FCP]  = 1'b1; any_error = 1'b1; end

            // Generate message TLP if unmasked error present
            if (any_error && |(new_status & ~aer_mask)) begin
                case (err_severity)
                    2'b00:   msg_type = MSG_ERR_COR;
                    2'b01:   msg_type = MSG_ERR_NONFATAL;
                    default: msg_type = MSG_ERR_FATAL;
                endcase

                nxt_tlp[255:248] = 8'h34;
                nxt_tlp[247:240] = 8'h00;
                nxt_tlp[239:232] = 8'h00;
                nxt_tlp[231:224] = msg_type;
                nxt_tlp[223:208] = 16'h0001;
                nxt_tlp[207:200] = 8'h00;
                nxt_tlp[199:192] = 8'h00;
                nxt_tlp[191:160] = new_status;
                nxt_tlp[159:0]   = 160'h0;
                nxt_valid = 1'b1;
                nxt_int   = 1'b1;
            end

            // ── Commit to registers (nonblocking only) ─────────────────────
            aer_status      <= new_status;
            aer_int         <= nxt_int;
            err_msg_valid   <= nxt_valid;
            err_msg_tlp     <= nxt_tlp;
            aer_status_prev <= aer_status;

            `ifdef SIMULATION
            if (new_status != aer_status_prev)
                $display("  [AER] status=%08h @%0t ns", new_status, $time/1000);
            `endif
        end
    end

endmodule
