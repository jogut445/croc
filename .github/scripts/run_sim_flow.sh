#!/bin/bash
# Copyright (c) 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Verilator simulation flow — mirrors the 5-step 'make sim' target.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$CROC_ROOT"

echo "=== [1/5] Building software ==="
make -C sw all

echo ""
echo "=== [2/5] Core configuration — print_config (also compiles verilator model) ==="
cd verilator
./run_verilator.sh --build --run ../sw/bin/test/print_config.hex
"$SCRIPT_DIR/check_sim.sh" croc.log

echo ""
echo "=== [3/5] Running all tests (including helloworld) ==="
pass=0; fail=0
for hex in ../sw/bin/helloworld.hex ../sw/bin/test/*.hex; do
    name=$(basename "$hex" .hex)
    case "$name" in flash_*|test_idma|test_xip|test_gpio) continue ;; esac
    extra=""
    [ "$name" = "test_spi_flash" ] && extra="--flash ../sw/test/spi_hello.hex"
    printf "  %-38s" "$name"
    if ./run_verilator.sh --run "$hex" $extra > "/tmp/vl_${name}.log" 2>&1; then
        echo " PASS"; ((pass++)) || true
    else
        echo " FAIL"
        grep -i "error\|assert\|exception\|FAILED" "/tmp/vl_${name}.log" | sed 's/^/    /' \
            || sed 's/^/    /' "/tmp/vl_${name}.log"
        ((fail++)) || true
    fi
done
echo ""
echo "  Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1

echo ""
echo "=== [4/5] JTAG boot → XiP flash execution (test_xip + spi_xip_payload) ==="
./run_verilator.sh \
    --run   ../sw/bin/test/test_xip.hex \
    --flash ../sw/test/spi_xip_payload.hex

echo ""
echo "=== [5/5] Autonomous flash-boot (all flash programs) ==="
pass=0; fail=0
for hex in ../sw/bin/flash_*.hex ../sw/bin/test/flash_*.hex; do
    [ -f "$hex" ] || continue
    name=$(basename "$hex" .hex)
    case "$name" in flash_test_idma|flash_test_xip|flash_test_gpio) continue ;; esac
    printf "  %-38s" "$name"
    if ./run_verilator.sh --flash-boot "$hex" > "/tmp/vl_${name}.log" 2>&1; then
        echo " PASS"; ((pass++)) || true
    else
        echo " FAIL"
        grep -i "error\|assert\|exception\|FAILED" "/tmp/vl_${name}.log" | sed 's/^/    /' \
            || sed 's/^/    /' "/tmp/vl_${name}.log"
        ((fail++)) || true
    fi
done
echo ""
echo "  Results: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1

cd "$CROC_ROOT"

echo ""
echo "============================================="
echo " Simulation completed"
echo "============================================="
