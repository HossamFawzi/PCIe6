// =============================================================
//  MODULE : seq_num_checker_rx  [FIXED]
//  Fix    : ELAB-303 — The reset condition of the always block
//           used a compound expression:
//             always @(posedge clk or negedge rst_n)
//               if (!rst_n || link_reset) ...
//
//           DC requires the if-reset condition to be a SIMPLE
//           identifier or its negation (e.g. !rst_n).
//           Compound OR conditions (|| link_reset) cause ELAB-303.
//
//  Solution: Move the link_reset branch out of the async-reset
//           condition into the synchronous else branch with
//           highest priority (first if in the else block).
//           This is the standard synthesizable coding style.
// =============================================================
module seq_num_checker_rx (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          link_reset,

    input  wire [11:0]   seq_rx,
    input  wire          tlp_rx_valid,
    input  wire          tlp_ok,
    input  wire [1023:0] tlp_clean,

    output reg           tlp_seq_ok,
    output reg           tlp_dup,
    output reg           tlp_seq_err,
    output reg           nak_req,
    output reg           seq_dup_ack,
    output reg  [11:0]   seq_err_val,
    output reg  [11:0]   next_expected,

    output reg  [1023:0] tlp_fwd,
    output reg           tlp_fwd_valid
);

    wire [11:0] expected_seq = next_expected;
    wire [11:0] prev_seq     = expected_seq - 12'd1;

    // FIX: link_reset handled synchronously (first priority in else branch)
    // to satisfy ELAB-303 simple-identifier reset condition rule.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            next_expected <= 12'h000;
            tlp_seq_ok    <= 1'b0;
            tlp_dup       <= 1'b0;
            tlp_seq_err   <= 1'b0;
            nak_req       <= 1'b0;
            seq_dup_ack   <= 1'b0;
            seq_err_val   <= 12'h000;
            tlp_fwd       <= 1024'b0;
            tlp_fwd_valid <= 1'b0;
        end else begin
            // Synchronous link reset — highest priority in clocked domain
            if (link_reset) begin
                next_expected <= 12'h000;
                tlp_seq_ok    <= 1'b0;
                tlp_dup       <= 1'b0;
                tlp_seq_err   <= 1'b0;
                nak_req       <= 1'b0;
                seq_dup_ack   <= 1'b0;
                seq_err_val   <= 12'h000;
                tlp_fwd       <= 1024'b0;
                tlp_fwd_valid <= 1'b0;
            end else begin
                // Defaults: clear all pulse outputs
                tlp_seq_ok    <= 1'b0;
                tlp_dup       <= 1'b0;
                tlp_seq_err   <= 1'b0;
                nak_req       <= 1'b0;
                seq_dup_ack   <= 1'b0;
                seq_err_val   <= 12'h000;
                tlp_fwd_valid <= 1'b0;

                if (tlp_rx_valid && tlp_ok) begin
                    if (seq_rx == expected_seq) begin
                        tlp_seq_ok    <= 1'b1;
                        tlp_fwd       <= tlp_clean;
                        tlp_fwd_valid <= 1'b1;
                        next_expected <= expected_seq + 12'd1;
                    end else if (seq_rx == prev_seq) begin
                        tlp_dup     <= 1'b1;
                        seq_dup_ack <= 1'b1;
                    end else begin
                        tlp_seq_err <= 1'b1;
                        nak_req     <= 1'b1;
                        seq_err_val <= seq_rx;
                    end
                end
            end
        end
    end

endmodule
