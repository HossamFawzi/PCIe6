module block_align_sync_hdr_checker (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [255:0] data_in,
    input  wire         data_valid,
    input  wire         block_lock,
    output reg  [255:0] aligned_data,
    output reg          aligned_valid,
    output reg  [1:0]   sync_hdr,
    output reg          align_err
);

    localparam SYNC_DATA  = 2'b01;
    localparam SYNC_OS    = 2'b10;

    reg [255:0] data_pipe;
    reg         valid_pipe;
    reg [1:0]   hdr_pipe;
    reg         lock_pipe;

    wire [1:0]  hdr_raw;
    wire        hdr_valid;

    assign hdr_raw   = data_in[1:0];
    assign hdr_valid = (hdr_raw == SYNC_DATA) || (hdr_raw == SYNC_OS);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            data_pipe    <= 256'd0;
            valid_pipe   <= 1'b0;
            hdr_pipe     <= 2'b00;
            lock_pipe    <= 1'b0;
        end else begin
            data_pipe    <= data_in;
            valid_pipe   <= data_valid;
            hdr_pipe     <= hdr_raw;
            lock_pipe    <= block_lock;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aligned_data  <= 256'd0;
            aligned_valid <= 1'b0;
            sync_hdr      <= 2'b00;
            align_err     <= 1'b0;
        end else begin
            if (valid_pipe && lock_pipe) begin
                aligned_data  <= {2'b00, data_pipe[255:2]};
                sync_hdr      <= hdr_pipe;
                aligned_valid <= 1'b1;
                align_err     <= ~((hdr_pipe == SYNC_DATA) || (hdr_pipe == SYNC_OS));
            end else if (valid_pipe && !lock_pipe) begin
                aligned_data  <= data_pipe;
                sync_hdr      <= hdr_pipe;
                aligned_valid <= 1'b0;
                align_err     <= 1'b1;
            end else begin
                aligned_data  <= 256'd0;
                aligned_valid <= 1'b0;
                sync_hdr      <= 2'b00;
                align_err     <= 1'b0;
            end
        end
    end

endmodule
