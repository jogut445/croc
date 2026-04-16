// Copyright 2024 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// Philippe Sauter <phsauter@iis.ee.ethz.ch>

#include "print.h"
#include "util.h"
#include "config.h"

const char hex_symbols[16] = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F'};

/// @brief format number as hexadecimal digits
/// @return number of characters written to buffer
uint8_t format_hex32(char *buffer, uint32_t num) {
    uint8_t idx = 0;
    if (num == 0) {
        buffer[0] = hex_symbols[0];
        return 1;
    }

    while (num > 0) {
        buffer[idx++] = hex_symbols[num & 0xF];
        num >>= 4;
    }
    return idx;
}

/// @brief format unsigned 32-bit integer as decimal digits (LSB first)
/// @return number of characters written to buffer
uint8_t format_uint32_dec(char *buffer, uint32_t num) {
    uint8_t idx = 0;
    if (num == 0) {
        buffer[idx++] = '0';
        return idx;
    }
    while (num > 0) {
        buffer[idx++] = '0' + (num % 10);
        num /= 10;
    }
    return idx;
}

void printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    char buffer[12]; // holds string while assembling
    uint8_t idx;

    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            if (*fmt == 'x') { // hexadecimal
                idx = format_hex32(buffer, va_arg(args, unsigned int));
                // print from buffer (reverse order)
                for (int j = idx - 1; j >= 0; j--) {
                    putchar(buffer[j]);
                }
            } else if (*fmt == 'u') { // unsigned decimal
                idx = format_uint32_dec(buffer, va_arg(args, unsigned int));
                for (int j = idx - 1; j >= 0; j--) {
                    putchar(buffer[j]);
                }
            } else if (*fmt == 'd') { // signed decimal
                int val = va_arg(args, int);
                if (val < 0) {
                    putchar('-');
                    // Convert to unsigned to handle INT32_MIN correctly
                    idx = format_uint32_dec(buffer, (unsigned int)(-val));
                } else {
                    idx = format_uint32_dec(buffer, (unsigned int)val);
                }
                for (int j = idx - 1; j >= 0; j--) {
                    putchar(buffer[j]);
                }
            }
            // Unknown specifiers are ignored (the '%' and the character are skipped)
        } else {
            putchar(*fmt);
        }
        fmt++;
    }

    va_end(args);
}
