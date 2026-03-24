Checkpoint 1 
 
Progress Report 
 
-  New files 
-  cacheline_adapter.sv 
-  The purpose of cacheline_adapter.sv is to serve as a bridge between the 
cache and the provided memory model in this MP. Its primary function is 
to assemble a complete 256-bit cache line during read operations by 
fetching data from DRAM. Currently, the module supports only read 
functionality. It issues a memory address, waits for valid responses, and 
reconstructs the full 256-bit cache line from four sequential 64-bit data 
bursts, following the behavior defined by the DRAM model. 
-  fetch.sv 
-  The purpose of fetch.sv is to retrieve the instruction from the line buffer 
and to put it into the instruction queue. It also maintains and updates the 
current PC. On each cycle, if the instruction queue is not full, the module 
issues a read request to the line buffer using the current PC value. When a 
valid response is received, it pushes the fetched instruction into the 
instruction queue, then increments the PC. If the queue is full, fetch stalls 
and continuously pulls from the linebuffer until the instruction is ready. 
-  Cache 
-  This cache is derived from mp_cache and implements a four-way 
set-associative design. It serves as the interface between the CPU and the 
cacheline_adapter. In this version, instead of fetching a single 32-bit word, 
the cache always returns a 256-bit block of data aligned to a byte 
boundary. 
-  Linebuffer 
-  The purpose of the linebuffer module is to act as a small instruction buffer 
sitting between the fetch stage and the instruction cache. It temporarily 
stores an entire 256-bit cache line (corresponding to 32 bytes or eight 
32-bit instructions) to reduce repeated cache accesses when fetching 
sequential instructions. When the fetch stage requests an instruction word, 
the linebuffer checks if the requested address falls within the currently 
buffered line. If it does, the instruction is immediately returned (a cache 
hit). If not, the module issues a new read request to the instruction cache 
and waits for the line fill. Once the new 256-bit line is received, it is stored 
locally, and the appropriate instruction word is returned to the fetch stage. 
The module also supports a flush signal to invalidate the buffered line 
when necessary, ensuring correct behavior across control flow changes 
such as jumps or branches. 
-  Queue 
-  The purpose of the queue module is to provide a simple FIFO (First-In, 
First-Out) buffer for storing and retrieving data elements between pipeline 
stages. It supports both enqueue and dequeue operations, maintaining 
internal head and tail pointers to track the current read and write positions 
within the queue. The design includes logic to detect when the queue is 
empty (head equals tail) and full (head and tail wrap around and overlap), 
preventing overflow or underflow. On a valid push operation, new data is 
written to the tail and the pointer advances; on a valid pop, data is read 
from the head, and that entry is invalidated. The module is parameterized 
by both data width and depth, allowing flexible use for various buffering 
needs such as instruction queues or data staging within the pipeline. 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
Diagram 
-  Design decisions. 
-  We are going for an explicit register renaming processor, with a separate PRF and 
with no ARF (i.e. all register values are only stored in the PRF, and the RAT only 
stores the physical register index for each architectural register). (Note that you 
can’t combine the PRF and ROB without also storing register values in the 
RAT/ARF, due to the case of an instruction that writes to a register committing 
and that ROB entry getting reused before instructions that read from that register 
have been issued.) 
-  See notes in the diagram for further reasoning that went into its creation. 
-  We’ll most likely be using sv interfaces to organize the signals between modules, 
for clarity of where the connections go in cpu.sv 




Chaeckpoint 2
 
Progress Report 
 
