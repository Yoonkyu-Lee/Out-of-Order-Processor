module rat
import ooo_cpu_types::*;
(
    input   logic               clk,
    input   logic               rst,

    // Read ports from decode (for looking up rs1, rs2)
    decode_rat_read_itf.rat read_port0,
    decode_rat_read_itf.rat read_port1,
    
    // Write port from decode (for allocating rd)
    decode_rat_write_itf.rat write_port,
    
    // CDB broadcast for updating ready bits
    input cdb_packet_t cdb_packet,
    
    // Interface to RRF
    rrf_rat_itf.rat rrf_itf
    
    // Interface to ROB
    //rrf_rob_itf.rrf rob_itf
);

    // RAT storage: maps architectural register -> physical register
    logic [LOG2_N_PHYS_REG-1:0] rat_table [32];
    
    // Ready b-it table: tracks if architectural register is ready (32 bits, one per arch reg)
    logic [31:0] ready_bits, ready_bits_read;
    logic [31:0] ready_bits_next;
    
    // Forward restore signal from ROB to RRF
    //assign rrf_itf.restore = rob_itf.restore;
    
    always_comb begin
        ready_bits_next = ready_bits;
        
        if (cdb_packet.valid && cdb_packet.rd_valid && cdb_packet.rd_arch_reg != 5'd0 &&
            cdb_packet.rd_phys_reg ==
                rat_table[cdb_packet.rd_arch_reg]) begin
            ready_bits_next[cdb_packet.rd_arch_reg] = 1'b1;
        end

        ready_bits_read = ready_bits_next;
        
        // Apply write port (clears ready b-it)
        if (write_port.write && write_port.arch_reg != 5'd0) begin
            ready_bits_next[write_port.arch_reg] = 1'b0;
        end
        
        // x0 always ready
        ready_bits_next[0] = 1'b1;
    end
    
    // Read port 0 - uses next ready bits for bypass
    assign read_port0.phys_reg = rat_table[read_port0.arch_reg];
    assign read_port0.reg_ready = (read_port0.arch_reg == 5'd0) ? 1'b1 : 
                                   ready_bits_read[read_port0.arch_reg];
    
    // Read port 1 - uses next ready bits for bypass
    assign read_port1.phys_reg = rat_table[read_port1.arch_reg];
    assign read_port1.reg_ready = (read_port1.arch_reg == 5'd0) ? 1'b1 : 
                                   ready_bits_read[read_port1.arch_reg];
    
    // Sequential logic for RAT table and ready bits
    always_ff @(posedge clk) begin
        if (rst) begin
            // Initialize RAT: arch reg i maps to phys reg i
            for (integer j = 0; j < 32; j++) begin
                rat_table[j] <= unsigned'(LOG2_N_PHYS_REG'(j));
            end
            
            // Initialize ready bits: all architectural registers ready
            ready_bits <= 32'hFFFFFFFF;
        end else if (rrf_itf.restore) begin
            // Restore RAT from RRF on branch mispredict/exception
            for (integer j = 0; j < 32; j++) begin
                rat_table[j] <= rrf_itf.phys_reg_mappings[j];
            end
            
            // All restored registers are ready (committed state)
            ready_bits <= 32'hFFFFFFFF;
        end else begin
            // Update RAT mapping
            if (write_port.write && write_port.arch_reg != 5'd0) begin
                rat_table[write_port.arch_reg] <= write_port.phys_reg;
            end
            
            // Update ready bits (using the computed next value)
            ready_bits <= ready_bits_next;
        end
    end

endmodule : rat
