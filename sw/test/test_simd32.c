#include "simd.h"

int main(void) {
    // padd_sat32
    CHECK_ASSERT(1, simd_padd_sat32(0xFFFFFFFEu, 2u) == 0xFFFFFFFFu);
    CHECK_ASSERT(2, simd_padd_sat32(0xFFFFFFFEu, 1u) == 0xFFFFFFFFu);
    CHECK_ASSERT(3, simd_padd_sat32(100u, 200u) == 300u);

    // psub_sat32
    CHECK_ASSERT(4, simd_psub_sat32(100u, 200u) == 0u);
    CHECK_ASSERT(5, simd_psub_sat32(300u, 100u) == 200u);
    CHECK_ASSERT(6, simd_psub_sat32(0u, 1u) == 0u);

    // popcount32
    CHECK_ASSERT(7, simd_popcount32(0xFFFFFFFFu) == 32u);
    CHECK_ASSERT(8, simd_popcount32(0xAAAAAAAAu) == 16u);
    CHECK_ASSERT(9, simd_popcount32(0u) == 0u);

    // prol32
    CHECK_ASSERT(10, simd_prol32(0x80000001u, 1u) == 0x00000003u);
    CHECK_ASSERT(11, simd_prol32(0x12345678u, 8u) == 0x34567812u);
    CHECK_ASSERT(12, simd_prol32(0xABCDEF01u, 0u) == 0xABCDEF01u);

    // combined: dot-product using pmul8 + padd8_acc
    // [1,2,3,4] · [5,6,7,8] = 5+12+21+32 = 70
    CHECK_ASSERT(13, simd_padd8_acc(simd_pmul8(PACK8(1, 2, 3, 4), PACK8(5, 6, 7, 8))) == 70u);

    // combined: pperm8 then padd8_acc (sum is order-independent)
    CHECK_ASSERT(14, simd_padd8_acc(simd_pperm8(PACK8(1, 2, 3, 4))) == 10u);

    // combined: psll8 then psub_sat8 (shift-then-saturate)
    // PACK8(1,2,3,4) << 4 = PACK8(0x10,0x20,0x30,0x40)
    // saturating sub PACK8(0xFF,0,0,0): [0x10-0xFF→0, 0x20-0, 0x30-0, 0x40-0]
    CHECK_ASSERT(15,
                 simd_psub_sat8(simd_psll8(PACK8(1, 2, 3, 4), 4u), PACK8(0xFF, 0, 0, 0)) == PACK8(0, 0x20, 0x30, 0x40));

    return 0;
}
