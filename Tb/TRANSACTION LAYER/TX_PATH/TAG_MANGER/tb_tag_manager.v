
`timescale 1ns/1ps

module tb_tag_manager;

reg        clk;
reg        rst_n;

reg        tag_req;
reg  [9:0] tag_return;
reg        tag_return_valid;
reg  [9:0] timeout_tag;

wire [9:0]  tag_alloc;
wire        tag_valid;
wire        tag_exhausted;
wire [9:0]  outstanding_count;
wire [63:0] req_addr_lkup;
wire [9:0]  req_len_lkup;
wire [3:0]  req_type_lkup;

tag_manager dut (
    .clk              (clk),
    .rst_n            (rst_n),
    .tag_req          (tag_req),
    .tag_return       (tag_return),
    .tag_return_valid (tag_return_valid),
    .timeout_tag      (timeout_tag),
    .tag_alloc        (tag_alloc),
    .tag_valid        (tag_valid),
    .tag_exhausted    (tag_exhausted),
    .outstanding_count(outstanding_count),
    .req_addr_lkup    (req_addr_lkup),
    .req_len_lkup     (req_len_lkup),
    .req_type_lkup    (req_type_lkup)
);

initial clk = 1'b0;
always  #5 clk = ~clk;

integer fail_count;
reg [9:0] alloc_store [0:15];
integer   k;

task alloc_tag;
    output [9:0] got_tag;
    output       got_valid;
    begin
        @(negedge clk);
        tag_req = 1'b1;

        @(posedge clk); #1;
        got_tag   = tag_alloc;
        got_valid = tag_valid;

        @(negedge clk);
        tag_req = 1'b0;
    end
endtask

task return_tag;
    input [9:0] t;
    begin
        @(negedge clk);
        tag_return       = t;
        tag_return_valid = 1'b1;
        @(negedge clk);
        tag_return_valid = 1'b0;
    end
endtask

task do_timeout;
    input [9:0] t;
    begin
        @(negedge clk);
        timeout_tag = t;
        @(negedge clk);
        timeout_tag = 10'd0;
    end
endtask

reg [9:0] t0, t1, t2, t3;
reg       v0;

initial begin
    fail_count       = 0;
    rst_n            = 1'b0;
    tag_req          = 1'b0;
    tag_return       = 10'd0;
    tag_return_valid = 1'b0;
    timeout_tag      = 10'd0;

    repeat(4) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;
    repeat(2) @(posedge clk);

    $display("\n--- TC1: Single tag allocation ---");
    alloc_tag(t0, v0);
    if (v0 === 1'b1) $display("  PASS [TC1: tag_valid=1]"); else begin $display("  FAIL [TC1: tag_valid=1] @ t=%0t", $time); fail_count = fail_count + 1; end
    if (tag_exhausted === 1'b0) $display("  PASS [TC1: not exhausted]"); else begin $display("  FAIL [TC1: not exhausted] @ t=%0t", $time); fail_count = fail_count + 1; end
    $display("  allocated tag = %0d", t0);

    $display("\n--- TC2: 4 sequential allocations ---");
    alloc_tag(t0, v0);
    if (v0 === 1'b1) $display("  PASS [TC2: alloc 1 valid]"); else begin $display("  FAIL [TC2: alloc 1 valid]"); fail_count = fail_count + 1; end

    alloc_tag(t1, v0);
    if (v0 === 1'b1) $display("  PASS [TC2: alloc 2 valid]"); else begin $display("  FAIL [TC2: alloc 2 valid]"); fail_count = fail_count + 1; end

    alloc_tag(t2, v0);
    if (v0 === 1'b1) $display("  PASS [TC2: alloc 3 valid]"); else begin $display("  FAIL [TC2: alloc 3 valid]"); fail_count = fail_count + 1; end

    alloc_tag(t3, v0);
    if (v0 === 1'b1) $display("  PASS [TC2: alloc 4 valid]"); else begin $display("  FAIL [TC2: alloc 4 valid]"); fail_count = fail_count + 1; end

    if (t0 !== t1) $display("  PASS [TC2: tags unique 0!=1]"); else begin $display("  FAIL [TC2]"); fail_count = fail_count + 1; end
    if (t1 !== t2) $display("  PASS [TC2: tags unique 1!=2]"); else begin $display("  FAIL [TC2]"); fail_count = fail_count + 1; end
    if (t2 !== t3) $display("  PASS [TC2: tags unique 2!=3]"); else begin $display("  FAIL [TC2]"); fail_count = fail_count + 1; end

    $display("\n--- TC3: Return tag, then re-allocate ---");
    alloc_tag(t0, v0);
    if (v0 === 1'b1) $display("  PASS [TC3: alloc ok]"); else begin $display("  FAIL [TC3]"); fail_count = fail_count + 1; end

    $display("  allocated=%0d, returning it", t0);
    return_tag(t0);
    repeat(2) @(posedge clk);

    alloc_tag(t1, v0);
    if (v0 === 1'b1) $display("  PASS [TC3: re-alloc after return ok]"); else begin $display("  FAIL [TC3]"); fail_count = fail_count + 1; end

    $display("\n--- TC4: Reclaim tag via timeout ---");
    alloc_tag(t0, v0);
    if (v0 === 1'b1) $display("  PASS [TC4: alloc ok]"); else begin $display("  FAIL [TC4]"); fail_count = fail_count + 1; end

    $display("  allocated=%0d, timing out", t0);
    do_timeout(t0);
    repeat(2) @(posedge clk);

    alloc_tag(t1, v0);
    if (v0 === 1'b1) $display("  PASS [TC4: alloc after timeout ok]"); else begin $display("  FAIL [TC4]"); fail_count = fail_count + 1; end

    $display("\n--- TC5: tag_req=0, no allocation ---");
    @(negedge clk);
    tag_req = 1'b0;
    @(posedge clk); #1;
    if (tag_valid === 1'b0) $display("  PASS [TC5: tag_valid=0]"); else begin $display("  FAIL [TC5]"); fail_count = fail_count + 1; end

    $display("\n--- TC6: Simultaneous allocate + return ---");
    alloc_tag(t0, v0);

    @(negedge clk);
    tag_req          = 1'b1;
    tag_return       = t0;
    tag_return_valid = 1'b1;

    @(posedge clk); #1;
    if (tag_valid === 1'b1) $display("  PASS [TC6: new tag allocated same cycle as return]");
    else begin $display("  FAIL [TC6] @ t=%0t", $time); fail_count = fail_count + 1; end

    @(negedge clk);
    tag_req          = 1'b0;
    tag_return_valid = 1'b0;

    $display("\n--- TC7: outstanding_count tracking ---");
    @(negedge clk); rst_n = 1'b0;
    repeat(2) @(posedge clk);
    @(negedge clk); rst_n = 1'b1;
    repeat(2) @(posedge clk);

    @(posedge clk); #1;
    if (outstanding_count === 10'd0) $display("  PASS [TC7: count=0 after reset]"); else fail_count = fail_count + 1;

    alloc_tag(t0, v0); @(posedge clk); #1;
    if (outstanding_count === 10'd1) $display("  PASS [TC7: count=1 after 1 alloc]"); else fail_count = fail_count + 1;

    alloc_tag(t1, v0); @(posedge clk); #1;
    if (outstanding_count === 10'd2) $display("  PASS [TC7: count=2 after 2 allocs]"); else fail_count = fail_count + 1;

    return_tag(t0); repeat(3) @(posedge clk); #1;
    if (outstanding_count === 10'd1) $display("  PASS [TC7: count=1 after 1 return]"); else fail_count = fail_count + 1;

    return_tag(t1); repeat(3) @(posedge clk); #1;
    if (outstanding_count === 10'd0) $display("  PASS [TC7: count=0 after all returned]"); else fail_count = fail_count + 1;

    $display("\n--- TC8: Allocate 8 tags, tag_exhausted=0 ---");
    for (k = 0; k < 8; k = k + 1) begin
        alloc_tag(t0, v0);
        alloc_store[k] = t0;
    end
    @(posedge clk); #1;
    if (tag_exhausted === 1'b0) $display("  PASS [TC8: not exhausted with 8 in use]"); else fail_count = fail_count + 1;

    for (k = 0; k < 8; k = k + 1) return_tag(alloc_store[k]);
    repeat(3) @(posedge clk);

    $display("\n--- TC9: Back-to-back alloc/return 8 times ---");
    for (k = 0; k < 8; k = k + 1) begin
        alloc_tag(t0, v0);
        if (v0 === 1'b1) $display("  PASS [TC9: alloc valid cycle %0d]", k); else fail_count = fail_count + 1;
        return_tag(t0);
        repeat(2) @(posedge clk);
    end

    repeat(4) @(posedge clk);
    $display("\n============================================");
    if (fail_count == 0)
        $display("  ALL TESTS PASSED");
    else
        $display("  %0d TEST(S) FAILED", fail_count);
    $display("============================================\n");
    $finish;
end

reg tag_req_d;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) tag_req_d <= 1'b0;
    else        tag_req_d <= tag_req;
end

always @(posedge clk) begin
    if (rst_n && tag_valid && !tag_req_d) begin
        $display("ERROR [sanity] tag_valid=1 without prior tag_req @ t=%0t", $time);
        fail_count = fail_count + 1;
    end
end

always @(posedge clk) begin
    if (rst_n && (outstanding_count == 10'd1023 && !tag_exhausted)) begin
        $display("ERROR [sanity] tag_exhausted should be 1 when outstanding_count hits max @ t=%0t", $time);
    end
end

endmodule