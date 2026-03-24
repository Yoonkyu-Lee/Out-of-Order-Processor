module dispatch
    import ooo_cpu_types::*;
    (
        input logic rst,
        dispatch_decode_itf.dispatch decode,
        rob_dispatch_itf.dispatch rob,
        rstat_dispatch_itf.dispatch rstat[N_RSTATS],
        input cdb_packet_t cdb
    );

    insn_t insn_in;
    logic ready_o;
    logic move;
    insn_t insn_out, insn_fwd;

    insn_t [0:N_RSTATS-1] insn_out_arr;
    logic [0:N_RSTATS-1] ready_arr;

    always_ff @(posedge rob.clk) begin
        if(rst) begin
            insn_in <= 'x;
            insn_in.valid <= '0;
        end else begin
            if(move) begin
                insn_in <= decode.insn;
            end else insn_in <= insn_fwd;
        end
    end

    always_comb begin
        insn_out = insn_in;

        // forwarding logic yay
        if(cdb.valid && cdb.rd_valid) begin
            if(insn_out.rs1.used &&
                insn_out.rs1.phys_idx == cdb.rd_phys_reg) begin
                insn_out.rs1.ready = '1;
            end
            if(insn_out.rs2.used &&
                insn_out.rs2.phys_idx == cdb.rd_phys_reg) begin
                insn_out.rs2.ready = '1;
            end
        end
        insn_fwd = insn_out;

        insn_out.valid &= rob.ready;
        insn_out.rob_idx = rob.rob_idx;

        ready_o = '0;
        for(integer i = 0; i < N_RSTATS; i++) begin
            if(({$bits(fu_typ_t){1'b0}} != (insn_out.fu_typ & RSTAT_TYPES[i])) &&
                ready_arr[i] && !ready_o && insn_out.valid) begin
                ready_o = '1;
                insn_out_arr[i] = insn_out;
            end else begin
                insn_out_arr[i] = 'x;
                insn_out_arr[i].valid = '0;
            end
        end

        move = (ready_o && rob.ready) || !insn_in.valid;
        decode.ready = move;

        rob.insn = insn_in;
        rob.insn.valid &= ready_o;
    end

    for(genvar i = 0; i < N_RSTATS; i++) begin
        assign rstat[i].insn = insn_out_arr[i];
        assign ready_arr[i] = rstat[i].ready;
    end
endmodule : dispatch
