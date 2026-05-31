`timescale 1ns/1ps
module tb_compliance_eieos_sos_gen;

    reg        clk, rst_n;
    reg        send_ts1, send_ts2, send_fts, send_eios;
    reg        send_eieos, send_sos, send_compliance;
    reg [7:0]  link_num, lane_num;
    reg        gen6_cap, flit_mode_cap, fec_cap;
    wire [255:0] os_data;
    wire         os_valid;
    wire [3:0]   os_type;

    integer pass=0, fail=0;

    compliance_eieos_sos_gen dut(
        .clk(clk), .rst_n(rst_n),
        .send_ts1(send_ts1), .send_ts2(send_ts2),
        .send_fts(send_fts), .send_eios(send_eios),
        .send_eieos(send_eieos), .send_sos(send_sos),
        .send_compliance(send_compliance),
        .link_num(link_num), .lane_num(lane_num),
        .gen6_cap(gen6_cap), .flit_mode_cap(flit_mode_cap), .fec_cap(fec_cap),
        .os_data(os_data), .os_valid(os_valid), .os_type(os_type)
    );

    always #5 clk = ~clk;

    task clr; begin
        send_ts1=0; send_ts2=0; send_fts=0; send_eios=0;
        send_eieos=0; send_sos=0; send_compliance=0;
    end endtask

    task send_os;
        input [6:0] which;
        begin
            clr();
            send_ts1=which[0]; send_ts2=which[1]; send_fts=which[2];
            send_eios=which[3]; send_eieos=which[4]; send_sos=which[5];
            send_compliance=which[6];
            @(posedge clk); #1;
            clr();
        end
    endtask

    localparam [255:0] EIEOS_PAT = {16{16'hFF00}};
    localparam [255:0] SOS_PAT   = {32{8'h1C}};
    localparam [255:0] EIOS_PAT  = {32{8'hBC}};

    initial begin
        clk=0; rst_n=0;
        link_num=8'h01; lane_num=8'h00;
        gen6_cap=1; flit_mode_cap=1; fec_cap=1;
        clr();
        @(posedge clk); @(posedge clk); rst_n=1; @(posedge clk); #1;

        $display("Test 1: EIEOS");
        send_os(7'b010000);
        if (os_valid && os_type==4'd4 && os_data==EIEOS_PAT) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d", os_valid, os_type); fail=fail+1; end

        $display("Test 2: EIOS");
        @(posedge clk); #1;
        send_os(7'b001000);
        if (os_valid && os_type==4'd3 && os_data==EIOS_PAT) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d", os_valid, os_type); fail=fail+1; end

        $display("Test 3: SOS");
        @(posedge clk); #1;
        send_os(7'b100000);
        if (os_valid && os_type==4'd5 && os_data==SOS_PAT) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d data=%h", os_valid, os_type, os_data[255:248]); fail=fail+1; end

        $display("Test 4: FTS");
        @(posedge clk); #1;
        send_os(7'b000100);
        if (os_valid && os_type==4'd2) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d", os_valid, os_type); fail=fail+1; end

        $display("Test 5: Compliance");
        @(posedge clk); #1;
        send_os(7'b1000000);
        if (os_valid && os_type==4'd6) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d", os_valid, os_type); fail=fail+1; end

        $display("Test 6: TS1 link/lane");
        @(posedge clk); #1;
        link_num=8'hAB; lane_num=8'hCD;
        send_os(7'b000001);
        if (os_valid && os_type==4'd0 && os_data[223:216]==8'hAB && os_data[215:208]==8'hCD)
            begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d lnk=%02h ln=%02h", os_valid, os_type,
                             os_data[223:216], os_data[215:208]); fail=fail+1; end

        $display("Test 7: TS2");
        @(posedge clk); #1;
        send_os(7'b000010);
        if (os_valid && os_type==4'd1) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: v=%b t=%0d", os_valid, os_type); fail=fail+1; end

        $display("Test 8: Priority EIEOS > EIOS");
        clr(); send_eieos=1; send_eios=1;
        @(posedge clk); #1; clr();
        if (os_valid && os_type==4'd4) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: t=%0d v=%b", os_type, os_valid); fail=fail+1; end

        $display("Test 9: No output when idle");
        clr(); @(posedge clk); #1; @(posedge clk); #1;
        if (!os_valid) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL: spurious output t=%0d", os_type); fail=fail+1; end

        $display("Test 10: Reset");
        send_sos=1; @(posedge clk); #1;
        rst_n=0; @(posedge clk); #1;
        if (!os_valid && os_data==256'h0) begin $display("PASS"); pass=pass+1; end
        else begin $display("FAIL"); fail=fail+1; end
        rst_n=1; clr();

        $display("\n=== compliance_eieos_sos_gen: %0d PASSED, %0d FAILED ===", pass, fail);
        if (fail==0) $display("ALL TESTS PASSED");
        $finish;
    end

    initial #5000 begin $display("TIMEOUT"); $finish; end
endmodule
