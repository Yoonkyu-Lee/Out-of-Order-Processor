module division
    import ooo_cpu_types::*;
    (
    input   logic               clk,
    input   logic               rst,           

    // From reservation station
    fu_rstat_itf.fu rstat_itf,

    // To CDB
    cdb_fu_itf.fu cdb_itf
);

    localparam WIDTH = 32;
    localparam QUEUE_DEPTH = 8;
    // Queue stores: result + rob_idx + rd info + rvfi
    localparam QUEUE_WIDTH = WIDTH + LOG2_N_ROB + 1 + 5 + LOG2_N_PHYS_REG + $bits(rvfi_t);

    // DesignWare DW_div_seq signals
    logic start;           // Start division
    logic hold;            // Hold current operation
    logic complete;        // Division complete
    logic [WIDTH-1:0] quotient;
    logic [WIDTH-1:0] remainder;
    logic divide_by_0;
    
    // Internal registers
    logic [WIDTH-1:0] rs1_abs, rs2_abs;
    logic result_negative;
    logic [LOG2_N_ROB-1:0] rob_idx_reg;
    logic div_signed_reg;
    logic div_rem_reg;
    logic rd_valid_reg;
    logic [4:0] rd_arch_reg_reg;
    logic [LOG2_N_PHYS_REG-1:0] rd_phys_reg_reg;
    rvfi_t rvfi_reg;
    
    // Output queue signals
    logic queue_push, queue_pop, queue_full, queue_empty;
    logic [QUEUE_WIDTH-1:0] queue_din, queue_dout;
    logic [WIDTH-1:0] result_to_queue;
    
    // Unpacked queue output
    logic [WIDTH-1:0] result_from_queue;
    logic [LOG2_N_ROB-1:0] rob_idx_from_queue;
    logic rd_valid_from_queue;
    logic [4:0] rd_arch_reg_from_queue;
    logic [LOG2_N_PHYS_REG-1:0] rd_phys_reg_from_queue;
    rvfi_t rvfi_from_queue;
    
    // State machine
    typedef enum logic [1:0] {
        IDLE,
        START,
        BUSY
    } state_t;
    
    state_t state, next_state;
    
    // State register
    always_ff @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
        end else begin
            state <= next_state;
        end
    end
    
    // Next state logic
    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (rstat_itf.insn.valid && !queue_full) begin
                    next_state = START;
                end
            end
            START: next_state = BUSY;
            BUSY: begin
                if (complete) begin
                    next_state = IDLE;
                end
            end
        endcase
    end
    
    // Control signals
    always_ff @(posedge clk) begin
        if (rst) begin
            start <= 1'b1;
            rob_idx_reg <= 'x;
            div_signed_reg <= 1'bx;
            div_rem_reg <= 1'bx;
            result_negative <= 1'bx;
            rd_valid_reg <= 1'bx;
            rd_arch_reg_reg <= 'x;
            rd_phys_reg_reg <= 'x;
            rvfi_reg <= 'x;
        end else begin
            case (state)
                IDLE: begin
                    if (rstat_itf.insn.valid && !queue_full) begin
                        start <= 1'b1;
                        rob_idx_reg <= rstat_itf.insn.rob_idx;
                        div_signed_reg <= rstat_itf.insn.div_sign;
                        div_rem_reg <= rstat_itf.insn.div_rem;
                        rd_valid_reg <= rstat_itf.insn.rd.used;
                        rd_arch_reg_reg <= rstat_itf.insn.rd.arch_idx;
                        rd_phys_reg_reg <= rstat_itf.insn.rd.phys_idx;
                        rvfi_reg <= rstat_itf.insn.rvfi;
                        
                        // Handle signed operands
                        if (rstat_itf.insn.div_sign) begin
                            rs1_abs <= rstat_itf.rs1_v[WIDTH-1] ? -rstat_itf.rs1_v : rstat_itf.rs1_v;
                            rs2_abs <= rstat_itf.rs2_v[WIDTH-1] ? -rstat_itf.rs2_v : rstat_itf.rs2_v;
                            if (rstat_itf.insn.div_rem)
                                // sign of remainder equals sign of dividend.
                                // in terms of modular arithmetic, we negate
                                // rs1, so we need to un-negate the output
                                result_negative <= rstat_itf.rs1_v[WIDTH-1];
                            else result_negative <= rstat_itf.rs1_v[WIDTH-1] ^ rstat_itf.rs2_v[WIDTH-1];
                        end else begin
                            rs1_abs <= rstat_itf.rs1_v;
                            rs2_abs <= rstat_itf.rs2_v;
                            result_negative <= 1'b0;
                        end
                    end else begin
                        start <= 1'b1;
                    end
                end
                START: start <= 1'b0;
                BUSY: begin
                    start <= 1'b0;
                end
            endcase
        end
    end
    
    // Hold signal - don't hold unless needed
    assign hold = 1'b0;
    
    // DesignWare Sequential Divider instantiation
    DW_div_seq #(
        .a_width(WIDTH),
        .b_width(WIDTH),
        .tc_mode(0),        // Unsigned (we handle sign externally)
        .num_cyc(WIDTH),    // 32 cycles
        .rst_mode(1),       // Synchronous reset
        .input_mode(1),     // Register inputs
        .output_mode(1),    // Register outputs
        .early_start(0)     // No early start
    ) divider (
        .clk(clk),
        .rst_n(~rst),
        .hold(hold),
        .start(start),
        .a(rs1_abs),
        .b(rs2_abs),
        .complete(complete),
        .divide_by_0(divide_by_0),
        .quotient(quotient),
        .remainder(remainder)
    );
    
    // Result computation with sign correction and divide-by-zero handling
    // Select quotient or remainder based on operation
    logic [WIDTH-1:0] div_result;
    
    always_comb begin
        // First select quotient or remainder
        if (div_rem_reg) begin
            // remainder
            div_result = remainder;
        end else begin
            // division
            div_result = quotient;
        end
        
        // Then handle divide-by-zero and sign
        if (divide_by_0) begin
            if (div_rem_reg) begin
                // return rs1 for rem by zero
                result_to_queue = result_negative ? -rs1_abs : rs1_abs;
            end else begin
                result_to_queue = '1;  // Return max value for divide by zero
            end
        end else if (result_negative) begin
            result_to_queue = -div_result;
        end else begin
            result_to_queue = div_result;
        end
    end
    
    // Queue control
    assign queue_push = complete && (state == BUSY);
    assign queue_din = {result_to_queue, rob_idx_reg, rd_valid_reg, 
                        rd_arch_reg_reg, rd_phys_reg_reg, rvfi_reg};
    assign queue_pop = cdb_itf.ready && !queue_empty;
    
    // Output queue - buffers division results until CDB is ready
    queue #(
        .WIDTH(QUEUE_WIDTH),
        .DEPTH(QUEUE_DEPTH)
    ) output_queue (
        .clk(clk),
        .rst(rst),
        .push(queue_push),
        .full(queue_full),
        .din(queue_din),
        .pop(queue_pop),
        .empty(queue_empty),
        .dout(queue_dout)
    );
    
    // Unpack queue output
    assign {result_from_queue, rob_idx_from_queue, rd_valid_from_queue,
            rd_arch_reg_from_queue, rd_phys_reg_from_queue, rvfi_from_queue} = queue_dout;
    
    // Update RVFI with result
    rvfi_t rvfi_out;
    always_comb begin
        rvfi_out = rvfi_from_queue;
        rvfi_out.rd_wdata = result_from_queue;
    end
    
    // CDB packet construction
    always_comb begin
        cdb_itf.cdb_packet = 'x;
        cdb_itf.cdb_packet.valid = !queue_empty;
        cdb_itf.cdb_packet.rd_valid = rd_valid_from_queue;
        cdb_itf.cdb_packet.rd_arch_reg = rd_arch_reg_from_queue;
        cdb_itf.cdb_packet.rd_phys_reg = rd_phys_reg_from_queue;
        cdb_itf.cdb_packet.rd_v = result_from_queue;
        cdb_itf.cdb_packet.rob_idx = rob_idx_from_queue;
        cdb_itf.cdb_packet.rvfi = rvfi_out;
        cdb_itf.cdb_packet.mispredict = '0;
    end
    
    // Ready signal back to reservation station
    assign rstat_itf.ready = (state == IDLE) && !queue_full;

endmodule : division
