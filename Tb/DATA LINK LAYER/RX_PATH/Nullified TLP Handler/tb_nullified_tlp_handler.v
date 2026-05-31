
`timescale 1ns/1ps

module tb_nullified_tlp_handler;

    reg          clk;
    reg          rst_n;
    reg          flit_null;
    reg [1023:0] flit_slot_data;
    reg          flit_slot_valid;

    wire         null_drop;
    wire [7:0]   null_count;

    nullified_tlp_handler dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_null      (flit_null),
        .flit_slot_data (flit_slot_data),
        .flit_slot_valid(flit_slot_valid),
        .null_drop      (null_drop),
        .null_count     (null_count)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task check8;
        input [191:0] label;
        input [7:0]   expected;
        input [7:0]   actual;
        begin
            if (expected === actual) begin
                $display("[PASS] %0s | exp=0x%02h got=0x%02h", label, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | exp=0x%02h got=0x%02h  @%0t", label, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check1;
        input [191:0] label;
        input         expected;
        input         actual;
        begin
            if (expected === actual) begin
                $display("[PASS] %0s | exp=%b got=%b", label, expected, actual);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s | exp=%b got=%b  @%0t", label, expected, actual, $time);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task drive_slot;
        input         is_null;
        input         is_valid;
        input [1023:0] data;
        begin

            @(posedge clk); #1;
            flit_null       <= is_null;
            flit_slot_valid <= is_valid;
            flit_slot_data  <= data;

            @(posedge clk); #1;

            flit_null       <= 1'b0;
            flit_slot_valid <= 1'b0;
            flit_slot_data  <= 1024'b0;
        end
    endtask

    initial begin
        $dumpfile("tb_nullified_tlp_handler.vcd");
        $dumpvars(0, tb_nullified_tlp_handler);

        rst_n           = 1'b0;
        flit_null       = 1'b0;
        flit_slot_data  = 1024'b0;
        flit_slot_valid = 1'b0;
        repeat(4) @(posedge clk);
        #1; rst_n = 1'b1;
        repeat(2) @(posedge clk); #1;

        $display("\n--- TC1: Single null slot ---");
        drive_slot(1'b1, 1'b1, {1024{1'b1}});
        check1("TC1 null_drop",       1'b1, null_drop);
        check8("TC1 null_count == 1", 8'h01, null_count);
        @(posedge clk); #1;

        $display("\n--- TC2: Non-null (real TLP) slot ---");
        drive_slot(1'b0, 1'b1, 1024'hCAFEBABE);
        check1("TC2 null_drop remains 0", 1'b0, null_drop);
        check8("TC2 null_count unchanged", 8'h01, null_count);
        @(posedge clk); #1;

        $display("\n--- TC3: 5 consecutive null slots ---");
        begin : tc3
            integer i;
            for (i = 0; i < 5; i = i + 1) begin
                @(posedge clk); #1;
                flit_null       <= 1'b1;
                flit_slot_valid <= 1'b1;
                flit_slot_data  <= 1024'b0;
            end

            @(posedge clk); #1;

            flit_null       <= 1'b0;
            flit_slot_valid <= 1'b0;
        end

        check8("TC3 null_count == 6", 8'h06, null_count);
        @(posedge clk); #1;

        $display("\n--- TC4: Saturate counter to 0xFF ---");
        begin : tc4
            integer i;

            for (i = 0; i < (8'hFF - 8'h06); i = i + 1) begin
                @(posedge clk); #1;
                flit_null       <= 1'b1;
                flit_slot_valid <= 1'b1;
                flit_slot_data  <= 1024'b0;
            end
            @(posedge clk); #1;
            flit_null       <= 1'b0;
            flit_slot_valid <= 1'b0;
        end
        check8("TC4 null_count == 0xFF", 8'hFF, null_count);
        @(posedge clk); #1;

        drive_slot(1'b1, 1'b1, 1024'b0);
        check8("TC4 null_count saturated", 8'hFF, null_count);
        @(posedge clk); #1;

        $display("\n--- TC5: flit_null=1 but flit_slot_valid=0 ---");
        drive_slot(1'b1, 1'b0 , 1024'b0);
        check1("TC5 null_drop stays 0", 1'b0, null_drop);
        check8("TC5 count unchanged",   8'hFF, null_count);
        @(posedge clk); #1;

        $display("\n--- TC6: Reset clears null_count ---");
        @(posedge clk); #1; rst_n = 1'b0;
        @(posedge clk); #1; rst_n = 1'b1;
        @(posedge clk); #1;
        check8("TC6 null_count == 0 after reset", 8'h00, null_count);
        check1("TC6 null_drop == 0 after reset",  1'b0,  null_drop);

        $display("\n========================================");
        $display("  Nullified TLP Handler TB: %0d PASS / %0d FAIL", pass_count, fail_count);
        $display("========================================\n");
        if (fail_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("SOME TESTS FAILED");
        $finish;
    end

    initial begin
        #200000;
        $display("[TIMEOUT] Testbench exceeded 200 us");
        $finish;
    end

endmodule