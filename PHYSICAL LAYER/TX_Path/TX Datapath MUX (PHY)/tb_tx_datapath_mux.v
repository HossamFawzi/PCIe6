`timescale 1ns/1ps
module tb_tx_datapath_mux;

    reg          clk, rst_n;
    reg [255:0]  enc_data, os_data;
    reg          enc_valid, os_valid;
    reg [2047:0] flit_data;
    reg          flit_valid, tx_elec_idle, flit_mode_en;
    wire [255:0] tx_out;
    wire         tx_out_valid, tx_elec_idle_out;
    wire [1:0]   mux_sel;

    integer pass=0, fail=0;

    tx_datapath_mux dut(
        .clk(clk), .rst_n(rst_n),
        .enc_data(enc_data), .enc_valid(enc_valid),
        .os_data(os_data), .os_valid(os_valid),
        .flit_data(flit_data), .flit_valid(flit_valid),
        .tx_elec_idle(tx_elec_idle), .flit_mode_en(flit_mode_en),
        .tx_out(tx_out), .tx_out_valid(tx_out_valid),
        .tx_elec_idle_out(tx_elec_idle_out), .mux_sel(mux_sel)
    );

    always #5 clk = ~clk;

    task clr; begin
        enc_valid=0; os_valid=0; flit_valid=0; tx_elec_idle=0; flit_mode_en=0;
    end endtask

    task tick; begin @(posedge clk); #1; end endtask

    initial begin
        clk=0; rst_n=0;
        enc_data=256'hAAAA; os_data=256'hBBBB; flit_data=2048'h0;
        clr();
        @(posedge clk); @(posedge clk); rst_n=1; tick();

        // Test 1: Electrical idle — highest priority
        $display("Test 1: Electrical idle priority");
        enc_valid=1; os_valid=1; flit_valid=1; tx_elec_idle=1; flit_mode_en=1;
        tick(); tick();
        if (tx_out_valid && tx_elec_idle_out && mux_sel==2'd0 && tx_out==256'h0) begin
            $display("PASS: Elec idle wins"); pass=pass+1;
        end else begin
            $display("FAIL: mux_sel=%0d out_valid=%b ei_out=%b", mux_sel, tx_out_valid, tx_elec_idle_out); fail=fail+1;
        end
        clr();

        // Test 2: OS priority over flit/enc
        $display("Test 2: OS over encoded data");
        os_data=256'hDEAD_BEEF; enc_data=256'h1234;
        os_valid=1; enc_valid=1;
        tick(); tick();
        if (tx_out_valid && mux_sel==2'd1 && tx_out==256'hDEAD_BEEF) begin
            $display("PASS: OS wins over enc"); pass=pass+1;
        end else begin
            $display("FAIL: mux_sel=%0d", mux_sel); fail=fail+1;
        end
        clr();

        // Test 3: FLIT mode when flit_mode_en and flit_valid
        $display("Test 3: FLIT mode selection");
        flit_data = {256'hCAFE_FACE, {1792{1'b0}}};
        flit_valid=1; flit_mode_en=1; enc_valid=1; enc_data=256'h1234;
        tick(); tick();
        if (tx_out_valid && mux_sel==2'd3 && tx_out==256'hCAFE_FACE) begin
            $display("PASS: FLIT selected with correct slice"); pass=pass+1;
        end else begin
            $display("FAIL: mux_sel=%0d tx_out=%h", mux_sel, tx_out[255:224]); fail=fail+1;
        end
        clr();

        // Test 4: Encoded data when nothing else active
        $display("Test 4: Encoded data fallback");
        enc_data=256'h5A5A_A5A5;
        enc_valid=1;
        tick(); tick();
        if (tx_out_valid && mux_sel==2'd2 && tx_out==256'h5A5A_A5A5) begin
            $display("PASS: enc selected"); pass=pass+1;
        end else begin
            $display("FAIL: mux_sel=%0d", mux_sel); fail=fail+1;
        end
        clr();

        // Test 5: No valid output when idle
        $display("Test 5: Idle - no output");
        tick(); tick();
        if (!tx_out_valid) begin
            $display("PASS: No output when idle"); pass=pass+1;
        end else begin
            $display("FAIL: Spurious output"); fail=fail+1;
        end

        // Test 6: flit_valid but flit_mode_en=0 -> falls to enc
        $display("Test 6: FLIT ignored when flit_mode_en=0");
        flit_valid=1; flit_mode_en=0; enc_valid=1; enc_data=256'hABCD;
        tick(); tick();
        if (tx_out_valid && mux_sel==2'd2) begin
            $display("PASS: FLIT ignored without flit_mode_en"); pass=pass+1;
        end else begin
            $display("FAIL: mux_sel=%0d", mux_sel); fail=fail+1;
        end
        clr();

        // Test 7: Reset
        $display("Test 7: Reset");
        enc_valid=1; enc_data=256'hFFFF;
        tick();
        rst_n=0; tick();
        if (!tx_out_valid && tx_out==256'h0) begin
            $display("PASS: Reset"); pass=pass+1;
        end else begin
            $display("FAIL: Reset"); fail=fail+1;
        end
        rst_n=1; clr();

        // Test 8: Elec idle output is zero data
        $display("Test 8: Elec idle zeroes tx_out");
        tx_elec_idle=1; enc_data=256'hFFFF; enc_valid=1;
        tick(); tick();
        if (tx_elec_idle_out && tx_out==256'h0) begin
            $display("PASS: Elec idle zeroes data"); pass=pass+1;
        end else begin
            $display("FAIL: tx_out=%h", tx_out[31:0]); fail=fail+1;
        end
        clr();

        $display("\n=== tx_datapath_mux: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #5000 begin $display("TIMEOUT"); $finish; end
endmodule
