# Verification

## Philosophy

The verification flow separates two questions that matter for processor design:

- Is the core functionally correct?
- Does the architecture improve throughput on meaningful workloads?

This repository includes collateral for both. The correctness path emphasizes directed and randomized instruction testing plus architectural-reference checking infrastructure. The performance path uses benchmark-style programs to compare baseline and enhanced configurations.

## Correctness Strategy

### Directed tests

The `testcode/` directory includes focused assembly programs for specific behaviors, such as:

- dependency handling
- out-of-order execution behavior
- multiply/divide execution
- branch and memory interactions

These tests are useful for bringing up one subsystem at a time and for reproducing deadlocks or pipeline ordering bugs.

### Randomized instruction generation

The repository also includes Python generators such as `rand_asm.py`, `rand_asm3.py`, and `mul_test_gen.py`. These are valuable for exercising operand combinations, dependency chains, and control-flow variation that are tedious to write by hand.

### Architectural reference checking

The simulation collateral includes `RVFI`-related infrastructure and Spike integration support. In practice, this lets the design be checked against a reference architectural model instead of relying only on waveform inspection.

That distinction matters: waveform debugging is useful for localizing bugs, but reference-based checking is what gives confidence that a long instruction stream is actually retiring the correct architectural state.

## Performance Evaluation

The benchmark set covers several different stress patterns:

- `coremark`: a general embedded CPU benchmark used as an overall throughput sanity check
- `fft`: a Fast Fourier Transform workload that stresses arithmetic throughput and structured loop execution
- `mergesort`: a sorting workload with recursion, comparisons, branches, and memory movement
- `aes_sha`: a mixed cryptographic workload combining arithmetic intensity, repeated helper routines, and memory interaction
- `compression`: a data-compression-style workload that is sensitive to branch behavior and irregular memory access

Taken together, these workloads help answer where the core wins and where it still stalls. They are not a substitute for a polished benchmarking paper, but they are very effective for showing whether front-end and control-hazard improvements move IPC in the expected direction.

## Running Simulations

All commands below assume the repository is being used from a Linux shell.

Before running simulations, load your site-specific toolchain setup script:

```bash
source /path/to/your/toolchain/setup.sh
```

Quick environment check:

```bash
which vcs
which spike
which riscv64-unknown-elf-gcc
echo "$DW"
```

All commands below are intended to be run from the repository root unless noted otherwise.

This environment check is not just convenience. The current project extends a smaller course setup repository with additional dependencies: DesignWare arithmetic IP, SRAM macro models, a generated memory image, and Spike/RVFI collateral. If `vcs`, `spike`, the RISC-V toolchain, or `DW` are missing, the full-system CPU flow cannot start.

Migration note: public-facing commands in this repository now use the neutral `OOOCPU_*` runtime naming scheme. Compatibility with older `ECE411_*` plusargs is still retained inside the active testbench flow for transition purposes.

### VCS full-system simulation

```bash
cd sim
make run_vcs_top_tb PROG=../testcode/ooo_test.s
```

Typical uses:
- targeted bring-up of a small assembly test
- waveform-heavy debugging
- X-propagation-sensitive investigation

Small tests that are useful before running longer benchmarks:

```bash
cd sim
make run_vcs_top_tb PROG=../testcode/ooo_test.s
make run_vcs_top_tb PROG=../testcode/dependency_test.s
make run_vcs_top_tb PROG=../testcode/mul_test.s
```

### Verilator full-system simulation

```bash
cd sim
make run_verilator_top_tb PROG=../testcode/ooo_test.s
```

Typical uses:
- faster long-program runs
- quick throughput experiments
- design-space iteration when dual-state simulation is acceptable

### Spike reference run

```bash
cd sim
make spike ELF=../testcode/coremark_im.elf
```

## Benchmark Runs

The repository's current `options.json` has `c_ext=false`, so the expected benchmark inputs are the `im` binaries.

Examples:

```bash
cd sim
make run_vcs_top_tb PROG=../testcode/coremark_im.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/fft.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/mergesort.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/aes_sha.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/compression.elf
```

To sweep several benchmarks in sequence:

```bash
cd sim

for prog in \
  ../testcode/coremark_im.elf \
  ../testcode/cp3_release_benches/im/fft.elf \
  ../testcode/cp3_release_benches/im/mergesort.elf \
  ../testcode/cp3_release_benches/im/aes_sha.elf \
  ../testcode/cp3_release_benches/im/compression.elf
do
  echo "===== $prog ====="
  make run_vcs_top_tb PROG="$prog"
  bash get_ipc.sh
  bash get_run_time.sh
done
```

If a run completes normally, the output should include lines like:

- `Monitor: Segment IPC: ...`
- `Monitor: Segment Time: ...`
- `$finish ...`

Those lines indicate that the benchmark region executed, the monitor emitted performance statistics, and the testbench exited cleanly.

## Logs and Outputs

Common output locations include:

- `sim/vcs/simulation.log`
- `sim/verilator/simulation.log`
- `sim/spike/spike.log`
- `sim/vcs/dump.fsdb`
- `sim/verilator/dump.fst`

The repository also includes helper scripts such as `sim/get_ipc.sh` and `sim/get_run_time.sh` for extracting simple execution metrics from simulation output.

Typical result extraction after a `VCS` run:

```bash
cd sim
bash get_ipc.sh
bash get_run_time.sh
grep 'Monitor:' vcs/simulation.log
```

The helper scripts read from `sim/vcs/simulation.log`, so they are best used with the VCS flow. For Verilator runs, inspect `sim/verilator/simulation.log` directly.

## Lint and Synthesis Checks

Correctness work is supported by static checks as well:

```bash
cd lint
make lint
```

```bash
cd synth
make synth
```

Lint is useful for catching structural RTL issues early. Synthesis is useful for validating that the implementation remains realistic as the control logic becomes more complex.

## Practical Lessons Reflected in the Flow

Several verification themes show up repeatedly in the project notes and collateral:

- valid-bit discipline matters in speculative pipelines
- front-end bugs often appear as back-end deadlocks later
- random tests are especially valuable once rename and broadcast paths are active
- performance features still need correctness-first bring-up and regression coverage
- Verilator is excellent for speed, but it is not a substitute for full correctness signoff
