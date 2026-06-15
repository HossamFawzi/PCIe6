// =============================================================================
// PCIe Gen6 DLL Support Block: Error Reporting Interface to TL AER (DLL_ERR)
// From HTML: grp="support", tag="DLL_ERR"
// Inputs : replay_rollover_err, dllp_crc_err, dllp_mal_err, lcrc_err,
//          flit_uncorr_err, lfsr_sync_err, clk, rst_n
// Outputs: dll_err_to_aer[5:0], dll_err_valid, dll_err_type[3:0],
//          dll_err_severity[1:0]
// Behavior: DLL cannot generate TLP msgs - passes all errors up to TL AER.
// =============================================================================
module dll_err (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       replay_rollover_err,
    input  wire       dllp_crc_err,
    input  wire       dllp_mal_err,
    input  wire       lcrc_err,
    input  wire       flit_uncorr_err,
    input  wire       lfsr_sync_err,
    output reg  [5:0] dll_err_to_aer,
    output reg        dll_err_valid,
    output reg  [3:0] dll_err_type,
    output reg  [1:0] dll_err_severity
);

    // Error type encoding
    localparam ERR_NONE           = 4'd0;
    localparam ERR_REPLAY_ROLLOVER= 4'd1;
    localparam ERR_DLLP_CRC       = 4'd2;
    localparam ERR_DLLP_MAL       = 4'd3;
    localparam ERR_LCRC           = 4'd4;
    localparam ERR_FLIT_UNCORR    = 4'd5;
    localparam ERR_LFSR_SYNC      = 4'd6;

    // Severity: 0=COR, 1=NONFATAL, 2=FATAL
    localparam SEV_COR      = 2'd0;
    localparam SEV_NONFATAL = 2'd1;
    localparam SEV_FATAL    = 2'd2;

    wire any_err = replay_rollover_err | dllp_crc_err | dllp_mal_err |
                   lcrc_err | flit_uncorr_err | lfsr_sync_err;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dll_err_to_aer  <= 6'd0;
            dll_err_valid   <= 1'b0;
            dll_err_type    <= ERR_NONE;
            dll_err_severity<= SEV_COR;
        end else begin
            dll_err_to_aer  <= {lfsr_sync_err, flit_uncorr_err,
                                lcrc_err, dllp_mal_err,
                                dllp_crc_err, replay_rollover_err};
            dll_err_valid   <= any_err;

            // Priority encode error type (highest severity first)
            if (replay_rollover_err) begin
                dll_err_type     <= ERR_REPLAY_ROLLOVER;
                dll_err_severity <= SEV_FATAL;
            end else if (flit_uncorr_err) begin
                dll_err_type     <= ERR_FLIT_UNCORR;
                dll_err_severity <= SEV_FATAL;
            end else if (lfsr_sync_err) begin
                dll_err_type     <= ERR_LFSR_SYNC;
                dll_err_severity <= SEV_FATAL;
            end else if (lcrc_err) begin
                dll_err_type     <= ERR_LCRC;
                dll_err_severity <= SEV_NONFATAL;
            end else if (dllp_crc_err) begin
                dll_err_type     <= ERR_DLLP_CRC;
                dll_err_severity <= SEV_COR;
            end else if (dllp_mal_err) begin
                dll_err_type     <= ERR_DLLP_MAL;
                dll_err_severity <= SEV_NONFATAL;
            end else begin
                dll_err_type     <= ERR_NONE;
                dll_err_severity <= SEV_COR;
            end
        end
    end

endmodule
