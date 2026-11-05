# RV32I Single-Cycle Processor

This is a single-cycle RISC-V core for the **RV32I** base integer ISA, written in SystemVerilog. It was verified in ModelSim against a self-checking testbench.

## Overview

Every instruction completes in one clock cycle: fetch, decode, execute, memory access and write-back all happen together. The core covers the 37 user-level RV32I instructions, which means arithmetic and logic ops, shifts, loads and stores, branches, jumps, `LUI` and `AUIPC`. Each part of the datapath (decoder, control unit, ALU, branch comparator, register file, memories) is its own small module, and the top-level file wires them together.

For verification, the testbench records each register write and each store into a commit log. It checks every entry against a reference log and prints PASS once the program writes its expected value to a fixed memory address.

## Architecture

![RV32I single-cycle datapath](docs/datapath.png)

From the decoded instruction, the control unit produces `pc_sel`, `op1_sel`, `op2_sel`, `alu_op`, `rf_wr_data_sel`, `rf_wr_en` and the `dmem_*` signals. The branch comparator outputs `branch_taken`, which is ORed with `pc_sel` to drive the next-PC mux.

Design notes:

- **Branches:** the ALU calculates the target address (`PC + imm`). A separate `branch_control` unit decides whether to take the branch.
- **Jumps:** for `JAL` and `JALR` the ALU also produces the target, and the write-back mux puts `PC + 4` into `rd`. For `JALR`, bit 0 of the target is cleared.
- **Write-back sources:** the ALU result, data memory, the immediate (for `LUI`), or `PC + 4` (for jumps).
- **Reset:** on reset the PC loads `RESET_PC`, which defaults to `0`. A request register inside `fetch` blocks instruction fetch for one cycle after reset so that the first instruction executes only once.

## Modules

| File | Module | Role |
|------|--------|------|
| `rtl/package.sv` | `risc_pkg` | Opcodes, ALU op enum, memory size enum, funct encodings, write-back source enum, control struct |
| `rtl/top.sv` | `top` | PC register, next-PC mux, ALU operand muxes, write-back mux, and the wiring between modules |
| `rtl/fetch.sv` | `fetch` | Sends the PC to the instruction memory and gates the fetch request after reset |
| `rtl/imem.sv` | `instruction_memory` | 1 KiB byte-addressed instruction memory with combinational read, loaded via `$readmemh` |
| `rtl/decode.sv` | `decode` | Pulls out instruction fields, flags the instruction type, builds the I/S/B/U/J immediates |
| `rtl/control.sv` | `control` | Produces the ALU op, operand and write-back selects, memory controls and register write enable |
| `rtl/reg_file.sv` | `register_file` | 32 x 32-bit registers; two combinational read ports, one synchronous write port; `x0` tied to zero; async active-low reset |
| `rtl/alu.sv` | `alu` | ADD, SUB, SLL, SRL, SRA, SLT, SLTU, XOR, OR, AND |
| `rtl/branch_control.sv` | `branch_control` | Comparisons for BEQ, BNE, BLT, BGE, BLTU, BGEU |
| `rtl/data_memory.sv` | `data_memory` | Little-endian data memory, 64 bytes by default (parameterised), with byte/halfword/word access and sign- or zero-extended loads |
| `tb/test_bench.sv` | `test_bench` | Self-checking testbench that compares commit logs |

## Supported instructions

| Type | Instructions |
|------|--------------|
| R | `ADD` `SUB` `SLL` `SLT` `SLTU` `XOR` `SRL` `SRA` `OR` `AND` |
| I (ALU) | `ADDI` `SLTI` `SLTIU` `XORI` `ORI` `ANDI` `SLLI` `SRLI` `SRAI` |
| I (load) | `LB` `LH` `LW` `LBU` `LHU` |
| I (jump) | `JALR` |
| S | `SB` `SH` `SW` |
| B | `BEQ` `BNE` `BLT` `BGE` `BLTU` `BGEU` |
| U | `LUI` `AUIPC` |
| J | `JAL` |

`FENCE`, `ECALL`, `EBREAK` and the CSR instructions are not supported.

## Repository layout

```
.
├── rtl/         SystemVerilog design files
├── tb/          testbench
├── programs/    assembly sources and .mem machine code
├── logs/        reference and generated commit logs
├── sim/         ModelSim script (run.do)
├── waveforms/   ModelSim waveform captures
└── README.md
```

## Simulation


The script recompiles everything (`rtl/package.sv` goes first since the other files import it), loads the testbench, adds the main signals to the wave window and runs until the testbench finishes.

### Switching programs

The program comes from the `$readmemh` call in `rtl/imem.sv`. To run something else:

1. Change the `$readmemh` path to the program's `.mem` file in `programs/`.
2. Update `DONE_ADDR` and `DONE_DATA` in `tb/test_bench.sv` using the values in the table below.
3. `expected_commit_log.txt` only matches `test_all`. For other programs, rename or delete it; if the file is missing, the testbench skips the comparison and only writes the log.

Each `.mem` file stores **one hex byte per line, most significant byte first**, so every instruction takes four lines.

## Test programs and results

All register writes and stores go into a commit log. When `expected_commit_log.txt` exists, each entry is checked against it. The run stops at the first mismatch, at an unknown PC, or after a 2000-cycle timeout. A program passes when it stores `DONE_DATA` to `DONE_ADDR`.

| Program | Files in `programs/` | Description | Pass condition |
|---------|----------------------|-------------|----------------|
| `test_all` | `test_all.asm`, `test_all.mem` | Exercises the full instruction set; every commit is checked against the reference log | `MEM[60] = 0x7637112C` |
| Fibonacci | `fibonacci_sequence_assembly.asm`, `fibonacci_sequence_machine_code.mem` | Generates the first 10 terms (0, 1, 1, 2, 3, 5, 8, 13, 21, 34) and stores them as words at addresses 0 through 36 | `MEM[36] = 34` |
| Array maximum | `max_array.asm`, `max_array.mem` | Writes `8, -21, 15, -3, 42, 17` to memory, finds the largest value with a signed compare and stores it at address 24 | `MEM[24] = 42` |
| Bubble sort | `bubble_sort+_assembly.asm`, `bs_machine_code.mem` | Places `7, 2, 9, 4` at addresses 0, 4, 8 and 12 and sorts them in place, largest first | Memory ends as `9, 7, 4, 2` (verified from the waveform, since this program has no completion store) |

### Waveforms

Data memory appears one byte per row in little-endian order, so a 32-bit word spans four rows.

**Bubble sort:** words 0 to 3 begin as `7, 2, 9, 4` and finish as `9, 7, 4, 2`.

![Bubble sort](waveforms/bubble_sort.png)

**Fibonacci:** terms show up in memory one at a time, with `34` landing at address 36 last.

![Fibonacci](waveforms/fibonacci.png)

**Array maximum:** after the array is written, `42` is stored at address 24.

![Find maximum](waveforms/find_max.png)

**test_all:** the complete run.

![test_all run](waveforms/test_all.png)

## Limitations and next steps

- Because it is single-cycle, the clock period is bounded by the longest path: fetch, then ALU, data memory and write-back.
- Both memories are small (64 bytes of data, 1 KiB of instructions) and read combinationally.
- There is no handling for misaligned accesses, and no exceptions, CSRs, `FENCE`, `ECALL` or `EBREAK`.
- The core has not been implemented on hardware yet. The next step is to synthesize it and run it on a Spartan FPGA board.
- Ideas for later: a 5-stage pipeline with hazard handling, the M extension for multiply and divide, and memory-mapped I/O.