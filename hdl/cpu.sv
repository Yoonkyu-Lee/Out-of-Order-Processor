module cpu
import ooo_cpu_types::*;
(
    input   logic               clk,
    input   logic               rst,

    output  logic   [31:0]      bmem_addr,
    output  logic               bmem_read,
    output  logic               bmem_write,
    output  logic   [63:0]      bmem_wdata,
    input   logic               bmem_ready,

    input   logic   [31:0]      bmem_raddr,
    input   logic   [63:0]      bmem_rdata,
    input   logic               bmem_rvalid
);

cdb_packet_t cdb_packet;

// hello world theres nothing here :(((((
// good luck!
icache_adapter_itf icache_adapter(.clk, .rst);
linebuffer_icache_itf linebuffer_icache(.clk, .rst);
fetch_linebuffer_itf fetch_linebuffer(.clk, .rst);
insn_queue_fetch_itf insn_queue_fetch(.clk, .rst);
decode_insn_queue_itf decode_insn_queue(.clk, .rst);
dispatch_decode_itf dispatch_decode(.clk, .rst);
decode_freelist_itf decode_freelist(.clk, .rst);
decode_rat_read_itf decode_rat_read[2](.clk, .rst);
decode_rat_write_itf decode_rat_write(.clk, .rst);
rstat_dispatch_itf rstat_dispatches[N_RSTATS](.clk, .rst);
//rstat_dispatch_itf alu_rstat_dispatch(.clk, .rst);
//rstat_dispatch_itf mul_rstat_dispatch(.clk, .rst);
//rstat_dispatch_itf div_rstat_dispatch(.clk, .rst);
rob_dispatch_itf rob_dispatch(.clk, .rst);
rrf_rob_itf rrf_rob(.clk, .rst);
rrf_rat_itf rrf_rat(.clk, .rst);
rrf_freelist_itf rrf_freelist(.clk, .rst);
fu_rstat_itf alu_rstat_fu(.clk, .rst);
fu_rstat_itf mul_rstat_fu(.clk, .rst);
fu_rstat_itf div_rstat_fu(.clk, .rst);
cdb_fu_itf cdb_fus[N_RSTATS](.clk, .rst);
//cdb_fu_itf alu_cdb_fu(.clk, .rst);
//cdb_fu_itf mul_cdb_fu(.clk, .rst);
//cdb_fu_itf div_cdb_fu(.clk, .rst);
rstat_prf_itf rstat_prfs[N_RSTATS*2](.clk, .rst);
//rstat_prf_itf alu_rstat_prf[2](.clk, .rst);
//rstat_prf_itf mul_rstat_prf[2](.clk, .rst);
//rstat_prf_itf div_rstat_prf[2](.clk, .rst);

// CP3 stuff
mispredict_t mispredict;
logic rst_mp;
assign rst_mp = rst || mispredict.mispredict;
freelist_rfreelist_t freelist_mp;
decode_freelist_itf rob_rfreelist(.clk, .rst);
lsq_rob_t rob_to_lsq;
fu_rstat_itf ldst_rstat_fu(.clk, .rst);
lsq_dcache_t dcache_to_lsq;
dcache_lsq_t lsq_to_dcache;
// dcache to/from cache_arbiter
logic   [31:0]      d_dfp_addr;
logic               d_dfp_read;
logic               d_dfp_write;
logic   [255:0]    d_dfp_rdata;
logic [255:0]       d_dfp_wdata;
logic              d_dfp_resp;
// cache_arbiter to/from cacheline_adapter
logic   [31:0]     dfp_addr;
logic              dfp_read;
logic              dfp_write;
logic   [255:0]     dfp_rdata;
logic   [255:0]    dfp_wdata;
logic               dfp_resp;


cacheline_adapter cacheline_adapter (
    .clk(clk), 
    .rst(rst),
    .bmem_addr(bmem_addr), 
    .bmem_read(bmem_read),
    .bmem_write(bmem_write), 
    .bmem_wdata(bmem_wdata),
    .bmem_ready(bmem_ready), 
    .bmem_raddr(bmem_raddr),
    .bmem_rdata(bmem_rdata), 
    .bmem_rvalid(bmem_rvalid),

    .dfp_addr(dfp_addr), 
    .dfp_read(dfp_read), 
    .dfp_rdata(dfp_rdata),
    .dfp_resp(dfp_resp), 
    .dfp_write(dfp_write), 
    .dfp_wdata(dfp_wdata)
);

