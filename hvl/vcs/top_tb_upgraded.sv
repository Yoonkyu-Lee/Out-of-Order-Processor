/*
module top_tb;

    timeunit 1ps;
    timeprecision 1ps;

    int clock_half_period_ps;
    int clock_period_ps;
    initial begin
        if (!$value$plusargs("OOOCPU_CLOCK_PERIOD_PS=%d", clock_period_ps) &&
            !$value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_period_ps)) begin
            // Default to 10ns period if not provided
            clock_period_ps = 10000;
        end
        clock_half_period_ps = clock_period_ps / 2;
    end

    bit clk;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;

    initial begin
        $fsdbDumpfile("dump.fsdb");
        if ($test$plusargs("OOOCPU_NO_DUMP_ALL") || $test$plusargs("NO_DUMP_ALL_ECE411")) begin
            $fsdbDumpvars(0, dut, "+all");
            $fsdbDumpoff();
        end else begin
            $fsdbDumpvars(0, "+all");
        end
        rst = 1'b1;
        repeat (2) @(posedge clk);
        rst <= 1'b0;

        run_all_queue_tests();

    end

    // queue test bench
    // logic clk, rst;

    logic pop, empty;
    logic [31:0] dout; 
    
    logic push, full;
    logic [31:0] din;

    queue dut (
        .*
    );


    // -----------------------------
    // Queue Tests
    // -----------------------------
    localparam int QDEPTH = 8;
    // Scoreboard storage (module-scope to avoid tool limitations on arrays in tasks)
    int model_mem[QDEPTH];
    int model_head;
    int model_tail;
    int model_qsize;
    // Random test control/state (module-scope for tool compatibility)
    logic do_push, do_pop;
    logic will_push, will_pop;
    int sel;
    int pushed_val;
    int head_val;
    int head_now;

    task automatic reset_dut();
        rst <= 1'b1;
        pop <= '0;
        push <= '0;
        din <= '0;
        repeat (2) @(posedge clk);
        rst <= 1'b0;
        @(posedge clk);
    endtask

    // Basic directed tests (refactor of existing tests)
    task automatic queue_basic_test();
        $display("START [queue_basic_test]");
        pop = '0;
        push = '0;
        din = '0;
        
        @(posedge clk);    
        //check initial empty state
        $display("Test 1: Checking initial empty state");
        if (!empty) begin $error("Queue should be empty initially"); $fatal; end
        
        //pop on empty should be ignored
        $display("Test 1a: Pop on empty (ignored)");
        pop = 1'b1;
        @(posedge clk);
        pop = 1'b0;
        @(posedge clk);
        if (!empty) begin $error("Queue should remain empty after pop on empty"); $fatal; end
        
        @(posedge clk);
        //push single element
        $display("\nTest 2: Push single element");
        push = 1'b1;
        din = 32'hDEADBEEF;
        @(posedge clk);
        push = 1'b0;
        @(posedge clk);
        
        if (!(!empty && dout == 32'hDEADBEEF)) begin $error("After single push, expected 0xDEADBEEF, got 0x%h", dout); $fatal; end
        
        //pop single element
        $display("\nTest 3: Pop single element");
        // Check data before popping
        if (!(dout == 32'hDEADBEEF)) begin $error("Expected 0xDEADBEEF at head, got 0x%h", dout); $fatal; end
        
        pop = 1'b1;
        @(posedge clk);
        pop = 1'b0;

        @(posedge clk);
        if (!empty) begin $error("Queue should be empty after pop"); $fatal; end
        
        //fill the queue
        $display("\nTest 4: Filling the queue");
        for (int i = 0; i < 8; i++) begin
            push = 1'b1;
            din = 32'h100 + i;
            @(posedge clk);
        end
        push = 1'b0;
        @(posedge clk);
        
        if (!full) begin $error("Queue should be full after %0d pushes", QDEPTH); $fatal; end
        
        //push when full (should not accept)
        $display("\nTest 5: Attempting to push when full");
        push = 1'b1;
        din = 32'hBAD_BEEF;
        @(posedge clk);
        push = 1'b0;
        @(posedge clk);
        if (!full) begin $error("Queue should remain full after push attempt when full"); $fatal; end
        
        //pop all elements and verify FIFO order
        $display("\nTest 6: Popping all elements (FIFO order check)");
        for (int i = 0; i < 8; i++) begin
            // Check data at head before popping
            if (!(dout == (32'h100 + i))) begin $error("Element %0d = 0x%h (expected 0x%h)", i, dout, 32'h100 + i); $fatal; end
            pop = 1'b1;
            @(posedge clk);
        end
        pop = 1'b0;
        @(posedge clk);
        
        if (!empty) begin $error("Queue should be empty after popping all"); $fatal; end
        
        //simultaneous push and pop
        $display("\nTest 7: Simultaneous push and pop");
        push = 1'b1;
        din = 32'hCAFEBABE;
        @(posedge clk);
        push = 1'b1;
        pop = 1'b1;
        din = 32'hFEEDFACE;
        @(posedge clk);
        push = 1'b0;
        pop = 1'b0;
        @(posedge clk);
        
        if (!(!empty && !full)) begin $error("Queue state incorrect after simultaneous ops"); $fatal; end
        
        //pop remaining and verify
        if (!(dout == 32'hFEEDFACE)) begin $error("Expected 0xFEEDFACE, got 0x%h", dout); $fatal; end
        pop = 1'b1;
        @(posedge clk);
        pop = 1'b0;
        @(posedge clk);
        $display("PASS  [queue_basic_test]");
    endtask

    // Wrap-around and boundary tests
    task automatic queue_wraparound_test();
        int expected_base;
        int expected_count;
        int after_pop_occ;
        int capacity;
        int attempted;
        int accepted;
        $display("\nTest 8: Wrap-around with mixed operations");
        $display("START [queue_wraparound_test] : Wrap-around with mixed operations");
        // Fill half
        for (int i = 0; i < QDEPTH/2; i++) begin
            push = 1'b1; din = 32'h200 + i; @(posedge clk);
        end
        push = 1'b0; @(posedge clk);
        // Pop a few
        for (int i = 0; i < QDEPTH/4; i++) begin
            if (!(dout == (32'h200 + i))) begin $error("Wrap pop %0d exp 0x%h got 0x%h", i, 32'h200 + i, dout); $fatal; end
            pop = 1'b1; @(posedge clk);
        end
        pop = 1'b0; @(posedge clk);
        // Push more than remaining space to force pointer wrap
        for (int i = 0; i < (QDEPTH/2 + 4); i++) begin
            if (!full) begin
                push = 1'b1; din = 32'h300 + i; @(posedge clk);
            end else begin
                push = 1'b0; @(posedge clk);
            end
        end
        push = 1'b0; @(posedge clk);
        // Drain all and ensure strict FIFO order across wrap
        expected_base = 32'h200 + (QDEPTH/4);
        expected_count = (QDEPTH/2 - QDEPTH/4);
        // First drain remaining from 0x200 series
        for (int i = 0; i < expected_count; i++) begin
            if (!(dout == (expected_base + i))) begin $error("Wrap drain A %0d exp 0x%h got 0x%h", i, expected_base + i, dout); $fatal; end
            pop = 1'b1; @(posedge clk);
        end
        pop = 1'b0; @(posedge clk);
        // Then drain the 0x300 series exactly for the number of accepted pushes
        after_pop_occ = (QDEPTH/2) - (QDEPTH/4);
        capacity      = QDEPTH - after_pop_occ;
        attempted     = (QDEPTH/2 + 4);
        accepted      = (attempted < capacity) ? attempted : capacity;
        for (int i = 0; i < accepted; i++) begin
            if (!(dout == (32'h300 + i))) begin $error("Wrap drain B %0d exp 0x%h got 0x%h", i, (32'h300 + i), dout); $fatal; end
            pop = 1'b1; @(posedge clk);
        end
        pop = 1'b0; @(posedge clk);
        if (!empty) begin $error("Queue should be empty after wrap-around drain"); $fatal; end
        $display("PASS  [queue_wraparound_test]");
    endtask

    // Randomized stress test with scoreboard
    task automatic queue_random_stress_test(int iters = 200);
        $display("\nTest 9: Randomized stress with scoreboard (%0d iters)", iters);
        $display("START [queue_random_stress_test] : Randomized stress with scoreboard (%0d iters)", iters);
        model_qsize = 0;
        model_head  = 0;
        model_tail  = 0;
        for (int t = 0; t < iters; t++) begin
            // Randomize ops (allow illegal ops to test ignore behavior)
            sel = $urandom_range(0,3);
            do_push = (sel == 0) || (sel == 2);
            do_pop  = (sel == 1) || (sel == 2);
            // Drive inputs for this cycle
            push = do_push;
            pop  = do_pop;
            din  = $urandom();

            // Check head data vs model before pop
            if (model_qsize > 0) begin
                if (empty) begin $error("Model says non-empty but DUT empty at t=%0d", t); $fatal; end
                // We cannot know exact value without tracking; track the head value
                // by peeking when we enqueued.
            end else begin
                if (!empty) begin $error("Model says empty but DUT non-empty at t=%0d", t); $fatal; end
            end

            // Update model based on pre-edge state
            will_push = do_push && (model_qsize < QDEPTH);
            will_pop  = do_pop  && (model_qsize > 0);
            pushed_val = din;

            // If pop will happen, check `dout` equals model head now
            if (will_pop) begin
                if (model_qsize == 0) begin
                    // should never hit
                end else begin
                    head_val = model_mem[model_head];
                    if (!(dout == head_val)) begin $error("Stress pop mismatch: exp 0x%h got 0x%h at t=%0d", head_val, dout, t); $fatal; end
                end
            end

            @(posedge clk);

            // Commit model updates after edge
            if (will_pop) begin
                model_head = (model_head + 1) % QDEPTH;
                model_qsize--;
            end
            if (will_push) begin
                model_mem[model_tail] = pushed_val;
                model_tail = (model_tail + 1) % QDEPTH;
                model_qsize++;
            end

            // Post-edge: check flags
            if (!(((model_qsize == 0) == empty))) begin $error("Empty flag mismatch: qsize=%0d empty=%0b", model_qsize, empty); $fatal; end
            if (!(((model_qsize == QDEPTH) == full))) begin $error("Full flag mismatch: qsize=%0d full=%0b", model_qsize, full); $fatal; end

            // Post-edge: if non-empty, check head matches model
            if (model_qsize > 0) begin
                head_now = model_mem[model_head];
                if (!(dout == head_now)) begin $error("Stress head mismatch: exp 0x%h got 0x%h at t=%0d", head_now, dout, t); $fatal; end
            end

            // Deassert controls for next cycle unless random keeps them
            push = 1'b0;
            pop  = 1'b0;
            @(posedge clk);
        end

        // Drain remaining and validate order
        while (model_qsize > 0) begin
            if (!(dout == model_mem[model_head])) begin $error("Final drain mismatch: exp 0x%h got 0x%h", model_mem[model_head], dout); $fatal; end
            pop = 1'b1; @(posedge clk);
            pop = 1'b0; @(posedge clk);
            model_head = (model_head + 1) % QDEPTH;
            model_qsize--;
        end
        if (!empty) begin $error("Queue should be empty after final drain"); $fatal; end
        $display("PASS  [queue_random_stress_test]");
    endtask

    task run_all_queue_tests();
        queue_basic_test();
        reset_dut();
        queue_wraparound_test();
        reset_dut();
        queue_random_stress_test(200);
        $display("\nPASS  [All queue tests]");
        $finish;
    endtask



    // `include "top_tb.svh" remove comment to test actual processor

endmodule
*/
