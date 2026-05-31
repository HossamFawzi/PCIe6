// ============================================================
//  PCIe Gen6 ? Configuration FSM  (CFG_FSM)
//  Tag: CFG_FSM  |  Group: LTSSM  |  Applies To: All Generations
//
//  Purpose:
//    Implements the LTSSM Configuration state. Negotiates
//    link/lane numbers via TS1/TS2 ordered sets and asserts
//    cfg_done once both sides agree.  Also handles the
//    upconfigure path (width upgrade without going to Recovery).
//
//  Interface derived from pcie_gen6_complete_all_layers_v2.html
//  ============================================================

module cfg_fsm (
    // ?? Clock / Reset ?????????????????????????????????????????
    input  wire        clk,
    input  wire        rst_n,          // active-low synchronous reset

    // ?? Inputs ????????????????????????????????????????????????
    input  wire [7:0]  ts1_link_num,   // link number carried in incoming TS1
    input  wire [7:0]  ts1_lane_num,   // lane number carried in incoming TS1
    input  wire        ts2_detected,   // TS2 ordered set received from partner
    input  wire        cfg_timer_exp,  // configuration timeout expired
    input  wire        upcfg_req,      // request to upconfigure link width

    // ?? Outputs ???????????????????????????????????????????????
    output reg  [7:0]  cfg_link_num,   // link number to advertise in outgoing TS2
    output reg  [7:0]  cfg_lane_num,   // lane number to advertise in outgoing TS2
    output reg         send_ts2,       // instruct TS2 generator to transmit
    output reg         cfg_done,       // configuration handshake completed
    output wire [5:0]  negotiated_width, // agreed link width (1/2/4/8/16 lanes)
    output reg         cfg_timeout_err   // configuration timed out
);

    // ?? State encoding ????????????????????????????????????????
    localparam [2:0]
        ST_IDLE       = 3'd0,   // waiting to enter Configuration
        ST_LNKNUM     = 3'd1,   // exchanging link numbers (TS1 phase)
        ST_LANENUM    = 3'd2,   // exchanging lane numbers (TS1 phase)
        ST_COMPLETE   = 3'd3,   // sending TS2 / awaiting TS2
        ST_UPCFG      = 3'd4,   // upconfigure ? width renegotiation
        ST_DONE       = 3'd5,   // handshake complete
        ST_TIMEOUT    = 3'd6;   // error: timed out

    reg [2:0] state, next_state;

    // ?? TS2 agreement counter ?????????????????????????????????
    //    PCIe requires two consecutive TS2s to confirm agreement
    reg [1:0] ts2_agree_cnt;

    // ?? Latched negotiated values ?????????????????????????????
    reg [7:0] latch_link_num;
    reg [7:0] latch_lane_num;

    // ?? Sequential state register ?????????????????????????????
    always @(posedge clk) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    // ?? Next-state logic ??????????????????????????????????????
    always @(*) begin
        next_state = state;  // default: hold

        case (state)
            ST_IDLE: begin
                // Advance when the upstream LTSSM Top enters Configuration
                // (signalled by ts1_link_num being driven non-PAD (!=8'hFF))
                if (ts1_link_num != 8'hFF)
                    next_state = ST_LNKNUM;
            end

            ST_LNKNUM: begin
                // Stay until a valid link number is seen from the partner;
                // timeout if we stall too long
                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_link_num != 8'hFF)
                    next_state = ST_LANENUM;
            end

            ST_LANENUM: begin
                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_lane_num != 8'hFF)
                    next_state = ST_COMPLETE;
            end

            ST_COMPLETE: begin
                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (upcfg_req)
                    next_state = ST_UPCFG;
                else if (ts2_agree_cnt == 2'd2)
                    next_state = ST_DONE;
            end

            ST_UPCFG: begin
                // Renegotiate width; re-enter TS1 link-number exchange
                if (cfg_timer_exp)
                    next_state = ST_TIMEOUT;
                else if (ts1_lane_num != 8'hFF)
                    next_state = ST_COMPLETE;
            end

            ST_DONE:    next_state = ST_IDLE;   // one-cycle pulse, then idle
            ST_TIMEOUT: next_state = ST_IDLE;   // one-cycle error pulse, then idle

            default:    next_state = ST_IDLE;
        endcase
    end

    // ?? Internal reg for combinational width decode ???????????
    reg [5:0] negotiated_width_r;
    assign negotiated_width = negotiated_width_r;

    // ?? Combinational width decode ? always tracks latch_lane_num ?????????
    always @(*) begin
        case (latch_lane_num)
            8'd0:    negotiated_width_r = 6'd1;
            8'd1:    negotiated_width_r = 6'd2;
            8'd3:    negotiated_width_r = 6'd4;
            8'd7:    negotiated_width_r = 6'd8;
            8'd15:   negotiated_width_r = 6'd16;
            default: negotiated_width_r = 6'd1;
        endcase
    end

    // ?? Output / datapath logic ???????????????????????????????
    always @(posedge clk) begin
        if (!rst_n) begin
            cfg_link_num      <= 8'h00;
            cfg_lane_num      <= 8'h00;
            send_ts2          <= 1'b0;
            cfg_done          <= 1'b0;
            cfg_timeout_err   <= 1'b0;
            ts2_agree_cnt     <= 2'd0;
            latch_link_num    <= 8'hFF;
            latch_lane_num    <= 8'hFF;
        end else begin
            // Default pulse signals off every cycle
            send_ts2        <= 1'b0;
            cfg_done        <= 1'b0;
            cfg_timeout_err <= 1'b0;

            case (state)
                // ?? Latch link number from partner ??????????
                ST_LNKNUM: begin
                    if (ts1_link_num != 8'hFF)
                        latch_link_num <= ts1_link_num;
                end

                // ?? Latch lane number from partner ??????????
                ST_LANENUM: begin
                    if (ts1_lane_num != 8'hFF)
                        latch_lane_num <= ts1_lane_num;
                end

                // ?? Send TS2; count partner TS2 agreements ??
                ST_COMPLETE: begin
                    // Echo back the negotiated numbers in TS2
                    cfg_link_num <= latch_link_num;
                    cfg_lane_num <= latch_lane_num;
                    send_ts2     <= 1'b1;

                    // Count incoming TS2 acknowledgements
                    if (ts2_detected && (ts2_agree_cnt < 2'd2))
                        ts2_agree_cnt <= ts2_agree_cnt + 2'd1;
                end

                // ?? Upconfigure: re-advertise wider width ???
                ST_UPCFG: begin
                    send_ts2     <= 1'b1;
                    cfg_link_num <= latch_link_num;
                    // Lane num field resets to PAD during width renegotiation
                    cfg_lane_num <= 8'hFF;
                    ts2_agree_cnt <= 2'd0;   // reset agreement counter
                    // Latch the new (wider) lane number from TS1 if valid
                    if (ts1_lane_num != 8'hFF)
                        latch_lane_num <= ts1_lane_num;
                end

                // ?? Handshake complete ???????????????????????
                ST_DONE: begin
                    cfg_done      <= 1'b1;
                    ts2_agree_cnt <= 2'd0;
                end

                // ?? Configuration timed out ??????????????????
                ST_TIMEOUT: begin
                    cfg_timeout_err <= 1'b1;
                    ts2_agree_cnt   <= 2'd0;
                    latch_link_num  <= 8'hFF;
                    latch_lane_num  <= 8'hFF;
                end

                default: ; // ST_IDLE: hold outputs
            endcase
        end
    end

endmodule
