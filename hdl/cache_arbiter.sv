module cache_arbiter
(
    input logic clk,
    input logic rst,

    // from icache
    input logic   [31:0]      i_dfp_addr,
    input logic               i_dfp_read,
    input logic               i_dfp_write,
    output logic   [255:0]    i_dfp_rdata,
    input logic [255:0]       i_dfp_wdata,
    output logic              i_dfp_resp,

    // from dcache
    input logic   [31:0]      d_dfp_addr,
    input logic               d_dfp_read,
    input logic               d_dfp_write,
    output logic   [255:0]    d_dfp_rdata,
    input logic [255:0]       d_dfp_wdata,
    output logic              d_dfp_resp,

    // to cacheline_adapter
    output logic   [31:0]     dfp_addr,
    output logic              dfp_read,
    output logic              dfp_write,
    input logic   [255:0]     dfp_rdata,
    output logic   [255:0]    dfp_wdata,
    input logic               dfp_resp
);

    // FSM-based arbitration with dcache priority
    enum logic {  
        idle,
        busy
    } state;
    
    logic locked_select;  // 0 = icache, 1 = dcache
    
    // when access happens
    logic i_cache_access, d_cache_access;
    assign i_cache_access = i_dfp_read | i_dfp_write;
    assign d_cache_access = d_dfp_read | d_dfp_write;
    
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= idle;
            locked_select <= 1'b0;
        end else begin
            case (state)
                idle: begin
                    // accept new request when idle
                    if (d_cache_access || i_cache_access) begin
                        state <= busy;
                        locked_select <= d_cache_access;  // dcache has priority
                    end
                end
                
                busy: begin
                    // Wait for response to complete transaction
                    if (dfp_resp) begin
                        state <= idle;
                    end
                end
            endcase
        end
    end
    
    always_comb begin
            dfp_addr = '0;
            dfp_read = '0;
            dfp_write = '0;
            dfp_wdata = '0;
            d_dfp_rdata = '0;
            d_dfp_resp = '0;
            i_dfp_rdata = '0;
            i_dfp_resp = '0;
        if (state == busy && locked_select) begin
            // Serving dcache
            dfp_addr = d_dfp_addr;
            dfp_read = d_dfp_read;
            dfp_write = d_dfp_write;
            dfp_wdata = d_dfp_wdata;
            d_dfp_rdata = dfp_rdata;
            d_dfp_resp = dfp_resp;
            i_dfp_rdata = '0;
            i_dfp_resp = '0;
        end else if (state == busy && !locked_select) begin
            // Serving icache
            dfp_addr = i_dfp_addr;
            dfp_read = i_dfp_read;
            dfp_write = i_dfp_write;
            dfp_wdata = i_dfp_wdata;
            i_dfp_rdata = dfp_rdata;
            i_dfp_resp = dfp_resp;
            d_dfp_rdata = '0;
            d_dfp_resp = '0;
        end else if (state == idle) begin
            // Pass through requests in IDLE state (prioritize dcache)
            if (d_cache_access) begin
                dfp_addr = d_dfp_addr;
                dfp_read = d_dfp_read;
                dfp_write = d_dfp_write;
                dfp_wdata = d_dfp_wdata;
                d_dfp_rdata = dfp_rdata;
                d_dfp_resp = dfp_resp;
                i_dfp_rdata = '0;
                i_dfp_resp = '0;
            end else begin
                dfp_addr = i_dfp_addr;
                dfp_read = i_dfp_read;
                dfp_write = i_dfp_write;
                dfp_wdata = i_dfp_wdata;
                i_dfp_rdata = dfp_rdata;
                i_dfp_resp = dfp_resp;
                d_dfp_rdata = '0;
                d_dfp_resp = '0;
            end
        end 
        
        // else begin
        // end
    end

endmodule : cache_arbiter