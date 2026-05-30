// ============================================================
//  PCIe Gen6 ? Recovery FSM  (RECV_FSM)
//  Tag: RECV_FSM  |  Group: LTSSM  |  Applies To: All Generations
//
//  Purpose:
//    Implements the LTSSM Recovery state machine.  Recovers an
//    active link after errors, performs speed-change sequences,
//    and drives equalization sub-states for Gen3+.
//
//  Sub-states modelled:
//    Recovery.RcvrLock  ? send TS1, wait for TS1 lock
//    Recovery.RcvrCfg   ? send TS2, wait for TS2 agreement
//    Recovery.Idle      ? wait for electrical-idle detect
//    Recovery.Speed     ? rate change handshake
//    Recovery.Equalization ? equalization phases (Gen3+)
//
//  Interface derived from pcie_gen6_complete_all_layers_v2.html
// ============================================================

module recv_fsm (
    // ?? Clock / Reset ?????????????????????????????????????????
    input  wire clk,
    input  wire rst_n,              // active-low synchronous reset

    // ?? Inputs ????????????????????????????????????????????????
    input  wire recv_req,           // LTSSM Top: enter Recovery
    input  wire ts1_detected,       // TS1 ordered set received from partner
    input  wire ts2_detected,       // TS2 ordered set received from partner
    input  wire idle_detected,      // electrical idle detected on RX
    input  wire speed_change_req,   // speed negotiation requests rate change
    input  wire eq_done,            // equalization controller finished
    input  wire recv_timer_exp,     // Recovery timeout expired

    // ?? Outputs ???????????????????????????????????????????????
    output reg  send_ts1,           // instruct TS1 generator to transmit
    output reg  send_ts2,           // instruct TS2 generator to transmit
    output reg  speed_change_en,    // enable PIPE rate change handshake
    output reg  eq_start,           // start equalization controller
    output reg  recv_done,          // recovery succeeded ? return to L0
    output reg  recv_timeout_err,   // recovery timed out
    output reg  retrain_req         // escalate: link retrain needed
);

    // ?? State encoding ????????????????????????????????????????
    localparam [2:0]
        ST_IDLE         = 3'd0,   // waiting for recv_req
        ST_RCVR_LOCK    = 3'd1,   // Recovery.RcvrLock   ? send TS1, wait TS1
        ST_RCVR_CFG     = 3'd2,   // Recovery.RcvrCfg    ? send TS2, wait TS2
        ST_RCVR_IDLE    = 3'd3,   // Recovery.Idle       ? wait elec-idle
        ST_SPEED        = 3'd4,   // Recovery.Speed      ? rate change
        ST_EQ           = 3'd5,   // Recovery.Equalization
        ST_DONE         = 3'd6,   // success ? one-cycle pulse
        ST_TIMEOUT      = 3'd7;   // failure ? one-cycle pulse

    reg [2:0] state, next_state;

    // ?? TS2 agree counter ? need 2 consecutive TS2s ???????????
    reg [1:0] ts2_cnt;

    // ?? Retrain counter ? if we time out repeatedly ???????????
    reg [1:0] retrain_cnt;

    // ?? Sequential state register ?????????????????????????????
    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    // ?? Next-state logic ??????????????????????????????????????
    always @(*) begin
        next_state = state;  // hold by default

        case (state)
            ST_IDLE: begin
                if (recv_req)
                    next_state = ST_RCVR_LOCK;
            end

            ST_RCVR_LOCK: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_detected)
                    next_state = ST_RCVR_CFG;
            end

            ST_RCVR_CFG: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (speed_change_req)
                    next_state = ST_SPEED;
                else if (ts2_cnt == 2'd2)
                    next_state = ST_RCVR_IDLE;
            end

            ST_RCVR_IDLE: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (idle_detected)
                    next_state = ST_DONE;
            end

            ST_SPEED: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else
                    // After speed change, go back through lock at the new rate
                    next_state = ST_RCVR_LOCK;
            end

            ST_EQ: begin
                if (recv_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (eq_done)
                    next_state = ST_RCVR_CFG;
            end

            ST_DONE:    next_state = ST_IDLE;
            ST_TIMEOUT: next_state = ST_IDLE;

            default:    next_state = ST_IDLE;
        endcase
    end

    // ?? Output / datapath logic ???????????????????????????????
    always @(posedge clk) begin
        if (!rst_n) begin
            send_ts1        <= 1'b0;
            send_ts2        <= 1'b0;
            speed_change_en <= 1'b0;
            eq_start        <= 1'b0;
            recv_done       <= 1'b0;
            recv_timeout_err <= 1'b0;
            retrain_req     <= 1'b0;
            ts2_cnt         <= 2'd0;
            retrain_cnt     <= 2'd0;
        end else begin
            // Pulse-type outputs ? default off each cycle
            send_ts1         <= 1'b0;
            send_ts2         <= 1'b0;
            speed_change_en  <= 1'b0;
            eq_start         <= 1'b0;
            recv_done        <= 1'b0;
            recv_timeout_err <= 1'b0;
            retrain_req      <= 1'b0;

            case (state)
                // ?? Recovery.RcvrLock ????????????????????????
                ST_RCVR_LOCK: begin
                    send_ts1 <= 1'b1;
                end

                // ?? Recovery.RcvrCfg ?????????????????????????
                ST_RCVR_CFG: begin
                    send_ts2 <= 1'b1;
                    if (ts2_detected && ts2_cnt < 2'd2)
                        ts2_cnt <= ts2_cnt + 2'd1;
                end

                // ?? Recovery.Idle ????????????????????????????
                ST_RCVR_IDLE: begin
                    // No outgoing symbols; wait for idle detect
                    ts2_cnt <= 2'd0;   // reset for next usage
                end

                // ?? Recovery.Speed ???????????????????????????
                ST_SPEED: begin
                    speed_change_en <= 1'b1;
                    ts2_cnt         <= 2'd0;
                end

                // ?? Recovery.Equalization ????????????????????
                ST_EQ: begin
                    eq_start <= 1'b1;
                end

                // ?? Recovery succeeded ???????????????????????
                ST_DONE: begin
                    recv_done   <= 1'b1;
                    retrain_cnt <= 2'd0;
                end

                // ?? Recovery timed out ???????????????????????
                ST_TIMEOUT: begin
                    recv_timeout_err <= 1'b1;
                    ts2_cnt          <= 2'd0;
                    // After two consecutive timeouts, escalate to retrain
                    if (retrain_cnt == 2'd2) begin
                        retrain_req  <= 1'b1;
                        retrain_cnt  <= 2'd0;
                    end else begin
                        retrain_cnt  <= retrain_cnt + 2'd1;
                    end
                end

                default: ; // ST_IDLE: hold
            endcase
        end
    end

endmodule
