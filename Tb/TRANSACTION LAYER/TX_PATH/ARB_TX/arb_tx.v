
module arb_tx (

    input  wire         clk,
    input  wire         rst_n,

    input  wire         req_p_valid,
    input  wire         req_np_valid,
    input  wire [575:0] req_p,
    input  wire [575:0] req_np,

    input  wire         credit_grant_p,
    input  wire         credit_grant_np,

    input  wire         ordering_ok,

    output reg  [575:0] arb_tlp,
    output reg          arb_tlp_valid,
    output reg  [1:0]   arb_type
);

localparam POSTED     = 1'b0;
localparam NON_POSTED = 1'b1;

reg last_granted;

wire can_send_p  = req_p_valid  && credit_grant_p  && ordering_ok;
wire can_send_np = req_np_valid && credit_grant_np && ordering_ok;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        arb_tlp       <= 576'b0;
        arb_tlp_valid <= 1'b0;
        arb_type      <= 2'b00;
        last_granted  <= POSTED;
    end else begin
        arb_tlp_valid <= 1'b0;

        if (!ordering_ok) begin

            arb_tlp_valid <= 1'b0;

        end
        else if (can_send_p && !can_send_np) begin

            arb_tlp       <= req_p;
            arb_tlp_valid <= 1'b1;
            arb_type      <= 2'b00;
            last_granted  <= POSTED;
        end
        else if (!can_send_p && can_send_np) begin

            arb_tlp       <= req_np;
            arb_tlp_valid <= 1'b1;
            arb_type      <= 2'b01;
            last_granted  <= NON_POSTED;
        end
        else if (can_send_p && can_send_np) begin

            if (last_granted == POSTED) begin

                arb_tlp       <= req_np;
                arb_tlp_valid <= 1'b1;
                arb_type      <= 2'b01;
                last_granted  <= NON_POSTED;
            end else begin

                arb_tlp       <= req_p;
                arb_tlp_valid <= 1'b1;
                arb_type      <= 2'b00;
                last_granted  <= POSTED;
            end
        end

    end
end

endmodule
