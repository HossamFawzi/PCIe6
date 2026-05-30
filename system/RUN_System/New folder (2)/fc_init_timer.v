// =============================================================
//  MODULE : fc_init_timer
//  TAG    : FC_INIT_TMR  🔴 MUST
//  LAYER  : Transaction Layer — Support Group
//  DESC   : Watchdog timer for the Flow Control Initialisation
//           handshake at link bring-up. If fc_init_done is not
//           asserted within fc_init_timeout_val cycles after
//           fc_init_start, the timer fires fc_init_timeout and
//           requests a retry (up to 3 retries) then fc_init_err.
//  SPEC   : PCIe 6.0 Base Spec §2.11.2 (FC Init Sequence)
// =============================================================
module fc_init_timer (
    input  wire         clk,
    input  wire         rst_n,

    // ── Control ───────────────────────────────────────────────
    input  wire         fc_init_start,          // Pulse: begin FC init
    input  wire         fc_init_done,           // Pulse: FC init complete
    input  wire [15:0]  fc_init_timeout_val,    // Timeout threshold

    // ── Outputs ───────────────────────────────────────────────
    output reg          fc_init_timeout,        // Pulse: timer expired
    output reg          fc_init_retry_req,      // Pulse: retry requested
    output reg          fc_init_err             // Sticky: all retries failed
);

    localparam MAX_RETRIES = 3;

    // ── FSM states ────────────────────────────────────────────
    localparam [1:0]
        S_IDLE    = 2'b00,
        S_RUNNING = 2'b01,
        S_RETRY   = 2'b10,
        S_ERROR   = 2'b11;

    reg [1:0]  state;
    reg [15:0] counter;
    reg [1:0]  retry_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            counter          <= 16'h0;
            retry_cnt        <= 2'h0;
            fc_init_timeout  <= 1'b0;
            fc_init_retry_req<= 1'b0;
            fc_init_err      <= 1'b0;
        end
        else begin
            // Default: de-assert pulses
            fc_init_timeout  <= 1'b0;
            fc_init_retry_req<= 1'b0;

            // synthesis full_case
            case (state)
                // ── Wait for start ──────────────────────────
                S_IDLE: begin
                    counter   <= fc_init_timeout_val;
                    retry_cnt <= 2'h0;
                    if (fc_init_start)
                        state <= S_RUNNING;
                end

                // ── Count down ──────────────────────────────
                S_RUNNING: begin
                    if (fc_init_done) begin
                        // Success
                        state   <= S_IDLE;
                        counter <= 16'h0;
                    end
                    else if (counter == 16'h1) begin
                        // Expired
                        fc_init_timeout <= 1'b1;
                        counter         <= 16'h0;
                        state           <= S_RETRY;
                    end
                    else begin
                        counter <= counter - 16'h1;
                    end
                end

                // ── Decide retry or error ───────────────────
                S_RETRY: begin
                    if (retry_cnt < MAX_RETRIES[1:0]) begin
                        retry_cnt        <= retry_cnt + 2'h1;
                        fc_init_retry_req<= 1'b1;
                        counter          <= fc_init_timeout_val;
                        state            <= S_RUNNING;
                    end
                    else begin
                        fc_init_err <= 1'b1;
                        state       <= S_ERROR;
                    end
                end

                // ── Permanent error — wait for reset ────────
                S_ERROR: begin
                    fc_init_err <= 1'b1; // sticky
                end

                // default: unreachable (2-bit FSM fully enumerated)
                // synthesis full_case covers this
                default: state <= S_IDLE; // pragma: unreachable
            endcase
        end
    end

endmodule
