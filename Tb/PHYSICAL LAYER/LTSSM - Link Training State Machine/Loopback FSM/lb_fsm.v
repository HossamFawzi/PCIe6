// ============================================================
// PCIe Gen6 Physical Layer - Module 8: Loopback FSM
// Master/slave loopback for physical layer testing and compliance
// Follows PCIe 6.0 Base Specification LTSSM Loopback state
// ============================================================
`timescale 1ns/1ps

module lb_fsm (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,

    // Inputs
    input  wire        lb_req,          // Request to enter Loopback state
    input  wire        lb_master,       // 1=Loopback Master, 0=Loopback Slave
    input  wire        ts1_lb_bit,      // Loopback bit received in TS1 ordered set
    input  wire        lb_timer_exp,    // Loopback timer expired (2ms timeout per spec)

    // Outputs
    output reg         lb_active,       // Loopback state is active
    output reg         send_ts1_lb,     // Send TS1 with Loopback bit set
    output reg         lb_data_en,      // Enable loopback data path (slave retransmits)
    output reg         lb_exit          // Loopback exit pulse (returns to Detect)
);

    // --------------------------------------------------------
    // State Encoding
    // --------------------------------------------------------
    localparam [3:0]
        ST_IDLE            = 4'd0,   // Normal operation, not in loopback
        ST_LB_ENTRY        = 4'd1,   // Sending TS1 with LB bit (master initiates)
        ST_LB_WAIT_TS1     = 4'd2,   // Master waiting for TS1 with LB bit from slave
        ST_LB_SLAVE_DETECT = 4'd3,   // Slave: detected LB bit in TS1, begin loopback
        ST_LB_ACTIVE_MSTR  = 4'd4,   // Master: loopback active, sending test patterns
        ST_LB_ACTIVE_SLV   = 4'd5,   // Slave: active, retransmitting received data
        ST_LB_EXIT_MSTR    = 4'd6,   // Master initiating exit (sends TS1 w/o LB bit)
        ST_LB_EXIT_SLV     = 4'd7,   // Slave initiating exit (timer / TS1 no LB)
        ST_LB_DONE         = 4'd8;   // Exit pulse, return to Detect

    reg [3:0] state, next_state;

    // TS1 loopback bit counter: master must receive 2 consecutive TS1s with LB bit
    reg [1:0] ts1_lb_cnt;

    // --------------------------------------------------------
    // State Register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_IDLE;
        else
            state <= next_state;
    end

    // --------------------------------------------------------
    // TS1 Loopback Bit Counter (master confirmation)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ts1_lb_cnt <= 2'd0;
        end else begin
            if (state == ST_LB_WAIT_TS1) begin
                if (ts1_lb_bit)
                    ts1_lb_cnt <= ts1_lb_cnt + 2'd1;
                else
                    ts1_lb_cnt <= 2'd0;
            end else begin
                ts1_lb_cnt <= 2'd0;
            end
        end
    end

    // --------------------------------------------------------
    // Next State Logic
    // --------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            ST_IDLE: begin
                if (lb_req)
                    next_state = lb_master ? ST_LB_ENTRY : ST_LB_SLAVE_DETECT;
            end

            // ------- MASTER PATH -------
            ST_LB_ENTRY: begin
                // Send TS1 with LB bit; transition to wait for partner ack
                if (lb_timer_exp)
                    next_state = ST_LB_WAIT_TS1;
            end

            ST_LB_WAIT_TS1: begin
                // Master waits for 2 TS1s with LB bit from slave
                if (lb_timer_exp)
                    next_state = ST_LB_DONE;   // Timeout - abort
                else if (ts1_lb_cnt >= 2'd2)
                    next_state = ST_LB_ACTIVE_MSTR;
            end

            ST_LB_ACTIVE_MSTR: begin
                // Master sends test pattern, loopback is active
                if (lb_timer_exp)
                    next_state = ST_LB_EXIT_MSTR;
            end

            ST_LB_EXIT_MSTR: begin
                // Master sends TS1 without LB bit to signal exit
                if (lb_timer_exp)
                    next_state = ST_LB_DONE;
            end

            // ------- SLAVE PATH -------
            ST_LB_SLAVE_DETECT: begin
                // Slave: received TS1 with LB bit, begin retransmitting
                if (ts1_lb_bit)
                    next_state = ST_LB_ACTIVE_SLV;
            end

            ST_LB_ACTIVE_SLV: begin
                // Slave retransmits data; exit when TS1 without LB bit or timer
                if (!ts1_lb_bit || lb_timer_exp)
                    next_state = ST_LB_EXIT_SLV;
            end

            ST_LB_EXIT_SLV: begin
                if (lb_timer_exp)
                    next_state = ST_LB_DONE;
            end

            ST_LB_DONE: begin
                // One-cycle exit pulse, return to idle
                next_state = ST_IDLE;
            end

            default: next_state = ST_IDLE;
        endcase
    end

    // --------------------------------------------------------
    // Output Logic (registered, based on current state)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lb_active    <= 1'b0;
            send_ts1_lb  <= 1'b0;
            lb_data_en   <= 1'b0;
            lb_exit      <= 1'b0;
        end else begin
            // Default de-assert single-cycle signals
            send_ts1_lb <= 1'b0;
            lb_exit     <= 1'b0;

            case (state)
                ST_IDLE: begin
                    lb_active  <= 1'b0;
                    lb_data_en <= 1'b0;
                end

                ST_LB_ENTRY: begin
                    lb_active   <= 1'b0;
                    send_ts1_lb <= 1'b1;  // Advertise loopback via TS1
                    lb_data_en  <= 1'b0;
                end

                ST_LB_WAIT_TS1: begin
                    lb_active   <= 1'b0;
                    send_ts1_lb <= 1'b1;  // Keep sending TS1 with LB bit
                    lb_data_en  <= 1'b0;
                end

                ST_LB_SLAVE_DETECT: begin
                    lb_active   <= 1'b0;
                    send_ts1_lb <= 1'b1;  // Slave echoes TS1 with LB bit back
                    lb_data_en  <= 1'b0;
                end

                ST_LB_ACTIVE_MSTR: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b0;  // Master drives test data (external)
                end

                ST_LB_ACTIVE_SLV: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b1;  // Slave retransmits received data
                end

                ST_LB_EXIT_MSTR: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;  // TS1 without LB bit signals exit
                    lb_data_en  <= 1'b0;
                end

                ST_LB_EXIT_SLV: begin
                    lb_active   <= 1'b1;
                    send_ts1_lb <= 1'b0;
                    lb_data_en  <= 1'b0;
                end

                ST_LB_DONE: begin
                    lb_active   <= 1'b0;
                    lb_data_en  <= 1'b0;
                    lb_exit     <= 1'b1;  // One-cycle exit pulse
                end

                default: begin
                    lb_active  <= 1'b0;
                    lb_data_en <= 1'b0;
                end
            endcase
        end
    end

endmodule
