#include "simd.h"
#include "uart.h"
#include "print.h"
#include "config.h"
#include "obi_timer.h"
#include <stdint.h>

// -----------------------------------------------------------------------------
// Config
// A is N×K, B is K×M, C is N×M  (C = A * B)
// M must be a multiple of 4 for the SIMD strip-mined kernel.
// -----------------------------------------------------------------------------
#define N 8
#define M 8 // must be multiple of 4
#define K 8

static uint8_t A[N * K];
static uint8_t B[K * M];
static uint32_t C_naive[N * M];
static uint32_t C_simd[N * M];

// AXPY arrays: Z = AXPY_ALPHA * X + Y  (N×M matrices)
#define AXPY_ALPHA 3u
static uint8_t X[N * M];
static uint8_t Y[N * M];
static uint8_t Z_naive[N * M];
static uint8_t Z_simd[N * M];

// -----------------------------------------------------------------------------
// Data generation
// Computes v = floor(sqrt(255)) so that v^2 <= 255.
// This ensures each individual simd_pmul8 product fits in 8 bits (no wrap).
// The accumulated sum K*v^2 is stored in uint32_t C, so K is unconstrained.
// -----------------------------------------------------------------------------
static uint8_t gen_max_val(void) {
    uint8_t v = 1;
    while ((uint32_t)(v + 1u) * (uint32_t)(v + 1u) <= 255u) v++;
    return v; // = 15 (15^2=225 <= 255, 16^2=256 > 255)
}

static void gen_data(void) {
    uint8_t v = gen_max_val();
    for (int i = 0; i < N; i++)
        for (int k = 0; k < K; k++) A[i * K + k] = (uint8_t)((i * 3 + k * 7) % v + 1);
    for (int k = 0; k < K; k++)
        for (int j = 0; j < M; j++) B[k * M + j] = (uint8_t)((k * 5 + j * 2) % v + 1);
}

// -----------------------------------------------------------------------------
// AXPY data generation
// Values are bounded so that AXPY_ALPHA * v + v = (AXPY_ALPHA+1) * v <= 255,
// guaranteeing no uint8 overflow in Z[i] = alpha * X[i] + Y[i].
// -----------------------------------------------------------------------------
static uint8_t axpy_max_val(void) {
    return (uint8_t)(255u / (AXPY_ALPHA + 1u));
}

static void gen_axpy_data(void) {
    uint8_t v = axpy_max_val();
    for (int i = 0; i < N * M; i++) {
        X[i] = (uint8_t)((i * 7 + 1) % v + 1);
        Y[i] = (uint8_t)((i * 3 + 5) % v + 1);
    }
}

// -----------------------------------------------------------------------------
// Naive AXPY: Z = alpha * X + Y  (element-wise, flat N*M vector)
// -----------------------------------------------------------------------------
static void axpy_naive(void) {
    for (int i = 0; i < N * M; i++) Z_naive[i] = (uint8_t)(AXPY_ALPHA * (uint32_t)X[i] + (uint32_t)Y[i]);
}

// -----------------------------------------------------------------------------
// SIMD strip-mined AXPY: Z = alpha * X + Y
// Goes through rows of the N×M matrices; processes 4 columns at a time.
// alpha is broadcast into all 4 lanes once; inner body is a single
// pmul8 (alpha*X) + padd8 (+ Y) per 4-element strip.
// Safe in 8-bit lanes because (AXPY_ALPHA+1) * axpy_max_val() <= 255.
// -----------------------------------------------------------------------------
static void axpy_simd(void) {
    const uint32_t av  = PACK8(AXPY_ALPHA, AXPY_ALPHA, AXPY_ALPHA, AXPY_ALPHA);
    // Static arrays are 4-byte aligned; M is a multiple of 4 so every strip
    // base is aligned.  One lw replaces 4×lbu+3×slli+3×or per operand;
    // one sw replaces 4×sb.  2× unrolled to amortize loop overhead (pointer
    // increments, counter, branch) across two strips of useful work.
    const uint32_t *xp = (const uint32_t *)X;
    const uint32_t *yp = (const uint32_t *)Y;
    uint32_t *zp       = (uint32_t *)Z_simd;
    for (int k = 0; k < N * M / 4; k += 2) {
        uint32_t x0 = xp[k], x1 = xp[k + 1];
        uint32_t y0 = yp[k], y1 = yp[k + 1];
        zp[k]     = simd_padd8(simd_pmul8(av, x0), y0);
        zp[k + 1] = simd_padd8(simd_pmul8(av, x1), y1);
    }
}

