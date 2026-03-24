module rfreelist
import ooo_cpu_types::*;
(
    input   logic               clk,
    input   logic               rst,           

    //allocate (dequeue) - for decode to get a new physical register
    input   logic               pop,
    output  logic [LOG2_N_PHYS_REG-1:0]   dout,
    output  logic               empty,

    //free (enqueue) - from RRF to return a physical register to the free list
    rrf_freelist_itf.freelist rrf_itf,

    output freelist_rfreelist_t to_freelist,
    input mispredict_t mispredict
);
localparam NUM_PHYS_REGS = N_PHYS_REG;

logic [NUM_PHYS_REGS-1:0][$clog2(NUM_PHYS_REGS)-1:0] free_regs;    // Queue of free physical register numbers
logic [NUM_PHYS_REGS-1:0][$clog2(NUM_PHYS_REGS)-1:0] free_regs_n;    // Queue of free physical register numbers on next clk cycle

//head and tail pointers
logic [$clog2(NUM_PHYS_REGS):0] head, tail, head_n, tail_n;

logic full;

//logic signals
always_comb begin
    //empty - default value
    empty = 1'b0;
    full = 1'b0;
    //empty when head equals tail
    if(head == tail) begin
        empty = 1'b1;
    end
    //full when head and tail indices match but wrap bits differ
    if(head[$clog2(NUM_PHYS_REGS)-1:0] == tail[$clog2(NUM_PHYS_REGS)-1:0] &&
       head[$clog2(NUM_PHYS_REGS)] != tail[$clog2(NUM_PHYS_REGS)]) begin
        full = 1'b1;
    end

    free_regs_n = free_regs;
    head_n = head;
    tail_n = tail;

    //free - store freed physical register number from RRF
    if(rrf_itf.push && !full) begin
        free_regs_n[tail[$clog2(NUM_PHYS_REGS)-1:0]] = rrf_itf.din;
        tail_n = tail + 1'b1;
    end
    //allocate - remove register from queue (being allocated to decode)
    if(pop && !empty) begin
        free_regs_n[head[$clog2(NUM_PHYS_REGS)-1:0]] = 'x;
        head_n = head + 1'b1;
    end

    // need to use free_regs_n, since we need to pop the rd used by jal/jalr
    // instructions
    to_freelist.write = mispredict.mispredict;
    to_freelist.free_regs = free_regs_n;
    to_freelist.head = head_n;
    to_freelist.tail = tail_n;
end

//allocate - output the next free physical register
assign dout = free_regs[head[$clog2(NUM_PHYS_REGS)-1:0]];

//assign full signal to interface
//assign rrf_itf.full = full;

always_ff @(posedge clk) begin
    if(rst) begin
        // Initialize with physical registers 32 through NUM_PHYS_REGS-1
        // (registers 1-31 are reserved for initial architectural register mappings)
        free_regs <= 'x;
        free_regs[0] <= '0; // x0 doesnt need a mapping
        for (integer i = 32; i < NUM_PHYS_REGS; i++) begin
            free_regs[i-31] <= unsigned'(($clog2(NUM_PHYS_REGS))'(i));
        end
        head <= '0;
        tail <= unsigned'(($clog2(NUM_PHYS_REGS)+1)'(NUM_PHYS_REGS - 31));  // Tail points past the last initialized register
    end else begin
        free_regs <= free_regs_n;
        head <= head_n;
        tail <= tail_n;
    end
end




endmodule : rfreelist
