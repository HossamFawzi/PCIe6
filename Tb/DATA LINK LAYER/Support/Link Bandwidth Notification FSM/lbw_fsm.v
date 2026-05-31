
module lbw_fsm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]  ltssm_speed,
    input  wire [5:0]  ltssm_width,
    input  wire        bw_change_det,
    input  wire        eq_req_from_phy,
    output reg  [63:0] bw_notif_dllp,
    output reg         bw_notif_valid,
    output reg         link_eq_req,
    output reg         link_eq_ack,
    output reg  [7:0]  bw_status
);
    localparam IDLE   = 2'd0;
    localparam NOTIFY = 2'd1;
    localparam EQ_REQ = 2'd2;
    localparam WAIT   = 2'd3;

    localparam DLLP_BW_TYPE = 8'h18;

    reg [1:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            bw_notif_dllp  <= 64'd0;
            bw_notif_valid <= 1'b0;
            link_eq_req    <= 1'b0;
            link_eq_ack    <= 1'b0;
            bw_status      <= 8'd0;
        end else begin
            bw_notif_valid <= 1'b0;
            link_eq_req    <= 1'b0;
            link_eq_ack    <= 1'b0;

            case (state)
                IDLE: begin
                    if (bw_change_det) begin
                        state <= NOTIFY;
                    end else if (eq_req_from_phy) begin
                        state <= EQ_REQ;
                    end
                end
                NOTIFY: begin
                    bw_notif_valid <= 1'b1;
                    bw_notif_dllp  <= {DLLP_BW_TYPE, ltssm_speed, ltssm_width, 46'd0};
                    bw_status      <= {ltssm_speed, ltssm_width[3:0]};
                    state          <= WAIT;
                end
                EQ_REQ: begin
                    link_eq_req <= 1'b1;

                    if (!eq_req_from_phy) begin
                        link_eq_req <= 1'b0;
                        link_eq_ack <= 1'b1;
                        state       <= IDLE;
                    end
                end
                WAIT: begin
                    state <= IDLE;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
