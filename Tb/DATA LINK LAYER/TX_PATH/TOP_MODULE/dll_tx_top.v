
`timescale 1ns/1ps

module dll_tx_top #(
    parameter BUF_DEPTH = 4096,
    parameter TLP_WIDTH = 1056,
    parameter PTR_W     = 12
)(

    input  wire         clk,
    input  wire         rst_n,

    input  wire [1023:0] tlp_in,
    input  wire          tlp_valid_in,
    input  wire [2047:0] flit_in,
    input  wire          flit_valid_in,
    input  wire          flit_mode_en,
    input  wire [7:0]    fc_update_ph,
    input  wire          fc_update_valid,

    input  wire [11:0]   ack_seq,
    input  wire [11:0]   nak_seq,
    input  wire          retry_req,
    input  wire          link_reset,

    input  wire [47:0]   dllp_raw_in,
    input  wire          dllp_raw_valid,

    input  wire [63:0]   ack_dllp,
    input  wire          ack_dllp_valid,

    input  wire [63:0]   pm_dllp,
    input  wire          pm_dllp_valid,

    input  wire          nop_valid,
    input  wire          bw_dllp_valid,

    input  wire [1:0]    flit_slot_used,
    input  wire [1023:0] null_pattern,

    input  wire [22:0]   lfsr_seed,
    input  wire          scramble_en,

    input  wire          tx_elec_idle_req,
    input  wire          tx_compliance_req,

    output wire          tl_ready,
    output wire [71:0]   fc_to_dllp,
    output wire          fc_dllp_send,

    output wire [11:0]   seq_num_out,
    output wire          seq_valid_out,
    output wire          seq_wrap,

    output wire [31:0]   lcrc_out,
    output wire [23:0]   flit_crc_out,
    output wire          crc_valid,

    output wire [15:0]   dllp_crc,
    output wire          dllp_crc_valid,
    output wire [63:0]   dllp_full_out,

    output wire [TLP_WIDTH-1:0] retry_tlp_out,
    output wire          retry_valid_out,
    output wire [11:0]   retry_seq_out,
    output wire          buf_full,
    output wire [11:0]   buf_occ,
    output wire          purge_done,

    output wire [2047:0] flit_padded_out,
    output wire          flit_padded_valid,
    output wire          null_inserted,
    output wire [7:0]    null_count,

    output wire [63:0]   dllp_arb_out,
    output wire          dllp_arb_valid,
    output wire [3:0]    dllp_type,

    output wire [255:0]  scrambled_data,
    output wire          scrambled_valid,
    output wire [22:0]   lfsr_state,

    output wire [255:0]  phy_txd,
    output wire          phy_tx_valid,
    output wire          phy_tx_elec_idle,
    output wire          phy_tx_compliance
);

    wire [1023:0] w_dll_tlp;
    wire          w_dll_tlp_valid;
    wire [2047:0] w_dll_flit;
    wire          w_dll_flit_valid;

    wire [11:0]   w_seq_num;
    wire          w_seq_valid;

    wire [63:0]   w_dllp_full;
    wire          w_dllp_full_valid;

    wire [2047:0] w_flit_null_out;
    wire          w_flit_null_valid;

    wire [63:0]   w_dllp_arb;
    wire          w_dllp_arb_valid;

    wire [TLP_WIDTH-1:0] w_retry_tlp;
    wire          w_retry_valid;
    wire [11:0]   w_retry_seq;

    wire [255:0]  w_mux_data;
    wire          w_mux_valid;
    wire          w_mux_sop;
    wire          w_mux_eop;

    wire [255:0]  w_scrm_data;
    wire          w_scrm_valid;

    reg  [1023:0]      w_dll_tlp_d;
    reg                w_dll_tlp_valid_d;
    reg  [11:0]        w_seq_num_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_dll_tlp_d       <= {1024{1'b0}};
            w_dll_tlp_valid_d <= 1'b0;
            w_seq_num_d       <= 12'h0;
        end else begin
            w_dll_tlp_d       <= w_dll_tlp;
            w_dll_tlp_valid_d <= w_dll_tlp_valid;
            w_seq_num_d       <= w_seq_num;
        end
    end
    wire [TLP_WIDTH-1:0] w_tlp_to_retry;
    assign w_tlp_to_retry = {w_dll_tlp_d, w_seq_num_d, {(TLP_WIDTH-1036){1'b0}}};

    tl_interface u_tl_if (
        .clk            (clk),
        .rst_n          (rst_n),

        .tlp_in         (tlp_in),
        .tlp_valid_in   (tlp_valid_in),
        .flit_in        (flit_in),
        .flit_valid_in  (flit_valid_in),
        .flit_mode_en   (flit_mode_en),
        .fc_update_ph   (fc_update_ph),
        .fc_update_valid(fc_update_valid),

        .dll_tlp        (w_dll_tlp),
        .dll_tlp_valid  (w_dll_tlp_valid),
        .dll_flit       (w_dll_flit),
        .dll_flit_valid (w_dll_flit_valid),
        .tl_ready       (tl_ready),
        .fc_to_dllp     (fc_to_dllp),
        .fc_dllp_send   (fc_dllp_send)
    );

    seq_num_gen u_seq_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_valid_in   (w_dll_tlp_valid | w_dll_flit_valid),
        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .retry_req      (retry_req),
        .link_reset     (link_reset),

        .seq_num        (w_seq_num),
        .seq_valid      (w_seq_valid),
        .seq_wrap       (seq_wrap)
    );

    assign seq_num_out  = w_seq_num;
    assign seq_valid_out = w_seq_valid;

    crc_gen u_crc_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .tlp_in         (w_dll_tlp),
        .tlp_valid      (w_dll_tlp_valid),
        .flit_in        (w_dll_flit),
        .flit_valid     (w_dll_flit_valid),
        .flit_mode_en   (flit_mode_en),
        .seq_num        (w_seq_num),

        .lcrc_out       (lcrc_out),
        .flit_crc_out   (flit_crc_out),
        .crc_valid      (crc_valid)
    );

    dllp_crc_gen u_dllp_crc_gen (
        .clk            (clk),
        .rst_n          (rst_n),
        .dllp_in        (dllp_raw_in),
        .dllp_valid_in  (dllp_raw_valid),

        .dllp_crc       (dllp_crc),
        .dllp_crc_valid (dllp_crc_valid),
        .dllp_full      (w_dllp_full)
    );
    assign dllp_full_out    = w_dllp_full;
    assign w_dllp_full_valid = dllp_crc_valid;

    retry_buf #(
        .BUF_DEPTH(BUF_DEPTH),
        .TLP_WIDTH(TLP_WIDTH),
        .PTR_W    (PTR_W)
    ) u_retry_buf (
        .clk            (clk),
        .rst_n          (rst_n),

        .tlp_in         (w_tlp_to_retry),
        .tlp_write_en   (w_dll_tlp_valid_d & ~buf_full),
        .seq_num_in     (w_seq_num),

        .ack_seq        (ack_seq),
        .nak_seq        (nak_seq),
        .retry_req      (retry_req),

        .retry_tlp      (w_retry_tlp),
        .retry_valid    (w_retry_valid),
        .retry_seq      (w_retry_seq),

        .buf_full       (buf_full),
        .buf_occ        (buf_occ),
        .purge_done     (purge_done)
    );
    assign retry_tlp_out  = w_retry_tlp;
    assign retry_valid_out= w_retry_valid;
    assign retry_seq_out  = w_retry_seq;

    flit_null_slot_inserter u_null_ins (
        .clk            (clk),
        .rst_n          (rst_n),
        .flit_in        (w_dll_flit),
        .flit_valid     (w_dll_flit_valid),
        .flit_slot_used (flit_slot_used),
        .null_pattern   (null_pattern),

        .flit_out       (w_flit_null_out),
        .flit_out_valid (w_flit_null_valid),
        .null_inserted  (null_inserted),
        .null_count     (null_count)
    );
    assign flit_padded_out   = w_flit_null_out;
    assign flit_padded_valid = w_flit_null_valid;

    dllp_arb u_dllp_arb (
        .clk            (clk),
        .rst_n          (rst_n),

        .ack_dllp       (ack_dllp),
        .ack_dllp_valid (ack_dllp_valid),

        .fc_dllp        (w_dllp_full),
        .fc_dllp_valid  (w_dllp_full_valid),

        .pm_dllp        (pm_dllp),
        .pm_dllp_valid  (pm_dllp_valid),

        .nop_valid      (nop_valid),

        .bw_dllp_valid  (bw_dllp_valid),

        .dllp_out       (w_dllp_arb),
        .dllp_out_valid (w_dllp_arb_valid),
        .dllp_type      (dllp_type)
    );
    assign dllp_arb_out   = w_dllp_arb;
    assign dllp_arb_valid = w_dllp_arb_valid;

    tx_datapath_mux u_tx_mux (
        .clk            (clk),
        .rst_n          (rst_n),

        .tlp_tx         ({w_dll_tlp, {(TLP_WIDTH-1024){1'b0}}}),
        .tlp_tx_valid   (w_dll_tlp_valid),

        .retry_tlp      (w_retry_tlp),
        .retry_valid    (w_retry_valid),

        .dllp_out       (w_dllp_arb),
        .dllp_valid     (w_dllp_arb_valid),

        .retry_req      (retry_req),

        .phy_tx_data    (w_mux_data),
        .phy_tx_valid   (w_mux_valid),
        .phy_tx_sop     (w_mux_sop),
        .phy_tx_eop     (w_mux_eop)
    );

    scrambler u_scrambler (
        .clk            (clk),
        .rst_n          (rst_n),
        .data_in        (w_mux_data),
        .data_valid_in  (w_mux_valid),
        .lfsr_seed      (lfsr_seed),
        .scramble_en    (scramble_en),
        .link_reset     (link_reset),

        .data_out       (w_scrm_data),
        .data_valid_out (w_scrm_valid),
        .lfsr_state     (lfsr_state)
    );
    assign scrambled_data  = w_scrm_data;
    assign scrambled_valid = w_scrm_valid;

    reg w_scrm_sop, w_scrm_eop;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_scrm_sop <= 1'b0;
            w_scrm_eop <= 1'b0;
        end else begin
            w_scrm_sop <= w_mux_sop;
            w_scrm_eop <= w_mux_eop;
        end
    end

    pcie6_phy_tx u_phy_tx (
        .clk                 (clk),
        .rst_n               (rst_n),
        .tx_data             (w_scrm_data),
        .tx_valid            (w_scrm_valid),
        .tx_sop              (w_scrm_sop),
        .tx_eop              (w_scrm_eop),
        .tx_elec_idle_req    (tx_elec_idle_req),
        .tx_compliance_req   (tx_compliance_req),

        .phy_txd             (phy_txd),
        .phy_tx_valid        (phy_tx_valid),
        .phy_tx_elec_idle    (phy_tx_elec_idle),
        .phy_tx_compliance   (phy_tx_compliance)
    );

endmodule
