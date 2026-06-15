// =============================================================================
// PCIe 6.0 Flit Mode Controller - Transaction Layer TX
// =============================================================================
// FLIT Structure (256 bytes = 2048 bits):
//   [2047:0]   - Payload (TLPs + DLLP padding)
//   flit_seq   - 12-bit rolling sequence number
//   flit_crc   - CRC-24 over payload
//
// FSM States:
//   IDLE      -> LOAD_1   : first TLP chunk latched
//   LOAD_1    -> LOAD_2   : second TLP chunk assembled
//   LOAD_2    -> CALC_CRC : pipeline stage
//   CALC_CRC  -> EMIT     : CRC computed
//   EMIT      -> WAIT_ACK : outputs driven for one cycle
//   WAIT_ACK  -> IDLE     : ACK received, seq increments
//   WAIT_ACK  -> RETRY    : ACK timeout, retry asserted
//   RETRY     -> IDLE     : retry ACK received
// =============================================================================

module flit_mode_controller (
    input  wire           clk,
    input  wire           rst_n,

    input  wire [1023:0]  tlp_in,
    input  wire           tlp_valid_in,
    input  wire           flit_mode_en,
    input  wire           dll_flit_ack,

    output reg  [2047:0]  flit_out,
    output reg            flit_valid,
    output reg  [23:0]    flit_crc,
    output reg  [11:0]    flit_seq,
    output reg            flit_retry_req,
    output reg            flit_overflow_err
);

    localparam FLIT_PAYLOAD_BITS = 2048;
    localparam TLP_CHUNK_BITS    = 1024;
    localparam ACK_TIMEOUT       = 4'd8;

    localparam [2:0]
        IDLE      = 3'd0,
        LOAD_1    = 3'd1,
        LOAD_2    = 3'd2,
        CALC_CRC  = 3'd3,
        EMIT      = 3'd4,
        WAIT_ACK  = 3'd5,
        RETRY     = 3'd6;

    reg [2:0]    state, next_state;
    reg [2047:0] flit_buf;
    reg [1023:0] chunk_reg;
    reg [11:0]   seq_counter;
    reg [2047:0] retry_buf;
    reg [11:0]   retry_seq;
    reg [23:0]   crc_result;
    reg [3:0]    ack_timer;

    // =========================================================================
    // CRC-24: x^24+x^23+x^6+x^5+x+1
    // =========================================================================
    function [23:0] crc24;
        input [2047:0] data;
        integer i;
        reg [23:0] crc;
        reg inv;
        begin
            crc = 24'hFFFFFF;
            for (i = 2047; i >= 0; i = i - 1) begin
                inv     = data[i] ^ crc[23];
                crc[23] = crc[22];
                crc[22] = crc[21];
                crc[21] = crc[20];
                crc[20] = crc[19];
                crc[19] = crc[18];
                crc[18] = crc[17];
                crc[17] = crc[16];
                crc[16] = crc[15];
                crc[15] = crc[14];
                crc[14] = crc[13];
                crc[13] = crc[12];
                crc[12] = crc[11];
                crc[11] = crc[10];
                crc[10] = crc[9];
                crc[9]  = crc[8];
                crc[8]  = crc[7];
                crc[7]  = crc[6];
                crc[6]  = crc[5]  ^ inv;
                crc[5]  = crc[4]  ^ inv;
                crc[4]  = crc[3];
                crc[3]  = crc[2];
                crc[2]  = crc[1];
                crc[1]  = crc[0]  ^ inv;
                crc[0]  = inv;
            end
            crc24 = crc ^ 24'hFFFFFF;
        end
    endfunction

    // FSM sequential
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) state <= IDLE;
        else        state <= next_state;
    end

    // FSM next-state
    always @(*) begin
        next_state = state;
        case (state)
            IDLE:     if (flit_mode_en && tlp_valid_in) next_state = LOAD_1;
            LOAD_1:   next_state = LOAD_2;
            LOAD_2:   next_state = CALC_CRC;
            CALC_CRC: next_state = EMIT;
            EMIT:     next_state = WAIT_ACK;
            WAIT_ACK:
                if      (dll_flit_ack)          next_state = IDLE;
                else if (ack_timer == 4'd0)     next_state = RETRY;
                else                            next_state = WAIT_ACK;
            RETRY:
                if (dll_flit_ack) next_state = IDLE;
                else              next_state = RETRY;
            default: next_state = IDLE;
        endcase
    end

    // FSM datapath
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_out          <= {FLIT_PAYLOAD_BITS{1'b0}};
            flit_valid        <= 1'b0;
            flit_crc          <= 24'h0;
            flit_seq          <= 12'h0;
            flit_retry_req    <= 1'b0;
            flit_overflow_err <= 1'b0;
            seq_counter       <= 12'h0;
            flit_buf          <= {FLIT_PAYLOAD_BITS{1'b0}};
            chunk_reg         <= {TLP_CHUNK_BITS{1'b0}};
            retry_buf         <= {FLIT_PAYLOAD_BITS{1'b0}};
            retry_seq         <= 12'h0;
            crc_result        <= 24'h0;
            ack_timer         <= ACK_TIMEOUT;
        end else begin
            flit_valid        <= 1'b0;
            flit_retry_req    <= 1'b0;
            flit_overflow_err <= 1'b0;

            case (state)
                IDLE: begin
                    ack_timer <= ACK_TIMEOUT;
                    if (flit_mode_en && tlp_valid_in)
                        chunk_reg <= tlp_in;
                end

                LOAD_1: begin
                    if (tlp_valid_in) begin
                        flit_buf <= {tlp_in, chunk_reg};
                    end else begin
                        flit_buf          <= {{TLP_CHUNK_BITS{1'b0}}, chunk_reg};
                        flit_overflow_err <= 1'b1;
                    end
                end

                LOAD_2: begin end

                CALC_CRC: begin
                    crc_result <= crc24(flit_buf);
                end

                // Drive outputs once; NO retry decision here
                EMIT: begin
                    flit_out   <= flit_buf;
                    flit_crc   <= crc_result;
                    flit_seq   <= seq_counter;
                    flit_valid <= 1'b1;
                    retry_buf  <= flit_buf;
                    retry_seq  <= seq_counter;
                    ack_timer  <= ACK_TIMEOUT;
                end

                // Hold valid, count down, still NO retry flag
                WAIT_ACK: begin
                    flit_out   <= retry_buf;
                    flit_crc   <= crc_result;
                    flit_seq   <= retry_seq;
                    flit_valid <= 1'b1;

                    if (dll_flit_ack) begin
                        seq_counter <= seq_counter + 12'h1;
                        flit_valid  <= 1'b0;
                    end else begin
                        ack_timer <= ack_timer - 4'd1;
                    end
                end

                // Timeout expired: re-emit + assert retry
                RETRY: begin
                    flit_out       <= retry_buf;
                    flit_crc       <= crc24(retry_buf);
                    flit_seq       <= retry_seq;
                    flit_valid     <= 1'b1;
                    flit_retry_req <= 1'b1;

                    if (dll_flit_ack) begin
                        flit_retry_req <= 1'b0;
                        flit_valid     <= 1'b0;
                        seq_counter    <= retry_seq + 12'h1;
                    end
                end

                default: ;
            endcase
        end
    end

endmodule