// -----------------------------------------------------------------------------
// Naive GEMM: C = A * B
// Standard i-j-k triple loop; 32-bit accumulator prevents intermediate overflow.
// -----------------------------------------------------------------------------
static void gemm_naive(void) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < M; j++) {
            uint32_t s = 0;
            for (int k = 0; k < K; k++) s += (uint32_t)A[i * K + k] * (uint32_t)B[k * M + j];
            C_naive[i * M + j] = s;
        }
    }
}

// -----------------------------------------------------------------------------
// SIMD strip-mined GEMM: C = A * B  (AXPY formulation)
// Loop order: i (row of A) → j in steps of 4 (col-strip of B) → k (shared dim).
//
// simd_pmul8 gives 4 exact 8-bit products per cycle (safe because v^2 <= 255).
// Each lane is extracted into its own uint32_t accumulator, so the sum K*v^2
// never overflows regardless of K.  C is stored as uint32_t.
// -----------------------------------------------------------------------------
static void gemm_simd(void) {
    for (int i = 0; i < N; i++) {
        for (int j = 0; j < M; j += 4) {
            uint32_t acc0 = 0, acc1 = 0, acc2 = 0, acc3 = 0;
            for (int k = 0; k < K; k++) {
                uint8_t a     = A[i * K + k];
                uint32_t av   = PACK8(a, a, a, a);
                uint32_t bv   = PACK8(B[k * M + j + 3], B[k * M + j + 2], B[k * M + j + 1], B[k * M + j + 0]);
                uint32_t prod = simd_pmul8(av, bv);
                acc0 += prod & 0xFFu;
                acc1 += (prod >> 8) & 0xFFu;
                acc2 += (prod >> 16) & 0xFFu;
                acc3 += prod >> 24;
            }
            C_simd[i * M + j + 0] = acc0;
            C_simd[i * M + j + 1] = acc1;
            C_simd[i * M + j + 2] = acc2;
            C_simd[i * M + j + 3] = acc3;
        }
    }
}

// -----------------------------------------------------------------------------
// Main: generate data, time both kernels, check correctness, print results.
// -----------------------------------------------------------------------------
int main(void) {
    uart_init();

    gen_data();
    gen_axpy_data();

    // -------------------------
    // Naive GEMM
    // -------------------------
    obi_timer_set_enable(0);
    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    gemm_naive();

    uint32_t cycles_naive = obi_timer_get_count();
    obi_timer_set_enable(0);

    // -------------------------
    // SIMD strip-mined GEMM
    // -------------------------
    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    gemm_simd();

    uint32_t cycles_simd = obi_timer_get_count();
    obi_timer_set_enable(0);

    // -------------------------
    // AXPY naive
    // -------------------------
    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    axpy_naive();

    uint32_t cycles_axpy_naive = obi_timer_get_count();
    obi_timer_set_enable(0);

    // -------------------------
    // AXPY SIMD
    // -------------------------
    obi_timer_set_count(0);
    obi_timer_set_enable(1);

    axpy_simd();

    uint32_t cycles_axpy_simd = obi_timer_get_count();
    obi_timer_set_enable(0);

    // -------------------------
    // Correctness checks
    // -------------------------
    int gemm_ok = 1;
    for (int idx = 0; idx < N * M; idx++) {
        if (C_naive[idx] != C_simd[idx]) {
            gemm_ok = 0;
            break;
        }
    }

    int axpy_ok = 1;
    for (int idx = 0; idx < N * M; idx++) {
        if (Z_naive[idx] != Z_simd[idx]) {
            axpy_ok = 0;
            break;
        }
    }

    // -------------------------
    // Print results
    // -------------------------
    printf("GEMM %dx%dx%d:\n", N, K, M);
    printf("  Naive : %u cycles\n", cycles_naive);
    printf("  SIMD  : %u cycles\n", cycles_simd);
    printf(gemm_ok ? "  Check : PASS\n" : "  Check : FAIL\n");

    printf("AXPY %dx%d  alpha=%u  max_val=%u\n", N, M, AXPY_ALPHA, (unsigned)axpy_max_val());
    printf("  Naive : %u cycles\n", cycles_axpy_naive);
    printf("  SIMD  : %u cycles\n", cycles_axpy_simd);
    printf(axpy_ok ? "  Check : PASS\n" : "  Check : FAIL\n");

    uart_write_flush();
    return 0;
}
