module cacheline_adapter
(
    input   logic               clk,
    input   logic               rst,
    

    // all from cpu
    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid,


    //from cache
    input   logic   [31:0]      dfp_addr,
    input   logic               dfp_read,
    input   logic               dfp_write,
    output  logic   [255:0]     dfp_rdata,
    input   logic   [255:0]     dfp_wdata,
    output  logic               dfp_resp


);

logic [255:0] read_data_buffer, read_data_buffer_n;
logic unused;
assign unused = |bmem_raddr;

//fsm state machine 
enum integer unsigned {
    idle,
    read_burst0,
    read_burst1,
    read_burst2,
    read_burst3,
    write_burst0,
    write_burst1,
    write_burst2,
    //write_burst3,
    resp_s
} state, state_next;

always_ff @(posedge clk) begin
    if (rst) begin
        state <= idle;
        read_data_buffer <= 'x;
    end else begin
        state <= state_next;
        read_data_buffer <= read_data_buffer_n;
    end
end


always_comb begin
    if (state != resp_s) begin
        dfp_resp = 1'b0;
        dfp_rdata = 'x;
    end else begin
        dfp_resp = 1'b1;
        dfp_rdata = read_data_buffer;
    end
end


// fsm combinational logic
always_comb begin
    //default values
    state_next = state;
    read_data_buffer_n = read_data_buffer;
    bmem_addr = '0;
    bmem_read = 1'b0;
    bmem_write = 1'b0;
    bmem_wdata = '0;

    unique case (state)
        idle: begin
            if (dfp_read && bmem_ready) begin
                state_next = read_burst0;
                bmem_addr = dfp_addr;
                bmem_read = 1'b1;
            end else if (dfp_write && bmem_ready) begin
                state_next = write_burst0;
                bmem_addr = dfp_addr;
                bmem_write = 1'b1;
                bmem_wdata = dfp_wdata[63:0];
            end
        end
        
        // Read burst states
        read_burst0: begin
            if (bmem_rvalid) begin
                read_data_buffer_n[63:0] = bmem_rdata;
                state_next = read_burst1;
            end
        end
        read_burst1: begin
            if (bmem_rvalid) begin
                read_data_buffer_n[127:64] = bmem_rdata;
                state_next = read_burst2;
            end
        end
        read_burst2: begin
            if (bmem_rvalid) begin
                read_data_buffer_n[191:128] = bmem_rdata;
                state_next = read_burst3;
            end
        end
        read_burst3: begin
            if (bmem_rvalid) begin
                read_data_buffer_n[255:192] = bmem_rdata;
                state_next = resp_s;
            end
        end
        

        write_burst0: begin
            state_next = write_burst1;
            bmem_addr = dfp_addr;
            bmem_write = 1'b1;
            bmem_wdata = dfp_wdata[127:64];
        end
        write_burst1: begin
            state_next = write_burst2;
            bmem_addr = dfp_addr;
            bmem_write = 1'b1;
            bmem_wdata = dfp_wdata[191:128];
        end
        write_burst2: begin
            state_next = resp_s;
            bmem_addr = dfp_addr;
            bmem_write = 1'b1;
            bmem_wdata = dfp_wdata[255:192];
        end
        /*write_burst3: begin
            state_next = resp_s;
        end*/
        
        resp_s: begin
            
            state_next = idle;
        end
        
        default: begin
            state_next = idle;
            read_data_buffer_n = '0;
        end
    endcase 
end


endmodule : cacheline_adapter
