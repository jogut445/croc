#include "simd.h"

// 2x4 * 4x2 uint8 matrix multiply
// A = {1,2,3,4 ; 5,6,7,8}  B = {1,2 ; 3,4 ; 5,6 ; 7,8}
// C = {50,60 ; 114,140}

static void matmul_scalar(const uint8_t A[2][4], const uint8_t B[4][2],
                           uint32_t C[2][2]) {
    for (int i = 0; i < 2; i++)
        for (int j = 0; j < 2; j++) {
            C[i][j] = 0;
            for (int k = 0; k < 4; k++)
                C[i][j] += (uint32_t)A[i][k] * B[k][j];
        }
}

static void matmul_simd(const uint8_t A[2][4], const uint8_t B[4][2],
                        uint32_t C[2][2]) {
    for (int i = 0; i < 2; i++) {
        uint32_t row = PACK8(A[i][3], A[i][2], A[i][1], A[i][0]);
        for (int j = 0; j < 2; j++) {
            uint32_t col = PACK8(B[3][j], B[2][j], B[1][j], B[0][j]);
            C[i][j] = simd_padd8_acc(simd_pmul8(row, col));
        }
    }
}

int main(void) {
    const uint8_t A[2][4] = {{1,2,3,4}, {5,6,7,8}};
    const uint8_t B[4][2] = {{1,2},{3,4},{5,6},{7,8}};
    uint32_t Cs[2][2];
    uint32_t Cv[2][2];

    matmul_scalar(A, B, Cs);
    matmul_simd  (A, B, Cv);

    CHECK_ASSERT(1, Cs[0][0] == 50u  && Cv[0][0] == 50u);
    CHECK_ASSERT(2, Cs[0][1] == 60u  && Cv[0][1] == 60u);
    CHECK_ASSERT(3, Cs[1][0] == 114u && Cv[1][0] == 114u);
    CHECK_ASSERT(4, Cs[1][1] == 140u && Cv[1][1] == 140u);

    return 0;
}
