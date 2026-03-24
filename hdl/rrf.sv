module rrf
    import ooo_cpu_types::*;
    (
        input   logic               clk,
        input   logic               rst,
        
        // Interface from ROB for retirement updates
        rrf_rob_itf.rrf rob_itf,
        
        // Interface to RAT for restore on mispredict
        rrf_rat_itf.rrf rat_itf,
        
        // Interface to freelist for freeing old physical registers
        rrf_freelist_itf.rrf freelist_itf,

        // mispredict signal from rob
        input mispredict_t mispredict
    );
    
    
    // RRF storage: tracks committed architectural register -> physical register mappings
    logic [LOG2_N_PHYS_REG-1:0] rrf_table [32];
    logic [LOG2_N_PHYS_REG-1:0] rrf_table_n [32];
    
    // Track the old physical register that needs to be freed
    logic [LOG2_N_PHYS_REG-1:0] old_phys_reg;
    
    // rrf_table_n calculation
    always_comb begin
        rrf_table_n = rrf_table;
        if (rob_itf.valid && rob_itf.arch_reg != 5'd0) begin
            rrf_table_n[rob_itf.arch_reg] = rob_itf.phys_reg;
        end
    end
    
    // Provide all mappings to RAT (combinational) - use next state
    always_comb begin
        for (integer i = 0; i < 32; i++) begin
            rat_itf.phys_reg_mappings[i] = rrf_table_n[i];
        end
        rat_itf.restore = mispredict.mispredict;
        // freelist can never overflow; safe to ignore
        //if(freelist_itf.full) begin end
    end
    
    assign old_phys_reg = rrf_table[rob_itf.arch_reg];
    assign freelist_itf.push = rob_itf.valid && rob_itf.arch_reg != 5'd0;
    assign freelist_itf.din = old_phys_reg;
    
    // Update RRF on retirement
    always_ff @(posedge clk) begin
        if (rst) begin
            // Initialize RRF: arch reg i maps to phys reg i
            for (integer i = 0; i < 32; i++) begin
                rrf_table[i] <= unsigned'(LOG2_N_PHYS_REG'(i));
            end
        end else begin
            // Update mapping when ROB retires an instruction
            if (rob_itf.valid && rob_itf.arch_reg != 5'd0) begin
                rrf_table[rob_itf.arch_reg] <= rob_itf.phys_reg;
            end
        end
    end

endmodule : rrf
