package ooo_cpu_types;
    // ROB size parameter
    // parameter ROB_DEPTH = 32;  // Default to 16 entries
    // parameter ROB_IDX_WIDTH = $clog2(ROB_DEPTH);
    
    typedef struct packed {
        logic [63:0] order;
        logic [31:0] inst;
        logic [4:0] rs1_addr, rs2_addr, rd_addr;
        logic [31:0] rs1_rdata, rs2_rdata, rd_wdata;
        logic [31:0] pc_rdata, pc_wdata;
        logic [31:0] mem_addr, mem_rdata, mem_wdata;
        logic [3:0] mem_rmask, mem_wmask;
    } rvfi_t;

    typedef struct packed {
        logic [31:0] pc;
        logic [31:0] pc_next;
        logic [31:0] insn;
        rvfi_t rvfi;
    } insn_queue_t;

    // note: the size of fu_typ_t could change in future checkpoints
    typedef enum logic [3:0] {
        FU_ALU = 4'b0001,
        FU_MUL = 4'b0010,
        FU_DIV = 4'b0100,
        FU_MEM = 4'b1000
    } fu_typ_t; // short for function unit type

    //localparam N_PHYS_REG = 1 << LOG2_N_PHYS_REG;
    // remember to tweak sram config when changing N_PHYS_REG!
    localparam N_PHYS_REG = 128;
    localparam LOG2_N_PHYS_REG = $clog2(N_PHYS_REG);
    //localparam N_ROB = 1 << LOG2_N_ROB;
    localparam N_ROB = 32;
    localparam LOG2_N_ROB = $clog2(N_ROB);

    localparam N_RSTATS = 4;
    localparam LOG2_N_RSTATS = $clog2(N_RSTATS);
    localparam logic [0:N_RSTATS-1] [$bits(fu_typ_t)-1:0] RSTAT_TYPES = {
        FU_ALU, FU_MUL, FU_DIV, FU_MEM
    };

    typedef struct packed {
        // whether an insn uses the given reg
        // (eg BEQ doesnt use rd)
        logic used;
        logic ready;
        logic [4:0] arch_idx;
        logic [LOG2_N_PHYS_REG-1:0] phys_idx;
    } reg_info_t;

    typedef enum logic [6:0] {
        f7_base = 7'b0000000,
        f7_aux  = 7'b0100000,
        // all rv32m insns use this funct7,
        // and have opcode op_reg
        f7_mul  = 7'b0000001
    } funct7_t;

    typedef enum logic [2:0] {
        mul    = 3'b000,
        mulh   = 3'b001,
        mulhsu = 3'b010,
        mulhu  = 3'b011,
        div    = 3'b100,
        divu   = 3'b101,
        rem    = 3'b110,
        remu   = 3'b111
    } mul_funct3_t;

    // BEGIN MP_PIPELINE CODE
