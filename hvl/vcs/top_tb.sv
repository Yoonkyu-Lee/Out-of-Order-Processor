module top_tb;

    timeunit 1ps;
    timeprecision 1ps;

    int clock_half_period_ps = 5000;  // default 10ns period
    initial begin
        if ($value$plusargs("OOOCPU_CLOCK_PERIOD_PS=%d", clock_half_period_ps) ||
            $value$plusargs("CLOCK_PERIOD_PS_ECE411=%d", clock_half_period_ps)) begin
            clock_half_period_ps = clock_half_period_ps / 2;
        end
    end

    bit clk = 1'b0;
    always #(clock_half_period_ps) clk = ~clk;
    bit rst;
    int testidx = 0; // default to 0

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

        // Run test based on plusargs
        if (!$value$plusargs("OOOCPU_TEST_IDX=%d", testidx)) begin
            void'($value$plusargs("TEST_IDX_MP_OWO=%d", testidx));
        end
        case (testidx)
            0: cpu_test_full();
            1: cpu_test();
            // 1: queue_test();
            2: linebuffer_test();
            // 3: freelist_test();
            // 2: cacheline_adapter_test();
            default: $fatal("unknown test idx %d, use `make run_vcs_top_tb TEST_IDX=n` to specify idx", testidx);
        endcase
        // if ($test$plusargs("RUN_LINEBUFFER_TEST")) linebuffer_test();

    end

    // Unit test infrastructure
    // `include "queue_tb.svh"
    `include "cacheline_adapter_tb.svh"
    `include "linebuffer_tb.svh"
    // `include "freelist_tb.svh"


    // Full system test (uncomment to enable when cpu is ready)
    // ------------------------------------------------------------------
    `include "top_tb.svh"

endmodule
