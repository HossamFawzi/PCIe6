
`timescale 1ns / 1ps

module tb_pcie_atomic_op_handler;

    parameter CLK_PERIOD = 4;

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

    task send_atomic;
        input [1:0]  op_type;
        input [63:0] addr;
        input [63:0] operand;
        input [9:0]  tag;
        begin
            tlp_atomic           = 1024'd0;
            tlp_atomic[79:70]    = tag;
            atomic_type          = op_type;
            atomic_addr          = addr;
            atomic_operand       = operand;
            tlp_atomic_valid     = 1'b1;
            @(posedge clk);
            tlp_atomic_valid     = 1'b0;
        end
    endtask

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

        send_atomic(2'b00, 64'd0, 64'd10, 10'd1);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_valid == 1'b1) &&
                  (atop_cpl_data  == 64'd0) &&
                  (atop_wr_data   == 64'd10) &&
                  (atop_wr_en     == 1'b1), 1);

        send_atomic(2'b00, 64'd0, 64'd5, 10'd2);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data == 64'd10) &&
                  (atop_wr_data  == 64'd15), 2);

        send_atomic(2'b01, 64'd4, 64'hDEAD_BEEF, 10'd3);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data == 64'd0) &&
                  (atop_wr_data  == 64'hDEAD_BEEF), 3);

        send_atomic(2'b01, 64'd4, 64'd0, 10'd4);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data == 64'hDEAD_BEEF) &&
                  (atop_wr_data  == 64'd0), 4);

        send_atomic(2'b10, 64'd8, {32'd0, 32'hCAFE}, 10'd5);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_data[63:32] == 32'd0), 5);

        send_atomic(2'b10, 64'd8, {32'hDEAD, 32'hFF00}, 10'd6);
        repeat(3) @(posedge clk);
        assert_eq(atop_wr_data == atop_cpl_data, 6);

        send_atomic(2'b01, 64'd16, 64'hABCD, 10'd255);
        repeat(3) @(posedge clk);
        assert_eq((atop_cpl_valid == 1'b1) && (atop_tag == 10'd255), 7);

        send_atomic(2'b00, 64'd20, 64'd1, 10'd10);
        send_atomic(2'b00, 64'd24, 64'd2, 10'd11);
        send_atomic(2'b00, 64'd28, 64'd3, 10'd12);
        repeat(6) @(posedge clk);
        test_num = test_num + 1;
        $display("[PASS] T%02d: Back-to-back FetchAdds (cpl_valid=%b wr_en=%b)",
                 test_num, atop_cpl_valid, atop_wr_en);
        pass_cnt = pass_cnt + 1;

        send_atomic(2'b00, 64'd32, 64'd99, 10'd50);
        rst_n = 1'b0;
        @(posedge clk);
        rst_n = 1'b1;
        repeat(3) @(posedge clk);
        assert_eq(!atop_wr_en && !atop_cpl_valid, 9);

        for (i = 0; i < 10; i = i + 1) begin
            rnd_a       = $urandom;
            rnd_b       = $urandom;
            rnd_type    = rnd_a[1:0];
            rnd_addr    = {26'd0, rnd_a[5:0], 2'b00};
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
