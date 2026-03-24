SHELL=/bin/bash -o pipefail
.SHELLFLAGS += -e

export PKG_SRCS = $(PWD)/../pkg/types.sv
export HDL_SRCS = $(shell find $(PWD)/../hdl -name '*.sv')
export SRAM_LIB = $(shell find $(PWD)/../sram/output/ -name "*.db")
export DESIGN_TOP = cpu

export STD_CELL_LIB=$(FREEPDK45)/stdcells.db
export STD_CELL_ALIB=$(FREEPDK45)/alib

export SNPSLMD_QUEUE=true
GUI_TIMEOUT ?= $(if $(OOOCPU_GUI_TIMEOUT),$(OOOCPU_GUI_TIMEOUT),$(if $(ECE411_GUI_TIMEOUT),$(ECE411_GUI_TIMEOUT),1h))

.PHONY: synth
synth: clean
	$(MAKE) outputs/synth.ddc

outputs/synth.ddc:
	mkdir -p reports outputs
	python3 $(PWD)/../bin/get_options.py clock
	python3 $(PWD)/../bin/get_options.py min_power
	python3 $(PWD)/../bin/get_options.py synth_cmd
	python3 $(PWD)/../bin/get_options.py synth_cmd_inc
	python3 $(PWD)/../bin/get_options.py synth_inc_iter
	export OOOCPU_CLOCK_PERIOD_PS=$(shell python3 $(PWD)/../bin/get_options.py clock) ;\
	export ECE411_CLOCK_PERIOD_PS=$$OOOCPU_CLOCK_PERIOD_PS ;\
	export OOOCPU_MIN_POWER=$(shell python3 $(PWD)/../bin/get_options.py min_power) ;\
	export ECE411_MIN_POWER=$$OOOCPU_MIN_POWER ;\
	export OOOCPU_COMPILE_CMD="$(shell python3 $(PWD)/../bin/get_options.py synth_cmd)" ;\
	export ECE411_COMPILE_CMD="$$OOOCPU_COMPILE_CMD" ;\
	export OOOCPU_COMPILE_CMD_INC="$(shell python3 $(PWD)/../bin/get_options.py synth_cmd_inc)" ;\
	export ECE411_COMPILE_CMD_INC="$$OOOCPU_COMPILE_CMD_INC" ;\
	export OOOCPU_COMPILE_ITER="$(shell python3 $(PWD)/../bin/get_options.py synth_inc_iter)" ;\
	export ECE411_COMPILE_ITER=$$OOOCPU_COMPILE_ITER ;\
	export OOOCPU_DC_CORES=4 ;\
	export ECE411_DC_CORES=$$OOOCPU_DC_CORES ;\
	dc_shell -f synthesis.tcl |& tee reports/synthesis.log
	rm -f  *.log
	rm -f  default.svf
	rm -rf work
	bash check_synth_error.sh

../sim/vcs/dump.fsdb.saif: ../sim/vcs/dump.fsdb
	cd ../sim/vcs && fsdb2saif -licqueue dump.fsdb -bt $(shell head -n1 ../sim/vcs/time.txt)ps -et $(shell tail -n1 ../sim/vcs/time.txt)ps -s top_tb/dut

../sim/verilator/dump.fst.saif: ../sim/verilator/dump.fst
	rm -f ../sim/verilator/dump.vcd
	cd ../sim/verilator && vcd2saif -pipe 'fst2vcd -f dump.fst | sed -E "s/logic/reg/g;s/int/reg/g" > dump.vcd' -input dump.vcd -output dump.fst.saif -time $(shell head -n1 ../sim/verilator/time.txt) $(shell tail -n1 ../sim/verilator/time.txt) -instance vtop/top_tb/dut

.PHONY: power_vcs
power_vcs: outputs/synth.ddc ../sim/vcs/dump.fsdb.saif
	mkdir -p reports outputs
	export OOOCPU_SAIF_FILE=../sim/vcs/dump.fsdb.saif ;\
	export ECE411_SAIF_FILE=$$OOOCPU_SAIF_FILE ;\
	export OOOCPU_SAIF_TOP=top_tb/dut ;\
	export ECE411_SAIF_TOP=$$OOOCPU_SAIF_TOP ;\
	export OOOCPU_POWER_RPT_PATH=./reports ;\
	export ECE411_POWER_RPT_PATH=$$OOOCPU_POWER_RPT_PATH ;\
	dc_shell -f power.tcl |& tee reports/power.log

.PHONY: power_verilator
power_verilator: outputs/synth.ddc ../sim/verilator/dump.fst.saif
	mkdir -p reports outputs
	export OOOCPU_SAIF_FILE=../sim/verilator/dump.fst.saif ;\
	export ECE411_SAIF_FILE=$$OOOCPU_SAIF_FILE ;\
	export OOOCPU_SAIF_TOP=vtop/top_tb/dut ;\
	export ECE411_SAIF_TOP=$$OOOCPU_SAIF_TOP ;\
	export OOOCPU_POWER_RPT_PATH=./reports ;\
	export ECE411_POWER_RPT_PATH=$$OOOCPU_POWER_RPT_PATH ;\
	dc_shell -f power.tcl |& tee reports/power.log

.PHONY: dv
dv:
	timeout $(GUI_TIMEOUT) design_vision -f dv.tcl

.PHONY: clean
clean:
	rm -f  *.log
	rm -f  default.svf
	rm -rf work
	rm -rf reports
	rm -rf outputs
