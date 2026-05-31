
module req_q #(
    parameter DEPTH_P  = 16,
    parameter DEPTH_NP = 16,
    parameter WIDTH    = 576
)(

    input  wire             clk,
    input  wire             rst_n,

    input  wire [WIDTH-1:0] req_in,
    input  wire             req_valid_in,

    input  wire             credit_grant_p,
    input  wire             credit_grant_np,

    output reg  [WIDTH-1:0] req_out,
    output reg              req_valid_out,
    output reg  [1:0]       req_type_out,

    output wire             q_full_p,
    output wire             q_full_np,
    output wire [7:0]       q_occ_p,
    output wire [7:0]       q_occ_np
);

reg [WIDTH-1:0] p_mem  [0:DEPTH_P-1];
reg [$clog2(DEPTH_P):0] p_wptr, p_rptr;
wire p_empty  = (p_wptr == p_rptr);
wire p_full_w = ((p_wptr - p_rptr) == DEPTH_P);
assign q_full_p  = p_full_w;
assign q_occ_p   = p_wptr - p_rptr;

reg [WIDTH-1:0] np_mem [0:DEPTH_NP-1];
reg [$clog2(DEPTH_NP):0] np_wptr, np_rptr;
wire np_empty  = (np_wptr == np_rptr);
wire np_full_w = ((np_wptr - np_rptr) == DEPTH_NP);
assign q_full_np = np_full_w;
assign q_occ_np  = np_wptr - np_rptr;

wire [3:0] in_type   = req_in[575:572];
wire       is_posted = (in_type == 4'd1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p_wptr  <= 0;
        np_wptr <= 0;
    end else if (req_valid_in) begin
        if (is_posted && !p_full_w) begin
            p_mem[p_wptr[$clog2(DEPTH_P)-1:0]] <= req_in;
            p_wptr <= p_wptr + 1;
        end else if (!is_posted && !np_full_w) begin
            np_mem[np_wptr[$clog2(DEPTH_NP)-1:0]] <= req_in;
            np_wptr <= np_wptr + 1;
        end

    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p_rptr       <= 0;
        np_rptr      <= 0;
        req_out      <= {WIDTH{1'b0}};
        req_valid_out<= 1'b0;
        req_type_out <= 2'b00;
    end else begin
        req_valid_out <= 1'b0;

        if (!np_empty && credit_grant_np) begin
            req_out       <= np_mem[np_rptr[$clog2(DEPTH_NP)-1:0]];
            req_valid_out <= 1'b1;
            req_type_out  <= 2'b01;
            np_rptr       <= np_rptr + 1;
        end

        else if (!p_empty && credit_grant_p) begin
            req_out       <= p_mem[p_rptr[$clog2(DEPTH_P)-1:0]];
            req_valid_out <= 1'b1;
            req_type_out  <= 2'b00;
            p_rptr        <= p_rptr + 1;
        end
    end
end

always @(posedge clk) begin
    if (rst_n && req_valid_in && is_posted && p_full_w)
        $warning("REQ_Q: Posted FIFO overflow — request dropped!");
    if (rst_n && req_valid_in && !is_posted && np_full_w)
        $warning("REQ_Q: Non-Posted FIFO overflow — request dropped!");
end

endmodule
