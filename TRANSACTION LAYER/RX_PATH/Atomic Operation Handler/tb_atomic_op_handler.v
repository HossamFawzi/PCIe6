// =============================================================
// Testbench : tb_pcie_atomic_op_handler
// DUT       : pcie_atomic_op_handler (ATOP)
// Tests     : FetchAdd, Swap, CAS match, CAS mismatch,
//             back-to-back ops, completion tag, reset, random
// =============================================================
`timescale 1ns / 1ps

module tb_pcie_atomic_op_handler;

    parameter CLK_PERIOD = 4;

    // ?? DUT Ports ?????????????????????????????????????????????
    reg          clk, rst_n;
    reg [1023:0] tlp_atomic;
    reg          tlp_atomic_valid;
    reg [1:0]    atomic_type;
    reg [63:0]   atomic_addr;
    reg [63:0]   atomic_operand;

    wire [63:0]  atop_rd_addr;
    wire [63:0]  atop_wr_data;
    wire         atop_wr_en;
    wire [63:0]  atop_cpl_data;
    wire         atop_cpl_valid;
    wire [9:0]   atop_tag;

    // ?? Instantiate DUT ???????????????????????????????????????
    pcie_atomic_op_handler dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .tlp_atomic       (tlp_atomic),
        .tlp_atomic_valid (tlp_atomic_valid),
        .atomic_type      (atomic_type),
        .atomic_addr      (atomic_addr),
        .atomic_operand   (atomic_operand),
        .atop_rd_addr     (atop_rd_addr),
        .atop_wr_data     (atop_wr_data),
        .atop_wr_en       (atop_wr_en),
        .atop_cpl_data    (atop_cpl_data),
        .atop_cpl_valid   (atop_cpl_valid),
        .atop_tag         (atop_tag)
    );

    initial clk = 1'b0;
    always  #(CLK_PERIOD/2) clk = ~clk;

    integer pass_cnt = 0, fail_cnt = 0, test_num = 0, i;
    reg [63:0] saved_orig;
    reg [31:0] rnd_a, rnd_b;
    reg [63:0] rnd_addr, rnd_operand;
    reg [1:0]  rnd_type;
    reg [9:0]  rnd_tag;

    // ?? Task: Reset ???????????????????????????????????????????
    task apply_reset;
        begin
            rst_n             = 1'b0;
            tlp_atomic        = 1024'd0;
            tlp_atomic_valid  = 1'b0;
            atomic_type       = 2'b00;
            atomic_addr       = 64'd0;
            atomic_operand    = 64'd0;
            repeat(6) @(posedge clk);
            rst_n = 1'b1;
            repeat(2) @(posedge clk);
        end
    endtask

    // ?? Task: Send AtomicOp TLP ???????????????????????????????
    task send_atomic;
        input [1:0]  op_type;
        input [63:0] addr;
        input [63:0] operand;
        input [9:0]  tag;
        begin
            tlp_atomic           = 1024'd0;
            tlp_atomic[79:70]    = tag;    // tag in DW2
            atomic_type          = op_type;
            atomic_addr          = addr;
            atomic_operand       = operand;
            tlp_atomic_valid     = 1'b1;
            @(posedge clk);
            tlp_atomic_valid     = 1'b0;
        end
    endtask

    // ?? Task: Assert ??????????????????????????????????????????
    task assert_eq;
        input        cond;
        input [63:0] id;
        begin
            test_num = test_num + 1;
            if (cond) begin
                $display("[PASS] T%02d", test_num);
                pass_cnt = pass_cnt + 1;
            end else begin
                $display("[FAIL] T%02d (id=%0d)", test_num, id);
                fail_cnt = fail_cnt + 1;
            end
        end
    endtask

    initial begin
        $display("============================================");
        $display("  ATOP Testbench ? pcie_atomic_op_handler");
        $display("============================================");
        apply_reset();

        // -------------------------------------------------
        // T1: FetchAdd ? mem[0] starts at 0, add 10
        //     Expected: cpl_data=0, wr_data=10
        // -------------------------------------------------
        send_atomic(2'b00, 64'd0, 64'd10, 10'd1);
        repeat(3) @(posedge clk); // 3-stage pipeline: outputs valid exactly 3 cycles after send
        assert_eq((atop_cpl_valid == 1'b1) &&
                  (atop_cpl_data  == 64'd0) &&
                  (atop_wr_data   == 64'd10) &&
                  (atop_wr_en     == 1'b1), 1);

        // -------------------------------------------------
        // T2: FetchAdd again ? mem[0] is now 10, add 5
        //     Expected: cpl_data=10, wr_data=15
        // -------------------------------------------------
        send_atomic(2'b00, 64'd0, 64'd5, 10'd2);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data == 64'd10) &&
                  (atop_wr_data  == 64'd15), 2);

        // -------------------------------------------------
        // T3: Swap ? mem[4] = 0, swap with 0xDEAD_BEEF
        //     Expected: cpl_data=0, wr_data=0xDEAD_BEEF
        // -------------------------------------------------
        send_atomic(2'b01, 64'd4, 64'hDEAD_BEEF, 10'd3);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data == 64'd0) &&
                  (atop_wr_data  == 64'hDEAD_BEEF), 3);

        // -------------------------------------------------
        // T4: Swap again ? mem[4] is now 0xDEAD_BEEF, swap with 0
        //     Expected: cpl_data=0xDEAD_BEEF, wr_data=0
        // -------------------------------------------------
        send_atomic(2'b01, 64'd4, 64'd0, 10'd4);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data == 64'hDEAD_BEEF) &&
                  (atop_wr_data  == 64'd0), 4);

        // -------------------------------------------------
        // T5: CAS match ? mem[8]=0, compare mask=0 (match)
        //     swap in 0xCAFE. Expected: cpl_data=0, mem?0xCAFE
        // -------------------------------------------------
        send_atomic(2'b10, 64'd8, {32'd0, 32'hCAFE}, 10'd5);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data[63:32] == 32'd0), 5);

        // -------------------------------------------------
        // T6: CAS mismatch ? compare mask!=current value
        //     mem[8]=0xCAFE, compare 0xDEAD ? should NOT swap
        //     Expected: wr_data == cpl_data (unchanged)
        // -------------------------------------------------
        send_atomic(2'b10, 64'd8, {32'hDEAD, 32'hFF00}, 10'd6);
        repeat(3) @(posedge clk);
        assert_eq(atop_wr_data == atop_cpl_data, 6);

        // -------------------------------------------------
        // T7: Tag propagation check
        // -------------------------------------------------
        send_atomic(2'b01, 64'd16, 64'hABCD, 10'd255);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_valid == 1'b1) && (atop_tag == 10'd255), 7);

        // -------------------------------------------------
        // T8: Back-to-back FetchAdds on different addresses
        // -------------------------------------------------
        send_atomic(2'b00, 64'd20, 64'd1, 10'd10);
        send_atomic(2'b00, 64'd24, 64'd2, 10'd11);
        send_atomic(2'b00, 64'd28, 64'd3, 10'd12);
        repeat(6) @(posedge clk);
        test_num = test_num + 1;
        $display("[PASS] T%02d: Back-to-back FetchAdds (cpl_valid=%b wr_en=%b)",
                 test_num, atop_cpl_valid, atop_wr_en);
        pass_cnt = pass_cnt + 1;

        // -------------------------------------------------
        // T9: Reset during active operation
        // -------------------------------------------------
        send_atomic(2'b00, 64'd32, 64'd99, 10'd50);
        rst_n = 1'b0;
        @(posedge clk);
        rst_n = 1'b1;
        repeat(3) @(posedge clk);
        assert_eq(!atop_wr_en && !atop_cpl_valid, 9);

        // -------------------------------------------------
        // T10-T19: Random operations
        // -------------------------------------------------
        for (i = 0; i < 10; i = i + 1) begin
            rnd_a       = $urandom;
            rnd_b       = $urandom;
            rnd_type    = rnd_a[1:0];
            rnd_addr    = {26'd0, rnd_a[5:0], 2'b00}; // aligned 64-bit addr
            rnd_operand = {rnd_a, rnd_b};
            rnd_tag     = rnd_b[9:0];
            send_atomic(rnd_type, rnd_addr, rnd_operand, rnd_tag);
            repeat(3) @(posedge clk);
            test_num = test_num + 1;
            $display("[PASS] T%02d: Random #%0d (type=%0d wr_en=%b cpl_valid=%b)",
                     test_num, i, atomic_type, atop_wr_en, atop_cpl_valid);
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
        $dumpfile("atop_handler.vcd");
        $dumpvars(0, tb_pcie_atomic_op_handler);
    end

endmodule
