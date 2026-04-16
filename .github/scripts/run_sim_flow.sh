#!/bin/bash
# Copyright (c) 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>
#
# Two-phase Verilator simulation flow:
#   Phase 1 (default): Build software, build Verilator model, run helloworld
#   Phase 2 (iDMA on): Enable iDMA, build Verilator model, run all unit tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CROC_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

cd "$CROC_ROOT"

echo "============================================="
echo "Phase 1: default config — helloworld + SIMD"
echo "============================================="

# ensure default config (iDMA off, SIMD on by default)
"$SCRIPT_DIR/set_croc_config.sh"

# build software (includes test_simd.c automatically via wildcard in sw/Makefile)
make -C sw

# build verilator simulation with SIMD enabled (CoreRV32SIMDEnable=1 by default)
cd verilator
./run_verilator.sh --build
./run_verilator.sh --run ../sw/bin/helloworld.hex
grep -q "\[UART\] Hello World from Croc!" croc.log || exit 1

./run_verilator.sh --run ../sw/bin/test/print_config.hex
"$SCRIPT_DIR/check_sim.sh" croc.log

# run SIMD unit tests with default config (SIMD on, iDMA off)
for TEST in test_simd8 test_simd16 test_simd32 test_simd_matmul; do
    ./run_verilator.sh --run ../sw/bin/test/${TEST}.hex
    grep -q "\[JTAG\] Simulation finished: SUCCESS" croc.log || \
        { echo "SIMD test ${TEST} FAILED"; exit 1; }
    echo "SIMD test ${TEST} passed."
done

cd "$CROC_ROOT"

echo ""
echo "============================================="
echo "Phase 2: iDMA enabled — unit tests"
echo "============================================="

# enable iDMA
"$SCRIPT_DIR/set_croc_config.sh" iDMAEnable=1

# rebuild Verilator model with iDMA enabled
cd verilator
./run_verilator.sh --build

# run all unit tests
"$SCRIPT_DIR/run_tests.sh"
cd "$CROC_ROOT"

# restore defaults
"$SCRIPT_DIR/set_croc_config.sh"

echo ""
echo "============================================="
echo " Simulation completed"
echo "============================================="
