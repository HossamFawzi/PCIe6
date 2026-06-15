// ============================================================
// PCIe Gen6 Physical Layer - Module 7: L1 FSM
// Handles L1, L1.1, L1.2 power management sub-states
// Coordinates with PM FSM in Data Link Layer
// PIPE 5.1 compliant
// ============================================================
`timescale 1ns/1ps

module l1_fsm (
    // Clock and Reset
    input  wire        clk,
    input  wire        rst_n,

    // Inputs
    input  wire        l1_req,          // Request to enter L1
    input  wire        l1_ack,          // Acknowledge from link partner (PM_Enter_L1 DLLP accepted)
    input  wire        l1_timer_exp,    // L1 entry/exit timer expired
    input  wire        pm_dllp_rx,      // PM_Request_Ack DLLP received
    input  wire        l1_exit_req,     // Request to exit L1 (traffic / wakeup)

    // Outputs
    output reg         send_eios,               // Send Electrical Idle Ordered Set
    output reg         l1_active,               // Link is in L1 state
    output reg         l1_exit,                 // L1 exit pulse
    output reg  [1:0]  pipe_power_down,         // PIPE PowerDown[1:0]: 00=P0,01=P0s,10=P1,11=P2
    output reg         l1_timeout_err           // L1 handshake timeout error
);

    // --------------------------------------------------------
    // State Encoding
    // --------------------------------------------------------
    localparam [3:0]
        ST_L0          = 4'd0,   // Normal active (L0)
        ST_L1_ENTRY    = 4'd1,   // Initiating L1 entry (send PM_Enter_L1 DLLP)
        ST_L1_WAIT_ACK = 4'd2,   // Waiting for PM_Request_Ack from partner
        ST_L1_SEND_EI  = 4'd3,   // Sending EIOS to enter electrical idle
        ST_L1          = 4'd4,   // L1 steady state (PHY in P1)
        ST_L1_1        = 4'd5,   // L1.1 sub-state (CLKREQ# de-asserted, ref clock off)
        ST_L1_2        = 4'd6,   // L1.2 sub-state (deeper power savings)
        ST_L1_EXIT     = 4'd7,   // L1 exit sequence
        ST_L1_EXIT_EI  = 4'd8,   // Exiting electrical idle
        ST_ERROR       = 4'd9;   // Timeout/error state

    reg [3:0] state, next_state;

    // Timeout counter for handshake
    reg [11:0] timeout_cnt;
    localparam TIMEOUT_LIMIT = 12'd4095;

    // --------------------------------------------------------
    // State Register
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= ST_L0;
        else
            state <= next_state;
    end

    // --------------------------------------------------------
    // Timeout Counter
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timeout_cnt <= 12'd0;
        end else begin
            case (state)
                ST_L1_WAIT_ACK: begin
                    if (pm_dllp_rx || l1_ack)
                        timeout_cnt <= 12'd0;
                    else if (timeout_cnt < TIMEOUT_LIMIT)
                        timeout_cnt <= timeout_cnt + 12'd1;
                end
                default: timeout_cnt <= 12'd0;
            endcase
        end
    end

    // --------------------------------------------------------
    // Next State Logic
    // --------------------------------------------------------
    always @(*) begin
        next_state = state;
        case (state)
            ST_L0: begin
                if (l1_req)
                    next_state = ST_L1_ENTRY;
            end

            ST_L1_ENTRY: begin
                // After initiating entry, wait for partner ack
                next_state = ST_L1_WAIT_ACK;
            end

            ST_L1_WAIT_ACK: begin
                if (timeout_cnt >= TIMEOUT_LIMIT)
                    next_state = ST_ERROR;
                else if (pm_dllp_rx || l1_ack)
                    next_state = ST_L1_SEND_EI;
            end

            ST_L1_SEND_EI: begin
                // Send EIOS then go to L1
                if (l1_timer_exp)
                    next_state = ST_L1;
            end

            ST_L1: begin
                // Stay in L1; deeper sub-states or exit
                if (l1_exit_req)
                    next_state = ST_L1_EXIT_EI;
                else if (l1_timer_exp)
                    next_state = ST_L1_1;
            end

            ST_L1_1: begin
                if (l1_exit_req)
                    next_state = ST_L1_EXIT_EI;
                else if (l1_timer_exp)
                    next_state = ST_L1_2;
            end

            ST_L1_2: begin
                if (l1_exit_req)
                    next_state = ST_L1_EXIT_EI;
            end

            ST_L1_EXIT_EI: begin
                if (l1_timer_exp)
                    next_state = ST_L1_EXIT;
            end

            ST_L1_EXIT: begin
                // One-cycle pulse state, return to L0
                next_state = ST_L0;
            end

            ST_ERROR: begin
                // Remain in error until reset
                next_state = ST_ERROR;
            end

            default: next_state = ST_L0;
        endcase
    end

    // --------------------------------------------------------
    // Output Logic (registered, based on current state)
    // --------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            send_eios         <= 1'b0;
            l1_active         <= 1'b0;
            l1_exit           <= 1'b0;
            pipe_power_down   <= 2'b00;
            l1_timeout_err    <= 1'b0;
        end else begin
            // Default de-assert pulses every clock
            send_eios      <= 1'b0;
            l1_exit        <= 1'b0;
            l1_timeout_err <= 1'b0;

            case (state)
                ST_L0: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;  // P0 - full power
                end

                ST_L1_ENTRY: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                ST_L1_WAIT_ACK: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                ST_L1_SEND_EI: begin
                    send_eios       <= 1'b1;   // Assert EIOS
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b01;  // P0s
                end

                ST_L1: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b10;  // P1
                end

                ST_L1_1: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b10;  // P1 (clkreq de-asserted externally)
                end

                ST_L1_2: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b11;  // P2 - deepest
                end

                ST_L1_EXIT_EI: begin
                    l1_active       <= 1'b1;
                    pipe_power_down <= 2'b01;  // P0s transitioning
                end

                ST_L1_EXIT: begin
                    l1_active       <= 1'b0;
                    l1_exit         <= 1'b1;   // One-cycle exit pulse
                    pipe_power_down <= 2'b00;  // P0
                end

                ST_ERROR: begin
                    l1_timeout_err  <= 1'b1;
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end

                default: begin
                    l1_active       <= 1'b0;
                    pipe_power_down <= 2'b00;
                end
            endcase
        end
    end

endmodule
