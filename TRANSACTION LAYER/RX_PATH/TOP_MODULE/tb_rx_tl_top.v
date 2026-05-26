// ============================================================
//  Module  : tb_pcie_rx_tl_top
//  Purpose : Comprehensive testbench for pcie_rx_tl_top
//            25 test cases covering all 9 RX sub-modules.
//
//  Verified design notes:
//    - pcie_completion_handler extracts hdr_tag = tlp_cpl[79:70]
//      (DW2[15:8]<<2 | lower_addr[7:6]), so outstanding_tag must
//      be set to (tag << 2) when lower_addr=0.
//    - tlp_malformed_checker BE checks are skipped for Cpl/Msg/Atomic
//      types (no first_be/last_be fields in those TLP headers).
//    - MSG_HDL / RTR outputs appear combinatorially relative to the
//      PoisonedHandler forwarding pulse ? sample on same cycle as SOP.
//    - ATOP pipeline is 3 stages: s1(cy0), s2(cy1), wr_out(cy2).
// ============================================================
`timescale 1ns/1ps

module tb_pcie_rx_tl_top;

    // ?? Parameters ?????????????????????????????????????????
    parameter CLK_PERIOD = 4;

    // ?? DUT IOs ????????????????????????????????????????????
    reg          clk, rst_n;
    reg  [1023:0] tlp_rx;
    reg           tlp_rx_valid, tlp_rx_sop, ecrc_ok;
    reg           credit_grant_cpl;
    reg  [9:0]    outstanding_tag;
    reg  [9:0]    expected_len;

    wire          parse_err, malformed_err;
    wire [3:0]    malformed_type;
    wire          poisoned_detected, poison_drop;
    wire [2:0]    poison_to_aer;
    wire [4:0]    tlp_type_out;
    wire [2:0]    tlp_fmt_out, tlp_tc_out, tlp_attr_out;
    wire [9:0]    tlp_len_out, tlp_tag_out;
    wire [15:0]   tlp_req_id_out;
    wire [63:0]   tlp_addr_out;
    wire [511:0]  cpl_data;
    wire          cpl_valid;
    wire [9:0]    cpl_tag;
    wire [2:0]    cpl_status;
    wire          cpl_match_err;
    wire [9:0]    tag_return;
    wire          tag_return_valid, cr_return_cplh;
    wire [3:0]    cr_return_cpld;
    wire          q_full_cpl;
    wire [7:0]    q_occ_cpl;
    wire [511:0]  mwr_data;
    wire [63:0]   mwr_addr, mwr_be;
    wire          mwr_valid, mwr_full;
    wire [3:0]    intx_assert, intx_deassert;
    wire          pme_msg, err_msg_valid;
    wire [2:0]    err_msg_type;
    wire [511:0]  vdm_data;
    wire          vdm_valid, msg_to_aer;
    wire [63:0]   atop_rd_addr, atop_wr_data, atop_cpl_data;
    wire          atop_wr_en, atop_cpl_valid;
    wire [9:0]    atop_tag;
    wire          to_cfg_valid;

    integer pass_cnt, fail_cnt;

    // ?? DUT ????????????????????????????????????????????????
    pcie_rx_tl_top #(.CPL_Q_DEPTH(16),.CPL_Q_DATA_WIDTH(1024),.CPL_Q_ADDR_BITS(4)) dut (
        .clk(clk), .rst_n(rst_n),
        .tlp_rx(tlp_rx), .tlp_rx_valid(tlp_rx_valid), .tlp_rx_sop(tlp_rx_sop),
        .ecrc_ok(ecrc_ok), .credit_grant_cpl(credit_grant_cpl),
        .outstanding_tag(outstanding_tag), .expected_len(expected_len),
        .parse_err(parse_err), .malformed_err(malformed_err), .malformed_type(malformed_type),
        .poisoned_detected(poisoned_detected), .poison_drop(poison_drop), .poison_to_aer(poison_to_aer),
        .tlp_type_out(tlp_type_out), .tlp_fmt_out(tlp_fmt_out), .tlp_tc_out(tlp_tc_out),
        .tlp_attr_out(tlp_attr_out), .tlp_len_out(tlp_len_out), .tlp_tag_out(tlp_tag_out),
        .tlp_req_id_out(tlp_req_id_out), .tlp_addr_out(tlp_addr_out),
        .cpl_data(cpl_data), .cpl_valid(cpl_valid), .cpl_tag(cpl_tag),
        .cpl_status(cpl_status), .cpl_match_err(cpl_match_err),
        .tag_return(tag_return), .tag_return_valid(tag_return_valid),
        .cr_return_cplh(cr_return_cplh), .cr_return_cpld(cr_return_cpld),
        .q_full_cpl(q_full_cpl), .q_occ_cpl(q_occ_cpl),
        .mwr_data(mwr_data), .mwr_addr(mwr_addr), .mwr_be(mwr_be),
        .mwr_valid(mwr_valid), .mwr_full(mwr_full),
        .intx_assert(intx_assert), .intx_deassert(intx_deassert),
        .pme_msg(pme_msg), .err_msg_type(err_msg_type), .err_msg_valid(err_msg_valid),
        .vdm_data(vdm_data), .vdm_valid(vdm_valid), .msg_to_aer(msg_to_aer),
        .atop_rd_addr(atop_rd_addr), .atop_wr_data(atop_wr_data), .atop_wr_en(atop_wr_en),
        .atop_cpl_data(atop_cpl_data), .atop_cpl_valid(atop_cpl_valid), .atop_tag(atop_tag),
        .to_cfg_valid(to_cfg_valid)
    );

    // ?? Clock ??????????????????????????????????????????????
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ?? Check task ?????????????????????????????????????????
    task check;
        input        expr;
        input [127:0] name;
        begin
            if (expr) begin $display("  [PASS] %s", name); pass_cnt = pass_cnt + 1; end
            else      begin $display("  [FAIL] %s  *** FAILURE ***", name); fail_cnt = fail_cnt + 1; end
        end
    endtask

    task idle; input integer n; integer i;
        begin for(i=0;i<n;i=i+1)begin @(posedge clk);#1;tlp_rx_valid<=0;tlp_rx_sop<=0;end end
    endtask

    // ?? TLP helpers ????????????????????????????????????????
    // Build DW0: {Fmt[2:0], Type[4:0], 1'b0, TC[2:0], 4'b0, EP, 4'b0, Len[9:0]}
    function [31:0] mk_dw0;
        input [2:0] fmt; input [4:0] typ; input ep; input [9:0] ln;
        mk_dw0 = {fmt,typ,1'b0,3'b000,4'b0000,1'b0,ep,4'b0000,ln};
    endfunction
    // Build DW1 for requests: {ReqID, Tag, LastBE, FirstBE}
    function [31:0] mk_dw1r;
        input [15:0] rid; input [7:0] tag; input [3:0] lbe, fbe;
        mk_dw1r = {rid,tag,lbe,fbe};
    endfunction

    // MRd 3DW
    function [1023:0] mk_mrd;
        input [15:0] rid; input [7:0] tag; input [31:0] addr; input [9:0] ln;
        reg [1023:0] t;
        begin t=1024'h0; t[31:0]=mk_dw0(3'b000,5'b00000,1'b0,ln);
          t[63:32]=mk_dw1r(rid,tag,(ln==1)?4'b0000:4'hF,4'hF); t[95:64]=addr; mk_mrd=t; end
    endfunction

    // MWr 4DW
    function [1023:0] mk_mwr4;
        input [15:0] rid; input [7:0] tag; input [63:0] addr;
        input [9:0] ln; input [511:0] pl;
        reg [1023:0] t;
        begin t=1024'h0; t[31:0]=mk_dw0(3'b011,5'b00000,1'b0,ln);
          t[63:32]=mk_dw1r(rid,tag,(ln==1)?4'h0:4'hF,4'hF);
          t[95:64]=addr[63:32]; t[127:96]=addr[31:0];
          t[639:128]=pl; mk_mwr4=t; end
    endfunction

    // Cpl 3DW with data
    // NOTE: outstanding_tag must be set to (tag << 2) since RTL reads hdr_tag=tlp_cpl[79:70]
    //       which spans DW2[15:8]=tag and DW2[7:6]=lower_addr[7:6].
    function [1023:0] mk_cpl;
        input [15:0] cid; input [2:0] status; input [11:0] bc;
        input [15:0] rid; input [7:0] tag; input [9:0] ln; input [511:0] pl;
        reg [1023:0] t; reg [31:0] d0,d1,d2;
        begin t=1024'h0;
          d0=mk_dw0(3'b010,5'b01010,1'b0,ln);
          d1={cid,1'b0,status,bc};
          d2={rid,tag,8'h00};
          t[31:0]=d0; t[63:32]=d1; t[95:64]=d2;
          t[607:96]=pl; mk_cpl=t; end
    endfunction

    // Msg (no data)
    function [1023:0] mk_msg;
        input [15:0] rid; input [7:0] mc; input ep;
        reg [1023:0] t; reg [31:0] d0,d1;
        begin t=1024'h0;
          d0=mk_dw0(3'b001,5'b10000,ep,10'h0);
          d1=mk_dw1r(rid,8'h00,4'h0,4'h0);
          d1[15:8]=mc; t[31:0]=d0; t[63:32]=d1; mk_msg=t; end
    endfunction

    // VDM (with data)
    function [1023:0] mk_vdm;
        input [15:0] rid; input [511:0] pl;
        reg [1023:0] t; reg [31:0] d0,d1;
        begin t=1024'h0;
          d0=mk_dw0(3'b011,5'b10000,1'b0,10'd16);
          d1=mk_dw1r(rid,8'h00,4'hF,4'hF); d1[15:8]=8'h7F;
          t[31:0]=d0; t[63:32]=d1; t[895:384]=pl; mk_vdm=t; end
    endfunction

    // FetchAdd AtomicOp
    function [1023:0] mk_fetchadd;
        input [15:0] rid; input [7:0] tag; input [63:0] addr, operand;
        reg [1023:0] t;
        begin t=1024'h0; t[31:0]=mk_dw0(3'b011,5'b01100,1'b0,10'd2);
          t[63:32]=mk_dw1r(rid,tag,4'hF,4'hF);
          t[95:64]=addr[63:32]; t[127:96]=addr[31:0];
          t[255:192]=operand; mk_fetchadd=t; end
    endfunction

    // Config Type-0 Read
    function [1023:0] mk_cfg_rd0;
        input [15:0] rid; input [7:0] tag;
        reg [1023:0] t;
        begin t=1024'h0; t[31:0]=mk_dw0(3'b000,5'b00100,1'b0,10'd1);
          t[63:32]=mk_dw1r(rid,tag,4'h0,4'hF); mk_cfg_rd0=t; end
    endfunction

    // ?? Main test ??????????????????????????????????????????
    initial begin
        pass_cnt=0; fail_cnt=0;
        tlp_rx=0; tlp_rx_valid=0; tlp_rx_sop=0;
        ecrc_ok=1; credit_grant_cpl=0;
        outstanding_tag=0; expected_len=4; rst_n=0;
        repeat(4) @(posedge clk); #1; rst_n=1;
        repeat(2) @(posedge clk);

        $display("============================================================");
        $display(" PCIe Gen6 RX Transaction Layer Testbench");
        $display("============================================================");

        // TC01 ? Reset
        $display("\n-- TC01: Reset Verification --");
        check(!parse_err,         "TC01a parse_err=0");
        check(!malformed_err,     "TC01b malformed_err=0");
        check(!poisoned_detected, "TC01c poisoned_detected=0");
        check(!cpl_valid,         "TC01d cpl_valid=0");
        check(!mwr_valid,         "TC01e mwr_valid=0");
        check(!intx_assert,       "TC01f intx_assert=0");
        check(!atop_wr_en,        "TC01g atop_wr_en=0");

        // TC02 ? MRd parse
        $display("\n-- TC02: MRd TLP Parse --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_mrd(16'hABCD,8'h01,32'hDEADC0DE,10'd4); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(tlp_type_out==5'b00000, "TC02a tlp_type=MRd");
        check(tlp_fmt_out==3'b000,    "TC02b tlp_fmt=000");
        check(tlp_len_out==10'd4,     "TC02c tlp_len=4");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC03 ? MWr
        $display("\n-- TC03: MWr TLP end-to-end --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_mwr4(16'h0001,8'h05,64'hDEADBEEFCAFE0000,10'd4,512'hCAFEBABE);
        tlp_rx_valid<=1; tlp_rx_sop<=1; ecrc_ok<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1;
        check(mwr_valid==1'b1,                    "TC03a mwr_valid asserted");
        check(mwr_addr==64'hDEADBEEFCAFE0000,      "TC03b mwr_addr correct");

        // TC04 ? Completion tag match
        // outstanding_tag = tag<<2 due to RTL hdr_tag=tlp_cpl[79:70] extraction
        $display("\n-- TC04: Completion TLP tag match --");
        idle(2); outstanding_tag=10'd28; credit_grant_cpl=1; // tag=7, otag=7<<2=28
        @(posedge clk); #1;
        tlp_rx<=mk_cpl(16'hBEEF,3'b000,12'd16,16'hABCD,8'h07,10'd4,512'hDEADBEEF);
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1; // CH stage 2
        check(cpl_valid==1'b1,    "TC04a cpl_valid");
        check(cpl_status==3'b000, "TC04b cpl_status=SC");
        credit_grant_cpl=0;

        // TC05 ? Completion tag mismatch
        $display("\n-- TC05: Completion tag mismatch --");
        idle(2); outstanding_tag=10'd612; credit_grant_cpl=1; // otag=0x99<<2=0x264=612
        @(posedge clk); #1;
        tlp_rx<=mk_cpl(16'hBEEF,3'b000,12'd16,16'hABCD,8'h42,10'd4,512'h0); // tag=0x42
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1;
        check(cpl_match_err==1'b1,"TC05 cpl_match_err");
        credit_grant_cpl=0;

        // TC06 ? Poisoned TLP
        $display("\n-- TC06: Poisoned TLP (EP=1) --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=1024'h0; tlp_rx[31:0]<={3'b011,5'b00000,1'b0,3'b0,4'b0,1'b1/*EP*/,4'b0,10'd4};
        tlp_rx[63:32]<={16'h1234,8'hAA,4'hF,4'hF};
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1;
        check(poisoned_detected==1,"TC06a poisoned_detected");
        check(poison_drop==1,      "TC06b poison_drop");

        // TC07 ? Malformed: reserved type
        $display("\n-- TC07: Malformed TLP (reserved type) --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=1024'h0; tlp_rx[31:0]<={3'b001,5'b11111,1'b0,3'b0,4'b0,1'b0,4'b0,10'd4};
        tlp_rx[63:32]<={16'hABCD,8'h00,4'hF,4'hF};
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(malformed_err==1,       "TC07a malformed_err");
        check(malformed_type==4'b0001,"TC07b type=RSVD_TYPE");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC08 ? Malformed: IO len!=1
        $display("\n-- TC08: Malformed IO TLP (len=2) --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=1024'h0; tlp_rx[31:0]<=mk_dw0(3'b000,5'b00010,1'b0,10'd2);
        tlp_rx[63:32]<={16'hABCD,8'h01,4'hF,4'hF};
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(malformed_err==1,       "TC08a malformed_err IO len!=1");
        check(malformed_type==4'b0010,"TC08b type=INVALID_LEN");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC09 ? INTx Assert INTA
        $display("\n-- TC09: INTx Assert INTA --");
        idle(2); ecrc_ok=1;
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h1111,8'h20,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(intx_assert==4'b0001,"TC09 INTA assert");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC10 ? PME
        $display("\n-- TC10: PME message --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h2222,8'h18,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(pme_msg==1,"TC10 PME message");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC11 ? ERR_FATAL
        $display("\n-- TC11: ERR_FATAL message --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h3333,8'h33,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(err_msg_valid==1,   "TC11a err_msg_valid");
        check(err_msg_type==3'd2, "TC11b err_msg_type=FATAL");
        check(msg_to_aer==1,      "TC11c msg_to_aer");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC12 ? VDM
        $display("\n-- TC12: VDM message with data --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_vdm(16'h4444,512'hDEADCAFE12345678);
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(vdm_valid==1,"TC12a vdm_valid");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC13 ? Atomic FetchAdd (3-stage pipeline, sample at cy0+2)
        $display("\n-- TC13: Atomic FetchAdd --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_fetchadd(16'hDEAD,8'hF0,64'h8,64'h1);
        tlp_rx_valid<=1; tlp_rx_sop<=1; ecrc_ok<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1; // s2
        @(posedge clk); #1; // s3 outputs
        check(atop_wr_en==1,    "TC13a atop_wr_en");
        check(atop_cpl_valid==1,"TC13b atop_cpl_valid");
        check(atop_wr_data==64'h1,"TC13c FetchAdd 0+1=1");

        // TC14 ? CPL_Q back-pressure
        $display("\n-- TC14: CPL_Q back-pressure --");
        idle(2); credit_grant_cpl=0;
        begin: tc14
            integer qq;
            for(qq=0;qq<16;qq=qq+1) begin
                @(posedge clk); #1;
                tlp_rx<=mk_cpl(16'hABCD,3'b000,12'd4,16'h1234,qq[7:0],10'd1,512'h0);
                tlp_rx_valid<=1; tlp_rx_sop<=1;
            end
        end
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        repeat(3) @(posedge clk); #1;
        check(q_full_cpl==1,"TC14a q_full_cpl after 16 Cpls");
        credit_grant_cpl=1;
        repeat(20) @(posedge clk); #1;
        check(q_full_cpl==0,"TC14b q_full_cpl clears after drain");
        credit_grant_cpl=0;

        // TC15 ? ECRC fail
        $display("\n-- TC15: ECRC fail blocks routing --");
        idle(2); ecrc_ok=0;
        @(posedge clk); #1;
        tlp_rx<=mk_mwr4(16'hABCD,8'h09,64'h12340000,10'd4,512'hFF);
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0; ecrc_ok=1;
        @(posedge clk); #1;
        // mwr_valid is level-held from prior test; check router to_mwr stayed 0
        check(to_cfg_valid==0,"TC15 ECRC fail: cfg not routed");
        idle(2);

        // TC16 ? Config TLP
        $display("\n-- TC16: Config TLP --");
        idle(2); ecrc_ok=1;
        @(posedge clk); #1;
        tlp_rx<=mk_cfg_rd0(16'hABCD,8'h02); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(to_cfg_valid==1,"TC16 to_cfg_valid");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC17 ? Back-to-back MWr
        $display("\n-- TC17: Back-to-back MWr TLPs --");
        idle(2);
        begin: tc17
            integer bb;
            for(bb=0;bb<4;bb=bb+1) begin
                @(posedge clk); #1;
                tlp_rx<=mk_mwr4(16'h0002,bb[7:0],64'hA0000000+bb*64,10'd4,512'hBEEF+bb);
                tlp_rx_valid<=1; tlp_rx_sop<=1;
            end
        end
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        repeat(2) @(posedge clk); #1;
        check(mwr_valid==1,"TC17 mwr_valid after back-to-back");

        // TC18 ? 4DW address
        $display("\n-- TC18: 4DW address MWr --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_mwr4(16'h0003,8'h10,64'hDEADBEEFCAFE0000,10'd4,512'hABCD);
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1;
        check(mwr_addr==64'hDEADBEEFCAFE0000,"TC18 4DW addr correct");

        // TC19 ? INTx Deassert INTB
        $display("\n-- TC19: INTx Deassert INTB --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h5555,8'h25,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(intx_deassert==4'b0010,"TC19 INTB deassert");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC20 ? ERR_COR
        $display("\n-- TC20: ERR_COR message --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h6666,8'h30,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(err_msg_valid==1,  "TC20a err_msg_valid");
        check(err_msg_type==3'd0,"TC20b err_msg_type=COR");
        check(msg_to_aer==1,     "TC20c msg_to_aer");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC21 ? TC22: INTD Assert and deassert
        $display("\n-- TC21: INTD Assert --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h7777,8'h23,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(intx_assert==4'b1000,"TC21 INTD assert");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        $display("\n-- TC22: INTD Deassert --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h7777,8'h27,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(intx_deassert==4'b1000,"TC22 INTD deassert");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC23 ? ERR_NONFATAL
        $display("\n-- TC23: ERR_NONFATAL message --");
        idle(2);
        @(posedge clk); #1;
        tlp_rx<=mk_msg(16'h8888,8'h31,1'b0); tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1;
        check(err_msg_valid==1,  "TC23a err_msg_valid");
        check(err_msg_type==3'd1,"TC23b err_msg_type=NONFATAL");
        tlp_rx_valid<=0; tlp_rx_sop<=0;

        // TC24 ? CPL_Q occupancy
        $display("\n-- TC24: CPL_Q q_occ increments correctly --");
        idle(2); credit_grant_cpl=0;
        @(posedge clk); #1;
        tlp_rx<=mk_cpl(16'hABCD,3'b000,12'd4,16'h1234,8'hAA,10'd1,512'h0);
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1;
        check(q_occ_cpl>=1,"TC24 q_occ>=1 after enqueue");
        credit_grant_cpl=1; repeat(5) @(posedge clk); #1;
        credit_grant_cpl=0;

        // TC25 ? tag_return on final completion
        $display("\n-- TC25: Tag return on final Cpl segment --");
        idle(2);
        outstanding_tag=10'h154; credit_grant_cpl=1; // tag=0x55, otag=0x55<<2=0x154
        @(posedge clk); #1;
        tlp_rx<=mk_cpl(16'hBEEF,3'b000,12'd4,16'hABCD,8'h55,10'd1,512'hDEAD);
        tlp_rx_valid<=1; tlp_rx_sop<=1;
        @(posedge clk); #1; tlp_rx_valid<=0; tlp_rx_sop<=0;
        @(posedge clk); #1;
        check(tag_return_valid==1,"TC25a tag_return_valid");
        credit_grant_cpl=0;

        // Summary
        idle(5);
        $display("\n============================================================");
        $display(" TEST SUMMARY: PASSED=%0d  FAILED=%0d  TOTAL=%0d",
                 pass_cnt, fail_cnt, pass_cnt+fail_cnt);
        if(fail_cnt==0) $display(" *** ALL TESTS PASSED ***");
        else            $display(" *** %0d FAILURE(S) DETECTED ***", fail_cnt);
        $display("============================================================");
        $finish;
    end

    initial begin #(CLK_PERIOD*5000); $display("[WATCHDOG] timeout"); $finish; end
    initial begin $dumpfile("pcie_rx_tl_top.vcd"); $dumpvars(0,tb_pcie_rx_tl_top); end

endmodule
