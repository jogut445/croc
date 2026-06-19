// Copyright (c) 2026 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "uart.h"
#include "util.h"
#include "config.h"

// SPI QSPI XiP controller – config registers.
// Sits at UserBaseAddr + 0x1000; addr[13:12]==2'b01 selects this space.
#define SPI_XIP_CFG_BASE  (USER_ROM_BASE_ADDR + 0x1000)
#define SPI_CFG_SCK_PIN   (*reg32(SPI_XIP_CFG_BASE, 0x00))
#define SPI_CFG_CSN_PIN   (*reg32(SPI_XIP_CFG_BASE, 0x04))
#define SPI_CFG_IO0_PIN   (*reg32(SPI_XIP_CFG_BASE, 0x08))
#define SPI_CFG_IO1_PIN   (*reg32(SPI_XIP_CFG_BASE, 0x0C))
#define SPI_CFG_IO2_PIN   (*reg32(SPI_XIP_CFG_BASE, 0x10))
#define SPI_CFG_IO3_PIN   (*reg32(SPI_XIP_CFG_BASE, 0x14))
#define SPI_CFG_CTRL      (*reg32(SPI_XIP_CFG_BASE, 0x18))

// XiP flash window: addr[13:12] != 2'b01, flash byte addr = OBI_addr[23:0].
// UserBaseAddr + 0x2000  =>  flash byte address 0x002000.
#define SPI_XIP_FLASH_BASE  (USER_ROM_BASE_ADDR + 0x2000)

// GPIO pin assignments – must match tb_croc_pkg SpiPin* constants.
#define SPI_PIN_SCK  0
#define SPI_PIN_CSN  1
#define SPI_PIN_IO0  2   // MOSI / quad D0
#define SPI_PIN_IO1  3   // MISO / quad D1
#define SPI_PIN_IO2  4   // WP   / quad D2
#define SPI_PIN_IO3  5   // HOLD / quad D3

int main(void) {
    uart_init();

    // Point each SPI function at a GPIO pin.
    SPI_CFG_SCK_PIN = SPI_PIN_SCK;
    SPI_CFG_CSN_PIN = SPI_PIN_CSN;
    SPI_CFG_IO0_PIN = SPI_PIN_IO0;
    SPI_CFG_IO1_PIN = SPI_PIN_IO1;
    SPI_CFG_IO2_PIN = SPI_PIN_IO2;
    SPI_CFG_IO3_PIN = SPI_PIN_IO3;
    // Route SPI signals onto the configured GPIO pins.
    SPI_CFG_CTRL = 1;
    fence();

    // Read null-terminated string from XiP flash.
    // The first access triggers a flash software-reset (~1000 cycles) then
    // fills a cache line; subsequent accesses in the same line hit the cache.
    const volatile char *msg = (const volatile char *)SPI_XIP_FLASH_BASE;
    uart_write_str("SPI flash says: ", 16);
    while (*msg) {
        putchar(*msg++);
    }
    uart_write_flush();

    return 0;
}