typedef enum logic [6:0] {
    op_lui       = 7'b0110111, // load upper imemediate (U type)
    op_auipc     = 7'b0010111, // add upper imemediate PC (U type)
    op_jal       = 7'b1101111, // jump and link (J type)
    op_jalr      = 7'b1100111, // jump and link register (I type)
    op_br        = 7'b1100011, // branch (B type)
    op_load      = 7'b0000011, // load (I type)
    op_store     = 7'b0100011, // store (S type)
    op_imm       = 7'b0010011, // arith ops with register/imemediate operands (I type)
    op_reg       = 7'b0110011  // arith ops with register operands (R type)
  } rv32i_opcode;

  typedef enum logic [2:0] {
    beq  = 3'b000,
    bne  = 3'b001,
    blt  = 3'b100,
    bge  = 3'b101,
    bltu = 3'b110,
    bgeu = 3'b111
  } branch_funct3_t;

  typedef enum logic [2:0] {
    branch_f3_beq  = 3'b000,
    branch_f3_bne  = 3'b001,
    branch_f3_blt  = 3'b100,
    branch_f3_bge  = 3'b101,
    branch_f3_bltu = 3'b110,
    branch_f3_bgeu = 3'b111
  } cmpop_t;

  typedef enum logic [2:0] {
    lb  = 3'b000,
    lh  = 3'b001,
    lw  = 3'b010,
    lbu = 3'b100,
    lhu = 3'b101
  } load_funct3_t;

  typedef enum logic [2:0] {
    sb = 3'b000,
    sh = 3'b001,
    sw = 3'b010
  } store_funct3_t;

  typedef enum logic [2:0] {
    add  = 3'b000, //check logic 30 for sub if op_reg opcode
    sll  = 3'b001,
    slt  = 3'b010,
    sltu = 3'b011,
    axor = 3'b100,
    sr   = 3'b101, //check logic 30 for logical/arithmetic
    aor  = 3'b110,
    aand = 3'b111
  } arith_funct3_t;

  typedef enum logic [3:0] {
    alu_add  = 4'b0000,
    alu_sll  = 4'b0001,
    alu_sra  = 4'b0010,
    alu_sub  = 4'b0011,
    alu_xor  = 4'b0100,
    alu_srl  = 4'b0101,
    alu_or   = 4'b0110,
    alu_and  = 4'b0111,
    alu_slt  = 4'b1000,
    alu_sltu = 4'b1001
  } alu_ops;

  typedef union packed {
    logic [31:0] word;

    struct packed {
      logic [11:0] i_imm;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  rd;
      rv32i_opcode opcode;
    } i_type;

    struct packed {
      logic [6:0]  funct7;
      logic [4:0]  rs2;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  rd;
      rv32i_opcode opcode;
    } r_type;

    struct packed {
      logic [11:5] imm_s_top;
      logic [4:0]  rs2;
      logic [4:0]  rs1;
      logic [2:0]  funct3;
      logic [4:0]  imm_s_bot;
      rv32i_opcode opcode;
    } s_type;

    struct packed {
      logic [31:12] imm;
      logic [4:0]   rd;
      rv32i_opcode  opcode;
    } j_type;
  } insn_word_t;
    // END MP_PIPELINE CODE

    typedef enum logic [1:0] {
        alu_use_alu,
        alu_use_cmp,
        alu_use_imm
    } alu_use_t;

    typedef struct packed {
        // insn going out of decode
        // used in many places lol, helps simplify the logic a b-it
        logic valid;
        // note that any dead logic gets eliminated by synthesis
        // (to a certain extent), so unused entries in this struct
        // shouldddd get optimized out

        // need original insn word for rob entry
        insn_word_t insn;
        fu_typ_t fu_typ;
        // reg_info_t.arch_idx is redundant since it's in insn too, but
        // synthesis shouldd be able to combine the flip flops together
        // since the offset in insn for each arch_idx is always the same,
        // so the flip flops have the same inputs
        reg_info_t rd, rs1, rs2;
        logic [LOG2_N_ROB-1:0] rob_idx;
        // TODO, may need more signals in here, especially if we precalculate
        // certain things in decode eg immediate values, alu op, etc
        logic [3:0] alu_op;
        logic [2:0] cmp_op;
        alu_use_t alu_use;

        logic mul_sext_b;
        logic mul_tc;
        logic mul_high;

        logic div_sign;
        logic div_rem;

        // should try to merge these together, to save on rstat area
        // (ie use the adder in dispatch trick for computing pc+imm)
        logic [31:0] pc, pc_next, imm;
        logic rob_done;
        logic mispredict;
        rvfi_t rvfi;
    } insn_t;

    // LSQ entry structure
    typedef struct packed {
        insn_t insn;
        logic [31:0] addr;
        logic [31:0] store_data;  // for stores
        logic [3:0] rmask;
        logic [3:0] wmask;
        logic is_load;
        logic is_store;
    } lsq_entry_t;

    typedef struct packed {
        logic valid;
        logic rd_valid; // whether the insn produced an rd
        logic [4:0] rd_arch_reg;
        logic [LOG2_N_PHYS_REG-1:0] rd_phys_reg;
        logic [31:0] rd_v;
        logic [LOG2_N_ROB-1:0] rob_idx;
        logic mispredict; // valid signal for pc_next
        logic [31:0] pc_next;
        rvfi_t rvfi;
    } cdb_packet_t;

    typedef struct packed {
        // high when a mispredict occurs,
        // when high, pc_next contains the new pc
        logic mispredict;
        logic [31:0] pc_next;
        logic [63:0] order; // order of branch insn
    } mispredict_t;

    // rfreelist (retirement freelist) receives the same push signals as freelist, but
    // receives pop signals from rob's currently committing insn.
    // so there are connections from
    // rfreelist -> freelist
    // rob -> rfreelist.decode_freelist_itf
    // rob -> rfreelist.mispredict_t
    // rrf -> rfreelist.rrf_freelist_itf

    typedef struct packed {
        // when write is high, copy rfreelist to freelist
        logic write;
        logic [N_PHYS_REG-1:0][LOG2_N_PHYS_REG-1:0] free_regs;
        logic [LOG2_N_PHYS_REG:0] head, tail;
    } freelist_rfreelist_t;

    typedef struct packed {
        // the rob idx that we're currently trying to commit.
        // all prior instructions have already committed.
        logic [LOG2_N_ROB-1:0] rob_head;
    } lsq_rob_t; // rob to lsq

    typedef struct packed {
        // same as mp_cache waveforms
        logic   [31:0]  ufp_addr;
        logic   [3:0]   ufp_rmask;
        logic   [3:0]   ufp_wmask;
        logic   [31:0]  ufp_wdata;
    } dcache_lsq_t; // lsq to dcache

    typedef struct packed {
        // same as mp_cache waveforms
        logic   [31:0]  ufp_rdata;
        logic           ufp_resp;
    } lsq_dcache_t; // dcache to lsq
