module linebuffer
#(
    parameter ADDR_WIDTH = 32,
    parameter LINE_BYTES = 32
)(
    input   logic                   clk,
    input   logic                   rst,

    // From Fetch (request context)
    input   logic   [ADDR_WIDTH-1:0] addr,    // B address (word selected by addr[4:2])
    input   logic                    read_en, // asserted when fetch wants a word
    input   logic                    flush,   // invalidate buffered line

    // To I-Cache (request interface)
    output  logic   [ADDR_WIDTH-1:0] ic_addr,     // address to request
    output  logic                    ic_read,     // read enable to cache
    
    // From I-Cache (line fill interface)
    // The cache delivers full lines and a line base tag
    input   logic                    ic_valid,    // 1-cycle pulse when a new line is available
    input   logic   [ADDR_WIDTH-1:5] ic_line_tag, // line base tag (addr[31:5])
    input   logic   [LINE_BYTES*8-1:0] ic_line_data, // 256b line

    // To Fetch
    output  logic   [31:0]           rdata,   // 32b instruction word
    output  logic                    valid    // high when rdata is valid (may span consecutive cycles within a line)
);


    // Local params and types
    localparam integer LINE_BITS = LINE_BYTES * 8;   // 256
    // WORDS_PER_LINE unused in this simplified design

    typedef enum logic [1:0] {
        S_IDLE,
        S_WAIT_MISS,   // waiting for downstream line
        S_RESP_HIT     // 1-cycle registered response for hit
    } state_e;


    // State
    state_e                 state, state_next;

    logic                   buf_valid_q, buf_valid_d;
    logic   [ADDR_WIDTH-1:5] buf_tag_q,   buf_tag_d;   // line tag
    logic   [LINE_BITS-1:0] buf_line_q,  buf_line_d;   // cached line

    // Outputs
    logic   [31:0]           rdata_d, rdata_q;
    logic                    valid_d, valid_q;


//
    always_comb begin
        // Defaults
        state_next          = state;
        buf_valid_d         = buf_valid_q;
        buf_tag_d           = buf_tag_q;
        buf_line_d          = buf_line_q;
        rdata_d             = rdata_q;
        valid_d             = 1'b0;
        
        // Default: pass through addr and read_en to cache
        ic_addr             = addr;
        ic_read             = 1'b0;

        if(|ic_line_tag) begin end

        unique case (state)
            S_IDLE: begin
                if (flush) buf_valid_d = 1'b0;
            end

            S_WAIT_MISS: begin
                // Not used
            end

            S_RESP_HIT: begin
                state_next = S_IDLE;
            end

            default: begin
                state_next = S_IDLE;
            end
        endcase
        
        // Continuous combinational hit path: if buffer valid and tag matches, drive valid/rdata
        if (read_en && buf_valid_q && buf_tag_q == addr[ADDR_WIDTH-1:5]) begin
            // HIT: serve from buffer
            rdata_d = buf_line_q[addr[4:2]*32 +: 32];
            valid_d = 1'b1;
            // No need to request from cache on hit
        end else if (read_en) begin
            // MISS: request from cache
            ic_addr = addr;
            ic_read = 1'b1;
        end
        
        // Accept new line from I-cache (overrides above if ic_valid this cycle)
        if (ic_valid) begin
            buf_line_d  = ic_line_data;
            buf_tag_d   = addr[ADDR_WIDTH-1:5];
            buf_valid_d = 1'b1;
            // If read_en is asserted and tag matches, respond immediately this cycle
            // if (read_en && ic_line_tag == addr[ADDR_WIDTH-1:5]) begin
            rdata_d = ic_line_data[addr[4:2]*32 +: 32];
            valid_d = 1'b1;
            // end
        end
    end

    
    // Sequential state
    always_ff @(posedge clk) begin
        if (rst) begin
            state              <= S_IDLE;
            buf_valid_q        <= 1'b0;
            buf_tag_q          <= '0;
            buf_line_q         <= '0;
            rdata_q            <= '0;
            valid_q            <= 1'b0;
        end else begin
            state              <= state_next;
            buf_valid_q        <= buf_valid_d;
            buf_tag_q          <= buf_tag_d;
            buf_line_q         <= buf_line_d;
            rdata_q            <= rdata_d;
            valid_q            <= valid_d;
        end
    end

    // Outputs (combinational for immediate response)
    assign rdata = rdata_d;
    assign valid = valid_d;

endmodule : linebuffer


