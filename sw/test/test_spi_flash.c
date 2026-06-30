// Copyright (c) 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "uart.h"
#include "util.h"
#include "config.h"

// SPI config register offsets from SPI_CFG_BASE_ADDR
#define SPI_CFG_SCK_PIN (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x00))
#define SPI_CFG_CSN_PIN (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x04))
#define SPI_CFG_IO0_PIN (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x08))
#define SPI_CFG_IO1_PIN (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x0C))
#define SPI_CFG_IO2_PIN (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x10))
#define SPI_CFG_IO3_PIN (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x14))
// SpiEn: enable register — must be set to 1 when running in JTAG boot mode
#define SPI_CFG_SPI_EN  (*(volatile uint32_t *)(SPI_CFG_BASE_ADDR + 0x18))

int main(void) {
    uart_init();

    // Enable the SPI flash controller (disabled by default in JTAG boot mode).
    SPI_CFG_SPI_EN = 1;

    // First read triggers the flash software-reset sequence (~1000 cycles)
    // then fills a cache line; subsequent reads in the same line hit the cache.
    const volatile char *msg = (const volatile char *)SPI_XIP_BASE_ADDR;
    uart_write_str("SPI flash says: ", 16);
    while (*msg) {
        putchar(*msg++);
    }
    putchar('\n');
    uart_write_flush();

    return 0;
}
