// Copyright (c) 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "uart.h"
#include "util.h"
#include "config.h"

// XiP flash window in the user domain.
// OBI address 0x20002000 -> HADDR[23:0] = 0x002000 -> flash byte 0x002000.
// Load flash content at @002000 in the hex file (see sw/test/spi_hello.hex).
// GPIO pins for SPI are fixed at compile time in spi_qspi_obi_wrap — no
// software configuration is needed.
#define SPI_XIP_FLASH_BASE  (USER_ROM_BASE_ADDR + 0x2000)

int main(void) {
    uart_init();

    // The first read triggers the flash software-reset sequence (~1000 cycles)
    // then fills a cache line; subsequent reads in the same line hit the cache.
    const volatile char *msg = (const volatile char *)SPI_XIP_FLASH_BASE;
    uart_write_str("SPI flash says: ", 16);
    while (*msg) {
        putchar(*msg++);
    }
    uart_write_flush();

    return 0;
}
