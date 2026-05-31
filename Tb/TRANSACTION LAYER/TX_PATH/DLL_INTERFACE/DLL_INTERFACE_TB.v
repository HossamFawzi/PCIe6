
module tb_pcie_gen6_dll_if;

    reg               clk_tb;
    reg               rst_n_tb;

    reg  [2047:0]     flit_in_tb;
    reg               flit_valid_in_tb;

    reg               dll_ack_tb;
    reg               dll_nak_tb;
    reg               dll_up_tb;

    reg  [71:0]       cr_update_tb;
    reg               cr_update_valid_tb;

    wire [1023:0]     tlp_rx_out_tb;
    wire              tlp_rx_valid_tb;

    wire [2047:0]     flit_to_dll_tb;
    wire              flit_to_dll_valid_tb;

    wire              dll_ready_tb;

    DLL_IF #(
        .TIMEOUT_MAX (200),
        .RETRY_MAX   (4)
    ) dut (
        .clk               (clk_tb),
        .rst_n             (rst_n_tb),
        .flit_in           (flit_in_tb),
        .flit_valid_in     (flit_valid_in_tb),
        .dll_ack           (dll_ack_tb),
        .dll_nak           (dll_nak_tb),
        .dll_up            (dll_up_tb),
        .cr_update         (cr_update_tb),
        .cr_update_valid   (cr_update_valid_tb),
        .tlp_rx_out        (tlp_rx_out_tb),
        .tlp_rx_valid      (tlp_rx_valid_tb),
        .flit_to_dll       (flit_to_dll_tb),
        .flit_to_dll_valid (flit_to_dll_valid_tb),
        .dll_ready         (dll_ready_tb)
    );

    initial  clk_tb = 1'b0;
    always #5 clk_tb = ~clk_tb;

    integer      error_count;
    integer      send_count;
    reg [2047:0] expected_flit;

    always @(posedge clk_tb) begin
        if (!dll_up_tb && flit_to_dll_valid_tb) begin
            $display("[%0t] ERROR: TX while dll_up=0", $time);
            error_count = error_count + 1;
        end
        if (flit_to_dll_valid_tb) begin
            send_count = send_count + 1;
            if (flit_to_dll_tb !== expected_flit) begin
                $display("[%0t] ERROR: FLIT mismatch got=%0h exp=%0h",
                    $time, flit_to_dll_tb[31:0], expected_flit[31:0]);
                error_count = error_count + 1;
            end
            else begin
                $display("[%0t] INFO : FLIT #%0d sent correctly",
                    $time, send_count);
            end
        end
    end

    task send_flit;
        input [2047:0] flit;
        begin
            @(posedge clk_tb); #1;
            flit_in_tb       = flit;
            flit_valid_in_tb = 1'b1;
            @(posedge clk_tb); #1;
            flit_valid_in_tb = 1'b0;
        end
    endtask

    task pulse_ack;
        begin
            @(posedge clk_tb); #1;
            dll_ack_tb = 1'b1;
            @(posedge clk_tb); #1;
            dll_ack_tb = 1'b0;
        end
    endtask

    task pulse_nak;
        begin
            @(posedge clk_tb); #1;
            dll_nak_tb = 1'b1;
            @(posedge clk_tb); #1;
            dll_nak_tb = 1'b0;
        end
    endtask

    initial begin

        rst_n_tb           = 1'b0;
        flit_in_tb         = 2048'h0;
        flit_valid_in_tb   = 1'b0;
        dll_ack_tb         = 1'b0;
        dll_nak_tb         = 1'b0;
        dll_up_tb          = 1'b0;
        cr_update_tb       = 72'h0;
        cr_update_valid_tb = 1'b0;
        error_count        = 0;
        send_count         = 0;
        expected_flit      = 2048'h0;

        repeat(4) @(posedge clk_tb);
        #1 rst_n_tb = 1'b1;
        repeat(2) @(posedge clk_tb);

        $display("");
        $display("[%0t] ===== TEST 1: Link-Up =====", $time);

        @(posedge clk_tb); #1;
        dll_up_tb = 1'b1;
        @(posedge clk_tb); #1;

        if (!dll_ready_tb) begin
            $display("[%0t] ERROR: dll_ready not set after dll_up=1", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : dll_ready=1 when dll_up=1", $time);
        end

        $display("");
        $display("[%0t] ===== TEST 2: Normal TX + ACK =====", $time);

        send_count    = 0;
        expected_flit = 2048'hAAAA;

        send_flit(expected_flit);
        repeat(3) @(posedge clk_tb);
        pulse_ack;
        repeat(2) @(posedge clk_tb);

        if (send_count !== 1) begin
            $display("[%0t] ERROR: Test2 - expected 1 send, got %0d",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test2 - Normal TX OK (sends=%0d)",
                $time, send_count);
        end

        $display("");
        $display("[%0t] ===== TEST 3: NAK + Replay =====", $time);

        send_count    = 0;
        expected_flit = 2048'hBBBB;

        send_flit(expected_flit);
        repeat(3) @(posedge clk_tb);
        pulse_nak;
        repeat(4) @(posedge clk_tb);
        pulse_ack;
        repeat(2) @(posedge clk_tb);

        if (send_count < 2) begin
            $display("[%0t] ERROR: Test3 - replay did not occur (sends=%0d)",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test3 - NAK replay OK (sends=%0d)",
                $time, send_count);
        end

        $display("");
        $display("[%0t] ===== TEST 4: Timeout Replay =====", $time);
        $display("[%0t] INFO : Waiting 2200ns for TIMEOUT_MAX=200 cycles...",
            $time);

        send_count    = 0;
        expected_flit = 2048'hCCCC;

        send_flit(expected_flit);

        #2200;

        pulse_ack;
        repeat(2) @(posedge clk_tb);

        if (send_count < 2) begin
            $display("[%0t] ERROR: Test4 - timeout replay failed (sends=%0d)",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test4 - Timeout replay OK (sends=%0d)",
                $time, send_count);
        end

        $display("");
        $display("[%0t] ===== TEST 5: Link-Down Protection =====", $time);

        send_count = 0;

        @(posedge clk_tb); #1;
        dll_up_tb = 1'b0;
        repeat(2) @(posedge clk_tb);

        @(posedge clk_tb); #1;
        flit_in_tb       = 2048'hDDDD;
        flit_valid_in_tb = 1'b1;
        @(posedge clk_tb); #1;
        flit_valid_in_tb = 1'b0;

        repeat(5) @(posedge clk_tb);

        if (send_count !== 0) begin
            $display("[%0t] ERROR: Test5 - TX during link-down (sends=%0d)",
                $time, send_count);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test5 - No TX during link-down", $time);
        end

        $display("");
        $display("[%0t] ===== TEST 6: Credit-Update RX Path =====", $time);

        dll_up_tb = 1'b1;

        @(posedge clk_tb); #1;
        cr_update_tb       = 72'hDEAD_BEEF_0000_0000_00;
        cr_update_valid_tb = 1'b1;

        @(posedge clk_tb); #1;
        cr_update_valid_tb = 1'b0;

        if (!tlp_rx_valid_tb) begin
            $display("[%0t] ERROR: Test6 - tlp_rx_valid not set", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] PASS : Test6 - tlp_rx_valid=1 data[31:0]=%0h",
                $time, tlp_rx_out_tb[31:0]);
        end

        repeat(3) @(posedge clk_tb);

        $display("");
        $display("====================================");
        if (error_count == 0)
            $display("TEST PASSED SUCCESSFULLY  (errors=0)");
        else
            $display("TEST FAILED  Errors = %0d", error_count);
        $display("====================================");
        $display("");

        #20 $stop;
    end

endmodule