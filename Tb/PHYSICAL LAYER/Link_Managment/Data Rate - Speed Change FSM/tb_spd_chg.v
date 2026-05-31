
`timescale 1ns/1ps

module tb_spd_chg;

reg        clk;
reg        rst_n;
reg        speed_change_en;
reg  [3:0] target_speed;
reg        recovery_done;
reg  [3:0] pipe_rate;

wire [3:0] pipe_rate_out;
wire       speed_change_done;
wire       speed_change_err;
wire       retrain_req;

spd_chg #(.TIMEOUT_VAL(14'd15)) dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .speed_change_en  (speed_change_en),
    .target_speed     (target_speed),
    .recovery_done    (recovery_done),
    .pipe_rate        (pipe_rate),
    .pipe_rate_out    (pipe_rate_out),
    .speed_change_done(speed_change_done),
    .speed_change_err (speed_change_err),
    .retrain_req      (retrain_req)
);

initial clk = 0;
always #5 clk = ~clk;

task step;
begin
    @(posedge clk); #1;
end
endtask

task do_reset;
begin
    rst_n           = 1'b0;
    speed_change_en = 1'b0;
    target_speed    = 4'd0;
    recovery_done   = 1'b0;
    pipe_rate       = 4'd1;
    repeat(4) @(posedge clk);
    #1; rst_n = 1'b1;
    step;
end
endtask

integer pass_cnt, fail_cnt;

task check;
    input [63:0] actual;
    input [63:0] expected;
    input [127:0] msg;
begin
    if (actual === expected) begin
        $display("  PASS | %0s  actual=%0h  expected=%0h", msg, actual, expected);
        pass_cnt = pass_cnt + 1;
    end else begin
        $display("  FAIL | %0s  actual=%0h  expected=%0h  MISMATCH",
                 msg, actual, expected);
        fail_cnt = fail_cnt + 1;
    end
end
endtask

task do_speed_change;
    input [3:0] tgt;
begin
    target_speed    = tgt;
    pipe_rate       = 4'd1;

    speed_change_en = 1'b1; step; speed_change_en = 1'b0;

    step;
    check(retrain_req,   1,   "p1: retrain_req=1        ");
    check(pipe_rate_out, tgt, "p1: pipe_rate_out=target ");

    recovery_done = 1'b1; step; recovery_done = 1'b0;

    pipe_rate = tgt; step;

    step;
    check(speed_change_done, 1, "p4: speed_change_done=1  ");
    check(speed_change_err,  0, "p4: speed_change_err=0   ");

    step;
    check(speed_change_done, 0, "p5: speed_change_done=0  ");
end
endtask

initial begin
    pass_cnt = 0;
    fail_cnt = 0;

    $display("\n===================================================");
    $display(" TB: spd_chg -- Data Rate / Speed Change FSM");
    $display("===================================================\n");

    $display("--- TEST 1: Reset state ---");
    do_reset;
    check(speed_change_done, 0,    "speed_change_done=0 rst  ");
    check(speed_change_err,  0,    "speed_change_err =0 rst  ");
    check(retrain_req,       0,    "retrain_req      =0 rst  ");
    check(pipe_rate_out,     4'd1, "pipe_rate_out=Gen1 rst   ");

    $display("\n--- TEST 2: Speed change Gen1->Gen3 ---");
    do_reset;
    do_speed_change(4'b0011);

    $display("\n--- TEST 3: Speed change Gen1->Gen6 ---");
    do_reset;
    do_speed_change(4'b0110);

    $display("\n--- TEST 4: Speed change Gen1->Gen5 ---");
    do_reset;
    do_speed_change(4'b0101);

    $display("\n--- TEST 5: Speed change Gen1->Gen2 ---");
    do_reset;
    do_speed_change(4'b0010);

    $display("\n--- TEST 6: Timeout (no recovery_done) ---");
    do_reset;
    target_speed    = 4'b0100;
    pipe_rate       = 4'b0001;

    speed_change_en = 1'b1; step; speed_change_en = 1'b0;

    repeat(18) step;
    check(speed_change_err,  1, "T6: speed_change_err=1   ");
    check(speed_change_done, 0, "T6: speed_change_done=0  ");
    check(pipe_rate_out,  4'd1, "T6: rate reverted Gen1   ");
    step;
    check(speed_change_err,  0, "T6: err de-asserted      ");

    $display("\n--- TEST 7: PHY rate echo mismatch -> timeout ---");
    do_reset;
    target_speed = 4'b0101;
    pipe_rate    = 4'b0001;

    speed_change_en = 1'b1; step; speed_change_en = 1'b0;

    step;

    recovery_done = 1'b1; step; recovery_done = 1'b0;

    repeat(16) step;
    check(speed_change_err,  1, "T7: speed_change_err=1   ");
    check(speed_change_done, 0, "T7: speed_change_done=0  ");

    $display("\n===================================================");
    $display(" Results: %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
    $display("===================================================\n");
    $finish;
end

initial begin
    $dumpfile("spd_chg.vcd");
    $dumpvars(0, tb_spd_chg);
end

endmodule
