
`timescale 1ns/1ps

module tb_cr_mgr;

reg clk;
reg rst_n;

always #5 clk = ~clk;

initial begin
    clk   = 0;
    rst_n = 0;
    #30;
    rst_n = 1;
end

reg         fc_init_done;
reg  [7:0]  init_ph,   init_nph,  init_cplh;
reg  [11:0] init_pd,   init_npd,  init_cpld;

reg  [7:0]  upd_ph,    upd_nph,   upd_cplh;
reg  [11:0] upd_pd,    upd_npd,   upd_cpld;
reg         upd_valid;

reg         tlp_sent;
reg         tlp_is_np;
reg  [9:0]  tlp_len;

wire        credit_grant_p;
wire        credit_grant_np;
wire        credit_grant_cpl;

wire [7:0]  dbg_ph_avail;
wire [11:0] dbg_pd_avail;
wire [7:0]  dbg_nph_avail;
wire [11:0] dbg_npd_avail;

cr_mgr u_cr_mgr (
    .clk              (clk),
    .rst_n            (rst_n),
    .fc_init_done     (fc_init_done),
    .init_ph          (init_ph),
    .init_pd          (init_pd),
    .init_nph         (init_nph),
    .init_npd         (init_npd),
    .init_cplh        (init_cplh),
    .init_cpld        (init_cpld),
    .upd_ph           (upd_ph),
    .upd_pd           (upd_pd),
    .upd_nph          (upd_nph),
    .upd_npd          (upd_npd),
    .upd_cplh         (upd_cplh),
    .upd_cpld         (upd_cpld),
    .upd_valid        (upd_valid),
    .tlp_sent         (tlp_sent),
    .tlp_is_np        (tlp_is_np),
    .tlp_len          (tlp_len),
    .credit_grant_p   (credit_grant_p),
    .credit_grant_np  (credit_grant_np),
    .credit_grant_cpl (credit_grant_cpl),
    .dbg_ph_avail     (dbg_ph_avail),
    .dbg_pd_avail     (dbg_pd_avail),
    .dbg_nph_avail    (dbg_nph_avail),
    .dbg_npd_avail    (dbg_npd_avail)
);

integer pass_count;
integer fail_count;

task do_init;
    input [7:0]  ph;
    input [11:0] pd;
    input [7:0]  nph;
    input [11:0] npd;
    begin
        @(posedge clk);
        fc_init_done = 0;
        @(posedge clk);
        init_ph      = ph;
        init_pd      = pd;
        init_nph     = nph;
        init_npd     = npd;
        init_cplh    = 8'd16;
        init_cpld    = 12'd64;

        fc_init_done = 1;

        repeat(3) @(posedge clk);
        #1;
    end
endtask

task do_send;
    input        is_np;
    input [9:0]  len;
    begin
        @(posedge clk);
        tlp_sent  = 1;
        tlp_is_np = is_np;
        tlp_len   = len;
        @(posedge clk);
        tlp_sent  = 0;
        repeat(2) @(posedge clk);
        #1;
    end
endtask

task do_update;
    input [7:0]  ph;
    input [11:0] pd;
    input [7:0]  nph;
    input [11:0] npd;
    begin
        @(posedge clk);
        upd_ph    = ph;
        upd_pd    = pd;
        upd_nph   = nph;
        upd_npd   = npd;
        upd_cplh  = 8'd0;
        upd_cpld  = 12'd0;
        upd_valid = 1;
        @(posedge clk);
        upd_valid = 0;
        repeat(2) @(posedge clk);
        #1;
    end
endtask

task check;
    input        got;
    input        expected;
    input [63:0] test_num;
    input [127:0] name;
    begin
        if (got !== expected) begin
            $display("FAIL Test%0d [%s] got=%0d exp=%0d  | ph=%0d pd=%0d nph=%0d npd=%0d",
                test_num, name, got, expected,
                dbg_ph_avail, dbg_pd_avail,
                dbg_nph_avail, dbg_npd_avail);
            fail_count = fail_count + 1;
        end else begin
            $display("PASS Test%0d [%s]  | ph=%0d pd=%0d nph=%0d npd=%0d",
                test_num, name,
                dbg_ph_avail, dbg_pd_avail,
                dbg_nph_avail, dbg_npd_avail);
            pass_count = pass_count + 1;
        end
    end
endtask

initial begin
    pass_count   = 0;
    fail_count   = 0;

    fc_init_done = 0;
    tlp_sent     = 0;
    tlp_is_np    = 0;
    tlp_len      = 0;
    upd_valid    = 0;
    upd_ph=0; upd_pd=0; upd_nph=0; upd_npd=0;
    upd_cplh=0; upd_cpld=0;
    init_ph=0; init_pd=0; init_nph=0; init_npd=0;
    init_cplh=0; init_cpld=0;

    @(posedge rst_n);
    repeat(3) @(posedge clk);

    $display("\n=== TEST 1: Before FC_INIT ? no grants ===");
    check(credit_grant_p,  0, 1, "grant_p before init ");
    check(credit_grant_np, 0, 2, "grant_np before init");

    $display("\n=== TEST 2: After FC_INIT ? grants active ===");
    do_init(8'd16, 12'd64, 8'd8, 12'd32);
    check(credit_grant_p,  1, 3, "grant_p after init  ");
    check(credit_grant_np, 1, 4, "grant_np after init ");

    $display("\n=== TEST 3: Send Posted TLP ? credits decrease ===");
    do_send(1'b0, 10'd4);

    check(dbg_ph_avail,  8'd15,  5, "ph_avail after P TLP");
    check(dbg_pd_avail, 12'd60,  6, "pd_avail after P TLP");

    check(dbg_nph_avail, 8'd8,   7, "nph unchanged       ");
    check(dbg_npd_avail, 12'd32, 8, "npd unchanged       ");

    $display("\n=== TEST 4: Send Non-Posted TLP ? NP credits decrease ===");
    do_send(1'b1, 10'd4);
    check(dbg_nph_avail, 8'd7,   9,  "nph_avail after NP  ");
    check(dbg_npd_avail, 12'd28, 10, "npd_avail after NP  ");

    check(dbg_ph_avail,  8'd15,  11, "ph unchanged        ");

    $display("\n=== TEST 5: Exhaust NPH credits ===");
    repeat(7) do_send(1'b1, 10'd1);

    check(dbg_nph_avail, 8'd0,  12, "nph exhausted       ");

    check(credit_grant_np, 0,   13, "grant_np = 0        ");

    check(credit_grant_p,  1,   14, "grant_p still ok    ");

    $display("\n=== TEST 6: UpdateFC refills credits ===");
    do_update(8'd0, 12'd0, 8'd8, 12'd32);
    check(dbg_nph_avail, 8'd8,  15, "nph refilled        ");

    check(credit_grant_np, 1,   16, "grant_np restored   ");

    $display("\n=== TEST 7: Infinite credits (init=0) ===");
    do_init(8'd0, 12'd0, 8'd0, 12'd0);

    repeat(20) do_send(1'b0, 10'd4);
    check(credit_grant_p,  1, 17, "grant_p infinite    ");
    repeat(20) do_send(1'b1, 10'd4);
    check(credit_grant_np, 1, 18, "grant_np infinite   ");

    $display("\n=== TEST 8: Reset clears everything ===");
    fc_init_done = 0;
    rst_n = 0;
    repeat(3) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);
    #1;
    check(credit_grant_p,  0, 19, "grant_p after rst   ");
    check(credit_grant_np, 0, 20, "grant_np after rst  ");
    check(dbg_ph_avail,    0, 21, "ph=0 after rst      ");
    check(dbg_nph_avail,   0, 22, "nph=0 after rst     ");

    repeat(3) @(posedge clk);
    $display("\n==========================================");
    $display("  RESULTS: %0d PASS  /  %0d FAIL", pass_count, fail_count);
    $display("==========================================\n");
    $finish;
end

initial begin
    $dumpfile("tb_cr_mgr.vcd");
    $dumpvars(0, tb_cr_mgr);
end

initial begin
    #50000;
    $display("TIMEOUT");
    $finish;
end

always @(posedge clk) begin
    if (tlp_sent)
        $display("t=%0t SEND %s len=%0d | ph=%0d pd=%0d nph=%0d npd=%0d",
            $time,
            tlp_is_np ? "NP" : "P ",
            tlp_len,
            dbg_ph_avail, dbg_pd_avail,
            dbg_nph_avail, dbg_npd_avail);

    if (upd_valid)
        $display("t=%0t UPD  ph+%0d pd+%0d nph+%0d npd+%0d",
            $time, upd_ph, upd_pd, upd_nph, upd_npd);
end

endmodule