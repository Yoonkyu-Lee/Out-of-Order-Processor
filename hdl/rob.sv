module rob
    import ooo_cpu_types::*;
    (
    rob_dispatch_itf.rob dispatch,
    rrf_rob_itf.rob rrf,
    input cdb_packet_t cdb,
    output logic rvfi_valid,
    output rvfi_t rvfi_out,
    decode_freelist_itf.decode rob_rfreelist,
    output mispredict_t mispredict,
    output lsq_rob_t lsq_rob
    );

    insn_t [0:N_ROB-1] entries;
    logic [LOG2_N_ROB:0] head, tail;
    logic [LOG2_N_ROB-1:0] head_idx, tail_idx;
    assign head_idx = head[LOG2_N_ROB-1:0];
    assign tail_idx = tail[LOG2_N_ROB-1:0];

    logic empty, full;
    assign empty = head == tail;
    assign full = head[LOG2_N_ROB] != tail[LOG2_N_ROB]
        && head_idx == tail_idx;

    logic commiting;
    always_comb begin
        commiting = !empty && entries[head_idx].rob_done && entries[head_idx].valid;
        rrf.valid = commiting && entries[head_idx].rd.used &&
            entries[head_idx].rd.arch_idx != 5'b0;
        rrf.arch_reg = entries[head_idx].rd.arch_idx;
        rrf.phys_reg = entries[head_idx].rd.phys_idx;
        // rrf.restore = '0; // mispredicet
        rvfi_valid = commiting;
        rvfi_out = entries[head_idx].rvfi;

        mispredict.mispredict = commiting && entries[head_idx].mispredict;
        mispredict.pc_next = entries[head_idx].pc_next;
        mispredict.order = entries[head_idx].rvfi.order;
        rob_rfreelist.pop = rrf.valid;
        // can ignore these, though empty should always(?) be '0 and
        // phys_reg should always match entries[head_idx].rd.phys_reg
        if (rob_rfreelist.empty | (|rob_rfreelist.phys_reg)) begin end

        lsq_rob.rob_head = head_idx;

        dispatch.ready = !full;
        dispatch.rob_idx = tail_idx;
    end

    always_ff @(posedge rrf.clk) begin
        if(rrf.rst || mispredict.mispredict) begin
            for(integer i = 0; i < N_ROB; i++) begin
                entries[i] <= 'x;
                // note: since we dont use the valid b-it
                // in entries, it gets optimized out.
                // still useful to have for sim
                entries[i].valid <= '0;
            end
            head <= '0;
            tail <= '0;
        end else begin
            // modeled after queue.sv
            if(dispatch.insn.valid && !full) begin
                entries[tail_idx] <= dispatch.insn;
                entries[tail_idx].rob_done <= '0;
                entries[tail_idx].mispredict <= '0;
                tail <= tail + 1'b1;
            end

            if(cdb.valid) begin
                entries[cdb.rob_idx].rvfi <= cdb.rvfi;
                entries[cdb.rob_idx].rob_done <= '1;
                entries[cdb.rob_idx].mispredict <= cdb.mispredict;
                if (cdb.mispredict)
                    entries[cdb.rob_idx].pc_next <= cdb.pc_next;
            end

            if(commiting) begin
                head <= head + 1'b1;
                entries[head_idx] <= 'x;
                entries[head_idx].valid <= '0;
            end

            // TODO set entry to unknown if we write to an
            // entry more than once between the above three cases
            // (this cannot happen normally i think)
        end
    end
endmodule : rob

