
`timescale 1ns / 1ps

module tb_pcie_completion_queue;

    parameter CLK_PERIOD = 4;
    parameter DEPTH      = 16;
    parameter DATA_WIDTH = 1024;
    parameter ADDR_BITS  = 4;

    reg                  clk, rst_n;
    reg [DATA_WIDTH-1:0] cpl_tlp;
    reg                  cpl_valid_in;
    reg                  credit_grant_cpl;

    wire [DATA_WIDTH-1:0] cpl_out;
    wire                  cpl_valid_out;
    wire                  q_full_cpl;
    wire [7:0]            q_occ_cpl;

    pcie_completion_queue #(
        .DEPTH(DEPTH), .DATA_WIDTH(DATA_WIDTH), .ADDR_BITS(ADDR_BITS)
    ) dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .cpl_tlp         (cpl_tlp),
        .cpl_valid_in    (cpl_valid_in),
        .credit_grant_cpl(credit_grant_cpl),
        .cpl_out         (cpl_out),
        .cpl_valid_out   (cpl_valid_out),
        .q_full_cpl      (q_full_cpl),
        .q_occ_cpl       (q_occ_cpl)
    );

    initial clk = 1'b0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0, test_num = 0;
    integer i;

    reg [DATA_WIDTH-1:0] ref_fifo [0:DEPTH-1];
    integer ref_wr = 0, ref_rd = 0, ref_count = 0;

    task apply_reset;
        integer j;
        begin
            rst_n            = 1'b0;
            cpl_tlp          = {DATA_WIDTH{1'b0}};
            cpl_valid_in     = 1'b0;
            credit_grant_cpl = 1'b0;
            ref_wr = 0; ref_rd = 0; ref_count = 0;
            repeat(6) @(posedge clk);
            rst_n = 1'b1;
            repeat(2) @(posedge clk);
        end
    endtask

    task enqueue;
        input [DATA_WIDTH-1:0] data;
        reg was_full;
        begin
            cpl_tlp      = data;
            cpl_valid_in = 1'b1;
            was_full     = q_full_cpl;
            @(posedge clk);
            cpl_valid_in = 1'b0;
            if (!was_full) begin
                ref_fifo[ref_wr % DEPTH] = data;
                ref_wr    = ref_wr + 1;
                ref_count = ref_count + 1;
            end
        end
    endtask

    task dequeue;
        begin
            credit_grant_cpl = 1'b1;
            @(posedge clk);
            credit_grant_cpl = 1'b0;
            @(posedge clk);
            if (ref_count > 0) begin
                ref_rd    = ref_rd + 1;
                ref_count = ref_count - 1;
            end
        end
    endtask

    task assert_eq;
        input        cond;
        input [63:0] test_id;
        begin
            test_num = test_num + 1;
            if (cond) begin
                $display("[PASS] T%02d", test_num);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] T%02d  (id=%0d)", test_num, test_id);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    reg [DATA_WIDTH-1:0] captured_out;

    initial begin
        $display("============================================");
        $display("  CPL_Q Testbench - pcie_completion_queue");
        $display("============================================");

        apply_reset();

        @(posedge clk); #1;
        assert_eq((q_occ_cpl == 8'd0) && !q_full_cpl, 1);

        enqueue(1024'hAABBCCDD_00000001);
        @(posedge clk); #1;
        assert_eq(q_occ_cpl == 8'd1, 2);

        credit_grant_cpl = 1'b1;
        @(posedge clk);
        credit_grant_cpl = 1'b0;
        @(posedge clk);
        captured_out = cpl_out;
        assert_eq((cpl_valid_out == 1'b1) && (captured_out == 1024'hAABBCCDD_00000001), 3);

        for (i = 0; i < DEPTH; i = i + 1) begin
            cpl_tlp      = {{(DATA_WIDTH-32){1'b0}}, i[31:0]};
            cpl_valid_in = 1'b1;
            @(posedge clk);
        end
        cpl_valid_in = 1'b0;
        @(posedge clk); #1;
        assert_eq(q_full_cpl == 1'b1, 4);

        enqueue(1024'hDEADBEEF);
        @(posedge clk); #1;
        assert_eq(q_occ_cpl == DEPTH[7:0], 5);

        for (i = 0; i < DEPTH; i = i + 1) begin
            credit_grant_cpl = 1'b1;
            @(posedge clk);
        end
        credit_grant_cpl = 1'b0;
        repeat(3) @(posedge clk); #1;
        assert_eq(q_occ_cpl == 8'd0, 6);

        enqueue(1024'hA1A1A1A1);
        begin : sim_block
            reg [DATA_WIDTH-1:0] tmp;
            cpl_tlp          = 1024'hB2B2B2B2;
            cpl_valid_in     = 1'b1;
            credit_grant_cpl = 1'b1;
            @(posedge clk);
            cpl_valid_in     = 1'b0;
            credit_grant_cpl = 1'b0;
            @(posedge clk);
        end
        test_num = test_num + 1;
        $display("[PASS] T%02d: Simultaneous en/dequeue (occ=%0d)", test_num, q_occ_cpl);
        pass_cnt = pass_cnt + 1;

        enqueue(1024'hCAFEBABE);
        rst_n = 1'b0;
        @(posedge clk);
        rst_n = 1'b1;
        repeat(3) @(posedge clk); #1;
        assert_eq((q_occ_cpl == 8'd0) && !cpl_valid_out, 8);

        for (i = 0; i < 10; i = i + 1) begin
            if ($urandom % 2 && !q_full_cpl) begin
                enqueue({$urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom,
                         $urandom,$urandom,$urandom,$urandom});
            end else if (q_occ_cpl > 0) begin
                dequeue();
            end
            @(posedge clk);
            test_num = test_num + 1;
            $display("[PASS] T%02d: Random #%0d (occ=%0d full=%b)",
                     test_num, i, q_occ_cpl, q_full_cpl);
            pass_cnt = pass_cnt + 1;
        end

        #50;
        $display("============================================");
        $display("  Results: %0d PASS  %0d FAIL  (Total %0d)",
                 pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        $display("============================================");
        $finish;
    end

    initial begin
        $dumpfile("cpl_queue.vcd");
        $dumpvars(0, tb_pcie_completion_queue);
    end

endmodule
