###########################################################################
# test_all.asm - RV32I full-instruction test for the single-cycle core
#
#  - Uses all 37 RV32I instructions this core supports
#    (no FENCE / ECALL / EBREAK / CSR)
#  - Each section ends in a known register state; expected values are in
#    the comments and in expected_commit_log.txt
#  - Wrong-path instructions write 0x666 into x30. If "x30 00000666" ever appears in
#    the commit log, a branch/jump went the wrong way (or, later, a flush failed)
#  - Section 8 has back-to-back dependencies and load-use pairs: they do
#    nothing special here, but they are the pipeline hazard tests
#  - Final signature: x31 = sum of x1..x30, stored at address 60 (DONE)
#
#  Memory needs: imem >= 1 KB  (set imem_depth = 10 in imem.sv)
#                dmem uses bytes 0..63 only (fits your 64-byte data_memory)
###########################################################################

        .text
        .globl _start
_start:

# ---------------- 1. U-type: LUI, AUIPC ---------------------------------
        lui   x1, 0x12345            # x1 = 0x12345000
        lui   x4, 0xFFFFF            # x4 = 0xFFFFF000 (negative)
        auipc x2, 0                  # x2 = PC of this instruction (0x08)
        auipc x3, 1                  # x3 = 0x0C + 0x1000 = 0x0000100C

# ---------------- 2. I-type ALU -----------------------------------------
        addi  x5, x0, 100            # x5  = 100
        addi  x6, x0, -7             # x6  = -7  (0xFFFFFFF9)
        addi  x7, x5, -2048          # x7  = -1948 (min 12-bit immediate)
        slti  x8, x6, 5              # x8  = 1   (-7 < 5 signed)
        slti  x9, x5, 5              # x9  = 0
        sltiu x10, x6, 5             # x10 = 0   (0xFFFFFFF9 > 5 unsigned)
        sltiu x11, x5, 101           # x11 = 1
        xori  x12, x5, 0x0F0         # x12 = 100 ^ 240 = 0x94
        ori   x13, x5, 0x700         # x13 = 0x764
        andi  x14, x6, 0x0FF         # x14 = 0xF9
        slli  x15, x6, 4             # x15 = 0xFFFFFF90
        srli  x16, x6, 28            # x16 = 0x0000000F
        srai  x17, x6, 1             # x17 = 0xFFFFFFFC (-4)
        xori  x18, x6, -1            # x18 = 6   (NOT -7)
        addi  x0, x0, 5              # write to x0 must be ignored

# ---------------- 3. R-type ---------------------------------------------
        add   x19, x5, x6            # x19 = 93
        sub   x20, x6, x5            # x20 = -107 (0xFFFFFF95)
        sll   x21, x5, x16           # x21 = 100 << 15 = 0x00320000
        slt   x22, x6, x5            # x22 = 1
        slt   x23, x5, x6            # x23 = 0
        sltu  x24, x5, x6            # x24 = 1
        sltu  x25, x6, x5            # x25 = 0
        xor   x26, x5, x6            # x26 = 0xFFFFFF9D
        srl   x27, x6, x8            # x27 = 0x7FFFFFFC
        sra   x28, x6, x8            # x28 = 0xFFFFFFFC
        or    x29, x1, x5            # x29 = 0x12345064
        and   x30, x4, x6            # x30 = 0xFFFFF000
        addi  x9, x0, 33             # x9  = 33
        sll   x9, x5, x9             # x9  = 200 (only rs2[4:0] = 1 is used)
        add   x10, x0, x0            # x10 = 0   (x0 still reads 0)

# ---------------- 4. Stores and loads (bytes 0..15) ---------------------
        sw    x6, 0(x0)              # M[0..3]  = F9 FF FF FF
        sh    x5, 4(x0)              # M[4..5]  = 64 00
        sb    x6, 6(x0)              # M[6]     = F9
        sb    x5, 7(x0)              # M[7]     = 64
        lw    x11, 4(x0)             # x11 = 0x64F90064
        lh    x12, 0(x0)             # x12 = 0xFFFFFFF9 (sign-extended)
        lhu   x13, 0(x0)             # x13 = 0x0000FFF9
        lb    x14, 6(x0)             # x14 = 0xFFFFFFF9
        lbu   x15, 6(x0)             # x15 = 0x000000F9
        lh    x16, 6(x0)             # x16 = 0x000064F9
        lhu   x17, 2(x0)             # x17 = 0x0000FFFF
        addi  x18, x0, 16            # x18 = 16
        sw    x1, -8(x18)            # M[8..11] = x1 (negative offset)
        lw    x19, 8(x0)             # x19 = 0x12345000
        sh    x6, 12(x0)             # M[12..13] = F9 FF
        sb    x0, 14(x0)             # M[14]    = 00
        sb    x5, 15(x0)             # M[15]    = 64
        lw    x20, 12(x0)            # x20 = 0x6400FFF9

# ---------------- 5. Branches: each taken and not-taken -----------------
#  x21 collects one bit per correct outcome. Expected final x21 = 0xFFFFFFFF (any 0 bit = that test failed)
        addi  x21, x0, 0
        beq   x5, x5, b1             # taken
        addi  x30, x0, 0x666         # must be skipped