endpackage : ooo_cpu_types

interface icache_adapter_itf (
    input logic clk,
    input logic rst
    );
    logic [31:0]  dfp_addr;
    logic         dfp_read;
    logic [255:0] dfp_rdata;
    logic         dfp_resp;
    modport icache (
        input dfp_resp, dfp_rdata,
        output dfp_addr, dfp_read
        );
    modport adapter (
        output dfp_resp, dfp_rdata,
        input dfp_addr, dfp_read
        );
endinterface : icache_adapter_itf

interface linebuffer_icache_itf (
    input logic clk,
    input logic rst
    );
    logic [31:0] ufp_addr;
    logic        ufp_read;
    logic [255:0] ufp_rdata;
    logic         ufp_resp;
    modport icache (
        input ufp_addr, ufp_read,
        output ufp_resp, ufp_rdata
        );
    modport linebuffer (
        output ufp_addr, ufp_read,
        input ufp_resp, ufp_rdata
        );
endinterface : linebuffer_icache_itf

interface fetch_linebuffer_itf (
    input logic clk,
    input logic rst
    );
    logic [31:0] addr;
    logic        read;
    logic [31:0] rdata;
    logic        resp;
    modport fetch (
        output addr, read,
        input rdata, resp
        );
    modport linebuffer (
        input addr, read,
        output rdata, resp
        );
endinterface : fetch_linebuffer_itf

interface insn_queue_fetch_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    insn_queue_t wdata;
    logic        full, push;
    modport fetch (
        output wdata, push,
        input full
        );
    modport insn_queue (
        input wdata, push,
        output full
        );
endinterface : insn_queue_fetch_itf

interface decode_insn_queue_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    insn_queue_t rdata;
    logic        empty, pop;
    modport insn_queue (
        output rdata, empty,
        input pop
        );
    modport decode (
        input rdata, empty,
        output pop
        );
endinterface : decode_insn_queue_itf

interface dispatch_decode_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    insn_t insn;
    logic ready;
    modport dispatch (
        output ready,
        input insn
        );
    modport decode (
        input ready,
        output insn
        );
endinterface : dispatch_decode_itf

interface decode_freelist_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    logic pop, empty;
    logic [LOG2_N_PHYS_REG-1:0] phys_reg;
    modport decode (
        output pop,
        input empty, phys_reg
        );
    modport freelist (
        input pop,
        output empty, phys_reg
        );
endinterface : decode_freelist_itf

interface decode_rat_read_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    logic [4:0] arch_reg;
    logic [LOG2_N_PHYS_REG-1:0] phys_reg;
    logic reg_ready;
    modport decode (
        output arch_reg,
        input phys_reg, reg_ready
        );
    modport rat (
        input arch_reg,
        output phys_reg, reg_ready
        );
endinterface : decode_rat_read_itf

interface decode_rat_write_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    logic write;
    logic [4:0] arch_reg;
    logic [LOG2_N_PHYS_REG-1:0] phys_reg;
    modport decode (
        output write, arch_reg, phys_reg
        );
    modport rat (
        input write, arch_reg, phys_reg
        );
endinterface : decode_rat_write_itf

