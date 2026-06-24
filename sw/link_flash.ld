/* Copyright (c) 2026 ETH Zurich and University of Bologna.
 * Licensed under the Apache License, Version 2.0, see LICENSE for details.
 * SPDX-License-Identifier: Apache-2.0
 */

/* Linker script for XiP (execute-in-place) flash boot.
 *
 * Memory map
 * ----------
 *   FLASH  VMA  0x2000_2000  where the CPU fetches/executes (via XiP controller)
 *   FLASHLD LMA  0x0000_2000  flash array byte address (@addr used by $readmemh)
 *   SRAM        0x1000_0000  8 KB on-chip SRAM — data, BSS, stack
 *
 * The XiP controller maps OBI address 0x2000_2000 → flash byte 0x002000,
 * so LMA = VMA - 0x2000_0000.  objcopy -O verilog emits LMA addresses,
 * giving the correct @002000 base in the hex output.
 *
 * At startup (crt0_flash.S):
 *   1. sp  ← __stack_pointer$ (top of SRAM)
 *   2. gp  ← __global_pointer$
 *   3. copy .misc initial values from __data_lma_vma (XiP OBI addr) → SRAM
 *   4. zero .bss
 *   5. call main()
 *   6. write CORESTATUS and halt (replaces bootrom _eoc)
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
    /* XiP execution window (VMA) */
    FLASH   (rx)  : ORIGIN = 0x20002000, LENGTH = 16M
    /* Flash byte addresses (LMA) — OBI 0x2000_2000 maps to flash byte 0x0 */
    FLASHLD       : ORIGIN = 0x00000000, LENGTH = 16M
    /* On-chip SRAM for writable data, BSS, and stack */
    SRAM    (rw)  : ORIGIN = 0x10000000, LENGTH = 8K
}

PHDRS
{
    text PT_LOAD FLAGS(5); /* Read + Execute */
    data PT_LOAD FLAGS(6); /* Read + Write   */
}

SECTIONS
{
    /DISCARD/ :
    {
        *(.riscv.attributes)
        *(.comment)
    }

    . = ORIGIN(FLASH);

    /* Code and read-only data: VMA in flash, LMA in flash array */
    .text : ALIGN(4)
    {
        *(.text._start)     /* startup code must be first */
        *(.text)
        *(.text.*)
        *(.rodata)
        *(.rodata.*)
    } > FLASH AT > FLASHLD :text

    /*
     * Reserve the first 12 bytes of SRAM for the bootrom trap-handler
     * pointer table (read by _trap_handler_wrapper at 0x0200_0200):
     *   0x1000_0000  placeholder word
     *   0x1000_0004  pointer to croc_exception_handler
     *   0x1000_0008  pointer to croc_interrupt_handler
     * crt0_flash.S fills these at startup; .misc/.data starts at 0x1000_000C.
     * NOLOAD means no bytes appear in the hex output — the startup code
     * initialises this area explicitly at runtime.
     */
    .vectors (NOLOAD) : ALIGN(4) { . += 12; } > SRAM :data

    /*
     * Writable data: executes from SRAM (VMA), initial values stored in flash
     * (LMA) and copied to SRAM by crt0_flash.S at startup.
     *
     * __data_lma_vma is the OBI/XiP address the startup code reads from.
     */
    .misc : ALIGN(4)
    {
        __data_start = .;
        *(.sdata)
        *(.sdata.*)
        *(.data)
        *(.data.*)
        __data_end = .;
    } > SRAM AT > FLASHLD :data

    /* XiP OBI address where .misc initial values are stored in flash */
    __data_lma_vma = LOADADDR(.misc) + (ORIGIN(FLASH) - ORIGIN(FLASHLD));

    /* BSS: zero-initialised at runtime, SRAM only, no LMA needed */
    .bss (NOLOAD) : ALIGN(4)
    {
        __bss_start = .;
        *(.sbss)
        *(.sbss.*)
        *(.bss)
        *(.bss.*)
        *(COMMON)
        __bss_end = .;
    } > SRAM :data
}

/* GP near the middle of .misc for efficient GP-relative small-data access */
PROVIDE(__global_pointer$ = ADDR(.misc) + SIZEOF(.misc) / 2);
/* Stack pointer at the top of SRAM */
PROVIDE(__stack_pointer$  = ORIGIN(SRAM) + LENGTH(SRAM));

/* SoC register */
PROVIDE(corestatus            = 0x03000008);

/* Bootrom fixed addresses (may be referenced by libgcc internals) */
PROVIDE(_eoc                  = 0x02000100);
PROVIDE(_trap_handler_wrapper = 0x02000200);
PROVIDE(_trap_exit            = 0x02000300);
