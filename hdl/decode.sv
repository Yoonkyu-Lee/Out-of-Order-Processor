module decode
    import ooo_cpu_types::*;
    (
        decode_insn_queue_itf.decode insn_queue,
        dispatch_decode_itf.decode dispatch,
        decode_freelist_itf.decode freelist,
        decode_rat_read_itf.decode rat_read[2],
        decode_rat_write_itf.decode rat_write
        //cdb_packet_t cdb
    );
    
    insn_t insn_n;
    insn_word_t insn_w;
    //insn_t insn_out;
    logic ready_i;
    logic move;
    logic rd_eq_z;

    logic [31:0] i_imm, u_imm;
    
    always_comb begin
        ready_i = dispatch.ready;
        move = ready_i && !insn_queue.empty;

        insn_queue.pop = ready_i;

        insn_n = 'x;
        insn_n.valid = !insn_queue.empty;
        insn_w.word = insn_queue.rdata.insn;
        insn_n.insn = insn_w;
        insn_n.pc = insn_queue.rdata.pc;
        insn_n.pc_next = insn_queue.rdata.pc_next;

        i_imm = {{21{insn_w.word[31]}},
            insn_w.word[30:20]};
        u_imm = {insn_w.word[31:12], 12'b0};

        insn_n.rob_done = '0;

        insn_n.rs1.used = '0;
        insn_n.rs2.used = '0;
        insn_n.rd.used = '0;
        insn_n.rd.arch_idx = insn_w.r_type.rd;
        insn_n.rs1.arch_idx = insn_w.r_type.rs1;
        insn_n.rs2.arch_idx = insn_w.r_type.rs2;
        // leave a sensible default path for invalid insns from
        // eg uninitialized memory
        insn_n.fu_typ = FU_ALU;
        case(insn_w.r_type.opcode)
        op_lui: begin
            insn_n.rd.used = '1;
            insn_n.fu_typ = FU_ALU;
            insn_n.imm = u_imm;
            insn_n.alu_use = alu_use_imm;
        end
        op_imm: begin
            insn_n.rd.used = '1;
            insn_n.rs1.used = '1;
            insn_n.fu_typ = FU_ALU;
            insn_n.imm = i_imm;
            case(insn_w.r_type.funct3)
            slt: begin
                //TODO in cp3 change this back to cmp
                //insn_n.cmp_op = blt;
                //insn_n.alu_use = alu_use_cmp;
                insn_n.alu_use = alu_use_alu;
                insn_n.alu_op = alu_slt;
            end
            sltu: begin
                //insn_n.cmp_op = bltu;
                //insn_n.alu_use = alu_use_cmp;
                insn_n.alu_use = alu_use_alu;
                insn_n.alu_op = alu_sltu;
            end
            sr: begin
                insn_n.alu_use = alu_use_alu;
                if(insn_w.r_type.funct7 == f7_base) begin
                    // srli
                    insn_n.alu_op = alu_srl;
                end else begin
                    // srai
                    insn_n.alu_op = alu_sra;
                end
            end
            add, sll, axor, aor, aand: begin
                insn_n.alu_use = alu_use_alu;
                insn_n.alu_op = {1'b0, insn_w.r_type.funct3};
            end
            endcase
        end
        op_reg: begin
            insn_n.rd.used = '1;
                insn_n.rs1.used = '1;
            insn_n.rs2.used = '1;
            case(insn_w.r_type.funct7)
            f7_base, f7_aux: begin
                insn_n.fu_typ = FU_ALU;
                case(insn_w.r_type.funct3)
                slt: begin
                    //TODO in cp3 change this back to cmp
                    //insn_n.alu_use = alu_use_cmp;
                    //insn_n.cmp_op = blt;
                    insn_n.alu_use = alu_use_alu;
                    insn_n.alu_op = alu_slt;
                end
                sltu: begin
                    //insn_n.alu_use = alu_use_cmp;
                    //insn_n.cmp_op = bltu;
                    insn_n.alu_use = alu_use_alu;
                    insn_n.alu_op = alu_sltu;
                end
                sr: begin
                    insn_n.alu_use = alu_use_alu;
                    if(insn_w.r_type.funct7 == f7_base) begin
                        // srl
                        insn_n.alu_op = alu_srl;
                    end else begin
                        // sra
                        insn_n.alu_op = alu_sra;
                    end
                end
                add: begin
                    insn_n.alu_use = alu_use_alu;
                    if(insn_w.r_type.funct7 == f7_base) begin
                        // add
                        insn_n.alu_op = alu_add;
                    end else begin
                        // sub
                        insn_n.alu_op = alu_sub;
                    end
                end
                sll, axor, aor, aand: begin
                    insn_n.alu_use = alu_use_alu;
                    insn_n.alu_op = {1'b0, insn_w.r_type.funct3};
                end
                endcase
            end
            f7_mul: begin
                case(insn_w.r_type.funct3)
                mul: begin
                    insn_n.fu_typ = FU_MUL;
                    insn_n.mul_sext_b = '0;
                    insn_n.mul_tc = '0;
                    insn_n.mul_high = '0;
                end
                mulh: begin
                    insn_n.fu_typ = FU_MUL;
                    insn_n.mul_sext_b = '1;
                    insn_n.mul_tc = '1;
                    insn_n.mul_high = '1;
                end
                mulhsu: begin
                    insn_n.fu_typ = FU_MUL;
                    insn_n.mul_sext_b = '0;
                    insn_n.mul_tc = '1;
                    insn_n.mul_high = '1;
                end
                mulhu: begin
                    insn_n.fu_typ = FU_MUL;
                    insn_n.mul_sext_b = '0;
                    insn_n.mul_tc = '0;
                    insn_n.mul_high = '1;
                end
                div: begin
                    insn_n.fu_typ = FU_DIV;
                    insn_n.div_sign = '1;
                    insn_n.div_rem = '0;
                end
                divu: begin
                    insn_n.fu_typ = FU_DIV;
                    insn_n.div_sign = '0;
                    insn_n.div_rem = '0;
                end
                rem: begin
                    insn_n.fu_typ = FU_DIV;
                    insn_n.div_sign = '1;
                    insn_n.div_rem = '1;
                end
                remu: begin
                    insn_n.fu_typ = FU_DIV;
                    insn_n.div_sign = '0;
                    insn_n.div_rem = '1;
                end
                endcase
            end
            endcase
        end
        op_auipc: begin
            insn_n.rd.used = '1;
            insn_n.rs1.used = '1;
            insn_n.rs1.arch_idx = 5'b0;  // x0 = 0
            insn_n.fu_typ = FU_ALU;
            insn_n.imm = u_imm + insn_n.pc;
            insn_n.alu_use = alu_use_alu;
            insn_n.alu_op = alu_add;
        end
        op_jal: begin
            insn_n.rd.used = '1;
            insn_n.fu_typ = FU_ALU;
            // J-type: imm[20|10:1|11|19:12] from inst[31|30:21|20|19:12]
            insn_n.imm = {{12{insn_w.word[31]}}, insn_w.word[19:12], insn_w.word[20], insn_w.word[30:21], 1'b0};
        end
        op_jalr: begin
            insn_n.rd.used = '1;
            insn_n.rs1.used = '1;
            insn_n.fu_typ = FU_ALU;
            insn_n.imm = i_imm;
            insn_n.alu_use = alu_use_alu;
        end
        op_br: begin
            insn_n.rs1.used = '1;
            insn_n.rs2.used = '1;
            insn_n.fu_typ = FU_ALU;
            insn_n.imm = {{20{insn_w.word[31]}}, insn_w.word[7], insn_w.word[30:25], insn_w.word[11:8], 1'b0};
            insn_n.cmp_op = insn_w.r_type.funct3;
            insn_n.alu_use = alu_use_cmp;
        end
        op_load: begin
            insn_n.rd.used = '1;
            insn_n.rs1.used = '1;
            insn_n.fu_typ = FU_MEM;
            insn_n.imm = i_imm;
        end
        op_store: begin
            insn_n.rs1.used = '1;
            insn_n.rs2.used = '1;
            insn_n.fu_typ = FU_MEM;
            insn_n.imm = {{20{insn_w.s_type.imm_s_top[11]}}, insn_w.s_type.imm_s_top, insn_w.s_type.imm_s_bot};
        end
        endcase

        // freelist allocation/dequeuing
        //rd_eq_z = insn_n.rd.arch_idx == 5'b0;
        // if rd is x0, we effectively dont use it
        insn_n.rd.used &= insn_n.rd.arch_idx != 5'b0;
        freelist.pop = move && insn_n.rd.used;
        insn_n.rd.phys_idx = freelist.phys_reg;
        // assert(!freelist.empty)

        // rat remapping
        rat_read[0].arch_reg = insn_n.rs1.arch_idx;
        insn_n.rs1.phys_idx = rat_read[0].phys_reg;
        insn_n.rs1.ready = rat_read[0].reg_ready;
        rat_read[1].arch_reg = insn_n.rs2.arch_idx;
        insn_n.rs2.phys_idx = rat_read[1].phys_reg;
        insn_n.rs2.ready = rat_read[1].reg_ready;

        // rat write
        //rat_write.write = move && insn_n.rd.used && !rd_eq_z;
        rat_write.write = freelist.pop;
        rat_write.arch_reg = insn_n.rd.arch_idx;
        rat_write.phys_reg = insn_n.rd.phys_idx;

        insn_n.rvfi = insn_queue.rdata.rvfi;
        insn_n.rvfi.inst = insn_w.word;
        insn_n.rvfi.rs1_addr = insn_n.rs1.used ?
            insn_n.rs1.arch_idx : 5'b0;
        insn_n.rvfi.rs1_rdata = insn_n.rs1.used ?
            32'bx : 32'b0;
        insn_n.rvfi.rs2_addr = insn_n.rs2.used ?
            insn_n.rs2.arch_idx : 5'b0;
        insn_n.rvfi.rs2_rdata = insn_n.rs2.used ?
            32'bx : 32'b0;
        insn_n.rvfi.rd_addr = insn_n.rd.used ?
            insn_n.rd.arch_idx : 5'b0;
        insn_n.rvfi.rd_wdata = insn_n.rd.used ?
            32'bx : 32'b0;
        insn_n.rvfi.mem_addr = '0;
        insn_n.rvfi.mem_rmask = '0;
        insn_n.rvfi.mem_wmask = '0;

        dispatch.insn = insn_n;
    end

    /*
    always_ff @(posedge insn_queue.clk) begin
        if(insn_queue.rst) begin
            insn_out <= 'x;
            insn_out.valid <= '0;
        end else begin
            if(move) begin
                insn_out <= insn_n;
            end
        end
    end
    */
endmodule : decode
