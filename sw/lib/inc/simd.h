#pragma once

#include <stdint.h>
#include "config.h"
#include "util.h"

// ---------------------------------------------------------------------------
// SIMD32-IBEX inline-asm wrappers
// funct3 selects lane width: 0=8-bit, 1=16-bit, 2=32-bit
// funct7 selects operation (decimal values used in .insn r)
// ---------------------------------------------------------------------------

// 8-bit lane operations (funct3 = 0)
static inline uint32_t simd_padd8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat8 (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub_sat8 (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 33, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Horizontal accumulate: rd = rs1[7:0]+rs1[15:8]+rs1[23:16]+rs1[31:24]  (rs2 unused)
static inline uint32_t simd_padd8_acc (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 0,  8, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Permute: reverse byte order {b3,b2,b1,b0}->{b0,b1,b2,b3}  (rs2 unused)
static inline uint32_t simd_pperm8    (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 0,  9, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Popcount: count set bits per byte lane  (rs2 unused)
static inline uint32_t simd_popcount8 (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 0, 10, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Lane-wise shift: shift amount from rs2[2:0]
static inline uint32_t simd_psll8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 24, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psrl8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 25, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Lane-wise rotate left: amount from rs2[2:0]
static inline uint32_t simd_prol8     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 26, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// 16-bit lane operations (funct3 = 1)
static inline uint32_t simd_padd16     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub16     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul16     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat16 (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub_sat16 (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 33, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Horizontal accumulate: rd = rs1[15:0]+rs1[31:16]  (rs2 unused)
static inline uint32_t simd_padd16_acc (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 1,  8, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Permute: swap halfword lanes {h1,h0}->{h0,h1}  (rs2 unused)
static inline uint32_t simd_pperm16    (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 1,  9, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Popcount: count set bits per halfword lane  (rs2 unused)
static inline uint32_t simd_popcount16 (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 1, 10, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Lane-wise shift: shift amount from rs2[3:0]
static inline uint32_t simd_psll16     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 24, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psrl16     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 25, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Lane-wise rotate left: amount from rs2[3:0]
static inline uint32_t simd_prol16     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 26, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// 32-bit operations (funct3 = 2)
static inline uint32_t simd_padd_sat32 (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub_sat32 (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 33, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Popcount: count set bits in full 32-bit word  (rs2 unused)
static inline uint32_t simd_popcount32 (uint32_t a)             { uint32_t r; asm volatile(".insn r 0x0b, 2, 10, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }
// Rotate left: amount from rs2[4:0]
static inline uint32_t simd_prol32     (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 26, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// ---------------------------------------------------------------------------
// Packing Wrappers
// ---------------------------------------------------------------------------
#define PACK8(b3, b2, b1, b0) \
    (((uint32_t)(uint8_t)(b3) << 24) | ((uint32_t)(uint8_t)(b2) << 16) | \
     ((uint32_t)(uint8_t)(b1) <<  8) |  (uint32_t)(uint8_t)(b0))

#define PACK16(h1, h0) \
    (((uint32_t)(uint16_t)(h1) << 16) | (uint32_t)(uint16_t)(h0))
