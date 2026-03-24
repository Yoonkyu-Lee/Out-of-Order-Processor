module prf
    import ooo_cpu_types::*;
    (
        rstat_prf_itf.prf rstats[N_RSTATS*2],
        input cdb_packet_t cdb
    );

    // TODO use sram for this maybe?
    logic [0:N_PHYS_REG-1] [31:0] entries;

    logic [0:N_RSTATS*2-1] [31:0] reg_v_arr;
    logic [0:N_RSTATS*2-1] [LOG2_N_PHYS_REG-1:0] phys_reg_arr;

    always_comb begin
        // might wanna latch this for timing. it'll match sram
        // then too
        for(integer i = 0; i < N_RSTATS*2; i++) begin
                //rstats[i][j].reg_v_valid = rstats[i][j].read;
                reg_v_arr[i] = entries[
                    phys_reg_arr[i]];
        end
    end

    for(genvar i = 0; i < N_RSTATS*2; i++) begin
        assign rstats[i].reg_v = reg_v_arr[i];
        assign phys_reg_arr[i] = rstats[i].phys_reg;
    end

    always_ff @(posedge rstats[0].clk) begin
        if(rstats[0].rst) begin
            entries <= '0;
        end else begin
            if(cdb.valid && cdb.rd_valid) begin
                entries[cdb.rd_phys_reg] <= cdb.rd_v;
            end
        end
    end
endmodule : prf
