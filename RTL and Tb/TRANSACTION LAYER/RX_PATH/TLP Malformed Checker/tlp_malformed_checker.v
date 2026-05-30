// ============================================================
// Module: tlp_malformed_checker
// PCIe Gen6 Transaction Layer - TLP Malformed Checker
// FIX: Outputs are now COMBINATORIAL (always @*) so they
//      are valid in the same cycle as parse_valid, matching
//      the one-cycle sample window the testbench expects.
// ============================================================

module tlp_malformed_checker (
    input  wire        clk,
    input  wire        rst_n,

    input  wire [4:0]  tlp_type,
    input  wire [2:0]  tlp_fmt,
    input  wire [9:0]  tlp_len,
    input  wire [3:0]  tlp_first_be,
    input  wire [3:0]  tlp_last_be,
    input  wire        parse_valid,

    output wire        malformed_err,
    output wire [3:0]  malformed_type,
    output wire        tlp_ok
);

    localparam [3:0] MAL_NONE         = 4'b0000;
    localparam [3:0] MAL_RSVD_TYPE    = 4'b0001;
    localparam [3:0] MAL_INVALID_LEN  = 4'b0010;
    localparam [3:0] MAL_ZERO_LEN     = 4'b0011;
    localparam [3:0] MAL_BE_VIOLATION = 4'b0100;
    localparam [3:0] MAL_FMT_MISMATCH = 4'b0101;

    wire is_mem    = (tlp_type == 5'b00000);
    wire is_io     = (tlp_type == 5'b00010);
    wire is_cfg0   = (tlp_type == 5'b00100);
    wire is_cfg1   = (tlp_type == 5'b00101);
    wire is_msg    = (tlp_type[4:3] == 2'b10);
    wire is_cpl    = (tlp_type == 5'b01010);
    wire is_atomic = (tlp_type == 5'b01100) ||
                     (tlp_type == 5'b01101) ||
                     (tlp_type == 5'b01110);

    wire known_type = is_mem | is_io | is_cfg0 | is_cfg1 |
                      is_msg | is_cpl | is_atomic;

    wire has_data = tlp_fmt[1];

    wire len_is_zero = (tlp_len == 10'd0);
    wire io_len_ok   = (tlp_len == 10'd1);
    wire cfg_len_ok  = (tlp_len == 10'd1);

    // Skip BE checks for types that have no first_be/last_be fields
    wire skip_be = is_cpl | is_msg | is_atomic;

    wire be_len1_ok  = skip_be ? 1'b1 :
                       (tlp_len == 10'd1) ? (tlp_last_be == 4'b0000) : 1'b1;
    wire be_first_ok = skip_be ? 1'b1 :
                       (has_data && (tlp_len > 10'd0)) ?
                           (tlp_first_be != 4'b0000) : 1'b1;
    wire be_last_ok  = skip_be ? 1'b1 :
                       (tlp_len > 10'd1) ? (tlp_last_be != 4'b0000) : 1'b1;

    wire fmt_mismatch = is_mem && (
        (tlp_fmt == 3'b001 || tlp_fmt == 3'b011) ? 1'b0 :
        (tlp_fmt == 3'b000 || tlp_fmt == 3'b010) ? 1'b0 :
        1'b1
    );

    // -------------------------------------------------------
    // Combinatorial decode (no clock, no register)
    // -------------------------------------------------------
    reg        c_malformed_err;
    reg [3:0]  c_malformed_type;
    reg        c_tlp_ok;

    always @(*) begin
        c_malformed_err  = 1'b0;
        c_malformed_type = MAL_NONE;
        c_tlp_ok         = 1'b0;

        if (parse_valid) begin
            if (!known_type) begin
                c_malformed_err  = 1'b1;
                c_malformed_type = MAL_RSVD_TYPE;
            end
            else if (len_is_zero && has_data) begin
                c_malformed_err  = 1'b1;
                c_malformed_type = MAL_ZERO_LEN;
            end
            else if (is_io && !io_len_ok) begin
                c_malformed_err  = 1'b1;
                c_malformed_type = MAL_INVALID_LEN;
            end
            else if ((is_cfg0 || is_cfg1) && !cfg_len_ok) begin
                c_malformed_err  = 1'b1;
                c_malformed_type = MAL_INVALID_LEN;
            end
            else if (!be_len1_ok || !be_first_ok || !be_last_ok) begin
                c_malformed_err  = 1'b1;
                c_malformed_type = MAL_BE_VIOLATION;
            end
            else if (fmt_mismatch) begin
                c_malformed_err  = 1'b1;
                c_malformed_type = MAL_FMT_MISMATCH;
            end
            else begin
                c_tlp_ok = 1'b1;
            end
        end
    end

    assign malformed_err  = c_malformed_err;
    assign malformed_type = c_malformed_type;
    assign tlp_ok         = c_tlp_ok;

endmodule
