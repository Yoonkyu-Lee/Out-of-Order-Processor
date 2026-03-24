// Linebuffer testbench infrastructure and task
// Include in top_tb.sv to enable linebuffer testing

// DUT interface signals (new interface)
logic                      lbdut_clk;
logic                      lbdut_rst;

logic   [31:0]             lbdut_addr;
logic                      lbdut_read_en;
logic                      lbdut_flush;

// To I-cache
logic   [31:0]             lbdut_ic_addr;
logic                      lbdut_ic_read;

// From I-cache
logic                      lbdut_ic_valid;
logic   [26:0]             lbdut_ic_line_tag;  // addr[31:5]
logic   [255:0]            lbdut_ic_line_data;

// To fetch
logic   [31:0]             lbdut_rdata;
logic                      lbdut_valid;

// Drive clock/reset from top_tb
assign lbdut_clk = clk;
assign lbdut_rst = rst;

linebuffer linebuffer_dut (
    .clk      (lbdut_clk),
    .rst      (lbdut_rst),
    .addr     (lbdut_addr),
    .read_en  (lbdut_read_en),
    .flush    (lbdut_flush),
    .ic_addr  (lbdut_ic_addr),
    .ic_read  (lbdut_ic_read),
    .ic_valid (lbdut_ic_valid),
    .ic_line_tag (lbdut_ic_line_tag),
    .ic_line_data(lbdut_ic_line_data),
    .rdata    (lbdut_rdata),
    .valid    (lbdut_valid)
);

// Simple downstream model: accepts a single line request and returns a 256b line
initial begin
    lbdut_ic_valid = 1'b0;
    lbdut_ic_line_tag = '0;
    lbdut_ic_line_data = '0;
    lbdut_flush   = 1'b0;
    lbdut_addr    = '0;
    lbdut_read_en = 1'b0;
end

// Optional: monitor cache requests
always @(posedge lbdut_clk) begin
    if (lbdut_ic_read) begin
        $display("[CACHE_REQ] t=%0t ic_addr=%h ic_read=%b", $time, lbdut_ic_addr, lbdut_ic_read);
    end
end

// Optional: simple external signal trace (keeps TB self-contained)
// Disabled to reduce output - enable only for debugging specific issues
// always @(posedge lbdut_clk) begin
//     $display("[DBG] t=%0t addr=%h read_en=%b ic_valid=%b valid=%b rdata=%h",
//              $time, lbdut_addr, lbdut_read_en, lbdut_ic_valid, lbdut_valid, lbdut_rdata);
// end

function automatic [255:0] lb_gen_line(input logic [31:0] line_base);
    // generate deterministic 8x32b words based on line_base and word index
    automatic logic [255:0] line;
    for (int i = 0; i < 8; i++) begin
        line[i*32 +: 32] = {line_base[31:8], 5'd0, 3'(i)} ^ 32'h00A5_5A00;
    end
    return line;
endfunction

