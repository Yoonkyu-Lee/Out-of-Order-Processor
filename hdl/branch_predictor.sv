module branch_predictor
    import ooo_cpu_types::*;
    (
        input logic clk,
        input logic rst,

        //from fetch
        input  logic [31:0] pc_fetch,
        output logic        predict_taken,
        output logic [31:0] predict_target,

        //cdb
        input cdb_packet_t cdb
    );

    // Gshare parameters
    localparam GHR_WIDTH = 8;  // Global history register width
    localparam PHT_SIZE = 256; // Pattern history table size (2^GHR_WIDTH)
    localparam PHT_IDX_WIDTH = $clog2(PHT_SIZE);
    localparam BTB_SIZE = 256; // Branch target buffer size
    localparam BTB_IDX_WIDTH = $clog2(BTB_SIZE);

    // global history register
    logic [GHR_WIDTH-1:0] ghr;

    // pattern history table
    logic [1:0] pht [PHT_SIZE-1:0];

    // branch target buffer
    logic [31:0] btb_tags [BTB_SIZE-1:0];
    logic [31:0] btb_targets [BTB_SIZE-1:0];
    logic        btb_valid [BTB_SIZE-1:0];

    // prediction logic
    logic [PHT_IDX_WIDTH-1:0] pred_pht_idx;
    logic [BTB_IDX_WIDTH-1:0] pred_btb_idx;
    logic btb_hit;

    assign pred_pht_idx = (pc_fetch[PHT_IDX_WIDTH+1:2] ^ ghr[PHT_IDX_WIDTH-1:0]);
    assign pred_btb_idx = pc_fetch[BTB_IDX_WIDTH+1:2];
    assign btb_hit = btb_valid[pred_btb_idx] && (btb_tags[pred_btb_idx] == pc_fetch);

    // Predict taken if: PHT counter >= 2 (weakly/strongly taken) AND BTB has target
    assign predict_taken = pht[pred_pht_idx][1] && btb_hit;
    assign predict_target = btb_hit ? btb_targets[pred_btb_idx] : 32'h0;


    logic is_branch, is_jal, is_jalr;
    logic actual_taken;
    logic [PHT_IDX_WIDTH-1:0] train_pht_idx;
    logic [BTB_IDX_WIDTH-1:0] train_btb_idx;
    logic [31:0] branch_pc, actual_target;

    assign is_branch = (cdb.rvfi.inst[6:0] == op_br);
    assign is_jal = (cdb.rvfi.inst[6:0] == op_jal);
    assign is_jalr = (cdb.rvfi.inst[6:0] == op_jalr);
    assign branch_pc = cdb.rvfi.pc_rdata;
    assign actual_target = cdb.rvfi.pc_wdata;
    assign actual_taken = (actual_target != branch_pc + 4);

    assign train_pht_idx = (branch_pc[PHT_IDX_WIDTH+1:2] ^ ghr[PHT_IDX_WIDTH-1:0]);
    assign train_btb_idx = branch_pc[BTB_IDX_WIDTH+1:2];



    // Training logic
    // Training logic
    always_ff @(posedge clk) begin
        if (rst) begin
            ghr <= '0;
            for (integer i = 0; i < PHT_SIZE; i++) begin
                pht[i] <= 2'b01;  // initialize to weakly not taken
            end
            for (integer i = 0; i < BTB_SIZE; i++) begin
                btb_valid[i] <= 1'b0;
                btb_tags[i] <= '0;
                btb_targets[i] <= '0;
            end
        end else begin
            // Train on conditional branches only
            if (cdb.valid && is_branch) begin
                // update pht
                if (actual_taken) begin
                    if (pht[train_pht_idx] != 2'b11)
                        pht[train_pht_idx] <= pht[train_pht_idx] + 1'b1;
                end else begin
                    if (pht[train_pht_idx] != 2'b00)
                        pht[train_pht_idx] <= pht[train_pht_idx] - 1'b1;
                end

                // Update BTB with target
                if (actual_taken) begin
                    btb_valid[train_btb_idx] <= 1'b1;
                    btb_tags[train_btb_idx] <= branch_pc;
                    btb_targets[train_btb_idx] <= actual_target;
                end

                // Update global history register
                ghr <= {ghr[GHR_WIDTH-2:0], actual_taken};
                
            end
            
            // Also train BTB on JAL/JALR (always taken)
            if (cdb.valid && (is_jal || is_jalr)) begin
                btb_valid[train_btb_idx] <= 1'b1;
                btb_tags[train_btb_idx] <= branch_pc;
                btb_targets[train_btb_idx] <= actual_target;
                

            end
        end
    end


endmodule : branch_predictor