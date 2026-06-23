# Copyright (c) 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Flash-boot startup code for the Croc SoC.
#
# Execution begins here when the bootrom detects BOOTMODE != 0 and jumps to
# the XiP flash base (0x2000_2000).  The CPU arrives with no stack, no GP,
# and mtvec still pointing to wherever the bootrom left it (or reset value).
#
# This file is paired with link_flash.ld which places:
#   .text / .rodata  → VMA 0x2000_2000+  (flash, execute-in-place)
#   .misc / .data    → VMA 0x1000_0000+  (SRAM, writable)
#                      LMA flash-array byte address (initial values in flash)
#   .bss             → VMA 0x1000_0000+  (SRAM, zero-initialised)
#
# Startup sequence:
#   1. Set sp = top of SRAM (0x1000_1000)
#   2. Set gp (GP-relative small-data optimisation)
#   3. Copy .misc initial values from flash (OBI XiP window) → SRAM
#   4. Zero .bss
#   5. call main()
#   6. Pack return code → write CORESTATUS → wfi  (replaces bootrom _eoc)
#
# Note: mtvec is NOT set up here.  If C code needs trap handling, it must
# call csrw mtvec itself before enabling interrupts.

.section .text._start
.globl _start
_start:
    # -----------------------------------------------------------------------
    # 1. Stack pointer: top of SRAM (defined in link_flash.ld)
    # -----------------------------------------------------------------------
    la    sp, __stack_pointer$

    # -----------------------------------------------------------------------
    # 2. Global pointer: near middle of .misc for GP-relative access.
    #    .option norelax prevents the assembler from turning this into a NOP
    #    (it would do so if gp is already set, but here it isn't).
    # -----------------------------------------------------------------------
    .option push
    .option norelax
    la    gp, __global_pointer$
    .option pop

    # -----------------------------------------------------------------------
    # 3. Copy .misc / .data initial values from flash to SRAM.
    #    __data_lma_vma = OBI address in the XiP window where the initial
    #    values live (= LOADADDR(.misc) + 0x2000_0000, set in link_flash.ld).
    #    __data_start / __data_end = SRAM destination range.
    # -----------------------------------------------------------------------
    la    a0, __data_start       # dst (SRAM)
    la    a1, __data_lma_vma     # src (flash XiP window, OBI address)
    la    a2, __data_end
    beq   a0, a2, .Lbss          # skip if .data / .misc is empty

.Ldata:
    lw    t0, 0(a1)
    sw    t0, 0(a0)
    addi  a0, a0, 4
    addi  a1, a1, 4
    blt   a0, a2, .Ldata

    # -----------------------------------------------------------------------
    # 4. Zero .bss in SRAM
    # -----------------------------------------------------------------------
.Lbss:
    la    a0, __bss_start
    la    a1, __bss_end
    beq   a0, a1, .Lmain

.Lbss_zero:
    sw    zero, 0(a0)
    addi  a0, a0, 4
    blt   a0, a1, .Lbss_zero

    # -----------------------------------------------------------------------
    # 5. Trap setup.
    #    The bootrom's _trap_handler_wrapper (0x0200_0200) reads function
    #    pointers from SRAM:
    #      0x1000_0004 → croc_exception_handler
    #      0x1000_0008 → croc_interrupt_handler
    #    link_flash.ld reserves the first 12 bytes of SRAM (.vectors NOLOAD)
    #    so .misc/.data starts at 0x1000_000C and does not overlap this table.
    # -----------------------------------------------------------------------
.Lmain:
    lui   t0, 0x10000               # SRAM base 0x1000_0000
    sw    zero, 0(t0)               # 0x1000_0000: placeholder (unused)
    la    t1, croc_exception_handler
    sw    t1, 4(t0)                 # 0x1000_0004
    la    t1, croc_interrupt_handler
    sw    t1, 8(t0)                 # 0x1000_0008
    li    t0, 0x02000200            # _trap_handler_wrapper in bootrom
    csrw  mtvec, t0

    call  main

    # -----------------------------------------------------------------------
    # 6. End-of-computation (mirrors bootrom _eoc at 0x0200_0100):
    #    pack return code (a0 << 1 | 1) into CORESTATUS so the testbench
    #    can detect completion via jtag_wait_for_eoc().
    # -----------------------------------------------------------------------
    slli  a0, a0, 1              # return code left-shifted
    ori   a0, a0, 1              # set bit 0 as EOC flag
    lui   t0, %hi(corestatus)    # = 0x03000
    sw    a0, %lo(corestatus)(t0) # → 0x0300_0008
    wfi

    # Spin in case wfi returns (e.g. spurious interrupt)
.Lhalt:
    j     .Lhalt

# ==================================================================
# Default exception handler (weak — override in C by defining your own)
# Mirrors the weak symbol in crt0.S so flash and SRAM builds behave
# identically when no custom handler is provided.
# ==================================================================
.section .text
.weak croc_exception_handler
.globl croc_exception_handler
croc_exception_handler:
    ret

# ==================================================================
# Default interrupt handler (weak — override in C)
# ==================================================================
.weak croc_interrupt_handler
.globl croc_interrupt_handler
croc_interrupt_handler:
    li    t0, 7             # timer interrupt ID
    bne   a0, t0, 1f        # not timer? skip
    li    t0, (1 << 7)      # MTIE bit
    csrc  mie, t0           # disable timer interrupt
1:
    ret
