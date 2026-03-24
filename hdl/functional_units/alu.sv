module alu
    import ooo_cpu_types::*;
    (
    //input   logic               clk,
    //input   logic               rst,           

    // From reservation station
    fu_rstat_itf.fu rstat_itf,

    // To CDB
    cdb_fu_itf.fu cdb_itf
);

    localparam WIDTH = 32;
    
    // Extract operands from interface
    logic signed   [31:0] as;
    logic signed   [31:0] bs;
    logic unsigned [31:0] au;
    logic unsigned [31:0] bu;
    
    // Select rs2 or immediate based on instruction
    logic [31:0] operand2;
    assign operand2 = rstat_itf.insn.rs2.used ? rstat_itf.rs2_v : rstat_itf.insn.imm;

    assign as = signed'(rstat_itf.rs1_v);
    assign bs = signed'(operand2);
    assign au = unsigned'(rstat_itf.rs1_v);
    assign bu = unsigned'(operand2);
    logic [WIDTH-1:0] aluout;
    logic [WIDTH-1:0] alu_fu_out;
    logic [3:0] aluop;
    logic [2:0] cmpop;
    logic br_en;
    rvfi_t rvfi_out;
    
    assign aluop = rstat_itf.insn.alu_op;
    assign cmpop = rstat_itf.insn.cmp_op;

    logic [31:0] rd_v;
    logic [31:0] target_pc;
    logic is_branch, is_jal, is_jalr;
        
/*
    always_ff @(posedge clk) begin
        if(rst) begin
        end else begin
        end
    end */

    // Branch comparison logic
    always_comb begin
        unique case (cmpop)
            branch_f3_beq : br_en = (au == bu);
            branch_f3_bne : br_en = (au != bu);
            branch_f3_blt : br_en = (as <  bs);
            branch_f3_bge : br_en = (as >= bs);
            branch_f3_bltu: br_en = (au <  bu);
            branch_f3_bgeu: br_en = (au >= bu);
            default       : br_en = 1'bx;
        endcase
    end

    // ALU operations
    always_comb begin
        unique case (aluop)
            alu_add:  aluout = au +   bu;
            alu_sll:  aluout = au <<  bu[4:0];
            alu_sra:  aluout = unsigned'(as >>> bu[4:0]);
            alu_sub:  aluout = au -   bu;
            alu_xor:  aluout = au ^   bu;
            alu_srl:  aluout = au >>  bu[4:0];
            alu_or:   aluout = au |   bu;
            alu_and:  aluout = au &   bu;
            alu_slt:  aluout = {31'b0, (as < bs)};
            alu_sltu: aluout = {31'b0, (au < bu)};
            default:  aluout = 'x;
        endcase 

        alu_fu_out = 'x;
        case(rstat_itf.insn.alu_use)
            alu_use_alu: alu_fu_out = aluout;
            alu_use_cmp: alu_fu_out = {31'b0, br_en};  // Branch comparison result
            alu_use_imm: alu_fu_out = rstat_itf.insn.imm;
        endcase

        // Determine rd value based on instruction type
        is_branch = (rstat_itf.insn.insn.i_type.opcode == op_br);
        is_jal    = (rstat_itf.insn.insn.i_type.opcode == op_jal);
        is_jalr   = (rstat_itf.insn.insn.i_type.opcode == op_jalr);
        
        // target PC
        if (is_jalr) begin
            target_pc = (rstat_itf.rs1_v + rstat_itf.insn.imm) & 32'hfffffffe;
        end else begin
            target_pc = rstat_itf.insn.pc + rstat_itf.insn.imm;  // Branch or JAL
        end
        
        // rd value
        if (is_jal || is_jalr) begin
            rd_v = rstat_itf.insn.pc + 'd4;  // Return address
        end else begin
            rd_v = alu_fu_out;  // Normal ALU result
        end

        cdb_itf.cdb_packet.valid = rstat_itf.insn.valid;
        cdb_itf.cdb_packet.rd_valid = rstat_itf.insn.rd.used &&
            rstat_itf.insn.rd.arch_idx != 5'b0;
        cdb_itf.cdb_packet.rd_arch_reg = rstat_itf.insn.rd.arch_idx;
        cdb_itf.cdb_packet.rd_phys_reg = rstat_itf.insn.rd.phys_idx;
        cdb_itf.cdb_packet.rd_v = rd_v;
        cdb_itf.cdb_packet.rob_idx = rstat_itf.insn.rob_idx;
        
        // Handle misprediction for branches/jumps
        if (is_branch) begin
            cdb_itf.cdb_packet.pc_next = br_en ? target_pc : rstat_itf.insn.pc + 32'd4;
            cdb_itf.cdb_packet.mispredict = (cdb_itf.cdb_packet.pc_next != rstat_itf.insn.pc_next);
        end else if (is_jal || is_jalr) begin
            cdb_itf.cdb_packet.mispredict = (target_pc != rstat_itf.insn.pc_next);
            cdb_itf.cdb_packet.pc_next = target_pc;
        end else begin
            cdb_itf.cdb_packet.mispredict = 1'b0;
            cdb_itf.cdb_packet.pc_next = '0;
        end
        
        rvfi_out = rstat_itf.insn.rvfi;
        rvfi_out.rd_wdata = rd_v;
        if (is_branch || is_jal || is_jalr) begin
            rvfi_out.pc_wdata = cdb_itf.cdb_packet.pc_next;
        end
        cdb_itf.cdb_packet.rvfi = rvfi_out;
    
        rstat_itf.ready = cdb_itf.ready;
    end
    
endmodule : alu