interface rstat_dispatch_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    insn_t insn;
    logic ready;
    modport rstat (
        input insn,
        output ready
        );
    modport dispatch (
        output insn,
        input ready
        );
endinterface : rstat_dispatch_itf

interface rob_dispatch_itf
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst
    );
    insn_t insn;
    logic [LOG2_N_ROB-1:0] rob_idx;
    logic ready;
    // rob_idx has its value the same
    // cycle as (insn.valid && ready)
    // is high
    modport rob (
        output ready, rob_idx,
        input insn, clk, rst
        );
    modport dispatch (
        input ready, rob_idx, clk, rst,
        output insn
        );
endinterface : rob_dispatch_itf

interface rrf_rob_itf
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst
    );
    logic valid;
    logic [4:0] arch_reg;
    logic [LOG2_N_PHYS_REG-1:0] phys_reg;
    //logic restore;  // Signal to restore RAT from committed state (on branch mispredict/exception)
    modport rrf (
        input valid, arch_reg, phys_reg, clk, rst
    );
    modport rob (
        input clk, rst,
        output valid, arch_reg, phys_reg
    );
endinterface : rrf_rob_itf

interface rrf_rat_itf
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst
    );
    logic restore;  // Signal to restore RAT from RRF (e.g., on branch mispredict)
    logic [LOG2_N_PHYS_REG-1:0] phys_reg_mappings [32];  // All 32 arch->phys mappings from RRF
    modport rrf (
        output restore, phys_reg_mappings
    );
    modport rat (
        input restore, phys_reg_mappings
    );
endinterface : rrf_rat_itf

interface rrf_freelist_itf
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst
    );
    logic push;  // RRF asserts to push a freed physical register
    // logic full;  // Freelist asserts when full (cannot accept more frees)
    logic [LOG2_N_PHYS_REG-1:0] din;  // Physical register to return to freelist
    modport rrf (
        output push, din
        //input full
    );
    modport freelist (
        input push, din
        //output full
    );
endinterface : rrf_freelist_itf

// cdb_arb_out_itf is just cdb_packet_t

interface cdb_fu_itf
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst
    );
    logic ready;
    cdb_packet_t cdb_packet;
    modport fu (
        output cdb_packet,
        input ready, clk, rst
        );
    modport arb (
        input cdb_packet, clk, rst,
        output ready
        );
endinterface : cdb_fu_itf

interface rstat_prf_itf
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst
    );
    // combinational response currently
    //logic read, ready_i;
    logic [LOG2_N_PHYS_REG-1:0] phys_reg;
    logic [31:0] reg_v;
    //logic reg_v_valid;
    modport rstat (
        output phys_reg,
        input reg_v, clk, rst
    );
    modport prf (
        input phys_reg, clk, rst,
        output reg_v
    );
endinterface : rstat_prf_itf

//////
// functional units
//////

interface fu_rstat_itf
    import ooo_cpu_types::*;
    (
    input logic clk,
    input logic rst
    );
    insn_t insn;
    logic [31:0] rs1_v, rs2_v;
    logic ready;
    modport fu (
        input insn, rs1_v, rs2_v, clk, rst,
        output ready
        );
    modport rstat (
        output insn, rs1_v, rs2_v,
        input ready, clk, rst
        );
endinterface : fu_rstat_itf


// interface functional_unit_itf 
//     import ooo_cpu_types::*;
//     (
//     input logic clk,
//     input logic rst
//     );
//     // Input signals (from reservation station)
//     logic                      valid_in;
//     logic [31:0]               rs1;
//     logic [31:0]               rs2;
//     logic [2:0]                aluop;
//     logic [LOG2_N_ROB-1:0]     rob_idx_in; // Updated to use LOG2_N_ROB
    
//     // Output signals (to CDB)
//     logic                      valid_out;
//     logic [31:0]               result;
//     logic [LOG2_N_ROB-1:0]     rob_idx_out; // Updated to use LOG2_N_ROB
    
//     modport reservation_station (
//         output valid_in, rs1, rs2, aluop, rob_idx_in,
//         input valid_out, result, rob_idx_out
//     );
    
//     modport fu (
//         input valid_in, rs1, rs2, aluop, rob_idx_in,
//         output valid_out, result, rob_idx_out
//     );
    
// endinterface : functional_unit_itf