-  New files 
-  Decode 
-  This module's role is to take a fetched instruction from the queue and 
convert it into a data packet in order for the functional unit to operate 
correctly. It also renames the destination register in order to perform 
register renaming. 
-  RRF 
-  This module’s role is to take fully committed instructions that came from 
the ROB, and update the architectural to physical register mappings from 
the retired instructions from the ROB. This also allows the RAT to recover 
from branch mispredictions and puts retired physical registers onto the 
free list. 
-  PRF 
-  This module stores all of the actual data values for the physical registers 
used in the CPU 
-  Free List 
-  This module simply stores all of the unused physical register numbers. 
When a physical register is needed for renaming, decode will pop a 
physical register off the stack  
-  Dispatch 
-  This module checks the current instruction and sends the instruction out to 
the appropriate reservation station based on what type of instruction it is. 
-  Reservation Station 
-  This module checks whether or not the instruction in this reservation 
station is ready to be sent into the functional unit or not 
-  ROB 
-  This module keeps track of the instructions keeps them in order. Even 
when instructions are done out of order, the ROB executes them in order 
at the end. 
-  Functional Units 
-  ALU 
-  This module executes all ALU instructions 
-  Division 
-  This module executes any and all division instructions in the 
division extension. 
-  Multiply 
-  This module executes any and all multiply instructions in the 
multiply instruction. 
-  Design decisions / Notes 
-  CDB now connects to dispatch and the RAT for properly updating the ready 
bits in the RAT and instructions to indicate that a given register’s physical 
register has computed its value. 
-  The RVFI struct gets passed from issue down to the function units and the 
CDB, and to the ROB. 
-  The unified insn_t struct gets passed from decode down to the function 
units, and to the ROB. (Aids in debugging, and most of the fields should be 
optimized out by synthesis.) 
-  Arrays of instances are a pain. (Their indices must be elaboration constants, 
i.e. genvars, you can’t construct a list from individual instances, only do 
lookup on an existing array, and they can’t be multi-dimensional.) Might be 
better to just use structs in the future. 
-  ALU FU is currently combinational, we’ll see what timing says. There is a 
buffer at each input to the CDB arbiter at least. 
-  Need to be careful with when instruction data can influence control bits, 
since uninitialized memory may be speculatively executed. If needed, can 
set the DRAM in options.json to output all zeros instead of unknowns. 
-  The RAT is transparent for the ready bits, but not for the physical register 
index (this being improperly implemented caused a bug). Because of this, 
decode doesn’t need a forwarding path. 
-  For the forwarding paths, need to be careful that every combinational path 
an instruction can traverse can be updated by the CDB. This includes the 
paths for when instruction stays put in a register due to a stall (another bug 
that occurred). 
-  Implementing a round-robin arbiter without using combinational loops is 
tricky. For now the CDB arbiter is just a priority arbiter, likewise for 
dispatch and the reservation stations. Might want to investigate changing 
this, e.g. for aged based issuing. 
-  Had some bugs from misinterpreting the sequential div datasheet. 
-  We might want to eliminate the x0 reg in the RAT and RRF if synthesis 
doesn’t already. The rest of the code already supports this. 
-  Always make sure to check valid bits. Had some bugs caused by X Prop 
that such checks prevent (e.g. control signals becoming unknown due to 
them being based on unknown data, when they should be set to some 
default if the valid bit is 0). 
-  The ALU currently uses extra alu_op values for slt and sltu. Should change 
this back once we have a proper comparator for branches. 
-  It seeeems that size’(i) is the correct way to assign an integer loop 
index to a variable, but would be good to check that synthesis doesn’t give 
a warning due to a signedness mismatch. 
-  Interface modports (if used) need to specify clk and rst as inputs too. 
Otherwise the modport doesn’t have permission to access the interface’s clk 
and rst. 
-  On mispredict, we mark all the insns in the rob (besides the mispredicted 
branch) as speculatively not ran, then when committing these 
speculatively-not-ran insns, we don't wait for them to be done on the cdb, 
and instead of sending the rd's to the rrf, we directly send them to the free 
list. 
-  When debugging deadlocks, it’s helpful to start from the ROB, check which 
instruction it’s waiting to be done, then work back from there. (I.e. then 
check if that instruction’s source regs were marked as ready, check if the 
FU deadlocked, etc.) Taking notes of the PCs of the involved instructions, 
the physical register indices, times when certain events occur (CDB, 
dispatch, commit, issue), etc helps. '



Final Report

