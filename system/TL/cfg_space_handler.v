// =============================================================
//  MODULE : cfg_space_handler
//  TAG    : CFG
//  LAYER  : Transaction Layer — Support Group
//  DESC   : PCIe Config Space Handler.
//           Handles CfgRd0/CfgWr0 TLPs, exposes decoded config
//           bits (max_payload, flit_mode_en, ecrc_en, ro_en)
//           to other TL blocks, and returns Cpl TLPs.
//  SPEC   : PCIe 6.0 Base Spec §7.5 (Config Space)
// =============================================================
module cfg_space_handler (
    input  wire          clk,
    input  wire          rst_n,

    // ── Inbound Config TLP ──────────────────────────────────
    input  wire [255:0]  tlp_cfg,        // Raw config-space TLP
    input  wire          tlp_cfg_valid,  // TLP is a CfgRd/CfgWr
    input  wire [11:0]   cfg_addr,       // DW-aligned byte offset
    input  wire [31:0]   cfg_wr_data,    // Write data (CfgWr)
    input  wire          cfg_wr_en,      // 1=Write  0=Read

    // ── Read Response ───────────────────────────────────────
    output reg  [31:0]   cfg_rd_data,    // Register read-back
    output reg           cfg_rd_valid,

    // ── Completion TLP to send upstream ─────────────────────
    output reg  [255:0]  cfg_cpl_tlp,
    output reg           cfg_cpl_valid,

    // ── Decoded capability bits (broadcast to TL) ───────────
    output reg  [2:0]    max_payload,    // 000=128B … 101=4KB
    output reg           flit_mode_en,   // Gen6 FLIT mode
    output reg           ecrc_en,        // End-to-End CRC
    output reg           ro_en           // Relaxed Ordering
);

    // ── Config Space: 1024 DWORDs = 4 KB ────────────────────
    reg [31:0] cfg_space [0:1023];

    // Standard PCIe capability register offsets (byte / 4)
    localparam [9:0] IDX_VENDDEV  = 10'h000; // Vendor/Device ID
    localparam [9:0] IDX_STATUS   = 10'h001; // Command/Status
    localparam [9:0] IDX_DEVCAP   = 10'h024; // DevCap  (PCIe Cap +0x04)
    localparam [9:0] IDX_DEVCTRL  = 10'h025; // DevCtrl (PCIe Cap +0x08)
    localparam [9:0] IDX_DEVCAP2  = 10'h02C; // DevCap2 (PCIe Cap +0x24)
    localparam [9:0] IDX_DEVCTRL2 = 10'h02D; // DevCtrl2(PCIe Cap +0x28)

    wire [9:0] dw_idx = cfg_addr[11:2];  // byte-addr → DWORD index

    integer i;

    // ── Reset / Defaults ─────────────────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 1024; i = i + 1)
                cfg_space[i] <= 32'h0;

            // Hard-code a few read-only registers
            cfg_space[IDX_VENDDEV]  <= 32'h1234_ABCD; // VendorID:DeviceID
            // DevCap: MPS up to 512B, Gen6-capable
            cfg_space[IDX_DEVCAP]   <= 32'h0000_0001; // MPS max = 256B
            // DevCap2: FLIT mode supported
            cfg_space[IDX_DEVCAP2]  <= 32'h0000_0001;

            max_payload   <= 3'b000; // 128 B
            flit_mode_en  <= 1'b0;
            ecrc_en       <= 1'b0;
            ro_en         <= 1'b0;
        end
        else if (tlp_cfg_valid && cfg_wr_en) begin
            // ---- Write path --------------------------------
            cfg_space[dw_idx] <= cfg_wr_data;

            // Decode DevCtrl register on the fly
            if (dw_idx == IDX_DEVCTRL) begin
                max_payload  <= cfg_wr_data[7:5];  // bits[7:5] MPS
                ro_en        <= cfg_wr_data[4];     // bit[4]   Enable RO
                ecrc_en      <= cfg_wr_data[11];    // bit[11]  ECRC enable
            end
            // Decode DevCtrl2 — FLIT mode
            if (dw_idx == IDX_DEVCTRL2) begin
                flit_mode_en <= cfg_wr_data[0];
            end
        end
    end

    // ── Read path (1-cycle latency) ──────────────────────────
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_rd_data  <= 32'h0;
            cfg_rd_valid <= 1'b0;
        end
        else if (tlp_cfg_valid && !cfg_wr_en) begin
            cfg_rd_data  <= cfg_space[dw_idx];
            cfg_rd_valid <= 1'b1;
        end
        else begin
            cfg_rd_valid <= 1'b0;
        end
    end

    // ── Completion TLP builder ───────────────────────────────
    //    Simple Cpl/CplD header assembly (3-DW header)
    //    Byte[0] = Fmt/Type  0x4A = CplD
    //    This is a minimal functional model
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_cpl_tlp   <= 256'h0;
            cfg_cpl_valid <= 1'b0;
        end
        else if (tlp_cfg_valid) begin
            if (!cfg_wr_en) begin
                // CfgRd → CplD (fmt=010 type=01010 → 8'h4A)
                cfg_cpl_tlp[255:248] <= 8'h4A;          // Fmt/Type = CplD
                cfg_cpl_tlp[247:240] <= 8'h00;          // Rsvd
                cfg_cpl_tlp[239:224] <= 16'h0001;       // Length = 1 DW
                cfg_cpl_tlp[223:208] <= tlp_cfg[223:208];// Completer ID
                cfg_cpl_tlp[207:196] <= 12'h004;        // Byte count
                cfg_cpl_tlp[195:192] <= 4'b0000;        // Status=SC
                cfg_cpl_tlp[191:176] <= tlp_cfg[191:176];// Requester ID
                cfg_cpl_tlp[175:168] <= tlp_cfg[167:160];// Tag
                cfg_cpl_tlp[167:160] <= 8'h00;          // Rsvd / LowerAddr
                cfg_cpl_tlp[159:128] <= cfg_space[dw_idx]; // Data
                cfg_cpl_tlp[127:0]   <= 128'h0;
                cfg_cpl_valid        <= 1'b1;
            end
            else begin
                // CfgWr → Cpl (no data)
                cfg_cpl_tlp[255:248] <= 8'h0A;          // Cpl (no data)
                cfg_cpl_tlp[247:128] <= 120'h0;
                cfg_cpl_tlp[127:0]   <= 128'h0;
                cfg_cpl_valid        <= 1'b1;
            end
        end
        else begin
            cfg_cpl_valid <= 1'b0;
        end
    end

endmodule
