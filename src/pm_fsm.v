
module pm_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [2:0]  pm_req_sw,
    input  wire        l0s_timer_exp,
    input  wire        l1_timer_exp,
    input  wire        pm_dllp_valid,
    input  wire [2:0]  pm_dllp_rx,
    output wire [2:0]  link_state,
    output reg  [2:0]  pm_dllp_type,
    output reg         pm_dllp_send,
    output reg  [2:0]  ltssm_pm_req
);

    localparam LS_L0   = 3'd0;
    localparam LS_L0s  = 3'd1;
    localparam LS_L1   = 3'd2;
    localparam LS_L1_1 = 3'd3;
    localparam LS_L1_2 = 3'd4;

    localparam PM_ENTER_L1  = 3'd1;
    localparam PM_ENTER_L23 = 3'd2;
    localparam PM_REQ_ACK   = 3'd3;
    localparam PM_ENTER_L0S = 3'd4;

    reg [2:0] link_state_r;

    assign link_state = ((pm_req_sw == PM_ENTER_L1) && (link_state_r != LS_L1))
                        ? LS_L1 : link_state_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pm_dllp_type <= 3'd0;
            pm_dllp_send <= 1'b0;
            link_state_r <= LS_L0;
            ltssm_pm_req <= 3'd0;
        end else begin
            pm_dllp_send <= 1'b0;

            if (pm_req_sw == PM_ENTER_L1 && link_state_r != LS_L1) begin
                link_state_r <= LS_L1;
                pm_dllp_type <= PM_ENTER_L1;
                pm_dllp_send <= 1'b1;
                ltssm_pm_req <= PM_ENTER_L1;
            end else begin

            case (link_state)
                LS_L0: begin
                    if (pm_req_sw == PM_ENTER_L0S || l0s_timer_exp) begin
                        link_state_r <= LS_L0s;
                        pm_dllp_type <= PM_ENTER_L0S;
                        pm_dllp_send <= 1'b1;
                        ltssm_pm_req <= PM_ENTER_L0S;
                    end else if (pm_req_sw == PM_ENTER_L1 || l1_timer_exp) begin
                        link_state_r <= LS_L1;
                        pm_dllp_type <= PM_ENTER_L1;
                        pm_dllp_send <= 1'b1;
                        ltssm_pm_req <= PM_ENTER_L1;
                    end
                end

                LS_L0s: begin
                    if (pm_dllp_valid && pm_dllp_rx == PM_REQ_ACK)
                        link_state_r <= LS_L0;
                    else if (pm_req_sw == PM_ENTER_L1 || l1_timer_exp) begin
                        link_state_r <= LS_L1;
                        pm_dllp_type <= PM_ENTER_L1;
                        pm_dllp_send <= 1'b1;
                        ltssm_pm_req <= PM_ENTER_L1;
                    end else if (pm_req_sw == 3'd0)
                        link_state_r <= LS_L0;
                end

                LS_L1: begin
                    if (pm_dllp_valid && pm_dllp_rx == PM_ENTER_L23)
                        link_state_r <= LS_L1_2;
                    else if (pm_dllp_valid && pm_dllp_rx == PM_REQ_ACK)
                        link_state_r <= LS_L0;
                    else if (pm_req_sw == 3'd0)
                        link_state_r <= LS_L0;
                end

                LS_L1_1, LS_L1_2: begin
                    if (pm_req_sw == 3'd0)
                        link_state_r <= LS_L0;
                end

                default: link_state_r <= LS_L0;
            endcase
            end
        end
    end
endmodule