task automatic lb_send_ic_line(input logic [31:0] any_addr);
    logic [31:0] base;
    logic [255:0] line_data;
    base = {any_addr[31:5], 5'b0};
    line_data = lb_gen_line(base);
    lbdut_ic_line_tag  = base[31:5];
    lbdut_ic_line_data = line_data;
    lbdut_ic_valid     = 1'b1;
    $display("[TB] ic_valid=1, sending 256b line: tag=%h line_data=%h @%0t", base[31:5], line_data, $time);
    @(posedge lbdut_clk);
    lbdut_ic_valid     = 1'b0;
endtask

// Helper: expect valid=1 and specific data this cycle
task automatic lb_expect_valid(input logic [31:0] exp_data);
    if (!lbdut_valid) begin
        $display("FAIL[linebuffer]: expected valid=1, got valid=0 @%0t", $time);
        $fatal(1);
    end
    if (lbdut_rdata !== exp_data) begin
        $display("FAIL[linebuffer]: expected rdata=%h, got rdata=%h @%0t",
                 exp_data, lbdut_rdata, $time);
        $fatal(1);
    end
    $display("PASS[linebuffer]: addr=%h word_idx=%0d valid=1 rdata=%h @%0t", 
             lbdut_addr, lbdut_addr[4:2], exp_data, $time);
endtask

// Helper: expect valid=0 this cycle
task automatic lb_expect_invalid();
    if (lbdut_valid !== 1'b0) begin
        $display("FAIL[linebuffer]: expected valid=0, got valid=%b rdata=%h @%0t",
                 lbdut_valid, lbdut_rdata, $time);
        $fatal(1);
    end
    $display("PASS[linebuffer]: valid=0 as expected @%0t", $time);
endtask

// Helper: expect two consecutive valid beats with resp held high across both
// (obsolete helper removed; using literal WaveDrom compare instead)

// Compute expected word from generated line
function automatic logic [31:0] lb_exp_word(input logic [31:0] addr);
    automatic logic [255:0] line;
    line = lb_gen_line({addr[31:5], 5'b0});
    return line[addr[4:2]*32 +: 32];
endfunction

// WaveDrom-compliant, straightforward scenario test
task automatic linebuffer_test_wavedrom();
    logic [31:0] A1, A2, B1;
    A1 = 32'hAAAA_A040;
    A2 = {A1[31:5], 5'd0} + 32'd8;
    B1 = 32'hAAAA_A080;

    // Reset phase
    @(posedge lbdut_clk);
    lbdut_addr    <= '0;
    lbdut_read_en <= 1'b0;
    lbdut_flush   <= 1'b0;

    // -------- First action: A1 miss then serve --------
    $display("=== First Action: A1 miss then serve ===");
    @(posedge lbdut_clk);
    lbdut_addr    <= A1;
    lbdut_read_en <= 1'b1; // rmask asserted window
    
    // Cycle 1: addr=A1, read_en=1, but no line yet -> valid should be 0
    @(posedge lbdut_clk);
    lb_expect_invalid();
    
    // Cycle 2: still waiting for line -> valid should be 0
    @(posedge lbdut_clk);
    lb_expect_invalid();
    
    // Provide line A, then expect valid next cycle
    lb_send_ic_line(A1);
    
    // Cycle after ic_valid: should see valid=1 with A1 data
    @(posedge lbdut_clk);
    lb_expect_valid(lb_exp_word(A1));

    // -------- Second action: A1 then A2 within line (continuous valid) --------
    $display("=== Second Action: A1 then A2 within same line (continuous valid) ===");
    // Keep read_en high; keep addr=A1 this cycle, then move to A2 next cycle
    
    // Cycle 1: addr=A1, line already loaded -> valid=1 with A1 data
    @(posedge lbdut_clk);
    lb_expect_valid(lb_exp_word(A1));
    if (lbdut_valid !== 1'b1) begin
        $display("FAIL: valid should be continuous (stay high), but it's not! @%0t", $time);
        $fatal(1);
    end
    $display("CHECK: valid is HIGH at start of A1->A2 transition @%0t", $time);
    
    lbdut_addr <= A2;  // Change to A2 (same cacheline)
    
    // Cycle 2: addr=A2, same line -> valid should remain 1 with A2 data (continuous)
    // This is the KEY test: valid must NOT drop to 0 between A1 and A2
    @(posedge lbdut_clk);
    if (lbdut_valid !== 1'b1) begin
        $display("FAIL: valid dropped to 0 during A1->A2 transition! Expected continuous valid=1 @%0t", $time);
        $fatal(1);
    end
    $display("CHECK: valid is STILL HIGH during A1->A2 transition (CONTINUOUS) @%0t", $time);
    lb_expect_valid(lb_exp_word(A2));
    $display("PASS: Confirmed CONTINUOUS valid across A1->A2 (no pulse, stayed high for 2+ cycles)");

    // -------- Third action: B1 (new line) miss then serve --------
    $display("=== Third Action: B1 (new line) miss then serve ===");
    @(posedge lbdut_clk);
    lbdut_addr <= B1; // change to new cacheline; still reading
    
    // Cycle 1: addr=B1 (different line), miss -> valid should be 0
    @(posedge lbdut_clk);
    lb_expect_invalid();
    
    // Provide line B
    lb_send_ic_line(B1);
    
    // Cycle after ic_valid: should see valid=1 with B1 data
    @(posedge lbdut_clk);
    lb_expect_valid(lb_exp_word(B1));

    // -------- Additional checks: read_en=0 and flush --------
    $display("=== Additional checks: read_en=0 should invalidate output ===");
    @(posedge lbdut_clk);
    lbdut_read_en <= 1'b0;  // Turn off read
    
    // With read_en=0, valid should go to 0 (even though buffer still has data)
    @(posedge lbdut_clk);
    lb_expect_invalid();
    
    // Turn read back on, should see valid immediately (hit)
    lbdut_read_en <= 1'b1;
    @(posedge lbdut_clk);
    lb_expect_valid(lb_exp_word(B1));
    
    // Test flush
    $display("=== Testing flush: should clear buffer ===");
    lbdut_flush <= 1'b1;
    @(posedge lbdut_clk);
    lbdut_flush <= 1'b0;
    
    // After flush, same address should miss (valid=0)
    @(posedge lbdut_clk);
    lb_expect_invalid();
    
    // Done
    lbdut_read_en <= 1'b0;
    @(posedge lbdut_clk);
endtask

// Basic additional tests (hit-only and boundary)
// Basic test removed to keep focus on exact WaveDrom compliance

task automatic linebuffer_test();
    $display("start[linebuffer]: %0t", $time);
    linebuffer_test_wavedrom();
    $display("PASS[linebuffer]: all tests passed");
    $display("Simulation complete. Ending.");
    $finish;
endtask


