module rstat
    import ooo_cpu_types::*;
    #(
        parameter NUM_SLOTS = 4
    )(
        input logic rst,
        rstat_dispatch_itf.rstat dispatch,
        rstat_prf_itf.rstat prf[2],
        fu_rstat_itf.rstat fu,
        input cdb_packet_t cdb
    );

    localparam LOG2_NUM_SLOTS = $clog2(NUM_SLOTS);

    insn_t [0:NUM_SLOTS-1] entries;
    logic [LOG2_NUM_SLOTS-1:0] next_in_slot, next_out_slot;
    logic out_valid;

    always_comb begin
        dispatch.ready = '0;
        out_valid = '0;
        next_in_slot = 'x;
        next_out_slot = 'x;
        for(integer i = 0; i < NUM_SLOTS; i++) begin
            if(!entries[i].valid) begin
                dispatch.ready = '1;
                next_in_slot = unsigned'(LOG2_NUM_SLOTS'(i));
                // yay sv implication operator :D nvm .w.
            end else if((!entries[i].rs1.used || entries[i].rs1.ready)
                && (!entries[i].rs2.used || entries[i].rs2.ready)) begin
                next_out_slot = unsigned'(LOG2_NUM_SLOTS'(i));
                out_valid = '1;
            end
        end

        if(out_valid) begin
            fu.insn = entries[next_out_slot];
            prf[0].phys_reg = fu.insn.rs1.phys_idx;
            prf[1].phys_reg = fu.insn.rs2.phys_idx;
            fu.rs1_v = fu.insn.rs1.arch_idx == 5'b0 ?
                32'b0 : prf[0].reg_v;
            fu.rs2_v = fu.insn.rs2.arch_idx == 5'b0 ?
                32'b0 : prf[1].reg_v;
            fu.insn.rvfi.rs1_rdata = fu.rs1_v;
            fu.insn.rvfi.rs2_rdata = fu.rs2_v;
        end else begin
            fu.insn = 'x;
            fu.insn.valid = '0;
            fu.rs1_v = 'x;
            fu.rs2_v = 'x;
            prf[0].phys_reg = '0;
            prf[1].phys_reg = '0;
        end
    end

    always_ff @(posedge fu.clk) begin
        if(rst) begin
            entries <= 'x;
            for(integer i = 0; i < NUM_SLOTS; i++) begin
                entries[i].valid <= '0;
            end
        end else begin
            if(dispatch.ready) begin
                entries[next_in_slot] <= dispatch.insn;
            end
            if(out_valid && fu.ready) begin
                entries[next_out_slot].valid <= '0;
            end

            if(cdb.valid && cdb.rd_valid) begin
                for(integer i = 0; i < NUM_SLOTS; i++) begin
                    if(entries[i].valid) begin
                        if(entries[i].rs1.phys_idx == cdb.rd_phys_reg) begin
                            entries[i].rs1.ready <= '1;
                        end
                        if(entries[i].rs2.phys_idx == cdb.rd_phys_reg) begin
                            entries[i].rs2.ready <= '1;
                        end
                    end
                end
            end
        end
    end
endmodule : rstat
