// ============================================================
// Module 49 : Fundamental Reset FSM (FUND_RST)
// PCIe Gen6 Physical Layer
// Sequences the fundamental reset (PERST#) release.
// Ensures correct power-on reset ordering:
//   PHY first → then DLL → then TL
// ============================================================
module fund_rst (
    input  wire        clk,
    input  wire        rst_n,         // System reset (highest priority)

    // Inputs
    input  wire        perst_n,       // PCIe fundamental reset (active low)
    input  wire        power_good,    // Power rail stable
    input  wire        clk_valid,     // Reference clock valid
    input  wire [15:0] rst_timeout_val,// Timeout between stages

    // Outputs — layered de-assertion (PHY first, DLL second, TL last)
    output reg         sys_rst_n,     // TL reset (de-asserted last)
    output reg         dl_rst_n,      // DLL reset
    output reg         phy_rst_n,     // PHY reset (de-asserted first)
    output reg         rst_done,      // All resets released (pulse)
    output reg [2:0]   rst_seq_state  // Current sequencing state (debug)
);

// Reset sequencing FSM
localparam S_HOLD       = 3'd0;  // All in reset
localparam S_WAIT_PWR   = 3'd1;  // Wait for power_good + clk_valid
localparam S_REL_PHY    = 3'd2;  // Release PHY reset
localparam S_WAIT_PHY   = 3'd3;  // Wait interval before DLL
localparam S_REL_DL     = 3'd4;  // Release DLL reset
localparam S_WAIT_DL    = 3'd5;  // Wait interval before TL
localparam S_REL_SYS    = 3'd6;  // Release TL/system reset
localparam S_DONE       = 3'd7;  // All released

reg [2:0]  state;
reg [15:0] timer;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sys_rst_n     <= 1'b0;
        dl_rst_n      <= 1'b0;
        phy_rst_n     <= 1'b0;
        rst_done      <= 1'b0;
        rst_seq_state <= 3'd0;
        state         <= S_HOLD;
        timer         <= 16'd0;
    end else begin
        rst_done <= 1'b0;

        // PERST# asserted → immediate return to hold
        if (!perst_n) begin
            sys_rst_n <= 1'b0;
            dl_rst_n  <= 1'b0;
            phy_rst_n <= 1'b0;
            state     <= S_HOLD;
            timer     <= 16'd0;
        end else begin
            case (state)
                S_HOLD: begin
                    sys_rst_n     <= 1'b0;
                    dl_rst_n      <= 1'b0;
                    phy_rst_n     <= 1'b0;
                    rst_seq_state <= S_HOLD;
                    if (perst_n)  // perst_n just de-asserted
                        state <= S_WAIT_PWR;
                end

                S_WAIT_PWR: begin
                    rst_seq_state <= S_WAIT_PWR;
                    if (power_good && clk_valid) begin
                        if (!phy_rst_n) begin   // Only sequence if not already released
                            timer <= 16'd0;
                            state <= S_REL_PHY;
                        end
                        // else: all resets already released, stay stable
                    end
                end

                S_REL_PHY: begin
                    phy_rst_n     <= 1'b1;   // Release PHY
                    rst_seq_state <= S_REL_PHY;
                    timer         <= 16'd0;
                    state         <= S_WAIT_PHY;
                end

                S_WAIT_PHY: begin
                    rst_seq_state <= S_WAIT_PHY;
                    if (timer >= rst_timeout_val) begin
                        timer <= 16'd0;
                        state <= S_REL_DL;
                    end else begin
                        timer <= timer + 16'd1;
                    end
                end

                S_REL_DL: begin
                    dl_rst_n      <= 1'b1;   // Release DLL
                    rst_seq_state <= S_REL_DL;
                    timer         <= 16'd0;
                    state         <= S_WAIT_DL;
                end

                S_WAIT_DL: begin
                    rst_seq_state <= S_WAIT_DL;
                    if (timer >= rst_timeout_val) begin
                        timer <= 16'd0;
                        state <= S_REL_SYS;
                    end else begin
                        timer <= timer + 16'd1;
                    end
                end

                S_REL_SYS: begin
                    sys_rst_n     <= 1'b1;   // Release TL
                    rst_seq_state <= S_REL_SYS;
                    state         <= S_DONE;
                end

                S_DONE: begin
                    rst_done      <= 1'b1;
                    rst_seq_state <= S_DONE;
                    state         <= S_WAIT_PWR; // Stay in WAIT_PWR (power still good, clk still valid)
                end

                default: state <= S_HOLD;
            endcase
        end
    end
end

endmodule
