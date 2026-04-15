#include "simd.h"

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

    // pmul8: lower 8 bits of lane product
    // [2*3, 3*4, 4*5, 5*6] = [6, 12, 20, 30]
    CHECK_ASSERT(5, simd_pmul8(PACK8(2,3,4,5), PACK8(3,4,5,6)) == PACK8(6,12,20,30));

    // pmul8 truncation: 16 * 16 = 256, lower byte = 0
    CHECK_ASSERT(6, simd_pmul8(PACK8(16,1,1,1), PACK8(16,1,1,1)) == PACK8(0,1,1,1));

    // padd_sat8: unsigned saturation at 0xFF
    // [255+1, 128+128, 16+240, 1+1] = [sat→255, sat→255, sat→255, 2]
    CHECK_ASSERT(7, simd_padd_sat8(PACK8(255,128, 16,1),
                                   PACK8(  1,128,240,1)) == PACK8(255,255,255,2));

    // padd_sat8: no saturation
    CHECK_ASSERT(8, simd_padd_sat8(PACK8(10,20,30,40), PACK8(1,2,3,4)) == PACK8(11,22,33,44));

    // padd8.acc: rd = sum of all four byte lanes (zero-extended to 32 bits)
    // 1 + 2 + 3 + 4 = 10
    CHECK_ASSERT(9, simd_padd8_acc(PACK8(1,2,3,4)) == 10u);

    // padd8.acc: 0x10 + 0x20 + 0x30 + 0x40 = 0xA0
    CHECK_ASSERT(10, simd_padd8_acc(PACK8(0x10,0x20,0x30,0x40)) == 0xA0u);

    // padd8.acc: all 0xFF lanes → 4*255 = 1020 = 0x3FC (result exceeds 8 bits)
    CHECK_ASSERT(11, simd_padd8_acc(PACK8(0xFF,0xFF,0xFF,0xFF)) == 0x3FCu);

    // =========================================================
    // 16-bit lane tests
    // =========================================================

    // padd16: [1+3, 2+4] = [4, 6]
    CHECK_ASSERT(12, simd_padd16(PACK16(1,2), PACK16(3,4)) == PACK16(4,6));

    // padd16 wrap: 0xFFFF + 1 = 0x0000
    CHECK_ASSERT(13, simd_padd16(PACK16(0xFFFF,0), PACK16(1,0)) == PACK16(0,0));

    // psub16: [10-5, 11-3] = [5, 8]
    CHECK_ASSERT(14, simd_psub16(PACK16(10,11), PACK16(5,3)) == PACK16(5,8));

    // psub16 wrap: 0x0001 - 0x0002 = 0xFFFF
    CHECK_ASSERT(15, simd_psub16(PACK16(1,0), PACK16(2,0)) == PACK16(0xFFFF,0));

    // pmul16: lower 16 bits of lane product
    // [2*4, 3*5] = [8, 15]
    CHECK_ASSERT(16, simd_pmul16(PACK16(2,3), PACK16(4,5)) == PACK16(8,15));

    // pmul16 truncation: 0x0100 * 0x0100 = 0x10000, lower 16 = 0
    CHECK_ASSERT(17, simd_pmul16(PACK16(0x0100,1), PACK16(0x0100,1)) == PACK16(0,1));

    // padd_sat16: unsigned saturation at 0xFFFF
    // [0xFFFF+1, 0x0100+0xFF00] = [sat→0xFFFF, sat→0xFFFF (0x10000)]
    CHECK_ASSERT(18, simd_padd_sat16(PACK16(0xFFFF, 0x0100),
                                     PACK16(     1, 0xFF00)) == PACK16(0xFFFF, 0xFFFF));

    // padd_sat16: no saturation
    CHECK_ASSERT(19, simd_padd_sat16(PACK16(100,200), PACK16(50,75)) == PACK16(150,275));

    // padd16.acc: rd = sum of both halfword lanes (zero-extended to 32 bits)
    // 1 + 2 = 3
    CHECK_ASSERT(20, simd_padd16_acc(PACK16(1,2)) == 3u);

    // padd16.acc: 0xFFFF + 0x0001 = 0x10000 (result exceeds 16 bits)
    CHECK_ASSERT(21, simd_padd16_acc(PACK16(0xFFFF, 0x0001)) == 0x10000u);

    // padd16.acc: 0x1234 + 0x5678 = 0x68AC
    CHECK_ASSERT(22, simd_padd16_acc(PACK16(0x1234, 0x5678)) == 0x68ACu);

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