cache_arbiter cache_arbiter (
    .clk(clk), 
    .rst(rst),
    .dfp_addr(dfp_addr), 
    .dfp_read(dfp_read), 
    .dfp_rdata(dfp_rdata),
    .dfp_resp(dfp_resp), 
    .dfp_write(dfp_write), 
    .dfp_wdata(dfp_wdata),

    .d_dfp_addr(d_dfp_addr), 
    .d_dfp_read(d_dfp_read), 
    .d_dfp_rdata(d_dfp_rdata),
    .d_dfp_resp(d_dfp_resp), 
    .d_dfp_write(d_dfp_write), 
    .d_dfp_wdata(d_dfp_wdata),

    .i_dfp_addr(icache_adapter.dfp_addr),
    .i_dfp_read(icache_adapter.dfp_read),
    .i_dfp_rdata(icache_adapter.dfp_rdata),
    .i_dfp_resp(icache_adapter.dfp_resp),
    .i_dfp_write('0),
    .i_dfp_wdata('x)
);

dcache dcahe_inst (
    .clk, .rst,
    .ufp_addr(lsq_to_dcache.ufp_addr),
    .ufp_rmask(lsq_to_dcache.ufp_rmask),
    .ufp_wmask(lsq_to_dcache.ufp_wmask),
    .ufp_wdata(lsq_to_dcache.ufp_wdata),

    .ufp_rdata(dcache_to_lsq.ufp_rdata),
    .ufp_resp(dcache_to_lsq.ufp_resp),
    
    .dfp_addr(d_dfp_addr),
    .dfp_read(d_dfp_read),
    .dfp_write(d_dfp_write),
    .dfp_wdata(d_dfp_wdata),
    .dfp_rdata(d_dfp_rdata),
    .dfp_resp(d_dfp_resp)
);

icache icache (
    .clk, .rst,
    .dfp_addr(icache_adapter.dfp_addr),
    .dfp_read(icache_adapter.dfp_read),
    .dfp_rdata(icache_adapter.dfp_rdata),
    .dfp_resp(icache_adapter.dfp_resp),
    
    .ufp_addr(linebuffer_icache.ufp_addr),
    .ufp_rmask({4{linebuffer_icache.ufp_read}}),
    .ufp_rdata(linebuffer_icache.ufp_rdata),
    .ufp_resp(linebuffer_icache.ufp_resp),
    .ufp_wmask('0), .ufp_wdata('x)
);

linebuffer linebuffer (
    .clk, .rst,
    .ic_addr(linebuffer_icache.ufp_addr),
    .ic_read(linebuffer_icache.ufp_read),
    .ic_valid(linebuffer_icache.ufp_resp),
    .ic_line_data(linebuffer_icache.ufp_rdata),
    .ic_line_tag('x),

    .addr(fetch_linebuffer.addr),
    .read_en(fetch_linebuffer.read),
    .rdata(fetch_linebuffer.rdata),
    .valid(fetch_linebuffer.resp),
    .flush('0)
);


fetch fetch (
    .rst, .clk,
    .rdata(fetch_linebuffer.rdata),
    .resp(fetch_linebuffer.resp),
    .addr(fetch_linebuffer.addr),
    .read(fetch_linebuffer.read),

    .push(insn_queue_fetch.push),
    .full(insn_queue_fetch.full),
    .din(insn_queue_fetch.wdata),
    .mispredict, 
    .cdb(cdb_packet)
);

queue #(
    .WIDTH($bits(insn_queue_t)),
    .DEPTH(8)
) insn_queue (
    .clk, .rst(rst_mp),
    .push(insn_queue_fetch.push),
    .full(insn_queue_fetch.full),
    .din(insn_queue_fetch.wdata),

    .pop(decode_insn_queue.pop),
    .empty(decode_insn_queue.empty),
    .dout(decode_insn_queue.rdata)
);

decode decode (
    //.rst(rst_mp),
    .insn_queue(decode_insn_queue.decode),
    .dispatch(dispatch_decode.decode),
    .freelist(decode_freelist.decode),
    .rat_read(decode_rat_read),
    .rat_write(decode_rat_write.decode)
);

cdb_arbiter cdb_arbiter (
    .clk, .rst(rst_mp),
    .fus(cdb_fus),
    .cdb(cdb_packet)
);

dispatch dispatch (
    .rst(rst_mp),
    .decode(dispatch_decode.dispatch),
    .rob(rob_dispatch.dispatch),
    .rstat(rstat_dispatches),
    .cdb(cdb_packet)
);

/////
// ROB (Reorder Buffer)
/////
logic rvfi_valid;
rvfi_t rvfi_out;

rob rob_inst (
    .dispatch(rob_dispatch.rob),
    .rrf(rrf_rob.rob),
    .cdb(cdb_packet),
    .rvfi_valid(rvfi_valid),
    .rvfi_out(rvfi_out),
    .rob_rfreelist(rob_rfreelist),
    .lsq_rob(rob_to_lsq),
    .mispredict
);

// Reservation Stations
rstat #(
    .NUM_SLOTS(4)
) alu_rstat (
    .rst(rst_mp),
    .dispatch(rstat_dispatches[0]),
    .prf(rstat_prfs[0:1]),
    .fu(alu_rstat_fu.rstat),
    .cdb(cdb_packet)
);

rstat #(
    .NUM_SLOTS(4)
) mul_rstat (
    .rst(rst_mp),
    .dispatch(rstat_dispatches[1]),
    .prf(rstat_prfs[2:3]),
    .fu(mul_rstat_fu.rstat),
    .cdb(cdb_packet)
);

rstat #(
    .NUM_SLOTS(4)
) div_rstat (
    .rst(rst_mp),
    .dispatch(rstat_dispatches[2]),
    .prf(rstat_prfs[4:5]),
    .fu(div_rstat_fu.rstat),
    .cdb(cdb_packet)
);

