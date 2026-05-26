`timescale 1ns/1ps
module tb_pipe_rx_interface_ctrl;

    reg          clk, rst_n;
    reg [255:0]  pipe_rxd;
    reg [31:0]   pipe_rxdatak;
    reg          pipe_rx_valid;
    reg [2:0]    pipe_rx_status;
    reg          pipe_rx_elec_idle;
    reg          pipe_clk;
    reg          pipe_phystatus;
    reg [1:0]    power_down_req;
    reg [3:0]    pipe_rate_req;
    reg          tx_detect_rx_req;
    reg          tx_elec_idle_req;
    reg          tx_compliance_req;
    reg          pclk_change_req;
    reg [1:0]    pipe_width_req;

    wire [1:0]   pipe_powerdown;
    wire [3:0]   pipe_rate;
    wire         pipe_txdetectrx;
    wire         pipe_txelecidle;
    wire         pipe_txcompliance;
    wire         pipe_pclkchangeack;
    wire [1:0]   pipe_width;
    wire [255:0] rx_data;
    wire [31:0]  rx_datak;
    wire         rx_valid;
    wire         rx_elec_idle;
    wire [2:0]   rx_status;
    wire         phystatus_sync;
    wire         pipe_up;
    wire         rate_change_busy;

    integer pass=0, fail=0;

    pipe_rx_interface_ctrl dut(
        .clk(clk), .rst_n(rst_n),
        .pipe_rxd(pipe_rxd), .pipe_rxdatak(pipe_rxdatak),
        .pipe_rx_valid(pipe_rx_valid), .pipe_rx_status(pipe_rx_status),
        .pipe_rx_elec_idle(pipe_rx_elec_idle),
        .pipe_clk(pipe_clk), .pipe_phystatus(pipe_phystatus),
        .power_down_req(power_down_req), .pipe_rate_req(pipe_rate_req),
        .tx_detect_rx_req(tx_detect_rx_req), .tx_elec_idle_req(tx_elec_idle_req),
        .tx_compliance_req(tx_compliance_req), .pclk_change_req(pclk_change_req),
        .pipe_width_req(pipe_width_req),
        .pipe_powerdown(pipe_powerdown), .pipe_rate(pipe_rate),
        .pipe_txdetectrx(pipe_txdetectrx), .pipe_txelecidle(pipe_txelecidle),
        .pipe_txcompliance(pipe_txcompliance), .pipe_pclkchangeack(pipe_pclkchangeack),
        .pipe_width(pipe_width),
        .rx_data(rx_data), .rx_datak(rx_datak),
        .rx_valid(rx_valid), .rx_elec_idle(rx_elec_idle),
        .rx_status(rx_status), .phystatus_sync(phystatus_sync),
        .pipe_up(pipe_up), .rate_change_busy(rate_change_busy)
    );

    always #5  clk      = ~clk;
    always #4  pipe_clk = ~pipe_clk;

    task tick(input integer n); integer i; begin for(i=0;i<n;i=i+1) @(posedge clk); #1; end endtask
    task tick_p(input integer n); integer i; begin for(i=0;i<n;i=i+1) @(posedge pipe_clk); #1; end endtask

    initial begin
        clk=0; pipe_clk=0; rst_n=0;
        pipe_rxd=0; pipe_rxdatak=0; pipe_rx_valid=0;
        pipe_rx_status=3'h0; pipe_rx_elec_idle=1;
        pipe_phystatus=0; power_down_req=2'h0; pipe_rate_req=4'h0;
        tx_detect_rx_req=0; tx_elec_idle_req=0; tx_compliance_req=0;
        pclk_change_req=0; pipe_width_req=2'h2;

        tick(4); rst_n=1; tick(2);

        // Test 1: Reset state - pipe_up should be 0
        $display("Test 1: Reset state");
        if (!pipe_up && !rate_change_busy) begin
            $display("PASS: Reset state correct"); pass=pass+1;
        end else begin
            $display("FAIL: pipe_up=%b busy=%b", pipe_up, rate_change_busy); fail=fail+1;
        end

        // Test 2: Control signals passthrough
        $display("Test 2: Control passthrough");
        power_down_req=2'h1; pipe_rate_req=4'h3;
        tx_elec_idle_req=1; pipe_width_req=2'h1;
        tick(3);
        if (pipe_powerdown==2'h1 && pipe_rate==4'h3 && pipe_txelecidle==1 && pipe_width==2'h1) begin
            $display("PASS: Control signals pass through"); pass=pass+1;
        end else begin
            $display("FAIL: pd=%h rate=%h ei=%b width=%h", pipe_powerdown, pipe_rate, pipe_txelecidle, pipe_width); fail=fail+1;
        end

        // Test 3: RX data latched and forwarded
        $display("Test 3: RX data forwarding");
        pipe_rxd = 256'hDEAD_BEEF;
        pipe_rx_valid=1; pipe_rx_elec_idle=0;
        tick_p(3);
        tick(8); // sync chain
        if (rx_valid) begin
            $display("PASS: RX valid propagated"); pass=pass+1;
        end else begin
            $display("FAIL: rx_valid not asserted after %0d cycles", 8); fail=fail+1;
        end

        // Test 4: pipe_up when valid and not elec idle
        $display("Test 4: pipe_up logic");
        pipe_rx_valid=1; pipe_rx_elec_idle=0;
        tick(8);
        if (pipe_up) begin
            $display("PASS: pipe_up asserted"); pass=pass+1;
        end else begin
            $display("FAIL: pipe_up not set (rx_valid=%b ei=%b)", rx_valid, rx_elec_idle); fail=fail+1;
        end

        // Test 5: pipe_up deasserts on elec_idle
        $display("Test 5: pipe_up deasserts on electrical idle");
        pipe_rx_elec_idle=1;
        tick(8);
        if (!pipe_up) begin
            $display("PASS: pipe_up deasserted on elec_idle"); pass=pass+1;
        end else begin
            $display("FAIL: pipe_up still set on elec_idle"); fail=fail+1;
        end

        // Test 6: Rate change FSM
        $display("Test 6: Rate change FSM");
        power_down_req=2'h0; tx_elec_idle_req=0;
        pipe_rate_req=4'h5;
        pclk_change_req=1;
        tick(3);
        pclk_change_req=0;
        if (rate_change_busy) begin
            $display("  rate_change_busy asserted"); 
            // Assert phystatus to complete handshake
            @(posedge clk); #1; pipe_phystatus=1;
            tick(8);
            if (pipe_pclkchangeack) begin
                $display("  pclkchangeack asserted");
                @(posedge clk); #1; pipe_phystatus=0;
                tick(5);
                if (!rate_change_busy) begin
                    $display("PASS: Rate change FSM complete"); pass=pass+1;
                end else begin
                    $display("FAIL: rate_change_busy not cleared"); fail=fail+1;
                end
            end else begin
                $display("FAIL: pclkchangeack not seen"); fail=fail+1;
            end
        end else begin
            $display("FAIL: rate_change_busy not set"); fail=fail+1;
        end

        // Test 7: phystatus_sync is synchronized
        $display("Test 7: phystatus_sync");
        pipe_phystatus=1;
        tick(5);
        if (phystatus_sync) begin
            $display("PASS: phystatus_sync propagated"); pass=pass+1;
        end else begin
            $display("FAIL: phystatus_sync not seen"); fail=fail+1;
        end
        pipe_phystatus=0;

        // Test 8: tx_detect_rx passthrough
        $display("Test 8: tx_detect_rx passthrough");
        tx_detect_rx_req=1; tick(2);
        if (pipe_txdetectrx) begin
            $display("PASS: txdetectrx"); pass=pass+1;
        end else begin
            $display("FAIL: txdetectrx"); fail=fail+1;
        end
        tx_detect_rx_req=0;

        $display("\n=== pipe_rx_interface_ctrl: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #50000 begin $display("TIMEOUT"); $finish; end
endmodule
