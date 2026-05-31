
module fund_rst (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        perst_n,
    input  wire        power_good,
    input  wire        clk_valid,
    input  wire [15:0] rst_timeout_val,

    output reg         sys_rst_n,
    output reg         dl_rst_n,
    output reg         phy_rst_n,
    output reg         rst_done,
    output reg [2:0]   rst_seq_state
);

localparam S_HOLD       = 3'd0;
localparam S_WAIT_PWR   = 3'd1;
localparam S_REL_PHY    = 3'd2;
localparam S_WAIT_PHY   = 3'd3;
localparam S_REL_DL     = 3'd4;
localparam S_WAIT_DL    = 3'd5;
localparam S_REL_SYS    = 3'd6;
localparam S_DONE       = 3'd7;

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
                    if (perst_n)
                        state <= S_WAIT_PWR;
                end

                S_WAIT_PWR: begin
                    rst_seq_state <= S_WAIT_PWR;
                    if (power_good && clk_valid) begin
                        if (!phy_rst_n) begin
                            timer <= 16'd0;
                            state <= S_REL_PHY;
                        end

                    end
                end

                S_REL_PHY: begin
                    phy_rst_n     <= 1'b1;
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
                    dl_rst_n      <= 1'b1;
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
                    sys_rst_n     <= 1'b1;
                    rst_seq_state <= S_REL_SYS;
                    state         <= S_DONE;
                end

                S_DONE: begin
                    rst_done      <= 1'b1;
                    rst_seq_state <= S_DONE;
                    state         <= S_WAIT_PWR;
                end

                default: state <= S_HOLD;
            endcase
        end
    end
end

endmodule
