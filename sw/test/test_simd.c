// Copyright (c) 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Unit test for the SIMD32-IBEX packed SIMD extension.
//
// All instructions use opcode custom-0 (0x0b), R-type encoding:
//   funct3 = 0  → 8-bit lanes  (4 lanes per 32-bit register)
//   funct3 = 1  → 16-bit lanes (2 lanes per 32-bit register)
//   funct3 = 2  → 32-bit scalar
//
//   funct7 encoding:
//     0x00 = padd       0x01 = psub       0x08 = pand
//     0x09 = por        0x0a = pxor       0x10 = pmul
//     0x20 = padd_sat (unsigned saturation)
//
// Instructions are emitted via the GAS .insn r directive:
//   .insn r OPCODE, FUNC3, FUNC7, rd, rs1, rs2

#include "util.h"

// ---------------------------------------------------------------------------
// Inline-asm wrappers
// ---------------------------------------------------------------------------

// 8-bit lane operations (funct3 = 0)
static inline uint32_t simd_padd8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pand8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  8, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_por8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  9, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pxor8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 10, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat8(uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// 16-bit lane operations (funct3 = 1)
static inline uint32_t simd_padd16    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub16    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul16    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat16(uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// 32-bit scalar operations (funct3 = 2)
static inline uint32_t simd_padd32    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub32    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul32    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat32(uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// ---------------------------------------------------------------------------
// Test helpers: pack four bytes or two halfwords into a uint32_t
// ---------------------------------------------------------------------------
#define PACK8(b3, b2, b1, b0) \
    (((uint32_t)(uint8_t)(b3) << 24) | ((uint32_t)(uint8_t)(b2) << 16) | \
     ((uint32_t)(uint8_t)(b1) <<  8) |  (uint32_t)(uint8_t)(b0))

#define PACK16(h1, h0) \
    (((uint32_t)(uint16_t)(h1) << 16) | (uint32_t)(uint16_t)(h0))

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------
int main(void) {

    // =========================================================
    // 8-bit lane tests
    // =========================================================

    // padd8: each lane adds independently, wrapping at 0xFF
    // lanes: [1+5, 2+6, 3+7, 4+8] = [6, 8, 10, 12]
    CHECK_ASSERT(1, simd_padd8(PACK8(1,2,3,4), PACK8(5,6,7,8)) == PACK8(6,8,10,12));

    // padd8 wrap: 0xFF + 0x01 = 0x00 (wraps)
    CHECK_ASSERT(2, simd_padd8(PACK8(0xFF,0,0,0), PACK8(1,0,0,0)) == PACK8(0,0,0,0));

    // psub8: each lane subtracts independently, wrapping at 0
    // [10-1, 11-2, 12-3, 16-7] = [9, 9, 9, 9]
    CHECK_ASSERT(3, simd_psub8(PACK8(10,11,12,16), PACK8(1,2,3,7)) == PACK8(9,9,9,9));

    // psub8 wrap: 0x01 - 0x02 = 0xFF (unsigned wrap)
    CHECK_ASSERT(4, simd_psub8(PACK8(1,0,0,0), PACK8(2,0,0,0)) == PACK8(0xFF,0,0,0));

    // pand8: bitwise AND, lane width is irrelevant
    CHECK_ASSERT(5, simd_pand8(0xF0F0F0F0u, 0x0F0F0F0Fu) == 0x00000000u);
    CHECK_ASSERT(6, simd_pand8(0xFFFFFFFFu, 0xA5A5A5A5u) == 0xA5A5A5A5u);

    // por8: bitwise OR
    CHECK_ASSERT(7, simd_por8(0xF0F0F0F0u, 0x0F0F0F0Fu) == 0xFFFFFFFFu);
    CHECK_ASSERT(8, simd_por8(0x00000000u, 0xA5A5A5A5u) == 0xA5A5A5A5u);

    // pxor8: bitwise XOR
    CHECK_ASSERT(9,  simd_pxor8(0xFF00FF00u, 0x00FF00FFu) == 0xFFFFFFFFu);
    CHECK_ASSERT(10, simd_pxor8(0xA5A5A5A5u, 0xA5A5A5A5u) == 0x00000000u);

    // pmul8: lower 8 bits of lane product
    // [2*3, 3*4, 4*5, 5*6] = [6, 12, 20, 30]
    CHECK_ASSERT(11, simd_pmul8(PACK8(2,3,4,5), PACK8(3,4,5,6)) == PACK8(6,12,20,30));

    // pmul8 truncation: 16 * 16 = 256, lower byte = 0
    CHECK_ASSERT(12, simd_pmul8(PACK8(16,1,1,1), PACK8(16,1,1,1)) == PACK8(0,1,1,1));

    // padd_sat8: unsigned saturation at 0xFF
    // [255+1, 128+128, 16+240, 1+1] = [sat→255, sat→255, sat→255, 2]
    CHECK_ASSERT(13, simd_padd_sat8(PACK8(255,128, 16,1),
                                    PACK8(  1,128,240,1)) == PACK8(255,255,255,2));

    // padd_sat8: no saturation case
    CHECK_ASSERT(14, simd_padd_sat8(PACK8(10,20,30,40), PACK8(1,2,3,4)) == PACK8(11,22,33,44));

    // =========================================================
    // 16-bit lane tests
    // =========================================================

    // padd16: [1+3, 2+4] = [4, 6]
    CHECK_ASSERT(15, simd_padd16(PACK16(1,2), PACK16(3,4)) == PACK16(4,6));

    // padd16 wrap: 0xFFFF + 1 = 0x0000
    CHECK_ASSERT(16, simd_padd16(PACK16(0xFFFF,0), PACK16(1,0)) == PACK16(0,0));

    // psub16: [10-5, 11-3] = [5, 8]
    CHECK_ASSERT(17, simd_psub16(PACK16(10,11), PACK16(5,3)) == PACK16(5,8));

    // psub16 wrap: 0x0001 - 0x0002 = 0xFFFF
    CHECK_ASSERT(18, simd_psub16(PACK16(1,0), PACK16(2,0)) == PACK16(0xFFFF,0));

    // pmul16: lower 16 bits of lane product
    // [2*4, 3*5] = [8, 15]
    CHECK_ASSERT(19, simd_pmul16(PACK16(2,3), PACK16(4,5)) == PACK16(8,15));

    // pmul16 truncation: 0x0100 * 0x0100 = 0x10000, lower 16 = 0
    CHECK_ASSERT(20, simd_pmul16(PACK16(0x0100,1), PACK16(0x0100,1)) == PACK16(0,1));

    // padd_sat16: unsigned saturation at 0xFFFF
    // [0xFFFF+1, 0x0100+0xFF00] = [sat→0xFFFF, sat→0xFFFF (0x10000)]
    CHECK_ASSERT(21, simd_padd_sat16(PACK16(0xFFFF, 0x0100),
                                     PACK16(     1, 0xFF00)) == PACK16(0xFFFF, 0xFFFF));

    // padd_sat16: no saturation
    CHECK_ASSERT(22, simd_padd_sat16(PACK16(100,200), PACK16(50,75)) == PACK16(150,275));

    // =========================================================
    // 32-bit scalar tests
    // =========================================================

    // padd32: scalar add (same as ADD)
    CHECK_ASSERT(23, simd_padd32(0x00010000u, 0x00020000u) == 0x00030000u);

    // padd32 wrap
    CHECK_ASSERT(24, simd_padd32(0xFFFFFFFFu, 1u) == 0x00000000u);

    // psub32: scalar subtract (same as SUB)
    CHECK_ASSERT(25, simd_psub32(0x00050000u, 0x00020000u) == 0x00030000u);

    // psub32 wrap
    CHECK_ASSERT(26, simd_psub32(0u, 1u) == 0xFFFFFFFFu);

    // pmul32: lower 32 bits of product
    CHECK_ASSERT(27, simd_pmul32(5u, 7u) == 35u);

    // pmul32 truncation: 0x10000 * 0x10000 = 0x100000000 → lower 32 = 0
    CHECK_ASSERT(28, simd_pmul32(0x00010000u, 0x00010000u) == 0x00000000u);

    // padd_sat32: unsigned saturation at 0xFFFFFFFF
    CHECK_ASSERT(29, simd_padd_sat32(0xFFFFFFFEu, 2u) == 0xFFFFFFFFu);

    // padd_sat32: exact boundary — 0xFFFFFFFE + 1 = 0xFFFFFFFF (no saturation)
    CHECK_ASSERT(30, simd_padd_sat32(0xFFFFFFFEu, 1u) == 0xFFFFFFFFu);

    // padd_sat32: no saturation
    CHECK_ASSERT(31, simd_padd_sat32(100u, 200u) == 300u);

    return 0;
}
