#include "simd.h"
#include "uart.h"
#include "print.h"
#include "config.h"
#include "obi_timer.h"

// -----------------------------------------------------------------------------
// Config
// -----------------------------------------------------------------------------
#define N 4

uint8_t A[N][N] = {
    {1, 2, 3, 4},
    {2, 3, 4, 1},
    {3, 4, 1, 2},
    {4, 1, 2, 3}
};

uint8_t B[N][N] = {
    {1, 1, 1, 1},
    {2, 2, 2, 2},
    {3, 3, 3, 3},
    {4, 4, 4, 4}
};

uint8_t C_naive[N][N];
uint8_t C_simd[N][N];

uint8_t D_naive[N][N];
uint8_t D_simd[N][N];

// -----------------------------------------------------------------------------
// Naive matrix addition
// -----------------------------------------------------------------------------
void mat_add_naive() {
    for (int i = 0; i < N; i++)
        for (int j = 0; j < N; j++) C_naive[i][j] = A[i][j] + B[i][j];
}

// -----------------------------------------------------------------------------
// SIMD matrix addition (row-wise, 4 elements at once)
// -----------------------------------------------------------------------------
void mat_add_simd() {
    for (int i = 0; i < N; i++) {
        uint32_t a   = PACK8(A[i][3], A[i][2], A[i][1], A[i][0]);
        uint32_t b   = PACK8(B[i][3], B[i][2], B[i][1], B[i][0]);

        uint32_t r   = simd_padd8(a, b);

        // unpack
        C_simd[i][0] = (r >> 0) & 0xFF;
        C_simd[i][1] = (r >> 8) & 0xFF;
        C_simd[i][2] = (r >> 16) & 0xFF;
        C_simd[i][3] = (r >> 24) & 0xFF;
    }
}

// -----------------------------------------------------------------------------
// Naive matrix multiplication
// -----------------------------------------------------------------------------
void mat_mul_naive() {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {
            uint16_t sum = 0;
            for (int k = 0; k < N; k++) {
                sum += A[i][k] * B[k][j];
            }
            D_naive[i][j] = (uint8_t)sum; // safe due to small values
        }
    }
}

// -----------------------------------------------------------------------------
// SIMD matrix multiplication
// Each dot product done with:
//   pmul8 + horizontal accumulate
// -----------------------------------------------------------------------------
void mat_mul_simd() {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < N; j++) {

            uint32_t row = PACK8(A[i][3], A[i][2], A[i][1], A[i][0]);
            uint32_t col = PACK8(B[3][j], B[2][j], B[1][j], B[0][j]);

            uint32_t mul = simd_pmul8(row, col);
            uint32_t sum = simd_padd8_acc(mul);

            D_simd[i][j] = (uint8_t)sum;
        }
    }
}

// -----------------------------------------------------------------------------
// Main with timing
// -----------------------------------------------------------------------------
int main() {

    uart_init();

    // -------------------------
    // Matrix Addition
    // -------------------------
    obi_timer_set_enable(0);
    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    mat_add_naive();

    uint32_t cycles_naive_add = obi_timer_get_count();
    obi_timer_set_enable(0);

    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    mat_add_simd();

    uint32_t cycles_simd_add = obi_timer_get_count();
    obi_timer_set_enable(0);

    // -------------------------
    // Matrix Multiplication
    // -------------------------
    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    mat_mul_naive();

    uint32_t cycles_naive_mul = obi_timer_get_count();
    obi_timer_set_enable(0);

    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    mat_mul_simd();

    uint32_t cycles_simd_mul = obi_timer_get_count();
    obi_timer_set_enable(0);

    // -------------------------
    // Print results
    // -------------------------
    printf("Matrix Add (cycles):\n");
    printf("  Naive: %u\n", cycles_naive_add);
    printf("  SIMD : %u\n", cycles_simd_add);

    printf("Matrix Mul (cycles):\n");
    printf("  Naive: %u\n", cycles_naive_mul);
    printf("  SIMD : %u\n", cycles_simd_mul);

    uart_write_flush();

    return 0;
}
