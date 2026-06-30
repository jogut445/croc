// Copyright (c) 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0/
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>

#include "uart.h"
#include "print.h"
#include "util.h"
#include "config.h"

int main() {

    // setup the UART peripheral
    uart_init();

    printf("Reading ROM until null terminator:\n");
    for (int i = 0; ; i++) {
        uint8_t word = *reg32(USER_ROM_BASE_ADDR, i * 4);
        if (word == 0) break;
        printf("%c", word);
    }
    printf("\n");

    // wait until uart has finished sending
    uart_write_flush();

    return 0;
}
