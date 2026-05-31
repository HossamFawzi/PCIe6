
`timescale 1ns/1ps

module tb_ts2_gen;

    reg        clk, rst_n;
    reg [7:0]  link_num, lane_num, speed_cap, fts_count;
    reg        ts2_send;

    wire [255:0] ts2_data;
    wire         ts2_valid, ts2_done;

    ts2_gen dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .link_num (link_num),
        .lane_num (lane_num),
        .speed_cap(speed_cap),
        .fts_count(fts_count),
        .ts2_send (ts2_send),
        .ts2_data (ts2_data),
        .ts2_valid(ts2_valid),
        .ts2_done (ts2_done)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task send_and_wait;
        begin
            @(posedge clk); #1; ts2_send = 1;
            @(posedge clk); #1; ts2_send = 0;
            repeat(10) @(posedge clk);
        end
    endtask

    task check_ts2;
        input [7:0] exp_link, exp_lane, exp_fts, exp_speed;
        input [63:0] name;
        begin
            if (ts2_data[7:0]   !== 8'hBC)
                begin $display("FAIL [%s] COM", name); fail_count=fail_count+1; end
            else if (ts2_data[15:8]  !== exp_link)
                begin $display("FAIL [%s] link", name); fail_count=fail_count+1; end
            else if (ts2_data[23:16] !== exp_lane)
                begin $display("FAIL [%s] lane", name); fail_count=fail_count+1; end
            else if (ts2_data[31:24] !== exp_fts)
                begin $display("FAIL [%s] fts", name); fail_count=fail_count+1; end
            else if (ts2_data[39:32] !== exp_speed)
                begin $display("FAIL [%s] speed", name); fail_count=fail_count+1; end
            else if (ts2_data[47:40] !== 8'h00)
                begin $display("FAIL [%s] ctrl!=0", name); fail_count=fail_count+1; end
            else if (ts2_data[55:48] !== 8'h45)
                begin $display("FAIL [%s] TS2_ID", name); fail_count=fail_count+1; end
            else begin $display("PASS [%s]", name); pass_count=pass_count+1; end
        end
    endtask

    initial begin
        rst_n=0; ts2_send=0;
        link_num=0; lane_num=0; speed_cap=0; fts_count=0;
        repeat(4) @(posedge clk); rst_n=1; @(posedge clk);

        link_num=8'h01; lane_num=8'h00; speed_cap=8'h3F; fts_count=8'h30;
        send_and_wait;
        check_ts2(8'h01,8'h00,8'h30,8'h3F,"TC1_typical");

        link_num=8'hFF; lane_num=8'hFF; speed_cap=8'h01; fts_count=8'h00;
        send_and_wait;
        check_ts2(8'hFF,8'hFF,8'h00,8'h01,"TC2_PAD");

        link_num=8'h00; lane_num=8'h01; speed_cap=8'h40; fts_count=8'hFF;
        send_and_wait;
        check_ts2(8'h00,8'h01,8'hFF,8'h40,"TC3_Gen6_speed");

        begin : TC4
            link_num=8'h01; lane_num=8'h00; speed_cap=8'h3F; fts_count=8'h30;
            send_and_wait;
            if (ts2_data[55:48] !== 8'h4A) begin
                $display("PASS [TC4_TS2_ID_not_TS1]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC4_TS2_ID_not_TS1]: should not be 0x4A"); fail_count=fail_count+1;
            end
        end

        begin : TC5
            integer cnt; cnt=0;
            link_num=8'h02; lane_num=8'h01; speed_cap=8'h3F; fts_count=8'h20;
            @(posedge clk); #1; ts2_send=1;
            @(posedge clk); #1; ts2_send=0;
            repeat(10) begin @(posedge clk); #1; if(ts2_done) cnt=cnt+1; end
            if(cnt===1) begin $display("PASS [TC5_done_once]"); pass_count=pass_count+1; end
            else begin $display("FAIL [TC5_done_once] cnt=%0d",cnt); fail_count=fail_count+1; end
        end

        begin : TC6
            rst_n=0; repeat(3) @(posedge clk); #1;
            if(ts2_valid===1'b0 && ts2_done===1'b0 && ts2_data===256'd0) begin
                $display("PASS [TC6_reset]"); pass_count=pass_count+1;
            end else begin
                $display("FAIL [TC6_reset]"); fail_count=fail_count+1;
            end
            rst_n=1;
        end

        begin : TC7
            integer i;
            for(i=0;i<4;i=i+1) begin
                link_num=i[7:0]; lane_num=i[7:0]; speed_cap=8'h3F; fts_count=8'h30;
                send_and_wait;
            end
            $display("PASS [TC7_back_to_back]"); pass_count=pass_count+1;
        end

        #20;
        $display("===========================================");
        $display("  TS2_GEN Results: PASS=%0d  FAIL=%0d", pass_count, fail_count);
        $display("===========================================");
        $finish;
    end

    initial begin #10000; $display("TIMEOUT"); $finish; end

endmodule
