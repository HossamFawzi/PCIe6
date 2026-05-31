
module vc_arbiter (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vc0_req,
    input  wire        vc1_req,
    input  wire        vc2_req,
    input  wire        vc3_req,
    input  wire [1:0]  vc_arb_scheme,
    input  wire [31:0] vc_weight,
    output reg  [3:0]  vc_grant,
    output reg  [2:0]  vc_grant_id,
    output reg         vc_arb_valid
);

    wire [3:0] req_bus = {vc3_req, vc2_req, vc1_req, vc0_req};

    reg [1:0]  rr_ptr;
    reg [7:0]  credits [0:3];

    reg [1:0]  rr_winner;
    reg        rr_found;

    integer i;

    always @(*) begin : RR_COMB
        integer j;
        rr_winner = 2'd0;
        rr_found  = 1'b0;
        for (j = 0; j < 4; j = j + 1) begin
            if (!rr_found && req_bus[(rr_ptr+j) % 4]) begin
                rr_winner = (rr_ptr + j) % 4;
                rr_found  = 1'b1;
            end
        end
    end

    reg [1:0]  wrr_winner;
    reg        wrr_found;
    reg        wrr_all_zero;

    always @(*) begin : WRR_COMB
        integer k;
        reg [7:0] best_cred;
        wrr_winner   = 2'd0;
        wrr_found    = 1'b0;
        wrr_all_zero = 1'b1;
        best_cred    = 8'h0;
        for (k = 0; k < 4; k = k + 1) begin
            if (req_bus[k] && credits[k] > 8'h0) begin
                wrr_all_zero = 1'b0;
                if (credits[k] > best_cred) begin
                    best_cred  = credits[k];
                    wrr_winner = k[1:0];
                    wrr_found  = 1'b1;
                end
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vc_grant     <= 4'h0;
            vc_grant_id  <= 3'h0;
            vc_arb_valid <= 1'b0;
            rr_ptr       <= 2'h0;
            for (i = 0; i < 4; i = i + 1)
                credits[i] <= 8'h0;
        end
        else begin
            vc_arb_valid <= 1'b0;
            vc_grant     <= 4'h0;
            vc_grant_id  <= 3'h0;

            if (req_bus != 4'h0) begin
                if (vc_arb_scheme == 2'b00) begin

                    if (rr_found) begin
                        vc_grant     <= 4'h1 << rr_winner;
                        vc_grant_id  <= {1'b0, rr_winner};
                        vc_arb_valid <= 1'b1;
                        rr_ptr       <= (rr_winner + 2'd1) % 4;
                    end
                end
                else begin

                    if (wrr_all_zero) begin

                        credits[0] <= vc_weight[7:0];
                        credits[1] <= vc_weight[15:8];
                        credits[2] <= vc_weight[23:16];
                        credits[3] <= vc_weight[31:24];
                    end
                    else if (wrr_found) begin
                        vc_grant             <= 4'h1 << wrr_winner;
                        vc_grant_id          <= {1'b0, wrr_winner};
                        vc_arb_valid         <= 1'b1;
                        credits[wrr_winner]  <= credits[wrr_winner] - 8'h1;
                    end
                end
            end
        end
    end

endmodule
