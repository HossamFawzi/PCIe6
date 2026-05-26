// =============================================================================
// Module  : pipe_interface_ctrl
// Block   : PIPE Interface Controller  (tag: PIPE_CTRL)
// Spec    : PCIe Gen6 PHY ? Link Management  /  PIPE 5.1
//
// Purpose : Central PIPE 5.1 controller.  Manages all PIPE control signals
//           between the digital RTL (LTSSM / link management) and the
//           analog PHY macro (SerDes).
//
// Key responsibilities:
//   ? Drive pipe_powerdown[1:0]  in response to LTSSM state + power requests
//   ? Set  pipe_rate[3:0]        for speed negotiation
//   ? Assert pipe_txdetectrx     to trigger receiver detection
//   ? Assert pipe_txelecidle     to enter Electrical Idle
//   ? Assert pipe_txcompliance   during compliance testing
//   ? Acknowledge pipe_pclkchangeack on pclk rate change
//   ? Drive pipe_width[1:0]      for bus-width negotiation
//
// Interfaces (from HTML reference):
//   Inputs  : pipe_phystatus, pipe_rxvalid, pipe_rxstatus[2:0],
//             ltssm_state[5:0], power_down_req[1:0], clk, rst_n
//   Outputs : pipe_powerdown[1:0], pipe_rate[3:0], pipe_txdetectrx,
//             pipe_txelecidle, pipe_txcompliance, pipe_pclkchangeack,
//             pipe_width[1:0]
// =============================================================================

