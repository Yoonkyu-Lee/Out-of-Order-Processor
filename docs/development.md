# Development

## Repository Map

- `hdl/`: main RTL modules for the core, caches, and functional units
- `hdl/functional_units/`: ALU, multiply, divide, and load/store execution blocks
- `pkg/`: shared packages and type definitions
- `hvl/common/`: shared testbench and monitor infrastructure
- `hvl/vcs/`: VCS-specific testbench collateral
- `hvl/verilator/`: Verilator-specific harness code
- `sim/`: simulation make targets and helper scripts
- `lint/`: SpyGlass lint setup
- `synth/`: synthesis, area, slack, and power-analysis flow
- `testcode/`: assembly tests, generators, and benchmark binaries
- `sram/`: SRAM generation/config collateral and generated macro outputs
- `docs/images/`: portfolio-facing diagrams and reused technical figures
- `docs/wavedrom/`: timing-diagram sources

## Configuration

Repository-wide settings live in `options.json`.

Important fields:

- `clock`: target clock period in picoseconds
- `c_ext`: enable or disable compressed-instruction support in the tooling flow
- `f_ext`: enable or disable floating-point support in the tooling flow
- `bmem_0_on_x`: control how uninitialized memory reads are modeled
- `dw_ip`: list of arithmetic IP blocks expected by the build flow

The synthesis section under `synth` controls options such as `compile_ultra`, `ungroup`, `gate_clock`, `retime`, and incremental compile settings.

## Environment Model

This repository assumes a Linux EDA environment where Synopsys simulation tools, DesignWare RTL models, Spike, and a RISC-V cross toolchain are provided by the shell environment rather than vendored into the repository.

In practice, the execution flow depends on four groups of external tooling:

- `vcs` for the reference simulation flow
- `verilator` for faster optional simulation
- `spike` plus the RVFI collateral used for architectural cross-checking
- `riscv64-unknown-elf-*` tools used by `generate_memory_file.py`

In the original development environment, these tools were enabled by a shell setup script rather than by per-project installation.

## Simulation Flow

The Synopsys and RISC-V toolchain environment is not available by default after login. Load your site-specific setup script first:

```bash
source /path/to/your/toolchain/setup.sh
```

Useful sanity checks:

```bash
which vcs
which spike
which riscv64-unknown-elf-gcc
echo "$DW"
```

If these do not resolve, the simulation flow below will fail before compilation starts.

The `DW` variable is especially important in this repository because the build flow expands `options.json` into DesignWare simulation models such as `DW_mult_pipe`, `DW_div_seq`, and `DW02_mult`.

Migration note: the repository now standardizes on `OOOCPU_*` runtime names. Some existing lab setups may still expose older `ECE411_*` environment variables or helper wrappers, and the active flow keeps compatibility with those during the transition.

### VCS

```bash
cd sim
make run_vcs_top_tb PROG=../testcode/ooo_test.s
```

Use VCS when you want:
- full four-state simulation behavior
- detailed waveform debug
- better confidence around unknown-state behavior

For this repository's current `options.json`, `c_ext` is disabled, so the intended benchmark binaries are the `im` variants rather than the `imc` variants.

Common benchmark runs:

```bash
cd sim
make run_vcs_top_tb PROG=../testcode/coremark_im.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/fft.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/mergesort.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/aes_sha.elf
make run_vcs_top_tb PROG=../testcode/cp3_release_benches/im/compression.elf
```

What this target does behind the scenes:

- compiles the CPU, testbench, SRAM models, and DesignWare models into `sim/vcs/top_tb`
- converts the selected `PROG` input into `sim/bin/memory_32.lst`
- links the program as `sim/bin/spike_dpi.elf` for the Spike-facing collateral
- launches the full-system testbench with clock, timeout, memory, and ELF plusargs

### Verilator

```bash
cd sim
make run_verilator_top_tb PROG=../testcode/ooo_test.s
```

Use Verilator when you want:
- faster turnaround on long-running programs
- quicker benchmark iteration
- a local-friendly flow for coarse performance experiments

Verilator is especially helpful for design-space iteration, but its dual-state execution model means it should not be treated as a complete replacement for a more rigorous correctness pass.

In this codebase, the helper scripts for IPC and runtime are written around the `VCS` log directory, so VCS is the easiest path when collecting benchmark results for documentation.

## Lint, Synthesis, and Power

### Lint

```bash
cd lint
make lint
```

### Synthesis

```bash
cd synth
make synth
```

### Power estimation from simulation activity

```bash
cd synth
make power_vcs
```

```bash
cd synth
make power_verilator
```

These flows make the repository more than a pure RTL dump. They show that the project was developed with attention to implementation realism, not just functional simulation.

## Working with Test Programs

The `testcode/` directory mixes three styles of input:

- handwritten assembly tests for targeted debug
- generated tests from small Python utilities
- benchmark binaries used for longer full-system runs

The simulation flow converts the selected program into the memory image expected by the testbench. In other words, the `PROG=...` argument is the normal entry point for switching workloads.

The repository currently includes:

- small bring-up tests such as `ooo_test.s`, `dependency_test.s`, and `mul_test.s`
- standalone benchmark binaries such as `coremark_im.elf`
- a benchmark set under `testcode/cp3_release_benches/im/`

## Diagram and Documentation Assets

- portfolio-facing block diagram: `docs/images/ooo-cpu-block-diagram.png`
- reusable timing figures: `docs/images/*.svg`
- WaveDrom sources for timing diagrams: `docs/wavedrom/*.json`

New documentation should prefer descriptive, stable filenames and should keep portfolio-facing material separate from preserved legacy collateral in `docs/archive/`.

## Notes on Dependencies

Some flows expect commercial EDA tools or environment-specific IP libraries. The repository keeps that collateral visible because it reflects the original development environment, but the main portfolio narrative focuses on architecture and engineering process rather than claiming turnkey portability across every machine.
