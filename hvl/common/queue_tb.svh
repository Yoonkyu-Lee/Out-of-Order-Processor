
// Queue testbench infrastructure and task
// Include this in top_tb.sv to enable queue testing

logic pop, empty;
logic [31:0] dout; 

logic push, full;
logic [31:0] din;

queue #(.DEPTH(16)) queue_dut (
    .*
);

task queue_test();
    pop = '0;
    push = '0;
    din = '0;
    
    @(posedge clk);    
    $display("Test 1: Checking initial empty state");
    if (empty) begin
        $display("PASS: Queue is initially empty");
    end else begin
        $display("FAIL: Queue should be empty initially");
    end
    
    @(posedge clk);
    $display("\nTest 2: Push single element");
    push = 1'b1;
    din = 32'hDEADBEEF;
    @(posedge clk);
    push = 1'b0;
    @(posedge clk);
    
    if (!empty && dout == 32'hDEADBEEF) begin
        $display("PASS: Queue has DEADBEEF :D");
    end else begin
        $display("FAIL: Queue should not be empty after push");
    end
    
    $display("\nTest 3: Pop single element");
    if (dout == 32'hDEADBEEF) begin
        $display("PASS: Correct data at head (0x%h)", dout);
    end else begin
        $display("FAIL: Expected 0xDEADBEEF at head, got 0x%h", dout);
    end
    
    pop = 1'b1;
    @(posedge clk);
    pop = 1'b0;

    @(posedge clk);
    if (empty) begin
        $display("PASS: Queue is empty after pop");
    end else begin
        $display("FAIL: Queue should be empty after pop");
    end

    $display("\nTest 3.1: Pop while empty");
    pop = 1'b1;
    @(posedge clk);
    pop = 1'b0;
    @(posedge clk);
    if (empty && !full) begin
        $display("PASS: Correctly empty after test 3.1");
    end else begin
        $display("FAIL: Expected queue to be empty after pop while empty");
    end
    
    $display("\nTest 4: Filling the queue");
    for (int i = 0; i < 16; i++) begin
        push = 1'b1;
        din = 32'h100 + i;
        @(posedge clk);
    end
    push = 1'b0;
    @(posedge clk);
    
    if (full) begin
        $display("PASS: Queue is full after 8 pushes");
    end else begin
        $display("FAIL: Queue should be full after 8 pushes");
    end
    
    $display("\nTest 5: Attempting to push when full");
    push = 1'b1;
    din = 32'hBAD_BEEF;
    @(posedge clk);
    push = 1'b0;
    @(posedge clk);
    
    $display("\nTest 6: Popping all elements (FIFO order check)");
    for (int i = 0; i < 16; i++) begin
        if (dout == (32'h100 + i)) begin
            $display("PASS: Element %0d = 0x%h (expected 0x%h)", i, dout, 32'h100 + i);
        end else begin
            $display("FAIL: Element %0d = 0x%h (expected 0x%h)", i, dout, 32'h100 + i);
        end
        pop = 1'b1;
        @(posedge clk);
    end
    pop = 1'b0;
    @(posedge clk);
    
    if (empty) begin
        $display("PASS: Queue is empty after popping all elements");
    end else begin
        $display("FAIL: Queue should be empty after popping all");
    end
    
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
    
    if (!empty && !full) begin
        $display("PASS: Queue state correct after simultaneous ops");
    end else begin
        $display("FAIL: Queue state incorrect after simultaneous ops. Got full=%d empty=%d",
            full, empty);
    end
    
    if (dout == 32'hFEEDFACE) begin
        $display("PASS: Correct data after simultaneous ops (0x%h)", dout);
    end else begin
        $display("FAIL: Expected 0xFEEDFACE, got 0x%h", dout);
    end
    pop = 1'b1;
    @(posedge clk);
    pop = 1'b0;
    @(posedge clk);

    $display("\nTest 8: Pop while empty");
    if (empty && !full) begin
        $display("PASS: Correctly empty after test 7");
    end else begin
        $display("FAIL: Expected queue to be empty");
    end
    pop = 1'b1;
    @(posedge clk);
    pop = 1'b0;
    @(posedge clk);
    if (empty && !full) begin
        $display("PASS: Correctly empty after test 8");
    end else begin
        $display("FAIL: Expected queue to be empty after pop while empty");
    end
    
    $display("\nAll tests completed");
    $finish;

endtask

