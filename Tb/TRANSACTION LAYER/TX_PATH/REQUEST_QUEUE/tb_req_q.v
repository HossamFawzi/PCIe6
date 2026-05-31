`timescale 1ns / 1ps

module tb_req_q;

    // ============================================================
    // Parameters & Signals
    // ============================================================
    parameter CLK_PERIOD = 10;
    parameter DEPTH_P    = 16;
    parameter DEPTH_NP   = 16;
    parameter WIDTH      = 576;

    reg              clk;
    reg              rst_n;

    // Inbound
    reg  [WIDTH-1:0] req_in;
    reg              req_valid_in;

    // Flow Control
    reg              credit_grant_p;
    reg              credit_grant_np;

    // Outbound
    wire [WIDTH-1:0] req_out;
    wire             req_valid_out;
    wire [1:0]       req_type_out;

    // Status
    wire             q_full_p;
    wire             q_full_np;
    wire [7:0]       q_occ_p;
    wire [7:0]       q_occ_np;

    // ============================================================
    // DUT Instantiation
    // ============================================================
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

    // ============================================================
    // Clock Generation
    // ============================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ============================================================
    // Test Infrastructure
    // ============================================================
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

    // Helper Task: Push Request
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

    // ============================================================
    // Main Test Sequence
    // ============================================================
    initial begin
        $display("==== TB req_q START ====");
        reset_dut();

        // -------------------------------------------------
        // T1: Basic Routing & Occupancy (Write Phase)
        // -------------------------------------------------
        // Push Posted (Type 1)
        push_req(4'd1, 572'hAAAA);
        #1; 
        check(q_occ_p == 1 && q_occ_np == 0, "Posted Req routed to P-FIFO");

        // Push Non-Posted (Type 0)
        push_req(4'd0, 572'hBBBB);
        #1;
        check(q_occ_p == 1 && q_occ_np == 1, "Non-Posted Req routed to NP-FIFO");

        // -------------------------------------------------
        // T2: Basic Dequeue & Credit Check (Read Phase)
        // -------------------------------------------------
        // Grant credit to P-FIFO ONLY (NP should stay buffered)
        credit_grant_p = 1;
        credit_grant_np = 0;
        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b00 && req_out[15:0] == 16'hAAAA, "Dequeue Posted with Credit");
        check(q_occ_p == 0 && q_occ_np == 1, "P-FIFO empty, NP-FIFO holds data");

        // Grant credit to NP-FIFO
        credit_grant_p = 0;
        credit_grant_np = 1;
        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b01 && req_out[15:0] == 16'hBBBB, "Dequeue Non-Posted with Credit");
        check(q_occ_p == 0 && q_occ_np == 0, "Both FIFOs empty");

        // Remove credits
        credit_grant_np = 0;
        @(posedge clk); #1;

        // -------------------------------------------------
        // T3: Read Priority Arbitration
        // NP has strict priority over P in DUT
        // -------------------------------------------------
        push_req(4'd1, 572'h1001); // Push P   (FIXED HEX FORMAT)
        push_req(4'd2, 572'h2002); // Push NP  (FIXED HEX FORMAT)
        
        // Grant credits to BOTH simultaneously
        credit_grant_p = 1;
        credit_grant_np = 1;
        
        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b01, "Priority Test: NP Dequeued First");
        
        @(posedge clk); #1;
        check(req_valid_out == 1 && req_type_out == 2'b00, "Priority Test: P Dequeued Second");

        // Cleanup
        credit_grant_p = 0;
        credit_grant_np = 0;
        @(posedge clk);

        // -------------------------------------------------
        // T4: Full Flags & Maximum Occupancy
        // -------------------------------------------------
        // Fill P-FIFO completely
        repeat(DEPTH_P) begin
            push_req(4'd1, 572'hFFFF);
        end
        #1;
        check(q_full_p == 1 && q_occ_p == DEPTH_P, "P-FIFO Full Flag asserted correctly");

        // Try to push one more to trigger simulation warning (visual check in console)
        push_req(4'd1, 572'hDEAD); 
        #1;
        check(q_occ_p == DEPTH_P, "P-FIFO ignores writes when full (Overflow Protection)");

        // Drain P-FIFO
        credit_grant_p = 1;
        repeat(DEPTH_P) @(posedge clk);
        credit_grant_p = 0;
        
        #1;
        check(q_occ_p == 0 && q_full_p == 0, "P-FIFO Drained completely");

        // -------------------------------------------------
        // T5: Stall without Credits
        // -------------------------------------------------
        push_req(4'd0, 572'h1234); // Push NP
        credit_grant_np = 0;       // NO credits
        
        @(posedge clk); #1;
        check(req_valid_out == 0 && q_occ_np == 1, "Output stalled correctly when no credits");
        
        // Now grant credit
        credit_grant_np = 1;
        @(posedge clk); #1;
        check(req_valid_out == 1, "Output resumes when credit granted");
        credit_grant_np = 0;

        // -------------------------------------------------
        // End of Simulation
        // -------------------------------------------------
        #20;
        $display("=================================");
        $display("==== RESULTS: PASS=%0d FAIL=%0d ====", pass, fail);
        $display("=================================");
        $finish;
    end

endmodule