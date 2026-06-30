// Copyright (c) 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// XiP (Execute in Place) smoke test.
//
// The flash payload (spi_xip_payload.hex) places a two-argument add function
// at SPI_XIP_BASE_ADDR (flash byte 0x000000 — the XiP controller subtracts
// the XiP base before issuing the flash address):
//
//   int xip_add(int a, int b) { return a + b; }
//
// This test calls it three times with different arguments, verifying that
// the CPU can fetch and execute instructions from the SPI flash XiP window
// and that argument passing / return values work correctly across the
// SRAM->flash->SRAM call boundary.

#include "uart.h"
#include "print.h"
#include "config.h"

typedef int (*xip_add_t)(int, int);

static void check(int a, int b, int got) {
    int expected = a + b;
    if (got == expected)
        printf("xip_add(%d, %d) = %d  PASS\n", a, b, got);
    else
        printf("xip_add(%d, %d) FAIL (expected %d, got %d)\n", a, b, expected, got);
}

int main(void) {
    uart_init();

    // Enable the SPI flash controller (disabled by default in JTAG boot mode).
    SPI_CFG_SPI_EN = 1;

    xip_add_t xip_add = (xip_add_t)SPI_XIP_BASE_ADDR;

    check(3, 4, xip_add(3, 4));
    check(10, 32, xip_add(10, 32));
    check(100, 23, xip_add(100, 23));

    uart_write_flush();
    return 0;
}
