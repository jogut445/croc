#include "simd.h"

int main(void) {
    // padd16
    CHECK_ASSERT(1, simd_padd16(PACK16(1, 2), PACK16(3, 4)) == PACK16(4, 6));
    CHECK_ASSERT(2, simd_padd16(PACK16(0xFFFF, 0), PACK16(1, 0)) == PACK16(0, 0));

    // psub16
    CHECK_ASSERT(3, simd_psub16(PACK16(10, 11), PACK16(5, 3)) == PACK16(5, 8));
    CHECK_ASSERT(4, simd_psub16(PACK16(1, 0), PACK16(2, 0)) == PACK16(0xFFFF, 0));

    // pmul16
    CHECK_ASSERT(5, simd_pmul16(PACK16(2, 3), PACK16(4, 5)) == PACK16(8, 15));
    CHECK_ASSERT(6, simd_pmul16(PACK16(0x0100, 1), PACK16(0x0100, 1)) == PACK16(0, 1));

    // padd_sat16
    CHECK_ASSERT(7, simd_padd_sat16(PACK16(0xFFFF, 0x0100), PACK16(1, 0xFF00)) == PACK16(0xFFFF, 0xFFFF));
    CHECK_ASSERT(8, simd_padd_sat16(PACK16(100, 200), PACK16(50, 75)) == PACK16(150, 275));

    // psub_sat16
    CHECK_ASSERT(9, simd_psub_sat16(PACK16(1000, 0), PACK16(500, 500)) == PACK16(500, 0));
    CHECK_ASSERT(10, simd_psub_sat16(PACK16(0xFFFF, 100), PACK16(0x1000, 50)) == PACK16(0xEFFF, 50));

    // padd16.acc
    CHECK_ASSERT(11, simd_padd16_acc(PACK16(1, 2)) == 3u);
    CHECK_ASSERT(12, simd_padd16_acc(PACK16(0xFFFF, 0x0001)) == 0x10000u);
    CHECK_ASSERT(13, simd_padd16_acc(PACK16(0x1234, 0x5678)) == 0x68ACu);

    // pperm16: swap halfwords
    CHECK_ASSERT(14, simd_pperm16(PACK16(0x1234, 0x5678)) == PACK16(0x5678, 0x1234));
    CHECK_ASSERT(15, simd_pperm16(simd_pperm16(PACK16(0xABCD, 0xEF01))) == PACK16(0xABCD, 0xEF01));

    // popcount16
    CHECK_ASSERT(16, simd_popcount16(PACK16(0xFFFF, 0x0000)) == PACK16(16, 0));
    CHECK_ASSERT(17, simd_popcount16(PACK16(0xAAAA, 0x5555)) == PACK16(8, 8));

    // psll16
    CHECK_ASSERT(18, simd_psll16(PACK16(0x0001, 0x0080), 4u) == PACK16(0x0010, 0x0800));
    CHECK_ASSERT(19, simd_psll16(PACK16(0x1234, 0x5678), 0u) == PACK16(0x1234, 0x5678));

    // psrl16
    CHECK_ASSERT(20, simd_psrl16(PACK16(0x8000, 0x4000), 4u) == PACK16(0x0800, 0x0400));
    CHECK_ASSERT(21, simd_psrl16(PACK16(0xFFFF, 0xFFFF), 8u) == PACK16(0x00FF, 0x00FF));

    // prol16
    CHECK_ASSERT(22, simd_prol16(PACK16(0x0001, 0x8000), 1u) == PACK16(0x0002, 0x0001));
    CHECK_ASSERT(23, simd_prol16(PACK16(0x1234, 0xF0F0), 4u) == PACK16(0x2341, 0x0F0F));

    return 0;
}
