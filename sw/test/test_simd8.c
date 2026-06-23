#include "simd.h"

int main(void) {
    // padd8
    CHECK_ASSERT(1, simd_padd8(PACK8(1, 2, 3, 4), PACK8(5, 6, 7, 8)) == PACK8(6, 8, 10, 12));
    CHECK_ASSERT(2, simd_padd8(PACK8(0xFF, 0, 0, 0), PACK8(1, 0, 0, 0)) == PACK8(0, 0, 0, 0));

    // psub8
    CHECK_ASSERT(3, simd_psub8(PACK8(10, 11, 12, 16), PACK8(1, 2, 3, 7)) == PACK8(9, 9, 9, 9));
    CHECK_ASSERT(4, simd_psub8(PACK8(1, 0, 0, 0), PACK8(2, 0, 0, 0)) == PACK8(0xFF, 0, 0, 0));

    // pmul8
    CHECK_ASSERT(5, simd_pmul8(PACK8(2, 3, 4, 5), PACK8(3, 4, 5, 6)) == PACK8(6, 12, 20, 30));
    CHECK_ASSERT(6, simd_pmul8(PACK8(16, 1, 1, 1), PACK8(16, 1, 1, 1)) == PACK8(0, 1, 1, 1));

    // padd_sat8
    CHECK_ASSERT(7, simd_padd_sat8(PACK8(255, 128, 16, 1), PACK8(1, 128, 240, 1)) == PACK8(255, 255, 255, 2));
    CHECK_ASSERT(8, simd_padd_sat8(PACK8(10, 20, 30, 40), PACK8(1, 2, 3, 4)) == PACK8(11, 22, 33, 44));

    // psub_sat8
    CHECK_ASSERT(9, simd_psub_sat8(PACK8(5, 10, 0, 255), PACK8(3, 20, 1, 100)) == PACK8(2, 0, 0, 155));
    CHECK_ASSERT(10, simd_psub_sat8(PACK8(10, 20, 30, 40), PACK8(1, 2, 3, 4)) == PACK8(9, 18, 27, 36));

    // padd8.acc
    CHECK_ASSERT(11, simd_padd8_acc(PACK8(1, 2, 3, 4)) == 10u);
    CHECK_ASSERT(12, simd_padd8_acc(PACK8(0x10, 0x20, 0x30, 0x40)) == 0xA0u);
    CHECK_ASSERT(13, simd_padd8_acc(PACK8(0xFF, 0xFF, 0xFF, 0xFF)) == 0x3FCu);

    // popcount8
    CHECK_ASSERT(14, simd_popcount8(PACK8(0xFF, 0xAA, 0x0F, 0x00)) == PACK8(8, 4, 4, 0));
    CHECK_ASSERT(15, simd_popcount8(PACK8(0x01, 0x03, 0x07, 0x0F)) == PACK8(1, 2, 3, 4));

    // psll8
    CHECK_ASSERT(16, simd_psll8(PACK8(0x01, 0x02, 0x04, 0x08), 2u) == PACK8(0x04, 0x08, 0x10, 0x20));
    CHECK_ASSERT(17, simd_psll8(PACK8(0xAB, 0xCD, 0xEF, 0x12), 0u) == PACK8(0xAB, 0xCD, 0xEF, 0x12));

    // psrl8
    CHECK_ASSERT(18, simd_psrl8(PACK8(0x80, 0x40, 0x20, 0x10), 2u) == PACK8(0x20, 0x10, 0x08, 0x04));
    CHECK_ASSERT(19, simd_psrl8(PACK8(0xFF, 0xFF, 0xFF, 0xFF), 4u) == PACK8(0x0F, 0x0F, 0x0F, 0x0F));

    // prol8
    CHECK_ASSERT(20, simd_prol8(PACK8(0x80, 0xFF, 0x0F, 0xAA), 1u) == PACK8(0x01, 0xFF, 0x1E, 0x55));
    CHECK_ASSERT(21, simd_prol8(PACK8(0xDE, 0xAD, 0xBE, 0xEF), 0u) == PACK8(0xDE, 0xAD, 0xBE, 0xEF));

    return 0;
}