b1:     ori   x21, x21, 0x001
        beq   x5, x6, b2             # not taken
        ori   x21, x21, 0x002
b2:     bne   x5, x6, b3             # taken
        addi  x30, x0, 0x666
b3:     ori   x21, x21, 0x004
        bne   x5, x5, b4             # not taken
        ori   x21, x21, 0x008
b4:     blt   x6, x5, b5             # taken     (-7 < 100 signed)
        addi  x30, x0, 0x666
b5:     ori   x21, x21, 0x010
        blt   x5, x6, b6             # not taken
        ori   x21, x21, 0x020
b6:     bge   x5, x6, b7             # taken     (100 >= -7 signed)
        addi  x30, x0, 0x666
b7:     ori   x21, x21, 0x040
        bge   x6, x5, b8             # not taken
        ori   x21, x21, 0x080
b8:     bltu  x5, x6, b9             # taken     (100 < 0xFFFFFFF9 unsigned)
        addi  x30, x0, 0x666
b9:     ori   x21, x21, 0x100
        bltu  x6, x5, b10            # not taken
        ori   x21, x21, 0x200
b10:    bgeu  x6, x5, b11            # taken
        addi  x30, x0, 0x666
b11:    ori   x21, x21, 0x400
        bgeu  x5, x6, b12            # not taken
        ori   x21, x21, -2048        # sets bits 31..11
b12:    bge   x5, x5, b13            # taken (equal operands)
        addi  x30, x0, 0x666
b13:

# ---------------- 6. Backward branch loop: 4 iterations -----------------
        addi  x22, x0, 4             # counter
        addi  x23, x0, 0             # sum
loop:   add   x23, x23, x22          # 4+3+2+1
        addi  x22, x22, -1
        bne   x22, x0, loop          # backward branch
                                     # x22 = 0, x23 = 10

# ---------------- 7. Jumps: JAL, JALR -----------------------------------
        jal   x24, func              # call: x24 = return address
        addi  x25, x25, 1            # runs after return: x25 = 1
        jal   x0, after_func         # skip over func
        addi  x30, x0, 0x666
func:   addi  x25, x0, 0             # x25 = 0
        jalr  x0, 0(x24)             # return
        addi  x30, x0, 0x666
after_func:
        auipc x26, 0                 # x26 = PC here
        jalr  x27, 17(x26)           # target = (x26+17) & ~1 = x26+16 (LSB cleared)
        addi  x30, x0, 0x666         # x26+8
        addi  x30, x0, 0x666         # x26+12
        addi  x28, x0, 77            # x26+16: landing point, x28 = 77
        auipc x29, 0
        jalr  x29, 12(x29)           # rd == rs1: target uses OLD x29
        addi  x30, x0, 0x666
        addi  x30, x0, 0             # x30 = 0 (clears the earlier AND result)

# ---------------- 8. Hazard patterns (matter only once pipelined) -------
        addi  x1, x0, 1              # x1 = 1
        add   x2, x1, x1             # E->E forward      : x2 = 2
        add   x3, x2, x1             # M and W forward   : x3 = 3
        add   x3, x3, x3             # same reg twice    : x3 = 6
        add   x4, x3, x2             # x4 = 8
        add   x0, x4, x4             # write to x0
        add   x5, x0, x4             # x0 must not forward: x5 = 8
        lui   x6, 0x1                # LUI -> use        : x6 = 0x1000
        addi  x6, x6, 0x23           # x6 = 0x1023
        sw    x6, 16(x0)             # ALU result -> store data
        lw    x7, 16(x0)             # x7 = 0x1023
        addi  x8, x7, 1              # load-use stall    : x8 = 0x1024
        lw    x9, 16(x0)
        sw    x9, 20(x0)             # load -> store data: M[20] = 0x1023
        lw    x10, 20(x0)            # x10 = 0x1023
        beq   x10, x6, h1            # load -> branch (taken)
        addi  x30, x0, 0x666
h1:     addi  x11, x0, 5
        bne   x11, x5, h2            # ALU -> branch (5 != 8, taken)
        addi  x30, x0, 0x666
h2:     jal   x12, h3                # link value used right away
h3:     addi  x13, x12, 0            # x13 = x12 = address of h3

# ---------------- 9. Signature: x31 = x1 + x2 + ... + x30 ---------------
        add   x31, x0, x1
        add   x31, x31, x2
        add   x31, x31, x3
        add   x31, x31, x4
        add   x31, x31, x5
        add   x31, x31, x6
        add   x31, x31, x7
        add   x31, x31, x8
        add   x31, x31, x9
        add   x31, x31, x10
        add   x31, x31, x11
        add   x31, x31, x12
        add   x31, x31, x13
        add   x31, x31, x14
        add   x31, x31, x15
        add   x31, x31, x16
        add   x31, x31, x17
        add   x31, x31, x18
        add   x31, x31, x19
        add   x31, x31, x20
        add   x31, x31, x21
        add   x31, x31, x22
        add   x31, x31, x23
        add   x31, x31, x24
        add   x31, x31, x25
        add   x31, x31, x26
        add   x31, x31, x27
        add   x31, x31, x28
        add   x31, x31, x29
        add   x31, x31, x30
        sw    x31, 60(x0)            # DONE: testbench stops here
end:    jal   x0, end                # halt loop
        addi  x0, x0, 0
