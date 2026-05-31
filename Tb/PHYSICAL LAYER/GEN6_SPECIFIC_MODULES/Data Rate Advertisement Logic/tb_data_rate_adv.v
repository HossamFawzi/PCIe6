
`timescale 1ns/1ps

module tb_data_rate_adv;

    reg        clk, rst_n;
    reg [7:0]  local_speed_cap;
    reg [7:0]  target_speed_req;
    reg [7:0]  partner_speed_cap;
    reg        partner_cap_valid;

    wire [7:0] adv_speed_cap;
    wire [7:0] negotiated_speed;
    wire [2:0] negotiated_gen;
    wire       negotiation_done;
    wire       speed_change_req;

    data_rate_adv dut (
        .clk              (clk),
        .rst_n            (rst_n),
        .local_speed_cap  (local_speed_cap),
        .target_speed_req (target_speed_req),
        .partner_speed_cap(partner_speed_cap),
        .partner_cap_valid(partner_cap_valid),
        .adv_speed_cap    (adv_speed_cap),
        .negotiated_speed (negotiated_speed),
        .negotiated_gen   (negotiated_gen),
        .negotiation_done (negotiation_done),
        .speed_change_req (speed_change_req)
    );

    initial clk = 0;
    always  #5 clk = ~clk;

    integer pass_count = 0;
    integer fail_count = 0;

    task do_reset;
        begin
            rst_n             = 0;
            local_speed_cap   = 8'h00;
            partner_speed_cap = 8'h00;
            partner_cap_valid = 0;
            target_speed_req  = 8'h00;
            repeat(4) @(posedge clk);
            #1; rst_n = 1;
            @(posedge clk); #1;
        end
    endtask

    task run_negotiation;
        input [7:0] local_cap;
        input [7:0] partner_cap;
        input [7:0] target;
        begin
            local_speed_cap   = local_cap;
            partner_speed_cap = partner_cap;
            target_speed_req  = target;
            partner_cap_valid = 0;

            @(posedge clk); #1;
            partner_cap_valid = 1;
            @(posedge clk); #1;
            partner_cap_valid = 0;

            begin : WAIT_DONE
                integer i;
                for (i = 0; i < 20; i = i + 1) begin
                    @(posedge clk); #1;
                    if (negotiation_done) disable WAIT_DONE;
                end
            end
        end
    endtask

    initial begin

        do_reset;
        run_negotiation(8'h3F, 8'h3F, 8'h00);
        if (negotiation_done && negotiated_gen === 3'd6 &&
            negotiated_speed[5] === 1'b1) begin
            $display("PASS [TC1_both_gen6]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC1_both_gen6] gen=%0d speed=0x%h done=%b",
                     negotiated_gen, negotiated_speed, negotiation_done);
            fail_count = fail_count + 1;
        end

        do_reset;
        run_negotiation(8'h3F, 8'h01, 8'h00);
        if (negotiation_done && negotiated_gen === 3'd1 &&
            negotiated_speed === 8'h01) begin
            $display("PASS [TC2_partner_gen1_fallback]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC2_partner_gen1_fallback] gen=%0d speed=0x%h",
                     negotiated_gen, negotiated_speed);
            fail_count = fail_count + 1;
        end

        do_reset;
        run_negotiation(8'h3F, 8'h1F, 8'h00);
        if (negotiation_done && negotiated_gen === 3'd5) begin
            $display("PASS [TC3_gen5_common]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC3_gen5_common] gen=%0d", negotiated_gen);
            fail_count = fail_count + 1;
        end

        do_reset;
        run_negotiation(8'h3F, 8'h3F, 8'h08);
        if (negotiation_done && negotiated_gen === 3'd4) begin
            $display("PASS [TC4_target_cap_gen4]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC4_target_cap_gen4] gen=%0d", negotiated_gen);
            fail_count = fail_count + 1;
        end

        do_reset;
        run_negotiation(8'h3F, 8'h3F, 8'h02);
        if (negotiation_done && negotiated_gen === 3'd2) begin
            $display("PASS [TC5_target_gen2]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC5_target_gen2] gen=%0d", negotiated_gen);
            fail_count = fail_count + 1;
        end

        do_reset;
        local_speed_cap   = 8'h3F;
        partner_cap_valid = 0;
        @(posedge clk); #1; @(posedge clk); #1;
        if (adv_speed_cap === 8'h3F) begin
            $display("PASS [TC6_adv_reflects_local]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC6_adv_reflects_local] adv=0x%h", adv_speed_cap);
            fail_count = fail_count + 1;
        end

        do_reset;
        run_negotiation(8'h3F, 8'h3F, 8'h00);

        do_reset;
        begin : TC7_SAMPLE
            integer saw_req;
            saw_req = 0;
            local_speed_cap   = 8'h3F;
            partner_speed_cap = 8'h3F;
            target_speed_req  = 8'h00;
            partner_cap_valid = 0;
            @(posedge clk); #1;
            partner_cap_valid = 1;
            @(posedge clk); #1;
            partner_cap_valid = 0;
            repeat(10) begin
                @(posedge clk); #1;
                if (speed_change_req) saw_req = 1;
                if (negotiation_done) disable TC7_SAMPLE;
            end
            if (saw_req) begin
                $display("PASS [TC7_speed_change_req]");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [TC7_speed_change_req]");
                fail_count = fail_count + 1;
            end
        end

        do_reset;
        begin : TC8_SAMPLE
            integer saw_req;
            saw_req = 0;
            local_speed_cap   = 8'h01;
            partner_speed_cap = 8'h01;
            target_speed_req  = 8'h00;
            partner_cap_valid = 0;
            @(posedge clk); #1;
            partner_cap_valid = 1;
            @(posedge clk); #1;
            partner_cap_valid = 0;
            repeat(10) begin
                @(posedge clk); #1;
                if (speed_change_req) saw_req = 1;
                if (negotiation_done) disable TC8_SAMPLE;
            end
            if (!saw_req) begin
                $display("PASS [TC8_gen1_no_speed_req]");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [TC8_gen1_no_speed_req] speed_change_req was asserted");
                fail_count = fail_count + 1;
            end
        end

        do_reset;
        begin : TC9
            integer cnt;
            cnt = 0;
            local_speed_cap   = 8'h3F;
            partner_speed_cap = 8'h3F;
            target_speed_req  = 8'h00;
            partner_cap_valid = 0;
            @(posedge clk); #1;
            partner_cap_valid = 1;
            @(posedge clk); #1;
            partner_cap_valid = 0;
            repeat(20) begin
                @(posedge clk); #1;
                if (negotiation_done) cnt = cnt + 1;
            end
            if (cnt === 1) begin
                $display("PASS [TC9_done_pulse_once]");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [TC9_done_pulse_once] cnt=%0d", cnt);
                fail_count = fail_count + 1;
            end
        end

        do_reset;
        begin : TC10
            local_speed_cap   = 8'h00;
            partner_speed_cap = 8'h3F;
            partner_cap_valid = 1;
            repeat(15) @(posedge clk); #1;
            partner_cap_valid = 0;
            if (!negotiation_done && negotiated_gen === 3'd0) begin
                $display("PASS [TC10_no_local_no_neg]");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [TC10_no_local_no_neg] done=%b gen=%0d",
                         negotiation_done, negotiated_gen);
                fail_count = fail_count + 1;
            end
        end

        do_reset;
        begin : TC11
            local_speed_cap   = 8'h3F;
            partner_speed_cap = 8'h3F;
            partner_cap_valid = 0;
            repeat(15) @(posedge clk); #1;
            if (!negotiation_done) begin
                $display("PASS [TC11_no_partner_valid_no_neg]");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [TC11_no_partner_valid_no_neg]");
                fail_count = fail_count + 1;
            end
        end

        do_reset;
        run_negotiation(8'h02, 8'h04, 8'h00);

        if (negotiation_done && negotiated_gen === 3'd1 &&
            negotiated_speed === 8'h01) begin
            $display("PASS [TC12_disjoint_fallback_gen1]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC12_disjoint_fallback_gen1] gen=%0d speed=0x%h",
                     negotiated_gen, negotiated_speed);
            fail_count = fail_count + 1;
        end

        do_reset;
        run_negotiation(8'h07, 8'h07, 8'h00);
        if (negotiation_done && negotiated_gen === 3'd3) begin
            $display("PASS [TC13_gen3_common]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC13_gen3_common] gen=%0d", negotiated_gen);
            fail_count = fail_count + 1;
        end

        rst_n = 0;
        repeat(3) @(posedge clk); #1;
        if (negotiated_speed === 8'h00 && negotiated_gen === 3'd0 &&
            !negotiation_done && !speed_change_req) begin
            $display("PASS [TC14_reset_clears]");
            pass_count = pass_count + 1;
        end else begin
            $display("FAIL [TC14_reset_clears] speed=0x%h gen=%0d done=%b req=%b",
                     negotiated_speed, negotiated_gen,
                     negotiation_done, speed_change_req);
            fail_count = fail_count + 1;
        end
        rst_n = 1;

        begin : TC15
            integer i;
            for (i = 0; i < 3; i = i + 1) begin
                do_reset;
                run_negotiation(8'h3F, 8'h3F, 8'h00);
            end
            if (negotiation_done && negotiated_gen === 3'd6) begin
                $display("PASS [TC15_back_to_back]");
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL [TC15_back_to_back]");
                fail_count = fail_count + 1;
            end
        end

        #20;
        $display("=============================================");
        $display("  DATA_RATE_ADV: PASS=%0d  FAIL=%0d",
                 pass_count, fail_count);
        $display("=============================================");
        $finish;
    end

    initial begin
        #200000;
        $display("WATCHDOG TIMEOUT — simulation hung");
        $finish;
    end

endmodule
