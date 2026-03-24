module fetch
import ooo_cpu_types::*;
(
    input logic clk,
    input logic rst,

    input mispredict_t mispredict,

    //from linebuffer
    input logic [31:0] rdata, // instruction
    input logic resp, //ready signal
    output logic [31:0] addr, // pc address to fetch from
    output logic read, // read signal enable (youre doing a read from the line buffer)

    //to instruction queue
    output logic push,
    input logic full,
    output insn_queue_t din,

    // CDB for branch predictor training
    input cdb_packet_t cdb
);


// prefetcher 

//logic signals
// pc_valid: whether the pc holds a linebuffer request that we care about
logic pc_valid;
logic [31:0] pc, pc_next; // program counter
logic [63:0] order;

// Branch predictor signals
logic predict_taken;
logic [31:0] predict_target;
logic [31:0] pc_for_prediction;

// Query predictor with the correct PC
// During normal operation: predict for pc_next
// During mispredict: we need the prediction for what comes AFTER we set pc=mispredict.pc_next
assign pc_for_prediction = pc_next;

branch_predictor bp_inst (
    .clk(clk),
    .rst(rst),
    .pc_fetch(pc_for_prediction),
    .predict_taken(predict_taken),
    .predict_target(predict_target),
    .cdb(cdb)
);


//pc sequentual logic
always_ff @(posedge clk) begin
    if(rst) begin
        // reset logic if needed
        pc_valid <= '1;
        pc <= 32'haaaaa000;
        pc_next <= 32'haaaaa004;
        order <= '0;
    end else begin
        if (mispredict.mispredict) begin
            if (read && !resp && !full) begin
                // need to keep pc and read stable through a mispredict
                pc_valid <= '0;
                pc_next <= mispredict.pc_next;
                order <= mispredict.order;
            end else begin
                pc_valid <= '1;
                pc <= mispredict.pc_next;
                // For the instruction at mispredict.pc_next, the next PC is always pc+4
                pc_next <= mispredict.pc_next + 32'd4;
                order <= mispredict.order + 64'd1;
            end
        end else if (!full && resp) begin
            // only advance PC when queue is not full and we get a response
            pc_valid <= '1;
            pc <= pc_next;
            pc_next <= predict_taken ? predict_target : (pc_next + 4);
            order <= order + 64'd1;
        end
        // if queue is full or no response yet, keep PC unchanged
    end
end

// Output assignments
always_comb begin
    // Always request from the current PC address
    addr = pc;
    read = !full;
    push = resp && pc_valid; // add when logic when br predictor is done
    din.insn = rdata;
    din.pc = pc;
    din.pc_next = pc_next;

    din.rvfi = 'x;
    din.rvfi.inst = rdata;
    din.rvfi.order = order;
    din.rvfi.pc_rdata = pc;
    din.rvfi.pc_wdata = pc_next;
    // the rest of rvfi is set in decode, rstat, and the end of the fus
end

endmodule : fetch
