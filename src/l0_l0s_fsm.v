// ============================================================
//  PCIe Gen6 ? L0 / L0s FSM  (L0_FSM)
//  Tag: L0_FSM  |  Group: LTSSM  |  Applies To: All Generations
//
//  Purpose:
//    Manages the normal active (L0) and standby (L0s) LTSSM
//    states.  L0s reduces power by parking the TX while the
//    link idles, and exits via Fast Training Sequences (FTS).
//
//  State summary:
//    L0            ? full active; normal data flow
//    L0s_TX_ENTRY  ? TX side sending EIOS, entering electrical idle
//    L0s_TX        ? TX in L0s (parked); waiting for exit request
//    L0s_TX_EXIT   ? TX exiting L0s via FTS burst
//    L0s_RX        ? RX side has detected EIOS; link is L0s
//    L0s_RX_EXIT   ? RX side received FTS; returning to L0
//    L0s_EXIT_DONE ? single-cycle "back to L0" handshake
//
//  Interface derived from pcie_gen6_complete_all_layers_v2.html
// ============================================================

module l0_fsm (
    // ?? Clock / Reset ?????????????????????????????????????????
    input  wire clk,
    input  wire rst_n,           // active-low synchronous reset

    // ?? Inputs ????????????????????????????????????????????????
    input  wire l0s_req,         // PM FSM: request to enter L0s (TX side)
    input  wire fts_detected,    // FTS ordered set received (L0s RX exit)
    input  wire eios_detected,   // EIOS received (partner entering L0s)
    input  wire l0s_timer_exp,   // L0s entry/exit timer expired
    input  wire recv_req,        // error/hot-reset detected ? go to Recovery

    // ?? Outputs ???????????????????????????????????????????????
    output reg  send_fts,        // send FTS burst to exit L0s
    output reg  send_eios,       // send EIOS to enter L0s
    output reg  l0_active,       // asserted when link is in full L0
    output reg  l0s_tx_active,   // asserted when TX side is in L0s
    output reg  l0s_rx_active,   // asserted when RX side is in L0s
    output reg  l0s_exit         // pulse: L0s fully exited, back to L0
);

    // ?? State encoding ????????????????????????????????????????
    localparam [2:0]
        ST_L0          = 3'd0,   // normal operation
        ST_L0S_TX_ENTRY = 3'd1,  // TX sending EIOS, entering idle
        ST_L0S_TX      = 3'd2,   // TX side is parked in L0s
        ST_L0S_TX_EXIT = 3'd3,   // TX side sending FTS to exit
        ST_L0S_RX      = 3'd4,   // RX detected EIOS ? RX side in L0s
        ST_L0S_RX_EXIT = 3'd5,   // RX received FTS burst ? exiting
        ST_EXIT_DONE   = 3'd6;   // one-cycle: fully back in L0

    reg [2:0] state, next_state;

    // ?? FTS counter ? count received FTS symbols ???????????????
    //    A minimum of 2 FTS are required; we use a simple 3-bit
    //    counter (counts 0..7).
    reg [2:0] fts_rx_cnt;
    localparam FTS_REQUIRED = 3'd2;

    // ?? Sequential state register ?????????????????????????????
    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_L0;
        else
            state <= next_state;
    end

    // ?? Next-state logic ??????????????????????????????????????
    always @(*) begin
        next_state = state;

        // Global override: error ? Recovery (handled by Top FSM;
        // l0_fsm just idles; actual Recovery entry controlled upstream)
        if (recv_req && (state != ST_L0)) begin
            // Pull back to L0 so the Top controller can switch to Recovery
            next_state = ST_L0;
        end else begin
            case (state)
                // ?? L0: normal active ????????????????????????
                ST_L0: begin
                    if (recv_req)
                        next_state = ST_L0;   // hold; Top will move to Recovery
                    else if (l0s_req)
                        next_state = ST_L0S_TX_ENTRY;
                    else if (eios_detected)
                        next_state = ST_L0S_RX;
                end

                // ?? TX entering L0s ? EIOS being sent ????????
                ST_L0S_TX_ENTRY: begin
                    if (l0s_timer_exp)   // EIOS sent; now in electrical idle
                        next_state = ST_L0S_TX;
                end

                // ?? TX parked in L0s ??????????????????????????
                ST_L0S_TX: begin
                    // Exit when upper layer has data or explicit wakeup
                    if (l0s_timer_exp)
                        next_state = ST_L0S_TX_EXIT;
                end

                // ?? TX sending FTS burst to exit ??????????????
                ST_L0S_TX_EXIT: begin
                    if (l0s_timer_exp)   // FTS burst done
                        next_state = ST_EXIT_DONE;
                end

                // ?? RX detected EIOS from partner ?????????????
                ST_L0S_RX: begin
                    if (fts_detected)
                        next_state = ST_L0S_RX_EXIT;
                end

                // ?? RX receiving FTS burst ?????????????????????
                ST_L0S_RX_EXIT: begin
                    if (fts_rx_cnt >= FTS_REQUIRED)
                        next_state = ST_EXIT_DONE;
                end

                // ?? Exit handshake complete ????????????????????
                ST_EXIT_DONE: begin
                    next_state = ST_L0;
                end

                default: next_state = ST_L0;
            endcase
        end
    end

    // ?? Output / datapath logic ???????????????????????????????
    always @(posedge clk) begin
        if (!rst_n) begin
            send_fts      <= 1'b0;
            send_eios     <= 1'b0;
            l0_active     <= 1'b1;   // power-on default: L0
            l0s_tx_active <= 1'b0;
            l0s_rx_active <= 1'b0;
            l0s_exit      <= 1'b0;
            fts_rx_cnt    <= 3'd0;
        end else begin
            // Pulse signals default off
            send_fts   <= 1'b0;
            send_eios  <= 1'b0;
            l0s_exit   <= 1'b0;

            case (state)
                // ?? L0: full active ??????????????????????????
                ST_L0: begin
                    l0_active     <= 1'b1;
                    l0s_tx_active <= 1'b0;
                    l0s_rx_active <= 1'b0;
                    fts_rx_cnt    <= 3'd0;
                end

                // ?? TX L0s entry: transmit EIOS ??????????????
                ST_L0S_TX_ENTRY: begin
                    l0_active <= 1'b0;
                    send_eios <= 1'b1;
                end

                // ?? TX parked ????????????????????????????????
                ST_L0S_TX: begin
                    l0s_tx_active <= 1'b1;
                end

                // ?? TX exit: send FTS burst ???????????????????
                ST_L0S_TX_EXIT: begin
                    send_fts <= 1'b1;
                end

                // ?? RX side in L0s ???????????????????????????
                ST_L0S_RX: begin
                    l0_active     <= 1'b0;
                    l0s_rx_active <= 1'b1;
                    fts_rx_cnt    <= 3'd0;
                end

                // ?? RX receiving FTS burst ????????????????????
                ST_L0S_RX_EXIT: begin
                    if (fts_detected && fts_rx_cnt < 3'd7)
                        fts_rx_cnt <= fts_rx_cnt + 3'd1;
                end

                // ?? Exit complete: return to L0 ???????????????
                ST_EXIT_DONE: begin
                    l0_active     <= 1'b1;
                    l0s_tx_active <= 1'b0;
                    l0s_rx_active <= 1'b0;
                    l0s_exit      <= 1'b1;
                    fts_rx_cnt    <= 3'd0;
                end

                default: ;
            endcase
        end
    end

endmodule
