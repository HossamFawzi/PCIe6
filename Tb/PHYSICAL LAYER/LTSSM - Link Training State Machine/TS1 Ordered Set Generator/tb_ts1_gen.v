
`timescale 1ns/1ps

module tb_ts1_gen;

    reg        clk, rst_n;
    reg [7:0]  link_num, lane_num, speed_cap, fts_count;
    reg        ts1_send, compliance_mode;

    wire [255:0] ts1_data;
    wire         ts1_valid, ts1_done;

    ts1_gen dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .link_num       (link_num),
        .lane_num       (lane_num),
        .speed_cap      (speed_cap),
        .fts_count      (fts_count),
        .ts1_send       (ts1_send),
        .compliance_mode(compliance_mode),
        .ts1_data       (ts1_data),
        .ts1_valid      (ts1_valid),
        .ts1_done       (ts1_done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task check;
        input [255:0] got;
        input [7:0]   exp_link, exp_lane, exp_fts, exp_speed;
        input         exp_compliance;
        input [127:0] test_name;
        reg [7:0] ctrl_byte;
        begin
            ctrl_byte = got[47:40];
            if (got[7:0]   !== 8'hBC) begin
                $display("FAIL [%s]: COM symbol wrong. Got 0x%0h", test_name, got[7:0]); fail_count=fail_count+1;
            end else if (got[15:8]  !== exp_link) begin
                $display("FAIL [%s]: Link num wrong. Got 0x%0h exp 0x%0h", test_name, got[15:8], exp_link); fail_count=fail_count+1;
            end else if (got[23:16] !== exp_lane) begin
                $display("FAIL [%s]: Lane num wrong. Got 0x%0h", test_name, got[23:16]); fail_count=fail_count+1;
            end else if (got[31:24] !== exp_fts) begin
                $display("FAIL [%s]: FTS wrong. Got 0x%0h", test_name, got[31:24]); fail_count=fail_count+1;
            end else if (got[39:32] !== exp_speed) begin
                $display("FAIL [%s]: Speed cap wrong. Got 0x%0h", test_name, got[39:32]); fail_count=fail_count+1;
            end else if (ctrl_byte[4] !== exp_compliance) begin
                $display("FAIL [%s]: Compliance bit wrong. Got %0b", test_name, ctrl_byte[4]); fail_count=fail_count+1;
            end else if (got[55:48] !== 8'h4A) begin
                $display("FAIL [%s]: TS1 ID wrong. Got 0x%0h", test_name, got[55:48]); fail_count=fail_count+1;
            end else begin
                $display("PASS [%s]", test_name); pass_count=pass_count+1;
            end
        end
    endtask

    task send_ts1_and_wait;
        begin
            @(posedge clk); #1;
            ts1_send = 1;
            @(posedge clk); #1;
            ts1_send = 0;

            repeat(10) begin
                if (!ts1_done) @(posedge clk);
            end
            @(posedge clk); #1;
        end
    endtask

    initial begin

        rst_n          = 0;
        ts1_send       = 0;
        compliance_mode= 0;
        link_num       = 8'h00;
        lane_num       = 8'h00;
        speed_cap      = 8'h00;
        fts_count      = 8'h00;

        repeat(4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        link_num  = 8'h01; lane_num = 8'h00;
        speed_cap = 8'h3F; fts_count = 8'h30;
        compliance_mode = 0;
        send_ts1_and_wait;
        check(ts1_data, 8'h01, 8'h00, 8'h30, 8'h3F, 1'b0, "TC1_Normal");

        link_num  = 8'hFF; lane_num = 8'hFF;
        speed_cap = 8'h01; fts_count = 8'h00;
        compliance_mode = 0;
        send_ts1_and_wait;
        check(ts1_data, 8'hFF, 8'hFF, 8'h00, 8'h01, 1'b0, "TC2_PAD_link_lane");

        link_num  = 8'h00; lane_num = 8'h00;
        speed_cap = 8'h3F; fts_count = 8'h10;
        compliance_mode = 1;
        send_ts1_and_wait;
        check(ts1_data, 8'h00, 8'h00, 8'h10, 8'h3F, 1'b1, "TC3_Compliance");

        link_num  = 8'h02; lane_num = 8'h01;
        speed_cap = 8'h40; fts_count = 8'hFF;
        compliance_mode = 0;
        send_ts1_and_wait;
        check(ts1_data, 8'h02, 8'h01, 8'hFF, 8'h40, 1'b0, "TC4_Gen6_speed");

        begin : TC5
            integer done_count;
            done_count = 0;
            link_num = 8'h05; lane_num = 8'h03;
            speed_cap = 8'h3F; fts_count = 8'h20;
            compliance_mode = 0;
            @(posedge clk); #1; ts1_send = 1;
            @(posedge clk); #1; ts1_send = 0;
            repeat(10) begin
                @(posedge clk); #1;
                if (ts1_done) done_count = done_count + 1;
            end
            if (done_count === 1) begin
                $display("PASS [TC5_done_pulse_once]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC5_done_pulse_once]: done_count=%0d", done_count); fail_count=fail_count+1;
            end
        end

        begin : TC6
            link_num = 8'h01; lane_num = 8'h00;
            speed_cap = 8'h3F; fts_count = 8'h30;
            compliance_mode = 0;
            send_ts1_and_wait;
            repeat(3) @(posedge clk);
            if (ts1_valid === 1'b0) begin
                $display("PASS [TC6_valid_deasserts]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC6_valid_deasserts]: ts1_valid still high"); fail_count=fail_count+1;
            end
        end

        begin : TC7
            rst_n = 0;
            repeat(3) @(posedge clk); #1;
            if (ts1_valid === 1'b0 && ts1_done === 1'b0 && ts1_data === 256'd0) begin
                $display("PASS [TC7_reset]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC7_reset]"); fail_count=fail_count+1;
            end
            rst_n = 1;
        end

        begin : TC8
            integer i;
            @(posedge clk);
            for (i=0; i<3; i=i+1) begin
                link_num  = i[7:0];
                lane_num  = i[7:0];
                speed_cap = 8'h3F;
                fts_count = 8'h30;
                compliance_mode = 0;
                send_ts1_and_wait;
            end
            $display("PASS [TC8_back_to_back]"); pass_count=pass_count+1;
        end

        #20;
        $display("===========================================");
        $display("  TS1_GEN Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin
        #10000;
        $display("TIMEOUT: simulation exceeded 10us");
        $finish;
    end

endmodule
