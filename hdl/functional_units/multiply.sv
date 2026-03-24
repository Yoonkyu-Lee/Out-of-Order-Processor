module multiply 
    import ooo_cpu_types::*;
    (
        input logic rst,
        fu_rstat_itf.fu rstat,
        cdb_fu_itf.fu cdb
    /*
    input   logic               clk,
    input   logic               rst,           

    //from functional unit
    output  logic               ready,
    input   logic               input_valid,
    input   logic [31:0]   rs1,
    input   logic [31:0]   rs2,
    input   logic               mul_signed,
    input   logic [LOG2_N_ROB-1:0]  rob_idx_in,

    // to CDB
    output  logic                      output_valid,
    output  logic [31:0]          rd_v,
    output  logic [LOG2_N_ROB-1:0]  rob_idx_out,
    input   logic                      cdb_ready
    */
);

    localparam NUM_STAGES = 4;  // Pipeline stages for multiplier
    //localparam QUEUE_DEPTH = 8; // Output queue depth
    //localparam QUEUE_WIDTH = 32 + $bits(insn_t); // result + rob_idx

    // DesignWare signals
    logic [31:0] a_reg;
    logic [32:0] b_reg;
    logic [64:0] product;
    logic tc_reg;  // Two's complement mode
    
    // Pipeline valid bits and ROB indices
    //logic [NUM_STAGES-1:0] valid_pipe;
    //logic [LOG2_N_ROB-1:0] rob_idx_pipe [NUM_STAGES];
    insn_t [0:NUM_STAGES-1] insn_pipe;
    
    // Output queue signals
    //logic queue_push, queue_pop, queue_full, queue_empty;
    //logic [QUEUE_WIDTH-1:0] queue_din, queue_dout;
    
    // Input stage - can accept when queue has space
    always_ff @(posedge cdb.clk) begin
        if (rst) begin
            a_reg <= 'x;
            b_reg <= 'x;
            tc_reg <= 'x;
            //valid_pipe[0] <= '0;
            //rob_idx_pipe[0] <= '0;
        end else begin
            if (cdb.ready) begin
                a_reg <= rstat.rs1_v;
                b_reg <= {rstat.insn.mul_sext_b & rstat.rs2_v[31],
                    rstat.rs2_v};
                tc_reg <= rstat.insn.mul_tc;
                //valid_pipe[0] <= 1'b1;
                //rob_idx_pipe[0] <= rstat.insn.rob_idx;
            end else begin
                //valid_pipe[0] <= 1'b0;
            end
        end
    end
    
    // DesignWare Pipelined Multiplier
    DW_mult_pipe #(
        .a_width(32),
        .b_width(33),
        .num_stages(NUM_STAGES),  // Number of pipeline stages
        .stall_mode(1),            // 1 = stall capability
        .rst_mode(0),              // 0 = no reset
        .op_iso_mode(0)            // 0 = no operand isolation
    ) mult_pipe (
        .clk(cdb.clk),
        .rst_n(~cdb.rst),
        .en(cdb.ready),  // Enable when queue has space
        .tc(tc_reg),               // Two's complement mode
        .a(a_reg),
        .b(b_reg),
        .product(product)
    );
    
    // Pipeline the valid bits and ROB indices to match multiplier latency
    always_ff @(posedge cdb.clk) begin
        if (rst) begin
            for (integer i = 0; i < NUM_STAGES; i++) begin
                //valid_pipe[i] <= '0;
                //rob_idx_pipe[i] <= '0;
                insn_pipe[i] <= 'x;
                insn_pipe[i].valid <= '0;
            end
        end else if (cdb.ready) begin
            insn_pipe[0] <= rstat.insn;
            // Advance pipeline when queue has space
            for (integer i = 1; i < NUM_STAGES; i++) begin
                //valid_pipe[i] <= valid_pipe[i-1];
                //rob_idx_pipe[i] <= rob_idx_pipe[i-1];
                insn_pipe[i] <= insn_pipe[i-1];
            end
        end
        // else: stall - keep current values
    end
    
    // Output queue - buffers results until CDB is ready
    /*assign queue_push = valid_pipe[NUM_STAGES-1] && (!queue_full || queue_pop);
    assign queue_din = {product[31:0], rob_idx_pipe[NUM_STAGES-1]};
    assign queue_pop = cdb_ready && !queue_empty;
    
    queue #(
        .WIDTH(32 + LOG2_N_ROB),
        .DEPTH(QUEUE_DEPTH)
    ) output_queue (
        .clk(cdb.clk),
        .rst(cdb.rst),
        .push(queue_push),
        .full(queue_full),
        .din(queue_din),
        .pop(queue_pop),
        .empty(queue_empty),
        .dout(queue_dout)
    );*/
    
    // Output assignments from queue
    //assign rstat.ready = !valid_pipe[0] || (!queue_full || queue_pop);
    assign rstat.ready = cdb.ready;
    //assign cdb. = !queue_empty;
    //assign {rd_v, rob_idx_out} = queue_dout;

    insn_t insn_out;
    assign insn_out = insn_pipe[NUM_STAGES-1];

    always_comb begin
        cdb.cdb_packet = 'x;
        cdb.cdb_packet.valid = insn_out.valid;
        cdb.cdb_packet.rd_valid = insn_out.rd.arch_idx != 5'b0;
        cdb.cdb_packet.rd_arch_reg = insn_out.rd.arch_idx;
        cdb.cdb_packet.rd_phys_reg = insn_out.rd.phys_idx;
        cdb.cdb_packet.rd_v = insn_out.mul_high ?
            product[63:32] : product[31:0];
        cdb.cdb_packet.rob_idx = insn_out.rob_idx;

        cdb.cdb_packet.rvfi = insn_out.rvfi;
        cdb.cdb_packet.rvfi.rd_wdata = cdb.cdb_packet.rd_v;
        cdb.cdb_packet.mispredict = '0;
    end

endmodule : multiply
