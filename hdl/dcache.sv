module dcache (
    input   logic           clk,
    input   logic           rst,

    // cpu side signals, ufp -> upward facing port
    input   logic   [31:0]  ufp_addr,
    input   logic   [3:0]   ufp_rmask,
    input   logic   [3:0]   ufp_wmask,
    output  logic   [31:0]  ufp_rdata,
    input   logic   [31:0]  ufp_wdata,
    output  logic           ufp_resp,

    // memory side signals, dfp -> downward facing port
    output  logic   [31:0]  dfp_addr,
    output  logic           dfp_read,
    output  logic           dfp_write,
    input   logic   [255:0] dfp_rdata,
    output  logic   [255:0] dfp_wdata,
    input   logic           dfp_resp
);
    // Signal timing info, rounding up:
    // ufp, dfp inputs                   - 1.6 ns delay
    // ufp, dfp outputs                  - 0.7 ns delay
    // sram inputs (from cache to sram)  - 0.1 ns delay
    // sram outputs (from sram to cache) - 0.5 ns delay
    // so the only path we cant have is from ufp/dfp inputs to ufp/dfp outputs

    // Outine of what occurs when:
    // In IDLE: Send addr to tag,data,valid arrays
    // In HIT: compare way tags againt input tag, decide
    // hit/writeback/allocate, calculate way for allocate,
    // update dirty / lru bits
    // In WRITEBACK: write out data_dout to dfp
    // In ALLOCATE: read in dfp to data, set valid, clear dirty,
    // set tag

    typedef enum logic [1:0] {
        IDLE, HIT, WRITEBACK, ALLOCATE
    } state_t;
    logic [1:0] state, state_next;
    typedef struct packed {
        logic [22:0] tag;
        logic [3:0] set;
        logic [2:0] offset;
        logic [1:0] byte_offset;
    } addr_t;
    // use ufp_addr_s when timing allows or in IDLE, otherwise use ufp_addr_prev
    // ie use ufp_addr_prev if it feeds into a ufp/dfp output
    addr_t ufp_addr_s;
    assign ufp_addr_s = ufp_addr;
    addr_t ufp_addr_prev;

    // Memory array signals
    // the data array entries are grouped into
    // 8 32-b-it words, instead of grouping by bytes.
    // this simplifies the wmask and data_din/out logic.
    logic [7:0] [3:0] data_wmask;
    logic [3:0] data_csb;
    // since we never read from one way while writing to
    // another, we use a common web across all ways.
    // this relies on the memory arrays ignoring web if
    // csb is 1 (disabled).
    logic data_web;
    logic [3:0] [7:0] [31:0] data_dout;
    logic [7:0] [31:0] data_din;

    logic [3:0] tag_csb;
    logic tag_web;
    logic [3:0] [22:0] tag_dout;
    logic [22:0] tag_din;

    logic [3:0] valid_csb;
    logic valid_web;
    logic [3:0] valid_dout;
    logic valid_din;

    logic [3:0] dirty_csb;
    logic dirty_web;
    logic [3:0] dirty_dout;
    logic dirty_din;

    logic lru_csb, lru_web;
    logic [2:0] lru_din, lru_dout;

    logic write_en;
    logic read_en;
    assign write_en = |ufp_wmask;
    assign read_en = |ufp_rmask;
    logic tag_match;
    logic [1:0] tag_match_idx; // way idx
    logic [1:0] allocate_idx; // way idx
    logic [31:0] tag_match_idx_raw;
    assign tag_match_idx = tag_match_idx_raw[1:0];

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            ufp_addr_prev <= 'x;
        end else begin
            state <= state_next;
            ufp_addr_prev <= ufp_addr_s;
        end
    end

    always_comb begin
        state_next = 'x;
        data_csb = '1; // active low
        // if csb is 1, web doesn't matter. the mp spec says it does, but the
        // verilog models all don't care about web if csb is 1
        data_web = 'x; data_wmask = 'x; data_din = 'x;
        tag_csb = '1; tag_web = 'x; tag_din = 'x;
        valid_csb = '1; valid_web = 'x; valid_din = 'x;
        dirty_csb = '1; dirty_web = 'x; dirty_din = 'x;
        lru_csb = '1; lru_web = 'x; lru_din = 'x;
        ufp_resp = '0; ufp_rdata = 'x;
        tag_match = 'x; tag_match_idx_raw = 'x;
        dfp_addr = 'x; dfp_read = '0; dfp_write = '0;
        dfp_wdata = 'x;
        // calculate the index for allocation.
        // we rely on lru_dout retaining its previous
        // value when lru_csb is 1, so only IDLE and
        // HIT (when there's a cache hit) should
        // set lru_csb to 0.
        allocate_idx[1] = lru_dout[2];
        allocate_idx[0] = lru_dout[allocate_idx[1]];
        // lru bits -> way idx -> lru bits -> ...
        // 000 -> 00 -> 101 -> 10 -> 011 -> 01 -> 110 -> 11 -> 000
        case (state)
            IDLE: begin
                if (write_en || read_en) begin
                    state_next = HIT;
                    data_csb = '0; data_web = '1; // active low, read
                    tag_csb = '0; tag_web = '1;
                    valid_csb = '0; valid_web = '1;
                    dirty_csb = '0; dirty_web = '1;
                    lru_csb = '0; lru_web = '1;
                end else begin
                    state_next = IDLE;
                end
            end
            HIT: begin
                tag_match = '0;
                for (integer i = 0; i < 4; i++) begin
                    if (valid_dout[i] && ufp_addr_prev.tag == tag_dout[i]) begin
                        // we don't care about the behavior
                        // if more than one tag matches
                        if (tag_match) begin
                            tag_match = 'x;
                            tag_match_idx_raw = 'x;
                        end else begin
                            tag_match = '1;
                            tag_match_idx_raw = unsigned'(i);
                        end
                    end
                end
                if (tag_match) begin
                    state_next = IDLE;
                    ufp_resp = '1;
                    if (write_en) begin
                        // write to data array
                        data_csb[tag_match_idx] = '0;
                        data_web = '0;
                        data_wmask = '0;
                        data_wmask[ufp_addr_prev.offset] = ufp_wmask;
                        data_din[ufp_addr_prev.offset] = ufp_wdata;
                        // set dirty b-it
                        dirty_csb[tag_match_idx] = '0;
                        dirty_web = '0;
                        dirty_din = '1;
                    end else begin // read
                        ufp_rdata = data_dout[tag_match_idx][ufp_addr_prev.offset];
                    end
                    // update lru
                    lru_csb = '0; lru_web = '0;
                    // lru stores the least recently accessed way
                    lru_din = lru_dout;
                    lru_din[2] = ~tag_match_idx[1];
                    lru_din[tag_match_idx[1]] = ~tag_match_idx[0];
                end else begin // tag mismatch
                    if (valid_dout[allocate_idx] && dirty_dout[allocate_idx]) begin
                        state_next = WRITEBACK;
                    end else begin
                        state_next = ALLOCATE;
                    end
                end
            end // end HIT case
            WRITEBACK: begin
                dfp_write = '1;
                dfp_addr = {tag_dout[allocate_idx], ufp_addr_prev.set, 5'b0};
                dfp_wdata = data_dout[allocate_idx];
                state_next = dfp_resp ? ALLOCATE : WRITEBACK;
            end
            ALLOCATE: begin
                dfp_read = '1;
                dfp_addr = {ufp_addr_prev.tag, ufp_addr_prev.set, 5'b0};
                if (dfp_resp) begin
                    state_next = IDLE;
                    // write data
                    data_csb[allocate_idx] = '0;
                    data_web = '0; data_wmask = '1;
                    data_din = dfp_rdata;
                    // set valid
                    valid_csb[allocate_idx] = '0;
                    valid_web = '0; valid_din = '1;
                    // clear dirty
                    dirty_csb[allocate_idx] = '0;
                    dirty_web = '0; dirty_din = '0;
                    // set tag
                    tag_csb[allocate_idx] = '0;
                    tag_web = '0; tag_din = ufp_addr_prev.tag;
                end else begin // no response
                    state_next = ALLOCATE;
                end
            end
        endcase
    end

    generate for (genvar i = 0; i < 4; i++) begin : arrays
        mp_cache_data_array data_array (
            .clk0       (clk),
            .csb0       (data_csb[i]),
            .web0       (data_web),
            .wmask0     (data_wmask),
            .addr0      (ufp_addr_s.set),
            .din0       (data_din),
            .dout0      (data_dout[i])
        );
        mp_cache_tag_array tag_array (
            .clk0       (clk),
            .csb0       (tag_csb[i]),
            .web0       (tag_web),
            .addr0      (ufp_addr_s.set),
            .din0       (tag_din),
            .dout0      (tag_dout[i])
        );
        sp_ff_array valid_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (valid_csb[i]),
            .web0       (valid_web),
            .addr0      (ufp_addr_s.set),
            .din0       (valid_din),
            .dout0      (valid_dout[i])
        );
        sp_ff_array dirty_array (
            .clk0       (clk),
            .rst0       (rst),
            .csb0       (dirty_csb[i]),
            .web0       (dirty_web),
            .addr0      (ufp_addr_s.set),
            .din0       (dirty_din),
            .dout0      (dirty_dout[i])
        );
    end endgenerate

    sp_ff_array #(
        .WIDTH      (3)
    ) lru_array (
        .clk0       (clk),
        .rst0       (rst),
        .csb0       (lru_csb),
        .web0       (lru_web),
        .addr0      (ufp_addr_s.set),
        .din0       (lru_din),
        .dout0      (lru_dout)
    );

endmodule : dcache
