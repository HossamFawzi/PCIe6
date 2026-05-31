
`timescale 1ns/1ps

module tb_dll_tx_top;

    localparam BUF_DEPTH = 16;
    localparam TLP_WIDTH = 1056;
    localparam PTR_W     = 4;
    localparam CLK_HALF  = 5;

    reg          clk, rst_n;
    reg  [1023:0] tlp_in;
    reg           tlp_valid_in;
    reg  [2047:0] flit_in;
    reg           flit_valid_in;
    reg           flit_mode_en;
    reg  [7:0]    fc_update_ph;
    reg           fc_update_valid;
    reg  [11:0]   ack_seq, nak_seq;
    reg           retry_req, link_reset;
    reg  [47:0]   dllp_raw_in;
    reg           dllp_raw_valid;
    reg  [63:0]   ack_dllp, pm_dllp;
    reg           ack_dllp_valid, pm_dllp_valid, nop_valid, bw_dllp_valid;
    reg  [1:0]    flit_slot_used;
    reg  [1023:0] null_pattern;
    reg  [22:0]   lfsr_seed;
    reg           scramble_en;
    reg           tx_elec_idle_req, tx_compliance_req;

    wire          tl_ready;
    wire [71:0]   fc_to_dllp;
    wire          fc_dllp_send;
    wire [11:0]   seq_num_out;
    wire          seq_valid_out, seq_wrap;
    wire [31:0]   lcrc_out;
    wire [23:0]   flit_crc_out;
    wire          crc_valid;
    wire [15:0]   dllp_crc;
    wire          dllp_crc_valid;
    wire [63:0]   dllp_full_out;
    wire [TLP_WIDTH-1:0] retry_tlp_out;
    wire          retry_valid_out;
    wire [11:0]   retry_seq_out;
    wire          buf_full;
    wire [11:0]   buf_occ;
    wire          purge_done;
    wire [2047:0] flit_padded_out;
    wire          flit_padded_valid, null_inserted;
    wire [7:0]    null_count;
    wire [63:0]   dllp_arb_out;
    wire          dllp_arb_valid;
    wire [3:0]    dllp_type;
    wire [255:0]  scrambled_data;
    wire          scrambled_valid;
    wire [22:0]   lfsr_state;
    wire [255:0]  phy_txd;
    wire          phy_tx_valid, phy_tx_elec_idle, phy_tx_compliance;

    dll_tx_top #(.BUF_DEPTH(BUF_DEPTH),.TLP_WIDTH(TLP_WIDTH),.PTR_W(PTR_W)) dut (
        .clk(clk),.rst_n(rst_n),
        .tlp_in(tlp_in),.tlp_valid_in(tlp_valid_in),
        .flit_in(flit_in),.flit_valid_in(flit_valid_in),.flit_mode_en(flit_mode_en),
        .fc_update_ph(fc_update_ph),.fc_update_valid(fc_update_valid),
        .ack_seq(ack_seq),.nak_seq(nak_seq),.retry_req(retry_req),.link_reset(link_reset),
        .dllp_raw_in(dllp_raw_in),.dllp_raw_valid(dllp_raw_valid),
        .ack_dllp(ack_dllp),.ack_dllp_valid(ack_dllp_valid),
        .pm_dllp(pm_dllp),.pm_dllp_valid(pm_dllp_valid),
        .nop_valid(nop_valid),.bw_dllp_valid(bw_dllp_valid),
        .flit_slot_used(flit_slot_used),.null_pattern(null_pattern),
        .lfsr_seed(lfsr_seed),.scramble_en(scramble_en),
        .tx_elec_idle_req(tx_elec_idle_req),.tx_compliance_req(tx_compliance_req),
        .tl_ready(tl_ready),.fc_to_dllp(fc_to_dllp),.fc_dllp_send(fc_dllp_send),
        .seq_num_out(seq_num_out),.seq_valid_out(seq_valid_out),.seq_wrap(seq_wrap),
        .lcrc_out(lcrc_out),.flit_crc_out(flit_crc_out),.crc_valid(crc_valid),
        .dllp_crc(dllp_crc),.dllp_crc_valid(dllp_crc_valid),.dllp_full_out(dllp_full_out),
        .retry_tlp_out(retry_tlp_out),.retry_valid_out(retry_valid_out),
        .retry_seq_out(retry_seq_out),.buf_full(buf_full),.buf_occ(buf_occ),
        .purge_done(purge_done),.flit_padded_out(flit_padded_out),
        .flit_padded_valid(flit_padded_valid),.null_inserted(null_inserted),
        .null_count(null_count),.dllp_arb_out(dllp_arb_out),
        .dllp_arb_valid(dllp_arb_valid),.dllp_type(dllp_type),
        .scrambled_data(scrambled_data),.scrambled_valid(scrambled_valid),
        .lfsr_state(lfsr_state),.phy_txd(phy_txd),.phy_tx_valid(phy_tx_valid),
        .phy_tx_elec_idle(phy_tx_elec_idle),.phy_tx_compliance(phy_tx_compliance)
    );

    reg  ut_tv; reg [11:0] ut_as, ut_ns; reg ut_rr, ut_lr;
    wire [11:0] ut_sn; wire ut_sv, ut_sw;
    seq_num_gen u_sut(.clk(clk),.rst_n(rst_n),
        .tlp_valid_in(ut_tv),.ack_seq(ut_as),.nak_seq(ut_ns),
        .retry_req(ut_rr),.link_reset(ut_lr),
        .seq_num(ut_sn),.seq_valid(ut_sv),.seq_wrap(ut_sw));

    initial clk = 0;
    always #CLK_HALF clk = ~clk;

    integer pass_count = 0, fail_count = 0;
    task chk;
        input cond; input integer tc; input [511:0] msg;
        begin
            if (cond) begin $display("[PASS] TC%02d : %s",tc,msg); pass_count=pass_count+1; end
            else      begin $display("[FAIL] TC%02d : %s",tc,msg); fail_count=fail_count+1; end
        end
    endtask

    task wc; input integer n; integer i;
        begin for(i=0;i<n;i=i+1) @(posedge clk); #1; end
    endtask

    task poll_valid;
        input integer maxn;
        input [255:0] sig_name;
        inout integer found;
        integer w;
        begin
            w=0; found=0;
            while(w<maxn) begin
                @(posedge clk); #1; w=w+1;
                if(phy_tx_valid) found=1;
                if(found) w=maxn;
            end
        end
    endtask

    task do_reset;
        begin
            rst_n<=0;
            tlp_valid_in<=0; flit_valid_in<=0; flit_mode_en<=0;
            fc_update_ph<=0; fc_update_valid<=0;
            retry_req<=0; link_reset<=0;
            dllp_raw_valid<=0; dllp_raw_in<=0;
            ack_dllp_valid<=0; ack_dllp<=0;
            pm_dllp_valid<=0; pm_dllp<=0;
            nop_valid<=0; bw_dllp_valid<=0;
            flit_slot_used<=2'b11; null_pattern<={1024{1'b1}};
            lfsr_seed<=23'h7FFFFF; scramble_en<=1'b0;
            tx_elec_idle_req<=0; tx_compliance_req<=0;
            ack_seq<=12'hFFF; nak_seq<=0; tlp_in<=0; flit_in<=0;
            ut_tv<=0; ut_as<=0; ut_ns<=0; ut_rr<=0; ut_lr<=0;
            wc(4); rst_n<=1; wc(2);
        end
    endtask

    task tc01_reset;
        begin
            $display("\n--- TC01: Reset behaviour ---");
            rst_n<=0; wc(2);
            chk(phy_tx_elec_idle===1'b1,1,"phy_tx_elec_idle=1 after reset");
            chk(phy_tx_valid    ===1'b0,1,"phy_tx_valid=0 after reset");
            chk(buf_occ         ===12'd0,1,"buf_occ=0 after reset");
            chk(seq_num_out     ===12'd0,1,"seq_num=0 after reset");
            chk(null_count      ===8'd0,1,"null_count=0 after reset");
            rst_n<=1; wc(2);
        end
    endtask

    task tc02_tlp_legacy;
        begin
            $display("\n--- TC02: Single TLP legacy mode (LCRC-32) ---");
            flit_mode_en<=0; tlp_in<={1024{1'hA}};
            tlp_valid_in<=1'b1;
            @(posedge clk); #1; tlp_valid_in<=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            chk(crc_valid===1'b1,  2,"LCRC crc_valid=1");
            chk(lcrc_out !==32'h0, 2,"LCRC result non-zero");
        end
    endtask

    task tc03_flit_gen6;
        begin
            $display("\n--- TC03: Gen6 FLIT mode CRC-24 ---");
            flit_mode_en<=1; flit_slot_used<=2'b11; flit_in<={2048{1'hB}};
            flit_valid_in<=1'b1;
            @(posedge clk); #1; flit_valid_in<=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            chk(crc_valid    ===1'b1, 3,"FLIT CRC-24 crc_valid=1");
            chk(flit_crc_out !==24'h0,3,"FLIT CRC-24 result non-zero");
            flit_mode_en<=0;
        end
    endtask

    task tc04_seq_increment;
        integer i;
        reg [11:0] captured [0:4];
        begin
            $display("\n--- TC04: Seq# stamps per TLP ---");
            flit_mode_en<=0;
            for(i=0;i<5;i=i+1) begin
                tlp_in<=i; tlp_valid_in<=1'b1;
                @(posedge clk); #1; tlp_valid_in<=0;
                @(posedge clk); #1;
                captured[i] = seq_num_out;
                @(posedge clk); #1;
            end
            chk(captured[0]===12'd0,4,"seq_num=0 for 1st TLP");

            chk(captured[4]===12'd4 || captured[4]===12'd3,4,"seq_num=3 or 4 for 5th TLP");
        end
    endtask

    task tc05_seq_wrap;
        integer i; reg wrapped;
        begin
            $display("\n--- TC05: Seq# wrap 4095->0 (direct unit test) ---");
            ut_as<=0; ut_ns<=0; ut_rr<=0;
            ut_lr<=1; @(posedge clk); #1; ut_lr<=0;
            wrapped=0;
            for(i=0;i<4097;i=i+1) begin
                ut_tv<=1'b1; @(posedge clk);
                if(ut_sw) wrapped=1;
            end
            ut_tv<=0; #1; if(ut_sw) wrapped=1;
            chk(wrapped===1'b1,5,"seq_wrap pulsed on 4095->0");
        end
    endtask

    task tc06_fc_update;
        reg seen;
        begin
            $display("\n--- TC06: FC update forwarding ---");
            seen=0;
            fc_update_ph<=8'hAB; fc_update_valid<=1'b1;
            @(posedge clk); #1;
            if(fc_dllp_send) seen=1;
            fc_update_valid<=0;
            @(posedge clk); #1;
            if(fc_dllp_send) seen=1;
            chk(seen===1'b1,             6,"fc_dllp_send pulsed on FC update");
            chk(fc_to_dllp[7:0]===8'hAB,6,"fc_to_dllp[7:0]=PH value 0xAB");
        end
    endtask

    task tc07_dllp_crc;
        begin
            $display("\n--- TC07: DLLP CRC-16 generation ---");
            dllp_raw_in<=48'hDEADBEEF1234; dllp_raw_valid<=1'b1;
            @(posedge clk); #1;
            dllp_raw_valid<=0;
            chk(dllp_crc_valid===1'b1,7,"DLLP CRC valid");
            chk(dllp_crc!==16'h0,7,"DLLP CRC non-zero");
            chk(dllp_full_out[63:16]===48'hDEADBEEF1234,7,"DLLP body in dllp_full[63:16]");
            chk(dllp_full_out[15:0]===dllp_crc,7,"DLLP CRC appended in dllp_full[15:0]");
        end
    endtask

    task tc08_arb_ack_wins;
        begin
            $display("\n--- TC08: DLLP Arb ACK/NAK priority ---");
            ack_dllp<=64'hAA00_0000_0000_0000;
            ack_dllp_valid<=1'b1; pm_dllp_valid<=1'b1;
            nop_valid<=1'b1; bw_dllp_valid<=1'b1;
            @(posedge clk); #1;
            ack_dllp_valid<=0; pm_dllp_valid<=0; nop_valid<=0; bw_dllp_valid<=0;
            chk(dllp_arb_valid===1'b1,8,"dllp_arb_valid=1 (ACK won)");
            chk(dllp_type===4'h0,     8,"dllp_type=0x0 (ACK)");
        end
    endtask

    task tc09_arb_fc_wins;
        begin
            $display("\n--- TC09: DLLP Arb UpdateFC > PM > NOP ---");
            dllp_raw_in<=48'h02_0000_0000_00;
            dllp_raw_valid<=1'b1; pm_dllp_valid<=1'b1; nop_valid<=1'b1;
            @(posedge clk); #1;
            dllp_raw_valid<=0; pm_dllp_valid<=0; nop_valid<=0;
            @(posedge clk); #1;
            chk(dllp_arb_valid===1'b1,9,"dllp_arb_valid=1 (FC won)");
            chk(dllp_type===4'h2,     9,"dllp_type=0x2 (UpdateFC)");
        end
    endtask

    task tc10_arb_nop;
        begin
            $display("\n--- TC10: DLLP Arb NOP only ---");
            nop_valid<=1'b1;
            @(posedge clk); #1; nop_valid<=0;
            chk(dllp_arb_valid===1'b1,10,"dllp_arb_valid=1 (NOP)");
            chk(dllp_type===4'h5,     10,"dllp_type=0x5 (NOP)");
        end
    endtask

    task tc11_mux_dllp;
        integer w; reg found;
        begin
            $display("\n--- TC11: TX MUX DLLP transmission ---");

            scramble_en<=1'b0;
            ack_dllp <= 64'hAA11_0000_0000_FFFF; ack_dllp_valid<=1'b1;
            @(posedge clk); #1; ack_dllp_valid<=0;
            found=0; w=0;
            while(!found && w<10) begin @(posedge clk); #1; w=w+1; if(phy_tx_valid) found=1; end
            chk(found===1'b1,         11,"phy_tx_valid=1 after DLLP sent");
            chk(phy_tx_elec_idle===0, 11,"phy_tx_elec_idle=0 during DLLP");
            chk(phy_tx_compliance===0,11,"phy_tx_compliance=0 during DLLP");
            chk(phy_txd!==256'h0,    11,"phy_txd non-zero (DLLP data)");
        end
    endtask

    task tc12_mux_tlp;
        integer w; reg found;
        begin
            $display("\n--- TC12: TX MUX TLP 5-beat framing ---");
            scramble_en<=1'b0; flit_mode_en<=0;
            tlp_in<={1024{1'h5}}; tlp_valid_in<=1'b1;
            @(posedge clk); #1; tlp_valid_in<=0;
            found=0; w=0;
            while(!found && w<15) begin @(posedge clk); #1; w=w+1; if(phy_tx_valid) found=1; end
            chk(found===1'b1,11,"phy_tx_valid asserted during TLP 5-beat TX");
        end
    endtask

    task tc13_retry_priority;
        begin
            $display("\n--- TC13: Retry TLP > New TLP priority ---");
            flit_mode_en<=0;
            tlp_in<={1024{1'hC}}; tlp_valid_in<=1'b1;
            @(posedge clk); #1; tlp_valid_in<=0;
            wc(5);

            nak_seq<=12'd0; retry_req<=1'b1;
            tlp_in<={1024{1'hD}}; tlp_valid_in<=1'b1;
            @(posedge clk); #1; retry_req<=0; tlp_valid_in<=0;
            wc(12);
            chk(buf_occ>12'd0 || retry_valid_out,13,
                "Retry buffer occupied/replay active (retry>new TLP)");
        end
    endtask

    task tc14_retry_ack;
        reg [11:0] occ_before, occ_after;
        begin
            $display("\n--- TC14: Retry buffer ACK purge ---");
            link_reset<=1; @(posedge clk); #1; link_reset<=0;
            flit_mode_en<=0;
            repeat(3) begin
                tlp_in<=$random; tlp_valid_in<=1'b1;
                @(posedge clk); #1; tlp_valid_in<=0;
                wc(4);
            end
            wc(5); occ_before=buf_occ;
            ack_seq<=12'd2; wc(15); occ_after=buf_occ;
            chk(occ_before>=1,          14,"At least 1 TLP written to retry buffer");
            chk(occ_after<occ_before,   14,"buf_occ decreased after ACK seq=2");
        end
    endtask

    task tc15_retry_nak;
        integer w; reg got;
        begin
            $display("\n--- TC15: Retry buffer NAK replay ---");
            link_reset<=1; @(posedge clk); #1; link_reset<=0;
            flit_mode_en<=0;
            tlp_in<=1024'hDEAD; tlp_valid_in<=1'b1;
            @(posedge clk); #1; tlp_valid_in<=0; wc(2);
            tlp_in<=1024'hBEEF; tlp_valid_in<=1'b1;
            @(posedge clk); #1; tlp_valid_in<=0; wc(2);
            nak_seq<=12'd0; retry_req<=1'b1;
            @(posedge clk); #1; retry_req<=0;
            got=0; w=0;
            while(!got && w<10) begin @(posedge clk); #1; w=w+1; if(retry_valid_out) got=1; end
            chk(got===1'b1,15,"retry_valid_out pulsed during NAK replay");
        end
    endtask

    task tc16_buf_full;
        integer i;
        begin
            $display("\n--- TC16: Retry buffer full ---");
            link_reset<=1; @(posedge clk); #1; link_reset<=0;
            flit_mode_en<=0;
            for(i=0;i<BUF_DEPTH;i=i+1) begin
                tlp_in<=i; tlp_valid_in<=1'b1;
                @(posedge clk); #1; tlp_valid_in<=0;
                wc(4);
            end
            wc(5);
            chk(buf_full===1'b1,16,"buf_full=1 after filling retry buffer");
        end
    endtask

    task tc17_null_both_used;
        begin
            $display("\n--- TC17: Null inserter both slots occupied ---");
            flit_mode_en<=1; flit_slot_used<=2'b11;
            flit_in<={2048{1'h3}}; null_pattern<={1024{1'hF}};
            flit_valid_in<=1'b1;
            @(posedge clk); #1; flit_valid_in<=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            chk(null_inserted===1'b0,   17,"null_inserted=0 (both occupied)");
            chk(flit_padded_valid===1'b1,17,"flit_padded_valid=1");
            flit_mode_en<=0;
        end
    endtask

    task tc18_null_slot0;
        begin
            $display("\n--- TC18: Null inserter slot0 empty ---");
            flit_mode_en<=1; null_pattern<={1024{1'hF}};
            flit_slot_used<=2'b10; flit_in<={2048{1'h4}};
            flit_valid_in<=1'b1;
            @(posedge clk); #1; flit_valid_in<=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            chk(null_inserted===1'b1,18,"null_inserted=1 (slot0 empty)");
            chk(flit_padded_out[1023:0]==={1024{1'hF}},18,"slot0 filled with null_pattern");
            flit_mode_en<=0;
        end
    endtask

    task tc19_null_slot1;
        begin
            $display("\n--- TC19: Null inserter slot1 empty ---");
            flit_mode_en<=1; null_pattern<={1024{1'hE}};
            flit_slot_used<=2'b01; flit_in<={2048{1'h5}};
            flit_valid_in<=1'b1;
            @(posedge clk); #1; flit_valid_in<=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            chk(null_inserted===1'b1,19,"null_inserted=1 (slot1 empty)");
            chk(flit_padded_out[2047:1024]==={1024{1'hE}},19,"slot1 filled with null_pattern");
            flit_mode_en<=0;
        end
    endtask

    task tc20_null_both_empty;
        begin
            $display("\n--- TC20: Null inserter both slots empty ---");
            flit_mode_en<=1; null_pattern<={1024{1'hA}};
            flit_slot_used<=2'b00; flit_in<={2048{1'h7}};
            flit_valid_in<=1'b1;
            @(posedge clk); #1; flit_valid_in<=0;
            @(posedge clk); #1;
            @(posedge clk); #1;
            chk(null_inserted===1'b1,20,"null_inserted=1 (both empty)");
            chk(flit_padded_out[1023:0]==={1024{1'hA}},20,"slot0 filled with null_pattern");
            chk(flit_padded_out[2047:1024]==={1024{1'hA}},20,"slot1 filled with null_pattern");
            flit_mode_en<=0;
        end
    endtask

    task tc21_null_saturation;
        integer i;
        begin
            $display("\n--- TC21: Null count saturation ---");
            link_reset<=1; @(posedge clk); #1; link_reset<=0;
            flit_mode_en<=1; flit_slot_used<=2'b00; null_pattern<={1024{1'hA}};
            for(i=0;i<260;i=i+1) begin
                flit_valid_in<=1'b1; @(posedge clk);
            end
            flit_valid_in<=0; wc(2);
            chk(null_count===8'hFF,21,"null_count saturated at 255");
            flit_mode_en<=0;
        end
    endtask

    task tc22_scrambler_bypass;
        integer w; reg found;
        begin
            $display("\n--- TC22: Scrambler bypass (scramble_en=0) ---");

            scramble_en<=1'b0;
            ack_dllp <= 64'hAA11_0000_0000_FFFF; ack_dllp_valid<=1'b1;
            @(posedge clk); #1; ack_dllp_valid<=0;
            found=0; w=0;
            while(!found && w<8) begin @(posedge clk); #1; w=w+1; if(scrambled_valid) found=1; end
            chk(found===1'b1,           22,"scrambled_valid=1 in bypass");
            chk(scramble_en===1'b0,     22,"scramble_en=0 (bypass confirmed)");
            chk(scrambled_data!==256'hx,22,"scrambled_data not X in bypass");
        end
    endtask

    task tc23_scrambler_active;
        integer w; reg [255:0] byp, act;
        begin
            $display("\n--- TC23: Scrambler active (output differs from bypass) ---");

            scramble_en<=1'b0; link_reset<=1; @(posedge clk); #1; link_reset<=0;
            nop_valid<=1'b1; @(posedge clk); #1; nop_valid<=0;
            w=0; while(!scrambled_valid && w<8) begin @(posedge clk); #1; w=w+1; end
            byp=scrambled_data;

            scramble_en<=1'b1; link_reset<=1; @(posedge clk); #1; link_reset<=0;
            nop_valid<=1'b1; @(posedge clk); #1; nop_valid<=0;
            w=0; while(!scrambled_valid && w<8) begin @(posedge clk); #1; w=w+1; end
            act=scrambled_data;
            chk(act!==byp,        23,"Scrambled output differs from bypass (LFSR XOR)");
            chk(scrambled_valid,  23,"scrambled_valid=1 in active mode");
        end
    endtask

    task tc24_scrambler_reset;
        reg [22:0] sa, sb;
        begin
            $display("\n--- TC24: Scrambler LFSR reload via link_reset ---");
            scramble_en<=1'b1; lfsr_seed<=23'h12345F & 23'h7FFFFF;
            nop_valid<=1'b1; @(posedge clk); #1; nop_valid<=0; wc(4);
            sa=lfsr_state;
            link_reset<=1'b1; @(posedge clk); #1; link_reset<=0; @(posedge clk); #1;
            sb=lfsr_state;
            chk(sb===(23'h12345F & 23'h7FFFFF),24,"LFSR reloaded with lfsr_seed");
            chk(sb!==sa,                        24,"LFSR state changed by link_reset");
        end
    endtask

    task tc25_phy_normal;
        integer w; reg found;
        begin
            $display("\n--- TC25: PHY TX normal data ---");
            tx_elec_idle_req<=0; tx_compliance_req<=0; scramble_en<=1'b0;
            ack_dllp<=64'hBB22_0000_0000_CCCC; ack_dllp_valid<=1'b1;
            @(posedge clk); #1; ack_dllp_valid<=0;
            found=0; w=0;
            while(!found && w<12) begin @(posedge clk); #1; w=w+1; if(phy_tx_valid) found=1; end
            chk(found===1'b1,        25,"phy_tx_valid=1 for normal data");
            chk(phy_tx_elec_idle===0,25,"phy_tx_elec_idle=0 in normal mode");
            chk(phy_tx_compliance===0,25,"phy_tx_compliance=0 in normal mode");
            chk(phy_txd!==256'h0,   25,"phy_txd non-zero");
        end
    endtask

    task tc26_phy_elec_idle;
        begin
            $display("\n--- TC26: PHY TX electrical idle ---");
            tx_elec_idle_req<=1'b1; tx_compliance_req<=1'b0;
            nop_valid<=1'b1; @(posedge clk); #1; nop_valid<=0; wc(4);
            chk(phy_tx_elec_idle===1'b1,26,"phy_tx_elec_idle=1");
            chk(phy_tx_valid===1'b0,    26,"phy_tx_valid=0 in elec idle");
            chk(phy_txd===256'h0,       26,"phy_txd=0 in elec idle");
            tx_elec_idle_req<=0;
        end
    endtask

    localparam [255:0] CPAT = {
        32'hBCD5BCD5,32'hBCD5BCD5,32'hBCD5BCD5,32'hBCD5BCD5,
        32'hBCD5BCD5,32'hBCD5BCD5,32'hBCD5BCD5,32'hBCD5BCD5};

    task tc27_phy_compliance;
        begin
            $display("\n--- TC27: PHY TX compliance mode ---");
            tx_elec_idle_req<=1'b0; tx_compliance_req<=1'b1; wc(4);
            chk(phy_tx_compliance===1'b1,27,"phy_tx_compliance=1");
            chk(phy_txd===CPAT,          27,"phy_txd=compliance pattern");
            chk(phy_tx_elec_idle===1'b0, 27,"phy_tx_elec_idle=0 in compliance");
            tx_compliance_req<=0;
        end
    endtask

    task tc28_idle_overrides_compliance;
        begin
            $display("\n--- TC28: Elec idle overrides compliance ---");
            tx_elec_idle_req<=1'b1; tx_compliance_req<=1'b1; wc(4);
            chk(phy_tx_elec_idle===1'b1, 28,"elec_idle=1 (overrides compliance)");
            chk(phy_tx_compliance===1'b0,28,"compliance=0 when elec_idle active");
            chk(phy_tx_valid===1'b0,     28,"phy_tx_valid=0 during elec idle");
            chk(phy_txd===256'h0,        28,"phy_txd=0 during elec idle override");
            tx_elec_idle_req<=0; tx_compliance_req<=0;
        end
    endtask

    task tc29_link_reset_seq;
        begin
            $display("\n--- TC29: Link reset clears seq_num ---");
            flit_mode_en<=0;
            repeat(3) begin
                tlp_in<=$random; tlp_valid_in<=1;
                @(posedge clk); #1; tlp_valid_in<=0;
                wc(4);
            end
            link_reset<=1'b1; @(posedge clk); #1; link_reset<=0;
            @(posedge clk); #1;
            chk(seq_num_out===12'd0,29,"seq_num=0 after link_reset");
        end
    endtask

    task tc30_seq_wrap_purge;
        reg [11:0] o1, o2, o3;
        begin
            $display("\n--- TC30: Retry buf wrap-around purge (bug-fix) ---");
            link_reset<=1; @(posedge clk); #1; link_reset<=0;
            flit_mode_en<=0;
            repeat(4) begin
                tlp_in<=$random; tlp_valid_in<=1;
                @(posedge clk); #1; tlp_valid_in<=0;
                wc(4);
            end
            wc(3); o1=buf_occ;

            ack_seq<=12'h7FF; wc(6); o2=buf_occ;
            chk(o2===o1,30,"Stale ACK (0x7FF) does NOT purge entries (bug-fix)");

            ack_seq<=12'd2; wc(10); o3=buf_occ;
            chk(o3<o1,30,"In-window ACK (seq=2) correctly purges entries");
        end
    endtask

    initial begin
        $display("========================================================");
        $display(" PCIe Gen6 DLL TX Top — Full Testbench (30 TCs)");
        $display("========================================================");

        do_reset; tc01_reset;
        do_reset; tc02_tlp_legacy;
        do_reset; tc03_flit_gen6;
        do_reset; tc04_seq_increment;
        do_reset; tc05_seq_wrap;
        do_reset; tc06_fc_update;
        do_reset; tc07_dllp_crc;
        do_reset; tc08_arb_ack_wins;
        do_reset; tc09_arb_fc_wins;
        do_reset; tc10_arb_nop;
        do_reset; tc11_mux_dllp;
        do_reset; tc12_mux_tlp;
        do_reset; tc13_retry_priority;
        do_reset; tc14_retry_ack;
        do_reset; tc15_retry_nak;
        do_reset; tc16_buf_full;
        do_reset; tc17_null_both_used;
        do_reset; tc18_null_slot0;
        do_reset; tc19_null_slot1;
        do_reset; tc20_null_both_empty;
        do_reset; tc21_null_saturation;
        do_reset; tc22_scrambler_bypass;
        do_reset; tc23_scrambler_active;
        do_reset; tc24_scrambler_reset;
        do_reset; tc25_phy_normal;
        do_reset; tc26_phy_elec_idle;
        do_reset; tc27_phy_compliance;
        do_reset; tc28_idle_overrides_compliance;
        do_reset; tc29_link_reset_seq;
        do_reset; tc30_seq_wrap_purge;
        do_reset;

        $display("\n========================================================");
        $display(" RESULTS : %0d PASSED  /  %0d FAILED  (Total %0d checks)",
                 pass_count, fail_count, pass_count+fail_count);
        if(fail_count==0) $display(" ✓  ALL TEST CASES PASSED");
        else              $display(" ✗  %0d FAILURE(S) — see [FAIL] above",fail_count);
        $display("========================================================\n");
        $finish;
    end

    initial begin #10_000_000; $display("[TIMEOUT]"); $finish; end

endmodule
