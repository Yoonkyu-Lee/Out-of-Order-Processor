# Architecture

## Overview

This processor implements an out-of-order `RV32IM` core in SystemVerilog using explicit register renaming. The design is centered around a small but representative OoO execution engine: fetch and queueing at the front end, rename and dispatch in the middle, reservation-station-based issue, multi-cycle execution units, common-data-path writeback, and in-order retirement through a reorder buffer.

The implementation favors clear hardware partitioning over aggressive complexity. It is intentionally portfolio-friendly rather than superscalar-research-heavy, which makes the design choices easy to inspect and discuss in an interview setting.

![Out-of-order CPU block diagram](images/ooo-cpu-block-diagram.png)

## End-to-End Data Flow

### 1. Fetch and instruction delivery

- `fetch.sv` drives the program counter and pulls instructions into an instruction queue.
- `linebuffer.sv` holds one 256-bit instruction cache line and serves repeated accesses within that line without re-querying the cache.
- `icache.sv` and `cacheline_adapter.sv` connect the core-facing request stream to the lower memory model.
- On control-flow redirects, the line buffer can be flushed so stale instructions are not reused after a branch or jump.

### 2. Decode and rename

- `decode.sv` parses the fetched instruction, builds a normalized internal instruction packet, and performs destination register renaming.
- The `RAT` maps architectural registers to physical registers used by in-flight instructions.
- The `freelist` supplies a fresh physical destination register when decode sees a writing instruction.
- The renamed instruction also allocates a `ROB` entry so completion can later retire in program order.

### 3. Dispatch, scheduling, and issue

- `dispatch.sv` routes decoded operations to the appropriate queue or reservation station based on instruction class.
- `queue.sv` and `queue2.sv` provide reusable buffering structures used across the front end and scheduling logic.
- Reservation stations track whether source operands are already available in the `PRF` or still pending on a future writeback.
- When all operands are ready and a matching functional unit is available, the instruction issues for execution.

### 4. Execute and writeback

- `alu.sv` handles integer arithmetic and logical operations.
- `multiply.sv` and `division.sv` cover the `M` extension with multi-cycle execution behavior.
- `ldst.sv` and the cache path handle memory-side execution.
- `cdb_arbiter.sv` arbitrates completion traffic and broadcasts results back to dependent structures.
- Broadcast results update waiting instructions and mark destination physical registers ready.

### 5. Retirement and recovery

- `rob.sv` preserves program order even when execution completes out of order.
- `rrf.sv` finalizes the committed architectural-to-physical mapping and returns no-longer-needed physical registers to the free list.
- This separation between speculative and retired mapping allows branch recovery without storing speculative values in a conventional architectural register file.
- On misprediction recovery, younger speculative work can be invalidated while preserving precise architectural state.

## Key Structures

### Physical register subsystem

The design uses a `PRF + RAT + RRF + freelist` split rather than a monolithic register file:

- `PRF`: stores the actual values for physical registers
- `RAT`: tracks the speculative architectural-to-physical mapping
- `RRF`: records the retired mapping used for architectural recovery
- `freelist`: recycles physical register numbers after retirement

This organization makes the rename path explicit and easier to reason about. It also avoids reusing ROB entries as the sole source of committed register values, which would complicate late consumers and recovery behavior.

### ROB and reservation stations

The `ROB` provides ordered commit and precise state. Reservation stations absorb out-of-order execution latency by holding operations until operands are ready. Together they let the core overlap independent instructions while still making retirement deterministic.

### Caches and memory interface

The design uses split instruction and data caches. The front end adds a line buffer to improve instruction delivery across sequential accesses within the same cache line. The cacheline adapter bridges between cache-facing transactions and the burst-oriented lower memory interface.

### Branch prediction

The advanced branch-handling feature documented in project notes is a `GShare` direction predictor paired with a `BTB` for target prediction. The fetch stage uses both structures together: a branch is predicted taken only when the direction predictor indicates taken and the BTB supplies a valid target. Predictor training happens when resolved branch information becomes available.

## Design Decisions and Tradeoffs

### Why explicit register renaming?

Explicit renaming was chosen because it cleanly separates speculative state from committed state and exposes the classic OoO machinery interviewers expect to see: physical registers, dependency tracking, ready bits, result broadcast, and recovery state.

### Why a line buffer in front of the I-cache?

The line buffer is a small, high-leverage front-end optimization. Once a 256-bit cache line is present locally, the fetch stage can serve several sequential instructions without re-accessing the cache datapath. This is a practical way to improve effective fetch throughput without immediately moving to a deeper front-end pipeline.

### Why keep the design single-issue and structured?

The repository demonstrates core OoO mechanisms without hiding them behind superscalar complexity. That tradeoff keeps the control logic understandable and makes verification more tractable while still showing meaningful architectural depth.

### Known implementation tradeoffs

Project notes call out several areas where simplicity won over peak performance:

- priority arbitration instead of fully age-ordered scheduling
- careful valid-bit gating to avoid X-propagation issues
- multi-cycle functional-unit behavior tuned for correctness first
- branch recovery logic designed for robustness rather than aggressive early recovery

## Current Limitations and Natural Extensions

The existing design is a strong baseline, but there are several natural extension points:

- age-based issue arbitration instead of simple priority selection
- more aggressive load/store scheduling and memory disambiguation
- wider front-end or superscalar issue/commit
- stronger recovery and prediction structures
- cleaner performance-counter and design-space-exploration instrumentation

These are useful interview discussion points because they follow directly from the current architecture rather than from a hypothetical redesign.
