module ldst  
    import ooo_cpu_types::*;
(
    input logic clk,
    input logic rst,

    // ROB
    input lsq_rob_t rob_to_lsq,

    // dcache
    output dcache_lsq_t lsq_to_dcache,
    input lsq_dcache_t dcache_to_lsq,

    // reservation station 
    input insn_t insn_in,
    input logic [31:0] rs1_v,
    input logic [31:0] rs2_v,
    output logic ready,

    // cdb
    output cdb_packet_t cdb_packet,
    input logic cdb_ready,

    // mispredict
    input mispredict_t mispredict
);
    // lsq
    localparam LSQ_DEPTH = 8;
    logic lsq_push, lsq_pop, lsq_full, lsq_empty;
    logic lsq_rst;
    lsq_entry_t lsq_din, lsq_dout, lsq_inflight;

    // ready signal to res station station
    assign ready = !lsq_full;

    // reset if mispredict or rst
    assign lsq_rst = rst || mispredict.mispredict;

    lsq_entry_t [N_ROB-1:0] lsq;

    always_ff @(posedge clk) begin
        if(lsq_rst) begin
            lsq <= 'x;
            for(integer i = 0; i < N_ROB; i++) begin
                lsq[i].insn.valid <= '0;
            end
        end else begin
            if (lsq_push) begin
                lsq[lsq_din.insn.rob_idx] <= lsq_din;
            end
            if (lsq_pop) begin
                lsq[rob_to_lsq.rob_head] <= 'x;
                lsq[rob_to_lsq.rob_head].insn.valid <= '0;
            end
        end
    end
    assign lsq_dout = lsq[rob_to_lsq.rob_head];
    assign lsq_full = '0;
    // note: lsq_empty could go from 1 to 0 without a push, unlike a standard
    // queue
    assign lsq_empty = !lsq_dout.insn.valid;

    /*
    queue #(
        .WIDTH($bits(lsq_entry_t)),
        .DEPTH(LSQ_DEPTH)
    ) lsq (
        .clk(clk),
        .rst(lsq_rst),
        .push(lsq_push),
        .full(lsq_full),
        .din(lsq_din),
        .pop(lsq_pop),
        .empty(lsq_empty),
        .dout(lsq_dout)
    ); */

    // Track inflight cache request
    /*
    logic inflight_request;
    always_ff @(posedge clk) begin
        if (rst) begin
            inflight_request <= 1'b0;
        end else if (dcache_to_lsq.ufp_resp) begin
            // Clear when response arrives
            inflight_request <= 1'b0;
        end else if ((lsq_to_dcache.ufp_rmask != 4'b0000 || lsq_to_dcache.ufp_wmask != 4'b0000)) begin
            // Set when issuing new request
            inflight_request <= 1'b1;
        end
    end */

    // Track if inflight request was from before mispredict
    logic inflight_is_stale;
    always_ff @(posedge clk) begin
        if (rst) begin
            inflight_is_stale <= 1'b0;
        end else if (mispredict.mispredict &&
                !dcache_to_lsq.ufp_resp) begin
            // Mark inflight request as stale
            inflight_is_stale <= 1'b1;
        end else if (dcache_to_lsq.ufp_resp) begin
            // Clear after response
            inflight_is_stale <= 1'b0;
        end
    end

    // memory address calculation
    logic [31:0] mem_addr;
    logic [31:0] mem_wdata;
    logic [3:0] mem_rmask, mem_wmask;
    logic is_load_insn, is_store_insn;
    
    // check if incoming instruction is load/store
    assign is_load_insn = insn_in.valid && (insn_in.insn.i_type.opcode == op_load);
    assign is_store_insn = insn_in.valid && (insn_in.insn.s_type.opcode == op_store);
    
    // calculate address: rs1 + immediate for loads/stores
    assign mem_addr = rs1_v + insn_in.imm;
    
    // generate masks and shift data for incoming instruction
    always_comb begin
        mem_rmask = 4'b0000;
        mem_wmask = 4'b0000;
        mem_wdata = '0;
        
        if (is_load_insn) begin
            unique case (insn_in.insn.i_type.funct3)
                lb, lbu: mem_rmask = 4'b0001 << mem_addr[1:0];
                lh, lhu: mem_rmask = 4'b0011 << mem_addr[1:0];
                lw     : mem_rmask = 4'b1111;
                default: mem_rmask = 'x;
            endcase
        end else if (is_store_insn) begin
            unique case (insn_in.insn.s_type.funct3)
                sb: mem_wmask = 4'b0001 << mem_addr[1:0];
                sh: mem_wmask = 4'b0011 << mem_addr[1:0];
                sw: mem_wmask = 4'b1111;
                default: mem_wmask = 'x;
            endcase
            
            unique case (insn_in.insn.s_type.funct3)
                sb: mem_wdata[8*mem_addr[1:0] +: 8]   = rs2_v[7:0];
                sh: mem_wdata[16*mem_addr[1] +: 16]   = rs2_v[15:0];
                sw: mem_wdata = rs2_v;
                default: mem_wdata = 'x;
            endcase
        end
    end
    
    // enqueue logic - push ready load/store instructions (but not during mispredict)
    always_comb begin
        lsq_push = (is_load_insn || is_store_insn) && !lsq_full && !mispredict.mispredict;
        
        lsq_din.insn = insn_in;
        lsq_din.addr = mem_addr;
        lsq_din.store_data = mem_wdata;
        lsq_din.rmask = mem_rmask;
        lsq_din.wmask = mem_wmask;
        lsq_din.is_load = is_load_insn;
        lsq_din.is_store = is_store_insn;
    end
    
    // send to dcache 
    logic can_issue, are_issuing;
    // need to keep dcache request constant until getting a response back
    lsq_entry_t lsq_dcache_req;
    always_comb begin
        // loads can issue immediately
        // stores can only issue when ROB head matches (in-order commit)
        can_issue = !lsq_empty && !mispredict.mispredict && cdb_ready &&
            !lsq_inflight.insn.valid;
        are_issuing = can_issue || lsq_inflight.insn.valid;
        lsq_dcache_req = lsq_inflight.insn.valid ? lsq_inflight : lsq_dout;
        
        lsq_to_dcache.ufp_addr = {lsq_dcache_req.addr[31:2], 2'b00};  // Word-align for cache
        lsq_to_dcache.ufp_rmask = {4{are_issuing}} & lsq_dcache_req.rmask;
        lsq_to_dcache.ufp_wmask = {4{are_issuing}} & lsq_dcache_req.wmask;
        lsq_to_dcache.ufp_wdata = lsq_dcache_req.store_data;
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            lsq_inflight <= 'x;
            lsq_inflight.insn.valid <= '0;
        end else begin
            if (can_issue) begin
                lsq_inflight <= lsq_dout;
            end else if (dcache_to_lsq.ufp_resp) begin
                lsq_inflight <= 'x;
                lsq_inflight.insn.valid <= '0;
            end
        end
    end
    
    // dequeue logic
    logic valid_response;
    assign valid_response = dcache_to_lsq.ufp_resp && !inflight_is_stale;
    assign lsq_pop = valid_response;
    // it's still ok to use lsq_dout for the following, since only on
    // mispredict does a mismatch between lsq_dcache_req and lsq_dout occur.
    
    // data load
    logic [31:0] rd_v;
    always_comb begin
        rd_v = '0;
        if (valid_response && lsq_dout.is_load) begin
            unique case (lsq_dout.insn.insn.i_type.funct3)
                lb : rd_v = {{24{dcache_to_lsq.ufp_rdata[7 + 8*lsq_dout.addr[1:0]]}}, dcache_to_lsq.ufp_rdata[8*lsq_dout.addr[1:0] +: 8]};
                lbu: rd_v = {{24{1'b0}}, dcache_to_lsq.ufp_rdata[8*lsq_dout.addr[1:0] +: 8]};
                lh : rd_v = {{16{dcache_to_lsq.ufp_rdata[15 + 16*lsq_dout.addr[1]]}}, dcache_to_lsq.ufp_rdata[16*lsq_dout.addr[1] +: 16]};
                lhu: rd_v = {{16{1'b0}}, dcache_to_lsq.ufp_rdata[16*lsq_dout.addr[1] +: 16]};
                lw : rd_v = dcache_to_lsq.ufp_rdata;
                default: rd_v = 'x;
            endcase
        end
    end
    
    // cdb
    always_comb begin
        cdb_packet = 'x;
        cdb_packet.valid = valid_response;
        cdb_packet.rd_valid = lsq_dout.is_load;
        cdb_packet.rd_arch_reg = lsq_empty ? 'x : lsq_dout.insn.insn.i_type.rd;
        cdb_packet.rd_phys_reg = lsq_empty ? 'x : lsq_dout.insn.rd.phys_idx;
        cdb_packet.rd_v = rd_v;
        cdb_packet.rob_idx = lsq_empty ? 'x : lsq_dout.insn.rob_idx;
        cdb_packet.rvfi = lsq_empty ? 'x : lsq_dout.insn.rvfi;
        cdb_packet.mispredict = '0;
        
        // rvfi
        if (valid_response) begin
            cdb_packet.rvfi.mem_addr = lsq_dout.addr;
            cdb_packet.rvfi.mem_rmask = lsq_dout.rmask;
            cdb_packet.rvfi.mem_wmask = lsq_dout.wmask;
            cdb_packet.rvfi.mem_wdata = lsq_dout.store_data;
            if (lsq_dout.is_load) begin
                cdb_packet.rvfi.mem_rdata = dcache_to_lsq.ufp_rdata;
                cdb_packet.rvfi.rd_wdata = rd_v;
            end else begin
                cdb_packet.rvfi.rd_wdata = 32'h0;
            end
        end
    end
    

endmodule : ldst
