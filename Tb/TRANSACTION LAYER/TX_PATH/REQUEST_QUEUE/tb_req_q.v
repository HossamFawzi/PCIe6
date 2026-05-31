`timescale 1ns / 1ps

module tb_req_q;

    parameter CLK_PERIOD = 10;
    parameter DEPTH_P    = 16;
    parameter DEPTH_NP   = 16;
    parameter WIDTH      = 576;

    reg              clk;
    reg              rst_n;

    reg  [WIDTH-1:0] req_in;
    reg              req_valid_in;

    reg              credit_grant_p;
    reg              credit_grant_np;

    wire [WIDTH-1:0] req_out;
    wire             req_valid_out;
    wire [1:0]       req_type_out;

    wire             q_full_p;
    wire             q_full_np;
    wire [7:0]       q_occ_p;
    wire [7:0]       q_occ_np;

    req_q #(
        .DEPTH_P(DEPTH_P),
        .DEPTH_NP(DEPTH_NP),
        .WIDTH(WIDTH)
    ) dut (
        .clk(clk),
        .rst_n(rst_n),
        .req_in(req_in),
        .req_valid_in(req_valid_in),
        .credit_grant_p(credit_grant_p),
        .credit_grant_np(credit_grant_np),
        .req_out(req_out),
        .req_valid_out(req_valid_out),
        .req_type_out(req_type_out),
        .q_full_p(q_full_p),
        .q_full_np(q_full_np),
        .q_occ_p(q_occ_p),
        .q_occ_np(q_occ_np)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer pass = 0, fail = 0, test_id = 0;

    task check;
        input boolean_cond;
        input [80*8:1] test_name;
    begin
        test_id = test_id + 1;
        if (boolean_cond) begin
            $display("[PASS] T%0d: %0s", test_id, test_name);
            pass = pass + 1;
        end else begin
            $display("[FAIL] T%0d: %0s", test_id, test_name);
            fail = fail + 1;
        end
    end
    endtask

    task reset_dut;
    begin
        rst_n = 0;
        req_in = 0;
        req_valid_in = 0;
        credit_grant_p = 0;
        credit_grant_np = 0;

        repeat(3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    end
    endtask

    task push_req;
        input [3:0]   rtype;
        input [571:0] rdata;
    begin
        req_in = {rtype, rdata};
        req_valid_in = 1;
        @(posedge clk);
        req_valid_in = 0;
    end
    endtask

    initial begin
        $display("==== TB req_q START ====");
        reset_dut();

        push_req(4'd1, 572'hAAAA);
        #1;
        check(q_occ_p == 1 && q_occ_np == 0, "Posted Req routed to P-FIFO");

        push_req(4'd0, 572'hBBBB);
        #1;
        check(q_occ_p == 1 && q_occ_np == 1, "Non-Posted Req routed to NP-FIFO");

        credit_grant_p = 1;
        credit_grant_np = 0;
        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b00 && req_out[15:0] == 16'hAAAA, "Dequeue Posted with Credit");
        check(q_occ_p == 0 && q_occ_np == 1, "P-FIFO empty, NP-FIFO holds data");

        credit_grant_p = 0;
        credit_grant_np = 1;
        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b01 && req_out[15:0] == 16'hBBBB, "Dequeue Non-Posted with Credit");
        check(q_occ_p == 0 && q_occ_np == 0, "Both FIFOs empty");

        credit_grant_np = 0;
        @(posedge clk); #1;

        push_req(4'd1, 572'h1001);
        push_req(4'd2, 572'h2002);

        credit_grant_p = 1;
        credit_grant_np = 1;

        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b01, "Priority Test: NP Dequeued First");

        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b00, "Priority Test: P Dequeued Second");

        credit_grant_p = 0;
        credit_grant_np = 0;
        @(posedge clk);

        repeat(DEPTH_P) begin
            push_req(4'd1, 572'hFFFF);
        end
        #1;
        check(q_full_p == 1 && q_occ_p == DEPTH_P, "P-FIFO Full Flag asserted correctly");

        push_req(4'd1, 572'hDEAD);
        #1;
        check(q_occ_p == DEPTH_P, "P-FIFO ignores writes when full (Overflow Protection)");

        credit_grant_p = 1;
        repeat(DEPTH_P) @(posedge clk);
        credit_grant_p = 0;

        #1;
        check(q_occ_p == 0 && q_full_p == 0, "P-FIFO Drained completely");

        push_req(4'd0, 572'h1234);
        credit_grant_np = 0;

        @(posedge clk); #1;
        check(req_valid_out == 0 && q_occ_np == 1, "Output stalled correctly when no credits");

        credit_grant_np = 1;
        @(posedge clk); #1;
        check(req_valid_out == 1, "Output resumes when credit granted");
        credit_grant_np = 0;

        #20;
        $display("=================================");
        $display("==== RESULTS: PASS=%0d FAIL=%0d ====", pass, fail);
        $display("=================================");
        $finish;
    end

endmodule