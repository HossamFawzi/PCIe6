
`timescale 1ns/1ps

module tb_pcie_mwr_hdl;

    reg          clk, rst_n;
    reg  [1023:0] tlp_mwr;
    reg           tlp_mwr_valid;
    reg  [63:0]   tlp_addr;
    reg  [9:0]    tlp_len;

    wire [511:0]  mwr_data;
    wire [63:0]   mwr_addr;
    wire [63:0]   mwr_be;
    wire          mwr_valid;
    wire          mwr_full;

    pcie_mwr_hdl dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_mwr(tlp_mwr), .tlp_mwr_valid(tlp_mwr_valid),
        .tlp_addr(tlp_addr), .tlp_len(tlp_len),
        .mwr_data(mwr_data), .mwr_addr(mwr_addr),
        .mwr_be(mwr_be), .mwr_valid(mwr_valid), .mwr_full(mwr_full)
    );

    initial clk = 0;
    always #2 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task build_mwr_tlp;
        input [9:0]   len_dw;
        input [3:0]   f_be;
        input [3:0]   l_be;
        input [63:0]  addr;
        input [511:0] pdata;
        begin
            tlp_mwr          = 1024'h0;
            tlp_mwr[1023:1021] = 3'b011;
            tlp_mwr[1020:1016] = 5'b00000;
            tlp_mwr[1001:992 ] = len_dw;
            tlp_mwr[991:976]   = 16'hABCD;
            tlp_mwr[975:968]   = 8'h01;
            tlp_mwr[967:964]   = l_be;
            tlp_mwr[963:960]   = f_be;
            tlp_mwr[959:928]   = addr[63:32];
            tlp_mwr[927:898]   = addr[31:2];
            tlp_mwr[897:896]   = 2'b00;
            tlp_mwr[895:384]   = pdata;
        end
    endtask

    task send_tlp;
        input [9:0]   len_dw;
        input [3:0]   f_be;
        input [3:0]   l_be;
        input [63:0]  addr;
        input [511:0] pdata;
        begin
            build_mwr_tlp(len_dw, f_be, l_be, addr, pdata);
            tlp_addr      = addr;
            tlp_len       = len_dw;
            tlp_mwr_valid = 1'b1;
            @(posedge clk);
            #1;
            tlp_mwr_valid = 1'b0;
        end
    endtask

    task check_output;
        input [63:0]  exp_addr;
        input [511:0] exp_data;
        input [63:0]  exp_be;
        input [127:0] test_name;
        begin
            if (mwr_valid !== 1'b1) begin
                $display("FAIL [%s] mwr_valid not asserted (=%b)",
                          test_name, mwr_valid);
                fail_count = fail_count + 1;
            end else if (mwr_addr !== exp_addr) begin
                $display("FAIL [%s] addr: exp=%h got=%h",
                          test_name, exp_addr, mwr_addr);
                fail_count = fail_count + 1;
            end else if (mwr_data !== exp_data) begin
                $display("FAIL [%s] data mismatch: exp=%h got=%h",
                          test_name, exp_data[31:0], mwr_data[31:0]);
                fail_count = fail_count + 1;
            end else if (mwr_be !== exp_be) begin
                $display("FAIL [%s] be: exp=%h got=%h",
                          test_name, exp_be, mwr_be);
                fail_count = fail_count + 1;
            end else begin
                $display("PASS [%s]", test_name);
                pass_count = pass_count + 1;
            end
        end
    endtask

    task check;
        input         cond;
        input [127:0] name;
        begin
            if (cond) begin $display("PASS [%s]", name); pass_count=pass_count+1; end
            else      begin $display("FAIL [%s]", name); fail_count=fail_count+1; end
        end
    endtask

    initial begin
        $dumpfile("tb_pcie_mwr_hdl.vcd");
        $dumpvars(0, tb_pcie_mwr_hdl);

        rst_n=0; tlp_mwr=0; tlp_mwr_valid=0; tlp_addr=0; tlp_len=0;
        repeat(4) @(posedge clk); #1;
        rst_n = 1;
        @(posedge clk); #1;

        $display("\n--- TEST 1: Single-DW MWr ---");
        begin : tc1
            reg [511:0] pdata;
            reg [63:0]  exp_be;
            pdata        = 512'h0;
            pdata[511:480] = 32'hCAFEBABE;
            exp_be       = 64'h0000_0000_0000_000F;
            send_tlp(10'd1, 4'hF, 4'h0, 64'hDEADBEEF00001234, pdata);
            check_output(64'hDEADBEEF00001234, pdata, exp_be, "TC1 Single-DW");
        end

        $display("\n--- TEST 2: 4-DW MWr ---");
        begin : tc2
            reg [511:0] pdata;
            reg [63:0]  exp_be;
            pdata          = 512'h0;
            pdata[511:480] = 32'h1111_1111;
            pdata[479:448] = 32'h2222_2222;
            pdata[447:416] = 32'h3333_3333;
            pdata[415:384] = 32'h4444_4444;

            exp_be = 64'h0000_0000_0000_FFFF;
            send_tlp(10'd4, 4'hF, 4'hF, 64'h0000100000000008, pdata);
            check_output(64'h0000100000000008, pdata, exp_be, "TC2 4-DW");
        end

        $display("\n--- TEST 3: Partial byte enables ---");
        begin : tc3
            reg [511:0] pdata;
            reg [63:0]  exp_be;
            pdata          = 512'h0;
            pdata[511:480] = 32'hAAAA_AAAA;
            pdata[479:448] = 32'hBBBB_BBBB;

            exp_be    = 64'h0;
            exp_be[1:0] = 2'b11;
            exp_be[7:6] = 2'b11;
            send_tlp(10'd2, 4'h3, 4'hC, 64'hBEEF0000FEED0100, pdata);
            check_output(64'hBEEF0000FEED0100, pdata, exp_be, "TC3 Partial BE");
        end

        $display("\n--- TEST 4: Reset clears outputs ---");

        check(mwr_valid === 1'b1, "TC4-pre valid=1");
        rst_n = 0;
        @(posedge clk); #1;
        check(mwr_valid === 1'b0, "TC4 Reset clears mwr_valid");
        check(mwr_addr  === 64'h0,"TC4 Reset clears mwr_addr");
        rst_n = 1;
        @(posedge clk); #1;

        $display("\n--- TEST 5: mwr_full asserted after capture ---");
        begin : tc5
            reg [511:0] pdata;
            pdata = 512'hA5A5;
            send_tlp(10'd1, 4'hF, 4'h0, 64'hCAFE_0001, pdata);
            check(mwr_full === 1'b1, "TC5 mwr_full=1 after capture");
            check(mwr_valid=== 1'b1, "TC5 mwr_valid=1 after capture");
        end

        $display("\n--- TEST 6: Consecutive TLPs overwrite ---");
        begin : tc6
            reg [511:0] pdata2;
            pdata2          = 512'h0;
            pdata2[511:480] = 32'hDEAD_DEAD;
            send_tlp(10'd1, 4'hF, 4'h0, 64'hFFFF_2222, pdata2);
            check(mwr_addr === 64'hFFFF_2222, "TC6 addr overwritten");
            check(mwr_data[511:480] === 32'hDEAD_DEAD, "TC6 data overwritten");
        end

        repeat(4) @(posedge clk);
        $display("\n========================================");
        $display("  RESULTS:  PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("========================================\n");
        $finish;
    end

    initial begin #100000; $display("TIMEOUT"); $finish; end
endmodule
