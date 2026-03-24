module cdb_arbiter
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst,
        
        // FU interface array
        // [0]=ALU, [1]=MUL, [2]=DIV (default order)
        // parameter i-nt NUM_FUS = 3 for now
        cdb_fu_itf.arb fus[N_RSTATS],
        
        // CDB output (broadcast)
        output cdb_packet_t cdb

        // might need to edit either this module or fus because
        // alu, mul, div is not using intf currently??
    );
    localparam NUM_FUS = N_RSTATS;

    // Round-Robin State
    // one-hot encoded
    //logic [0:N_RSTATS-1] next_priority;  // FU with priority in the next cycle

    // buffer one packet per fu, so that we can have multiple
    // fus with ready high
    cdb_packet_t [0:N_RSTATS-1] inp_pkts;
    logic [0:N_RSTATS-1] inp_ready;

    // Arbitration Logic (Combinational)
    logic [$clog2(NUM_FUS)-1:0] grant_idx;  // Index of granted FU
    logic grant_valid;  // Was any FU selected?

    logic [0:N_RSTATS-1] fus_ready;
    cdb_packet_t [0:N_RSTATS-1] fus_pkts;

    for(genvar i = 0; i < N_RSTATS; i++) begin
        assign fus[i].ready = fus_ready[i];
        assign fus_pkts[i] = fus[i].cdb_packet;
    end

    /*
    logic [0:N_RSTATS-1] rr_try;

    for(genvar i = 0; i < N_RSTATS; i++) begin
        assign rr_try
    end
    */

    always_comb begin
        // Default: no grant
        cdb = 'x;
        cdb.valid = '0;
        grant_idx = 'x;
        grant_valid = 1'b0;

        // Clear all ready signals
        inp_ready = '0;

        // Round-robin arbitration: 2-pass search
        // Pass 1: Search from next_priority to end
        // TODO: potentially improve synthesizeability of this loop
        // (by passing a signal between each iteration, where
        // iteration next_priority starts at one, and each iteration
        // passes the signal to the next only if the current one
        // isnt valid)
        for (integer i = 0; i < NUM_FUS; i++) begin
            //genvar idx = (next_priority + i) % NUM_FUS;  // Wrap around
            //integer idx = next_priority + i;
            //if(idx >= NUM_FUS) idx -= NUM_FUS;
            if (inp_pkts[i].valid && !grant_valid) begin
                cdb = inp_pkts[i];
                inp_ready[i] = 1'b1;
                grant_idx = unsigned'(LOG2_N_RSTATS'(i));
                grant_valid = 1'b1;
                break;  // Found one, stop
            end
        end
        //rr_try = '0;

        // set fu ready signals
        for (integer i = 0; i < NUM_FUS; i++) begin
            fus_ready[i] = inp_ready[i] || !inp_pkts[i].valid;
        end
    end

    // Update next_priority (Sequential)
    always_ff @(posedge clk) begin
        if (rst) begin
            /*next_priority <= '0;  // Start with FU[0]
            next_priority[0] <= '1; */
            for(integer i = 0; i < N_RSTATS; i++) begin
                inp_pkts[i] <= 'x;
                inp_pkts[i].valid <= '0;
            end
        end else begin
            /*
            if (grant_valid) begin
                // Move to next FU for fairness
                //next_priority <= (grant_idx + 1) % NUM_FUS;
                next_priority <= '0;
                next_priority[(grant_idx+1)%N_RSTATS] <= '1;
                // by setting next_priority to the fu after
                // the one we went with this cycle (grant_idx)
                // we properly evenly cycle between the available
                // fus if only a subset are available (eg only alu
                // fus if the code doesnt use div/mul)
            end */
            // else: no grant this cycle, keep same priority

            for(integer i = 0; i < N_RSTATS; i++) begin
                if(fus_ready[i]) inp_pkts[i] <= fus_pkts[i];
            end
        end
    end

endmodule : cdb_arbiter

// Obsolete idea using port from each fu...
/*
 import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst,
        
        // From ALU
        input logic alu_valid,
        input logic [31:0] alu_result,
        input logic [LOG2_N_ROB-1:0] alu_rob_idx,
        output logic alu_ready,
        
        // From Multiplier
        input logic mul_valid,
        input logic [31:0] mul_result,
        input logic [LOG2_N_ROB-1:0] mul_rob_idx,
        output logic mul_ready,
        
        // From Divider
        input logic div_valid,
        input logic [31:0] div_result,
        input logic [LOG2_N_ROB-1:0] div_rob_idx,
        output logic div_ready,
        
        // CDB output (broadcast to all modules)
        output cdb_packet_t cdb
    );
*/