module pipe_interface_ctrl (
    // ?? Clock & Reset ????????????????????????????????????????????????????????
    input  wire        clk,                    // PIPE / core clock
    input  wire        rst_n,                  // Active-low synchronous reset

    // ?? PIPE Inputs (from analog PHY macro) ??????????????????????????????????
    input  wire        pipe_phystatus,         // PHY operation complete
    input  wire        pipe_rxvalid,           // RX data valid from PHY
    input  wire [2:0]  pipe_rxstatus,          // RX status code from PHY

    // ?? Control Inputs (from LTSSM / link management) ????????????????????????
    input  wire [5:0]  ltssm_state,            // Current LTSSM state
    input  wire [1:0]  power_down_req,         // Requested PIPE power-down level

    // ?? PIPE Outputs (to analog PHY macro) ???????????????????????????????????
    output reg  [1:0]  pipe_powerdown,         // PHY power-down control
    output reg  [3:0]  pipe_rate,              // PHY data rate select
    output reg         pipe_txdetectrx,        // Start receiver detection
    output reg         pipe_txelecidle,        // TX Electrical Idle
    output reg         pipe_txcompliance,      // TX compliance pattern enable
    output reg         pipe_pclkchangeack,     // PCLK change acknowledge
    output reg  [1:0]  pipe_width              // PIPE bus width select
);

    // =========================================================================
    // LTSSM State Encoding (PCIe Base Spec 5.0 §4.2.6 ? 6-bit encoding)
    // =========================================================================
    localparam LTSSM_DETECT_QUIET     = 6'h00;
    localparam LTSSM_DETECT_ACTIVE    = 6'h01;
    localparam LTSSM_POLLING_ACTIVE   = 6'h02;
    localparam LTSSM_POLLING_COMPL    = 6'h03;
    localparam LTSSM_POLLING_CONFIG   = 6'h04;
    localparam LTSSM_CONFIG_LWIDTH    = 6'h05;
    localparam LTSSM_CONFIG_LWIDTH_A  = 6'h06;
    localparam LTSSM_CONFIG_LANE_NUM  = 6'h07;
    localparam LTSSM_CONFIG_LANE_A    = 6'h08;
    localparam LTSSM_CONFIG_COMPLETE  = 6'h09;
    localparam LTSSM_CONFIG_IDLE      = 6'h0A;
    localparam LTSSM_L0               = 6'h10;
    localparam LTSSM_L0S_TX           = 6'h11;
    localparam LTSSM_L0S_RX           = 6'h12;
    localparam LTSSM_L1_ENTRY         = 6'h13;
    localparam LTSSM_L1_IDLE          = 6'h14;
    localparam LTSSM_L2_IDLE          = 6'h15;
    localparam LTSSM_L2_TX_WAKE       = 6'h16;
    localparam LTSSM_RECOVERY_RCVRL0  = 6'h20;
    localparam LTSSM_RECOVERY_RCVRCFG= 6'h21;
    localparam LTSSM_RECOVERY_IDLE    = 6'h22;
    localparam LTSSM_RECOVERY_SPEED   = 6'h23;
    localparam LTSSM_HOT_RESET        = 6'h30;
    localparam LTSSM_DISABLED         = 6'h31;
    localparam LTSSM_LOOPBACK_ENTRY   = 6'h32;
    localparam LTSSM_LOOPBACK_ACTIVE  = 6'h33;
    localparam LTSSM_LOOPBACK_EXIT    = 6'h34;

    // =========================================================================
    // PIPE Power-Down Encoding (PIPE 5.1 Table 5-1)
    // =========================================================================
    localparam PIPE_P0   = 2'b00;  // Fully active
    localparam PIPE_P0S  = 2'b01;  // Beacon / Receiver detect
    localparam PIPE_P1   = 2'b10;  // L1 low power
    localparam PIPE_P2   = 2'b11;  // L2 / L3 powerdown

    // =========================================================================
    // PIPE Rate Encoding (PIPE 5.1)
    // =========================================================================
    localparam RATE_GEN1 = 4'b0001;  //  2.5 GT/s
    localparam RATE_GEN2 = 4'b0010;  //  5.0 GT/s
    localparam RATE_GEN3 = 4'b0100;  //  8.0 GT/s
    localparam RATE_GEN4 = 4'b1000;  // 16.0 GT/s
    localparam RATE_GEN5 = 4'b1001;  // 32.0 GT/s
    localparam RATE_GEN6 = 4'b1010;  // 64.0 GT/s (PAM4)

    // =========================================================================
    // PIPE Width Encoding
    // =========================================================================
    localparam WIDTH_8   = 2'b00;   //  8-bit PIPE bus
    localparam WIDTH_16  = 2'b01;   // 16-bit PIPE bus
    localparam WIDTH_32  = 2'b10;   // 32-bit PIPE bus

    // =========================================================================
    // RxStatus codes (PIPE 5.1 Table 5-4)
    // =========================================================================
    localparam RXST_OK         = 3'b000;
    localparam RXST_SKP_ADD    = 3'b001;
    localparam RXST_SKP_REMOVE = 3'b010;
    localparam RXST_DETECT_OK  = 3'b011;
    localparam RXST_DETECT_NOK = 3'b100;
    localparam RXST_EI         = 3'b101;
    localparam RXST_DISPERR    = 3'b110;
    localparam RXST_SYMBERR    = 3'b111;

    // =========================================================================
    // Internal state for pclk-change handshake
    // =========================================================================
    reg        phystatus_prev;         // previous cycle phystatus
    reg        pclk_change_pending;    // waiting for phystatus to ack

    // =========================================================================
    // 1. Power-down control
    //    Map LTSSM state and power_down_req to the PIPE power-down field
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_powerdown <= PIPE_P0;
        end else begin
            // power_down_req from the link manager overrides LTSSM
            // in non-trivial implementations; here LTSSM state is primary
            case (ltssm_state)
                LTSSM_L0,
                LTSSM_POLLING_ACTIVE,
                LTSSM_POLLING_CONFIG,
                LTSSM_CONFIG_LWIDTH,
                LTSSM_CONFIG_LWIDTH_A,
                LTSSM_CONFIG_LANE_NUM,
                LTSSM_CONFIG_LANE_A,
                LTSSM_CONFIG_COMPLETE,
                LTSSM_CONFIG_IDLE,
                LTSSM_RECOVERY_RCVRL0,
                LTSSM_RECOVERY_RCVRCFG,
                LTSSM_RECOVERY_IDLE,
                LTSSM_RECOVERY_SPEED   : pipe_powerdown <= PIPE_P0;

                LTSSM_DETECT_QUIET,
                LTSSM_DETECT_ACTIVE    : pipe_powerdown <= PIPE_P0S;

                LTSSM_L0S_TX,
                LTSSM_L0S_RX          : pipe_powerdown <= PIPE_P0S;

                LTSSM_L1_ENTRY,
                LTSSM_L1_IDLE         : pipe_powerdown <= PIPE_P1;

                LTSSM_L2_IDLE,
                LTSSM_L2_TX_WAKE,
                LTSSM_HOT_RESET,
                LTSSM_DISABLED        : pipe_powerdown <= PIPE_P2;

                default               : pipe_powerdown <= power_down_req;
            endcase
        end
    end

    // =========================================================================
    // 2. Rate select
    //    Defaults to Gen1 at reset; updated via Recovery.Speed
    // =========================================================================
    // In a full implementation this would be driven by the speed negotiation
    // block (SPD_NEG/SPD_CHG). Here we drive it directly from the LTSSM
    // Recovery.Speed sub-state using an internal register updated externally.
    // For standalone clarity the register is exposed as a combinational decode
    // of ltssm_state; a production block would latch the target speed from
    // the speed-negotiation CSR.
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_rate <= RATE_GEN1;
        end else begin
            // Hold current rate except in Recovery.Speed where it is updated
            if (ltssm_state == LTSSM_RECOVERY_SPEED) begin
                // In a full design: pipe_rate <= target_speed_reg
                // For demonstration: keep current value (speed CSR driven)
                pipe_rate <= pipe_rate;
            end
            // Rate is NOT changed outside of Recovery; hold whatever was set
        end
    end

    // =========================================================================
    // 3. TX Detect Receiver
    //    Assert for one PIPE clock cycle in Detect.Active
    // =========================================================================
    reg detect_triggered;

    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_txdetectrx  <= 1'b0;
            detect_triggered <= 1'b0;
        end else begin
            if (ltssm_state == LTSSM_DETECT_ACTIVE && !detect_triggered) begin
                pipe_txdetectrx  <= 1'b1;
                detect_triggered <= 1'b1;
            end else if (ltssm_state != LTSSM_DETECT_ACTIVE) begin
                pipe_txdetectrx  <= 1'b0;
                detect_triggered <= 1'b0;
            end else begin
                pipe_txdetectrx <= 1'b0; // pulse width = 1 cycle
            end
        end
    end

    // =========================================================================
    // 4. TX Electrical Idle
    //    Assert in any state where the TX lane must not drive signal
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_txelecidle <= 1'b1;
        end else begin
            case (ltssm_state)
                LTSSM_L0,
                LTSSM_POLLING_ACTIVE,
                LTSSM_POLLING_COMPL,
                LTSSM_POLLING_CONFIG,
                LTSSM_CONFIG_LWIDTH,
                LTSSM_CONFIG_LWIDTH_A,
                LTSSM_CONFIG_LANE_NUM,
                LTSSM_CONFIG_LANE_A,
                LTSSM_CONFIG_COMPLETE,
                LTSSM_CONFIG_IDLE,
                LTSSM_RECOVERY_RCVRL0,
                LTSSM_RECOVERY_RCVRCFG,
                LTSSM_RECOVERY_IDLE,
                LTSSM_RECOVERY_SPEED,
                LTSSM_LOOPBACK_ACTIVE  : pipe_txelecidle <= 1'b0;

                default                : pipe_txelecidle <= 1'b1;
            endcase
        end
    end

    // =========================================================================
    // 5. TX Compliance
    //    Assert only in Polling.Compliance (= LTSSM_POLLING_COMPL)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_txcompliance <= 1'b0;
        end else begin
            pipe_txcompliance <=
                (ltssm_state == LTSSM_POLLING_COMPL) ? 1'b1 : 1'b0;
        end
    end

    // =========================================================================
    // 6. PCLK Change Acknowledge
    //    PHY asserts pipe_phystatus on rising edge to signal PCLK change.
    //    We respond with a one-cycle pclkchangeack.
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            phystatus_prev       <= 1'b0;
            pclk_change_pending  <= 1'b0;
            pipe_pclkchangeack   <= 1'b0;
        end else begin
            phystatus_prev <= pipe_phystatus;

            // Rising edge on phystatus (from PIPE rate change) ? ack
            if (pipe_phystatus && !phystatus_prev &&
                ltssm_state == LTSSM_RECOVERY_SPEED) begin
                pclk_change_pending <= 1'b1;
            end

            if (pclk_change_pending) begin
                pipe_pclkchangeack  <= 1'b1;
                pclk_change_pending <= 1'b0;
            end else begin
                pipe_pclkchangeack  <= 1'b0;
            end
        end
    end

    // =========================================================================
    // 7. PIPE Bus Width
    //    Width scales with negotiated speed.
    //    Gen1?2 ? 16-bit, Gen3+ ? 32-bit at 250 MHz PIPE clock
    //    (in a full design this is driven by the speed negotiation block)
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            pipe_width <= WIDTH_16;
        end else begin
            case (pipe_rate)
                RATE_GEN1,
                RATE_GEN2              : pipe_width <= WIDTH_16;
                RATE_GEN3,
                RATE_GEN4,
                RATE_GEN5,
                RATE_GEN6              : pipe_width <= WIDTH_32;
                default                : pipe_width <= WIDTH_32;
            endcase
        end
    end

endmodule
