#!/bin/bash
# Copyright (c) 2026 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Thomas Benz     <tbenz@iis.ee.ethz.ch>

set -e  # Exit on error
set -u  # Error on undefined vars


################
# Setup
################
# Source environment
source "../env.sh"


################
# Helpers
################

show_help() {
    cat << EOF
Verilator Coordinator

Usage:
    ./run_verilator.sh [OPTIONS]

Options:
    --help, -h          Show this help message
    --dry-run, -n       Only print commands instead of executing
    --verbose, -v       Print commands while executing
    --flist             Regenerate flist (croc.f)
    --build             Build croc_soc Verilator binary
    --run BINARY        Run binary in Verilator
    --flash HEX         Load HEX file into SPI flash memory
    --flash-test        Run SPI XiP flash test after loading (uses built-in pattern if no --flash)

Example:
    # Build and run RTL simulation with given binary
    ./run_verilator.sh --build --run ../sw/bin/helloworld.hex

    # Run with SPI flash content loaded from a hex file
    ./run_verilator.sh --run ../sw/bin/helloworld.hex --flash my_flash.hex

    # Run the SPI flash test with the built-in test pattern (no hex file needed)
    ./run_verilator.sh --run ../sw/bin/helloworld.hex --flash-test

EOF
    exit 0
}


run_cmd() {
    if [ "$DRYRUN" = 1 ]; then
        echo $1
    else
        eval $1
    fi
}


build_verilator() {
    run_cmd "echo [INFO][Verilator] Build Verilator"
    run_cmd "verilator \
        -Wno-fatal \
        -Wno-style \
        -Wno-BLKANDNBLK \
        -Wno-WIDTHEXPAND \
        -Wno-WIDTHTRUNC \
        -Wno-WIDTHCONCAT \
        -Wno-ASCRANGE \
        -Wno-TIMESCALEMOD \
        -Wno-SPECIFYIGN \
        -Wno-RISEFALLDLY \
        --binary \
        -j 0 \
        --timing \
        --autoflush \
        --trace-fst \
        --trace-threads 2 \
        --trace-structs \
        --unroll-count 1 \
        --unroll-stmts 1 \
        --x-assign fast \
        --x-initial fast \
        -O3 \
        --top tb_croc_soc \
        -f croc.f 2>&1 | \
        tee ${PROJ_NAME}_build.log"
}


generate_flist() {
    run_cmd "echo [INFO][Bender] Generate croc.f"
    run_cmd "bender \
        script flist-plus \
        -t rtl \
        -t verilator \
        -t synthesis \
        -D VERILATOR=1 \
        -D COMMON_CELLS_ASSERTS_OFF=1 \
        > croc.f"

    run_cmd "echo [INFO][Bender] Remove absolute paths"
    run_cmd "sed -i 's|${CROC_ROOT}|..|g' croc.f"

    run_cmd "echo [INFO][Bender] File list generated: croc.f"
}

run_binary() {
    local binary=$1
    local extra_args=""
    [ -n "$FLASH_HEX" ]  && extra_args="$extra_args +flash=$FLASH_HEX"
    [ "$FLASH_TEST" = 1 ] && extra_args="$extra_args +flash_test"
    run_cmd "echo [INFO][Verilator] Running $binary"
    run_cmd "obj_dir/Vtb_croc_soc +binary=\"$binary\" $extra_args | tee ${PROJ_NAME}.log"
}


####################
# Parse Arguments
####################

DRYRUN=0
FLASH_HEX=""
FLASH_TEST=0
RUN_BINARY=""
DO_BUILD=0
DO_FLIST=0

# default action if no argument is given
if [ $# -eq 0 ]; then
    show_help
    return 0
fi

# check for global arguments
for arg in "$@"; do
    [[ "$arg" == -v || "$arg" == --verbose ]] && set -x
    [[ "$arg" == -n || "$arg" == --dry-run ]] && DRYRUN=1
done

# parse arguments — collect all flags before executing
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h)
            show_help
            ;;
        --verbose|-v)
            shift
            ;;
        --dry-run|-n)
            shift
            ;;
        --flist)
            DO_FLIST=1
            shift
            ;;
        --build)
            DO_BUILD=1
            shift
            ;;
        --run)
            RUN_BINARY=$2
            shift 2
            ;;
        --flash)
            FLASH_HEX=$2
            shift 2
            ;;
        --flash-test)
            FLASH_TEST=1
            shift
            ;;
        # Error handling
        *)
            echo "[ERROR] Unknown option: $1 (use --help for usage)" >&2
            exit 1
            ;;
    esac
done

# execute in logical order: flist → build → run
[ "$DO_FLIST"  = 1 ] && generate_flist
[ "$DO_BUILD"  = 1 ] && build_verilator
[ -n "$RUN_BINARY" ] && run_binary "$RUN_BINARY"
