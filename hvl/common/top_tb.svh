    longint timeout;
    initial begin
        if (!$value$plusargs("OOOCPU_TIMEOUT=%d", timeout)) begin
            void'($value$plusargs("TIMEOUT_ECE411=%d", timeout));
        end
    end

    bit cpu_clk;
    bit cpu_rst = '1;
    bit run_cpu_test = '0;
    assign cpu_clk = clk && run_cpu_test;

    mem_itf_banked mem_itf(.rst(cpu_rst), .clk(cpu_clk), .*);
    dram_w_burst_frfcfs_controller mem(.itf(mem_itf));

    mon_itf #(.CHANNELS(8)) mon_itf(.rst(cpu_rst), .clk(cpu_clk), .*);
    monitor #(.CHANNELS(8)) monitor(.itf(mon_itf));

    cpu dut(
        .clk            (cpu_clk),
        .rst            (cpu_rst),

        .bmem_addr  (mem_itf.addr  ),
        .bmem_read  (mem_itf.read  ),
        .bmem_write (mem_itf.write ),
        .bmem_wdata (mem_itf.wdata ),
        .bmem_ready (mem_itf.ready ),
        .bmem_raddr (mem_itf.raddr ),
        .bmem_rdata (mem_itf.rdata ),
        .bmem_rvalid(mem_itf.rvalid)
    );

    `include "rvfi_reference.svh"

    import ooo_cpu_types::*;
    // Fetch-stage regression hook
    logic insn_queue_pop = 'x;

    logic insn_queue_empty;
    assign insn_queue_empty = dut.decode_insn_queue.empty;
    insn_queue_t insn_queue_dout;
    assign insn_queue_dout = dut.decode_insn_queue.rdata;
    bit [31:0] expected_addr;
    bit [31:0] expected_insn;

    localparam NUM_POP_PROB_THRESHOLDS = 5;
    int pop_prob_threshold = 0;
    int pop_rand_sample;

    always_ff @(posedge cpu_clk) begin
        if (cpu_rst) 
            expected_addr = 32'hAAAAA000;
        if (!cpu_rst && insn_queue_pop && !insn_queue_empty) begin
            if (insn_queue_dout.pc !== expected_addr) begin
                $fatal("incorrect pc popped from insn queue, expected %x, got %x",
                    expected_addr, insn_queue_dout.pc);
            end
            expected_insn = mem.internal_memory_array
                    [expected_addr[31:5]]
                    [expected_addr[4:2] * 32 +: 32];
            if (insn_queue_dout.insn !== expected_insn) begin
                $fatal("incorrect insn popped from insn queue, expected %x, got %x",
                    expected_insn, insn_queue_dout.insn);
            end
            expected_addr = expected_addr + 32'd4;
            if (insn_queue_dout.pc_next !== expected_addr) begin
                $fatal("incorrect pc_next popped from insn queue, expected %x, got %x",
                    expected_addr, insn_queue_dout.pc);
            end
        end
    end

    task cpu_test_full();
        run_cpu_test <= '1;
        repeat(2) @(posedge cpu_clk);
        cpu_rst <= '1;
        repeat(1) @(posedge cpu_clk);
        cpu_rst <= '0;
    endtask : cpu_test_full

    task cpu_test();
        run_cpu_test <= '1;
        force dut.decode_insn_queue.pop = insn_queue_pop;
        // repeat(2) @(posedge cpu_clk);
        // cpu_rst <= '1;
        // repeat(2) @(posedge cpu_clk);
        // cpu_rst <= '0;

        // Fetch-stage regression hook
        while(pop_prob_threshold < NUM_POP_PROB_THRESHOLDS) begin
            // reset pc between tests
            repeat(2) @(posedge cpu_clk);
            cpu_rst <= '1;
            repeat(1) @(posedge cpu_clk);
            cpu_rst <= '0;

            repeat(100) begin
                std::randomize(pop_rand_sample) with {
                    pop_rand_sample >= 0;
                    pop_rand_sample < NUM_POP_PROB_THRESHOLDS-1;
                };
                insn_queue_pop <= pop_rand_sample < pop_prob_threshold;
                @(posedge cpu_clk);
            end
            pop_prob_threshold++;
        end
        $finish();
    endtask : cpu_test

    always @(posedge cpu_clk) begin
        if (mon_itf.halt) begin
            $finish;
        end
        if (mem_itf.error != 0 || mon_itf.error != 0) begin
            $fatal;
        end
    end

    always @(posedge clk) begin
        if (timeout == 0) begin
            $error("TB Error: Timed out");
            $fatal;
        end
        timeout <= timeout - 1;
    end
