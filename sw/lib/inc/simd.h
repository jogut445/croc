#pragma once

#include <stdint.h>
#include "config.h"
#include "util.h"

// ---------------------------------------------------------------------------
// static inline-asm wrappers
// ---------------------------------------------------------------------------

// 8-bit lane operations (funct3 = 0)
static inline uint32_t simd_padd8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul8    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat8(uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 0, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Horizontal accumulate: rd = rs1[7:0]+rs1[15:8]+rs1[23:16]+rs1[31:24]  (rs2 unused)
static inline uint32_t simd_padd8_acc(uint32_t a) { uint32_t r; asm volatile(".insn r 0x0b, 0, 8, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }

// 16-bit lane operations (funct3 = 1)
static inline uint32_t simd_padd16    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub16    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul16    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat16(uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 1, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
// Horizontal accumulate: rd = rs1[15:0]+rs1[31:16]  (rs2 unused)
static inline uint32_t simd_padd16_acc(uint32_t a) { uint32_t r; asm volatile(".insn r 0x0b, 1, 8, %0, %1, zero" : "=r"(r) : "r"(a)); return r; }

// 32-bit scalar operations (funct3 = 2)
static inline uint32_t simd_padd32    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2,  0, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_psub32    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2,  1, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_pmul32    (uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 16, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }
static inline uint32_t simd_padd_sat32(uint32_t a, uint32_t b) { uint32_t r; asm volatile(".insn r 0x0b, 2, 32, %0, %1, %2" : "=r"(r) : "r"(a), "r"(b)); return r; }

// ---------------------------------------------------------------------------
// Packing Wrappers
// ---------------------------------------------------------------------------
#define PACK8(b3, b2, b1, b0) \
    (((uint32_t)(uint8_t)(b3) << 24) | ((uint32_t)(uint8_t)(b2) << 16) | \
     ((uint32_t)(uint8_t)(b1) <<  8) |  (uint32_t)(uint8_t)(b0))

#define PACK16(h1, h0) \
    (((uint32_t)(uint16_t)(h1) << 16) | (uint32_t)(uint16_t)(h0))