rstat #(
    .NUM_SLOTS(4)
) ldst_rstat (
    .rst(rst_mp),
    .dispatch(rstat_dispatches[3]),
    .prf(rstat_prfs[6:7]),
    .fu(ldst_rstat_fu.rstat),
    .cdb(cdb_packet)
);

/////
// Physical Register File
/////
prf prf_inst (
    .rstats(rstat_prfs),
    .cdb(cdb_packet)
);
/////
// Functional Units
/////
alu alu_inst (
    //.clk, .rst,
    .rstat_itf(alu_rstat_fu.fu),
    .cdb_itf(cdb_fus[0])
);

multiply multiply_inst (
    .rst(rst_mp),
    .rstat(mul_rstat_fu.fu),
    .cdb(cdb_fus[1])
);

division division_inst (
    .clk, .rst(rst_mp),
    .rstat_itf(div_rstat_fu.fu),
    .cdb_itf(cdb_fus[2])
);

ldst ldst_inst (
    .clk, .rst,
    .rob_to_lsq,
    .lsq_to_dcache,
    .dcache_to_lsq,

    .insn_in(ldst_rstat_fu.insn),
    .rs1_v(ldst_rstat_fu.rs1_v),
    .rs2_v(ldst_rstat_fu.rs2_v),
    .ready(ldst_rstat_fu.ready),

    .cdb_packet(cdb_fus[3].cdb_packet),
    .cdb_ready(cdb_fus[3].ready),

    .mispredict
);

/////
// Register Renaming Components
/////

// Freelist for physical register management
freelist freelist_inst (
    .clk, .rst,
    .pop(decode_freelist.pop),
    .dout(decode_freelist.phys_reg),
    .empty(decode_freelist.empty),
    .rrf_itf(rrf_freelist.freelist),
    .from_rfreelist(freelist_mp)
);
// Freelist but we pop on commit instead of on decode
rfreelist rfreelist_inst (
    .clk, .rst,
    .pop(rob_rfreelist.pop),
    .dout(rob_rfreelist.phys_reg),
    .empty(rob_rfreelist.empty),
    .rrf_itf(rrf_freelist.freelist),
    .to_freelist(freelist_mp),
    .mispredict
);

// Register Alias Table (RAT)
rat rat_inst (
    .clk, .rst,
    .read_port0(decode_rat_read[0].rat),
    .read_port1(decode_rat_read[1].rat),
    .write_port(decode_rat_write.rat),
    .cdb_packet(cdb_packet),
    .rrf_itf(rrf_rat.rat)
    //.rob_itf(rrf_rob.rrf)
);

// Retired Register File (RRF)
rrf rrf_inst (
    .clk, .rst,
    .rob_itf(rrf_rob.rrf),
    .rat_itf(rrf_rat.rrf),
    .freelist_itf(rrf_freelist.rrf),
    .mispredict
);

endmodule : cpu
