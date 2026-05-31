
`timescale 1ns/1ps

module tb_pcie_msg_hdl;

    reg          clk, rst_n;
    reg  [1023:0] tlp_msg;
    reg           tlp_msg_valid;
    reg  [7:0]    msg_code;

    wire [3:0]    intx_assert;
    wire [3:0]    intx_deassert;
    wire          pme_msg;
    wire [2:0]    err_msg_type;
    wire          err_msg_valid;
    wire [511:0]  vdm_data;
    wire          vdm_valid;
    wire          msg_to_aer;

    pcie_msg_hdl dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_msg(tlp_msg), .tlp_msg_valid(tlp_msg_valid),
        .msg_code(msg_code),
        .intx_assert(intx_assert), .intx_deassert(intx_deassert),
        .pme_msg(pme_msg),
        .err_msg_type(err_msg_type), .err_msg_valid(err_msg_valid),
        .vdm_data(vdm_data), .vdm_valid(vdm_valid),
        .msg_to_aer(msg_to_aer)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task send_msg;
        input [7:0]    code;
        input [1023:0] tlp;
        begin
            @(negedge clk);
            tlp_msg       = tlp;
            msg_code      = code;
            tlp_msg_valid = 1'b1;
            @(posedge clk);
            #1;
            tlp_msg_valid = 1'b0;
        end
    endtask

    task check;
        input         cond;
        input [255:0] name;
        begin
            if (cond) begin
                $display("PASS [%s]", name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [%s]", name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_pcie_msg_hdl.vcd");
        $dumpvars(0, tb_pcie_msg_hdl);

        rst_n = 0; tlp_msg = 0; tlp_msg_valid = 0; msg_code = 0;
        repeat(4) @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        $display("\n--- TEST 1: INTx Assert ---");

        send_msg(8'h20, 1024'h0);
        check(intx_assert === 4'b0001, "TC1a INTA_ASSERT");

        send_msg(8'h21, 1024'h0);
        check(intx_assert === 4'b0010, "TC1b INTB_ASSERT");

        send_msg(8'h22, 1024'h0);
        check(intx_assert === 4'b0100, "TC1c INTC_ASSERT");

        send_msg(8'h23, 1024'h0);
        check(intx_assert === 4'b1000, "TC1d INTD_ASSERT");

        $display("\n--- TEST 2: INTx Deassert ---");

        send_msg(8'h24, 1024'h0);
        check(intx_deassert === 4'b0001, "TC2a INTA_DEASSERT");

        send_msg(8'h25, 1024'h0);
        check(intx_deassert === 4'b0010, "TC2b INTB_DEASSERT");

        send_msg(8'h26, 1024'h0);
        check(intx_deassert === 4'b0100, "TC2c INTC_DEASSERT");

        send_msg(8'h27, 1024'h0);
        check(intx_deassert === 4'b1000, "TC2d INTD_DEASSERT");

        $display("\n--- TEST 3: PME ---");
        send_msg(8'h18, 1024'h0);
        check(pme_msg === 1'b1, "TC3 PME_msg");

        $display("\n--- TEST 4: ERR_COR ---");
        send_msg(8'h30, 1024'h0);
        check(err_msg_valid === 1'b1 && err_msg_type === 3'd0,
              "TC4 ERR_COR type+valid");
        check(msg_to_aer === 1'b1, "TC4 ERR_COR->AER");

        $display("\n--- TEST 5: ERR_NONFATAL ---");
        send_msg(8'h31, 1024'h0);
        check(err_msg_valid === 1'b1 && err_msg_type === 3'd1,
              "TC5 ERR_NONFATAL");

        $display("\n--- TEST 6: ERR_FATAL ---");
        send_msg(8'h33, 1024'h0);
        check(err_msg_valid === 1'b1 && err_msg_type === 3'd2,
              "TC6 ERR_FATAL");

        $display("\n--- TEST 7: VDM with data ---");
        begin : tc7
            reg [1023:0] vdm_tlp;
            reg [511:0]  exp_payload;
            vdm_tlp     = 1024'h0;
            exp_payload = 512'hDEAD_BEEF_CAFE_BABE_1234_5678_9ABC_DEF0;
            vdm_tlp[895:384] = exp_payload;
            send_msg(8'h7F, vdm_tlp);
            check(vdm_valid === 1'b1, "TC7 VDM_valid");
            check(vdm_data  === exp_payload, "TC7 VDM_data");
        end

        $display("\n--- TEST 8: VDM no data ---");
        send_msg(8'h7E, 1024'h0);
        check(vdm_valid === 1'b1 && vdm_data === 512'h0,
              "TC8 VDM_NODATA");

        $display("\n--- TEST 9: SPL -> AER ---");
        send_msg(8'h50, 1024'h0);
        check(msg_to_aer === 1'b1, "TC9 SPL_to_AER");

        $display("\n--- TEST 10: Unknown code -> AER ---");
        send_msg(8'hFF, 1024'h0);
        check(msg_to_aer === 1'b1, "TC10 Unknown_to_AER");

        $display("\n--- TEST 11: Reset clears outputs ---");

        send_msg(8'h18, 1024'h0);
        check(pme_msg === 1'b1, "TC11-pre pme_msg=1");

        rst_n = 0;
        @(posedge clk); #1;
        check(pme_msg       === 1'b0 &&
              intx_assert   === 4'b0  &&
              intx_deassert === 4'b0  &&
              err_msg_valid === 1'b0  &&
              vdm_valid     === 1'b0  &&
              msg_to_aer    === 1'b0,
              "TC11 all_cleared_on_reset");
        rst_n = 1;
        @(posedge clk); #1;

        $display("\n--- TEST 12: No spurious output valid=0 ---");
        @(negedge clk);
        msg_code      = 8'h20;
        tlp_msg       = 1024'h0;
        tlp_msg_valid = 1'b0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        check(intx_assert === 4'b0000, "TC12 No_spurious_INTx");

        $display("\n--- TEST 13: Pulse semantics ---");
        send_msg(8'h18, 1024'h0);
        check(pme_msg === 1'b1, "TC13a pme_msg pulse asserted");

        @(posedge clk); #1;
        check(pme_msg === 1'b0, "TC13b pme_msg pulse cleared");

        repeat(4) @(posedge clk);
        $display("\n========================================");
        $display("  RESULTS:  PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin #200000; $display("TIMEOUT"); $finish; end
endmodule
