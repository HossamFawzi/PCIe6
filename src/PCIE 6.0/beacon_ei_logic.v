// =============================================================================
// Module  : beacon_ei_logic
// Block   : Beacon / Electrical Idle Logic  (tag: BEAC)
// Spec    : PCIe Gen6 PHY ? Link Management
//
// Purpose : Detects and drives Electrical Idle (EI) on the PIPE interface
//           and generates / detects the PME Beacon signal used to wake the
//           link from L2 / L3 power states.
//
// Interfaces (from HTML reference):
//   Inputs  : beacon_req, ei_req, pipe_rx_elec_idle, pm_state[2:0], clk, rst_n
//   Outputs : pipe_tx_elec_idle, beacon_detect, ei_detect, wakeup_req
// =============================================================================

module beacon_ei_logic (
    // ?? Clock & Reset ????????????????????????????????????????????????????????
    input  wire        clk,               // System / PIPE clock
    input  wire        rst_n,             // Active-low synchronous reset

    // ?? Inputs ???????????????????????????????????????????????????????????????
    input  wire        beacon_req,        // Request to transmit PME beacon
    input  wire        ei_req,            // Request to enter Electrical Idle TX
    input  wire        pipe_rx_elec_idle, // PIPE: RX is detecting Electrical Idle
    input  wire [2:0]  pm_state,          // Current PM / LTSSM power state

    // ?? Outputs ??????????????????????????????????????????????????????????????
    output reg         pipe_tx_elec_idle, // PIPE: drive TX into Electrical Idle
    output reg         beacon_detect,     // Beacon pulse detected on RX
    output reg         ei_detect,         // Electrical Idle detected on RX
    output reg         wakeup_req         // Wake-up request to power management
);

    // =========================================================================
    // PM State encoding (PCIe spec ? subset used here)
    // =========================================================================
    localparam PM_L0   = 3'b000;   // Active
    localparam PM_L0S  = 3'b001;   // L0s
    localparam PM_L1   = 3'b010;   // L1
    localparam PM_L2   = 3'b011;   // L2
    localparam PM_L3   = 3'b100;   // L3 (off)

    // =========================================================================
    // Beacon detection parameters
    // A beacon is a burst of ?2 µs on the differential pair.
    // At 250 MHz PIPE clock that is ?500 clock cycles of sampled idle-exit.
    // We use a simple counter-based detector here.
    // =========================================================================
    localparam BEACON_DETECT_THRESHOLD = 16'd500;  // clocks beacon must persist
    localparam EI_DETECT_THRESHOLD     = 8'd8;     // clocks EI must persist

    // =========================================================================
    // Beacon TX state machine
    // =========================================================================
    localparam BCN_IDLE      = 2'b00;   // Waiting for request
    localparam BCN_ASSERT    = 2'b01;   // Driving beacon (TX not in EI)
    localparam BCN_DEASSERT  = 2'b10;   // Inter-beacon gap (TX in EI)
    localparam BCN_DONE      = 2'b11;   // Beacon burst complete

    reg [1:0]  bcn_state;
    reg [15:0] bcn_on_cnt;    // How long beacon is asserted
    reg [15:0] bcn_off_cnt;   // Inter-beacon gap counter
    reg [3:0]  bcn_pulse_cnt; // Number of pulses sent (spec: at least 2)

    // Beacon ON / OFF timings (in clock cycles at 250 MHz)
    localparam BCN_ON_CYCLES  = 16'd250;  // ~1 µs on
    localparam BCN_OFF_CYCLES = 16'd250;  // ~1 µs off
    localparam BCN_MIN_PULSES = 4'd4;     // minimum beacon pulses

    // =========================================================================
    // EI / Beacon RX detection counters
    // =========================================================================
    reg [15:0] beacon_cnt;    // counts consecutive non-EI RX cycles
    reg [7:0]  ei_cnt;        // counts consecutive EI RX cycles

    // =========================================================================
    // Beacon TX state machine
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            bcn_state     <= BCN_IDLE;
            bcn_on_cnt    <= 16'd0;
            bcn_off_cnt   <= 16'd0;
            bcn_pulse_cnt <= 4'd0;
        end else begin
            case (bcn_state)

                BCN_IDLE : begin
                    bcn_on_cnt    <= 16'd0;
                    bcn_off_cnt   <= 16'd0;
                    bcn_pulse_cnt <= 4'd0;
                    // Only allow beacon in L2/L3 and when explicitly requested
                    if (beacon_req &&
                        (pm_state == PM_L2 || pm_state == PM_L3)) begin
                        bcn_state <= BCN_ASSERT;
                    end
                end

                BCN_ASSERT : begin
                    if (bcn_on_cnt == BCN_ON_CYCLES - 1) begin
                        bcn_on_cnt    <= 16'd0;
                        bcn_pulse_cnt <= bcn_pulse_cnt + 1'b1;
                        bcn_state     <= BCN_DEASSERT;
                    end else begin
                        bcn_on_cnt <= bcn_on_cnt + 1'b1;
                    end
                end

                BCN_DEASSERT : begin
                    if (bcn_off_cnt == BCN_OFF_CYCLES - 1) begin
                        bcn_off_cnt <= 16'd0;
                        if (bcn_pulse_cnt >= BCN_MIN_PULSES && !beacon_req) begin
                            bcn_state <= BCN_DONE;
                        end else begin
                            bcn_state <= BCN_ASSERT;
                        end
                    end else begin
                        bcn_off_cnt <= bcn_off_cnt + 1'b1;
                    end
                end

                BCN_DONE : begin
                    // Return to idle when request is de-asserted
                    if (!beacon_req)
                        bcn_state <= BCN_IDLE;
                end

                default : bcn_state <= BCN_IDLE;
            endcase
        end
    end

    // =========================================================================
    // TX Electrical Idle output
    // Priority: EI request overrides beacon (beacon temporarily releases EI)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_tx_elec_idle <= 1'b1;  // Default: TX in electrical idle
        end else begin
            if (ei_req) begin
                // Explicit EI request: force TX to idle
                pipe_tx_elec_idle <= 1'b1;
            end else if (bcn_state == BCN_ASSERT) begin
                // During beacon assertion, release TX from idle to create signal
                pipe_tx_elec_idle <= 1'b0;
            end else begin
                // All other cases: TX in electrical idle
                pipe_tx_elec_idle <= 1'b1;
            end
        end
    end

    // =========================================================================
    // RX Electrical Idle detection
    // pipe_rx_elec_idle must be stable for EI_DETECT_THRESHOLD cycles
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            ei_cnt    <= 8'd0;
            ei_detect <= 1'b0;
        end else begin
            if (pipe_rx_elec_idle) begin
                if (ei_cnt < EI_DETECT_THRESHOLD) begin
                    ei_cnt <= ei_cnt + 1'b1;
                end
                ei_detect <= (ei_cnt >= EI_DETECT_THRESHOLD - 1);
            end else begin
                ei_cnt    <= 8'd0;
                ei_detect <= 1'b0;
            end
        end
    end

    // =========================================================================
    // RX Beacon detection
    // A beacon is detected when RX exits EI for >= BEACON_DETECT_THRESHOLD
    // clocks while we are in L2 or L3
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            beacon_cnt    <= 16'd0;
            beacon_detect <= 1'b0;
        end else begin
            if (pm_state == PM_L2 || pm_state == PM_L3) begin
                // Look for RX coming out of electrical idle
                if (!pipe_rx_elec_idle) begin
                    if (beacon_cnt < BEACON_DETECT_THRESHOLD) begin
                        beacon_cnt <= beacon_cnt + 1'b1;
                    end
                    beacon_detect <=
                        (beacon_cnt >= BEACON_DETECT_THRESHOLD - 1);
                end else begin
                    beacon_cnt    <= 16'd0;
                    beacon_detect <= 1'b0;
                end
            end else begin
                beacon_cnt    <= 16'd0;
                beacon_detect <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Wake-up request
    // Assert wakeup_req when a beacon is confirmed or when EI exits unexpectedly
    // in a sleep state, which also signals remote wake intent.
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            wakeup_req <= 1'b0;
        end else begin
            if (beacon_detect) begin
                // Beacon detected: request link wake-up
                wakeup_req <= 1'b1;
            end else if (pm_state == PM_L0 || pm_state == PM_L0S) begin
                // Link is active: clear wakeup request
                wakeup_req <= 1'b0;
            end
            // Hold wakeup_req until PM clears it by transitioning to L0
        end
    end

endmodule