Abstract
This report presents the design of an Explicit Register Renaming out-of-order
RISC-V processor developed in SystemVerilog. It details the microarchitectural
components required for out-of-order execution and examines the design and
optimization decisions made to improve performance while maintaining efficient
use of hardware resources. This report will also go over how the project was
managed and what we have learned at the end of this MP.
1 Project Overview
There were three main checkpoints in this project, as well as a final advanced features
checkpoint. Checkpoint one implements the basic fetch logic in order to load instruc-
tions into a queue structure. Checkpoint two implements ALU arithmetic instructions
to work with our processor. Checkpoint three implements memory and branch instruc-
tions, and the final advanced features checkpoint implements optimizations to increase
the Instructions Per Cycle (IPC) metric while keeping resource utilization down. For
version control our team used Github and for communication between team members
we used Discord.
2 Design
Figure 1 is the block design for our CPU. The basic control flow of our CPU first starts
by fetching an instruction from memory and stores it into an instruction queue. Then
what follows is a decode stage that interprets the instruction and breaks it down into
its operands and values that the CPU can decipher. Also in this stage, we allocate a
new entry in the reorder buffer (ROB) and rename all of the architectural registers
into physical register numbers in order to execute all the instructions out of order. It
reaches the dispatch stage and sends the instruction to its proper functional unit to the
reservation station. Once the values in the registers are ready in the reservation station,
they are sent out to the functional unit. Once the instruction is done processing, it is
sent out to the common data bus and is sent to the ROB for it to be fully committed.
1
Once the head of the ROB has the instruction ready to be fully committed, the final
value is written to the retired register file.
Fig. 1 Block Diagram of the OOO CPU
3 Modules
This section will talk about all of the modules inside the block diagram.
The cacheline adapter module serves as the interface between the cache and the
provided DRAM memory model. Its primary responsibility is to assemble a complete
256-bit cache line during read operations by issuing a memory request and collect-
ing four sequential 64-bit data bursts from DRAM. These bursts are combined to
reconstruct the full cache line according to the DRAM model’s behavior. The current
implementation supports read-only functionality.
The fetch module is responsible for retrieving instructions from the line buffer
and inserting them into the instruction queue while maintaining and updating the
program counter (PC). On each cycle, if the instruction queue is not full, the fetch
stage issues a read request using the current PC value. When a valid instruction is
returned, it is pushed into the instruction queue and the PC is incremented. If the
instruction queue is full, the fetch stage stalls until space becomes available.
The instruction cache is derived from the provided mp cache and implements a
four-way set-associative design. It serves as the interface between the CPU and the
cacheline adapter. Unlike a conventional cache that returns a single 32-bit word, this
cache always returns a full 256-bit cache line aligned to a byte boundary, enabling
efficient instruction delivery to the line buffer.
2
The linebuffer module acts as a small instruction buffer between the fetch stage
and the instruction cache. It temporarily stores an entire 256-bit cache line, cor-
responding to eight 32-bit instructions, to reduce repeated cache accesses during
sequential instruction fetches. When the fetch stage requests an instruction, the line
buffer checks whether the requested address falls within the currently buffered cache
line. On a hit, the instruction is returned immediately; on a miss, a new cache line is
requested from the instruction cache and stored locally once received. The module
also supports a flush signal to invalidate the buffered line during control flow changes
such as branches or jumps.
The queue module provides a parameterized FIFO buffer for transferring data
between pipeline stages. It supports enqueue and dequeue operations using internal
head and tail pointers to track read and write positions. Logic is included to detect
full and empty conditions, preventing overflow and underflow. The queue is parame-
terized by both data width and depth, allowing it to be reused for various buffering
needs throughout the pipeline.
The decode module translates fetched instructions from the instruction queue into
structured data packets suitable for execution. It decodes instruction fields, generates
control signals, and performs destination register renaming by allocating a new phys-
ical register, enabling out-of-order execution and eliminating false dependencies.
The RRF (Retirement Register File) module processes fully committed instruc-
tions from the reorder buffer (ROB). It updates the architectural-to-physical register
mappings upon retirement, ensures correct architectural state, supports recovery
from branch mispredictions, and returns freed physical registers to the free list.
The PRF (Physical Register File) module stores the actual data values associated
with all physical registers in the processor. It provides read access to functional units
and supports write-back and result broadcasting when instructions complete execu-
tion.
The free list module maintains a pool of unused physical register identifiers. When
the decode stage requires a new physical register during renaming, it allocates one by
popping an entry from the free list. Physical registers that are no longer needed after
instruction retirement are returned to the free list for future reuse.
The dispatch module examines decoded instructions and routes them to the
appropriate reservation station based on instruction type. This stage connects the
decode logic to the dynamic scheduling structures of the processor.
Each reservation station holds instructions waiting to be issued to a functional
unit. The reservation station tracks operand readiness and listens for result broad-
casts. When all operands are available and the appropriate functional unit is free, the
instruction is issued for execution. Essentially the reservation station is a queue of all
3
of the instructions waiting to be executed.
The reorder buffer (ROB) maintains the original program order of instructions
executing out of order. While instructions may complete execution in any order,
the ROB ensures they commit in order, preserving precise exceptions and correct
architectural state.
The functional units execute instructions once they are issued from the reservation
stations. The ALU handles integer arithmetic and logical operations, the multiply
unit executes multiplication instructions defined by the RISC-V multiply extension,
and the division unit executes division instructions from the RISC-V division exten-
sion, typically over multiple cycles.
After everything combined, Table 1 contains our baseline IPC metrics.
Benchmark Goal Baseline
aes sha 0.41 0.291903
compression 0.32 0.285482
fft.elf 0.49 0.407259
mergesort 0.55 0.335576
coremark 0.45 0.296657
Table 1 Performance comparison
between Goal and Baseline
configurations
4 Advanced Features
The one working advanced feature we finished is a GShare branch predictor with a
BTB to predict the branch and target address at fetch stage. The main purpose of
this is to reduce control hazards by allowing the processor to speculatively guess a
pc along a predicted control path. During instruction fetch, the predictor receives the
current program counter and generates a prediction indicating whether the instruction
is likely to be taken and, if so, the predicted target address. The direction prediction
is produced using a Pattern History Table (PHT) indexed by the XOR of the global
history register (GHR) and selected bits of the fetch PC, implementing the classic
Gshare prediction scheme. Each PHT entry is a 2-bit saturating counter, where values
in the weakly or strongly taken states indicate a taken prediction. Target prediction is
handled by a Branch Target Buffer (BTB), which stores previously observed branch
PCs along with their corresponding target addresses. A BTB hit occurs when the
indexed entry is valid and the stored tag matches the fetch PC. A branch is predicted
taken only when both the PHT indicates taken and the BTB contains a valid target for
the branch. The predictor is trained using information on the CDB once an instruction
completes execution. The predictor identifies what instruction are coming through
4
fetch and updates the pattern history table of 8 bits and updates them using a 2-bit
saturation counter. Table 2 shows how much the IPC has improved.

Benchmark Baseline Branch Predictor
0.291903 0.2990
aes sha
compression 0.285482 0.4930
fft.elf 0.407259 0.4657
mergesort 0.335576 0.3500
coremark 0.296657 0.3660
Table 2 Performance comparison between Baseline
and Branch Predictor configurations