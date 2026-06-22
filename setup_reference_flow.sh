#!/usr/bin/env bash
# setup_reference_flow.sh
#
# One-shot setup script — run once after cloning the croc repo on an ETH VLSI2
# machine.  It:
#   1.  Installs the ETH reference flow into croc/reference_flow/
#   2.  Ports all your custom changes (SIMD extension, user ROM, XiP SPI flash,
#       flash-boot bootrom, software, chip layout) into the reference flow
#   3.  Regenerates the technology files via icdesign
#
# After it finishes, cd into reference_flow/ and run the backend:
#   cd reference_flow && make nonfree
#
# The script is idempotent — safe to re-run after updating your RTL.

set -euo pipefail

INSTALL_SH="/home/vlsi2/reference_flow/install.sh"
CROC="$(cd "$(dirname "$0")" && pwd)"
REF="$CROC/reference_flow"

die()         { echo "ERROR: $*" >&2; exit 1; }

patch_file() {
    # Replace OLD with NEW in FILE; no-op if NEW already present.
    # Uses -- to guard against patterns that start with '-'.
    local file="$1" old="$2" new="$3"
    if grep -qF -- "$new" "$file"; then
        return 0
    fi
    grep -qF -- "$old" "$file" || die "Pattern not found in $file:\n  $old"
    sed -i "s|${old}|${new}|g" "$file"
}

insert_before() {
    # Insert NEW_LINE immediately before BEFORE_LINE in FILE; no-op if present.
    local file="$1" new_line="$2" before="$3"
    if ! grep -qF "$new_line" "$file"; then
        sed -i "s|${before}|${new_line}\n${before}|" "$file"
    fi
}

step() { echo ""; echo "[$1] $2"; }

# ----------------------------------------------------------------
# 0. Pre-flight checks
# ----------------------------------------------------------------
[ -f "$INSTALL_SH" ] || die "ETH install script not found: $INSTALL_SH\n       Are you on an ETH VLSI2 machine?"
command -v icdesign >/dev/null 2>&1 || die "'icdesign' not in PATH. Source your ETH environment first."

echo "========================================================"
echo " croc/setup_reference_flow.sh"
echo " CROC root : $CROC"
echo " Target    : $REF"
echo "========================================================"

# ----------------------------------------------------------------
# 1. Install reference flow (skipped if already present)
# ----------------------------------------------------------------
step "1/15" "Installing ETH reference flow..."
if [ -d "$REF" ]; then
    echo "  reference_flow/ already exists — skipping install"
else
    (cd "$CROC" && "$INSTALL_SH")
    [ -d "$REF" ] || die "install.sh ran but reference_flow/ was not created"
    echo "  installed reference_flow/"
fi

# ----------------------------------------------------------------
# 2. SIMD extension — all modified cve2 files (tech-independent)
# ----------------------------------------------------------------
step "2/15" "Copying SIMD extension (rtl/cve2/)..."
for f in cve2_pkg.sv cve2_alu.sv cve2_core.sv cve2_core_tracing.sv \
          cve2_decoder.sv cve2_ex_block.sv cve2_id_stage.sv; do
    [ -f "$CROC/rtl/cve2/$f" ] || die "Missing: $CROC/rtl/cve2/$f"
    cp "$CROC/rtl/cve2/$f" "$REF/rtl/cve2/$f"
    echo "  rtl/cve2/$f"
done

# ----------------------------------------------------------------
# 3. User domain — ROM module, package, instantiation
# ----------------------------------------------------------------
step "3/15" "Copying user domain RTL..."
cp "$CROC/rtl/user_domain/user_rom.sv" "$REF/rtl/user_domain/user_rom.sv"
echo "  rtl/user_domain/user_rom.sv"
cp "$CROC/rtl/user_pkg.sv"    "$REF/rtl/user_pkg.sv"
echo "  rtl/user_pkg.sv"
cp "$CROC/rtl/user_domain.sv" "$REF/rtl/user_domain.sv"
echo "  rtl/user_domain.sv"

# ----------------------------------------------------------------
# 4. XiP SPI flash controller (EF_QSPI + OBI wrapper)
#    ef_qspi_xip_ctrl/ contains synthesisable Verilog only;
#    sst26wf080b.v is a simulation model (not needed for synthesis).
# ----------------------------------------------------------------
step "4/15" "Copying XiP SPI controller..."
mkdir -p "$REF/rtl/user_domain/ef_qspi_xip_ctrl"
for f in DMC.v EF_QSPI_XIP_CTRL.v EF_QSPI_XIP_CTRL_AHBL.v; do
    cp "$CROC/rtl/user_domain/ef_qspi_xip_ctrl/$f" \
       "$REF/rtl/user_domain/ef_qspi_xip_ctrl/$f"
    echo "  rtl/user_domain/ef_qspi_xip_ctrl/$f"
done
cp "$CROC/rtl/user_domain/spi_qspi_obi_wrap.sv" \
   "$REF/rtl/user_domain/spi_qspi_obi_wrap.sv"
echo "  rtl/user_domain/spi_qspi_obi_wrap.sv"

# ----------------------------------------------------------------
# 5. Boot-from-flash RTL
#    croc_soc, croc_domain, soc_ctrl_regs: carry boot_sel_i port.
#    bootrom: 30-word table with BOOTMODE check + _flash_boot path.
#    croc_chip: NOT copied (sg13cmos5l pad cell names in ref flow differ
#    from sg13g2 names here).  Instead, patch GPIO[8] to be input-only.
# ----------------------------------------------------------------
step "5/15" "Copying boot-from-flash RTL..."
cp "$CROC/rtl/croc_soc.sv"    "$REF/rtl/croc_soc.sv"
echo "  rtl/croc_soc.sv      (boot_sel_i wired to gpio_i[8])"
cp "$CROC/rtl/croc_domain.sv" "$REF/rtl/croc_domain.sv"
echo "  rtl/croc_domain.sv   (boot_sel_i port added)"
cp "$CROC/rtl/soc_ctrl/soc_ctrl_regs.sv" "$REF/rtl/soc_ctrl/soc_ctrl_regs.sv"
echo "  rtl/soc_ctrl/soc_ctrl_regs.sv  (boot_sel_i + FF reset from GPIO)"
cp "$CROC/rtl/bootrom/bootrom.sv" "$REF/rtl/bootrom/bootrom.sv"
echo "  rtl/bootrom/bootrom.sv  (30-word table: BOOTMODE check + _flash_boot)"
cp "$CROC/rtl/bootrom/bootrom.S"  "$REF/rtl/bootrom/bootrom.S"
echo "  rtl/bootrom/bootrom.S   (source reference)"

# Patch reference flow's croc_chip.sv: make GPIO[8] permanently input-only.
# The ref flow uses sg13cmos5l cell names; the pad module name may differ but
# the port interface is the same.  We change the c2p_en of the GPIO[8] pad
# from the driven signal to 1'b0.
CHIP_SV="$REF/rtl/croc_chip.sv"
if grep -q "boot_sel\|c2p_en(1'b0).*gpio8\|gpio8.*c2p_en(1'b0)" "$CHIP_SV" 2>/dev/null; then
    echo "  rtl/croc_chip.sv     GPIO[8] input-only already patched"
elif grep -q "pad_gpio8_io\|gpio\[8\]\|gpio_io\[8\]" "$CHIP_SV" 2>/dev/null; then
    # Replace the c2p_en output-enable of the GPIO[8] pad with a constant 0.
    # Works for both sg13g2 and sg13cmos5l pad cell instantiations.
    sed -i '/pad_gpio8_io\|gpio_io\[8\]/s/\.c2p_en([^)]*)/\.c2p_en(1'\''b0)/' "$CHIP_SV"
    echo "  rtl/croc_chip.sv     patched GPIO[8] c2p_en → 1'b0 (boot_sel, input-only)"
else
    echo "  WARNING: could not auto-patch croc_chip.sv for GPIO[8] input-only."
    echo "           Manually set GPIO[8] pad's c2p_en to 1'b0 in:"
    echo "           $CHIP_SV"
fi

# ----------------------------------------------------------------
# 6. Core configuration — SIMD enable, RV32M/B, SramBankNumWords=1024
#    NOT copied: croc_chip.sv (pad cell names are sg13cmos5l-specific)
#    NOT copied: tc_sram_impl.sv (reference_flow already has gen_1024x32xBx1
#                which maps 1024x32 onto the 512x64 physical macro)
# ----------------------------------------------------------------
step "6/15" "Copying core configuration RTL..."
cp "$CROC/rtl/core_wrap.sv" "$REF/rtl/core_wrap.sv"
echo "  rtl/core_wrap.sv  (RV32M, RV32B, RV32SIMD enabled)"
cp "$CROC/rtl/croc_pkg.sv"  "$REF/rtl/croc_pkg.sv"
echo "  rtl/croc_pkg.sv   (SramBankNumWords=1024, CoreRV32SIMDEnable=1)"

# ----------------------------------------------------------------
# 7. Software — SIMD intrinsics, extended print, test programs,
#               flash linker script + startup, updated Makefile
# ----------------------------------------------------------------
step "7/15" "Copying software..."
cp "$CROC/sw/config.h"        "$REF/sw/config.h"
echo "  sw/config.h"
cp "$CROC/sw/lib/inc/simd.h"  "$REF/sw/lib/inc/simd.h"
echo "  sw/lib/inc/simd.h"
cp "$CROC/sw/lib/src/print.c" "$REF/sw/lib/src/print.c"
echo "  sw/lib/src/print.c"
for f in "$CROC"/sw/test/*.c "$CROC"/sw/test/*.hex; do
    cp "$f" "$REF/sw/test/$(basename "$f")"
    echo "  sw/test/$(basename "$f")"
done
cp "$CROC/sw/link_flash.ld" "$REF/sw/link_flash.ld"
echo "  sw/link_flash.ld  (XiP flash linker script: VMA=0x2000_2000, LMA=0x0000_2000)"
cp "$CROC/sw/crt0_flash.S"  "$REF/sw/crt0_flash.S"
echo "  sw/crt0_flash.S   (flash startup: sp/gp setup, .data copy, .bss zero, CORESTATUS)"
cp "$CROC/sw/Makefile"      "$REF/sw/Makefile"
echo "  sw/Makefile       (adds flash_* hex targets for every program)"

# ----------------------------------------------------------------
# 8. Simulation model (verilator only — not for synthesis)
# ----------------------------------------------------------------
step "8/15" "Copying simulation flash model..."
cp "$CROC/rtl/test/spiflash.v" "$REF/rtl/test/spiflash.v"
echo "  rtl/test/spiflash.v  (PicoSoC QSPI model, verilator-compatible)"

# ----------------------------------------------------------------
# 9. Testbench updates
# ----------------------------------------------------------------
step "9/15" "Copying testbench updates..."
cp "$CROC/rtl/test/tb_croc_pkg.sv" "$REF/rtl/test/tb_croc_pkg.sv"
echo "  rtl/test/tb_croc_pkg.sv  (BootSelPin, SpiXipFlashBase constants)"
cp "$CROC/rtl/test/tb_croc_soc.sv" "$REF/rtl/test/tb_croc_soc.sv"
echo "  rtl/test/tb_croc_soc.sv  (flash model wiring, flash_boot_mode, GPIO[8])"

# ----------------------------------------------------------------
# 10. Run scripts (vsim + verilator)
# ----------------------------------------------------------------
step "10/15" "Copying simulation run scripts..."
cp "$CROC/vsim/run_vsim.sh"           "$REF/vsim/run_vsim.sh"
echo "  vsim/run_vsim.sh        (--flash-boot mode)"
cp "$CROC/verilator/run_verilator.sh" "$REF/verilator/run_verilator.sh"
echo "  verilator/run_verilator.sh  (--flash-boot mode)"

# ----------------------------------------------------------------
# 11. Filelists — yosys (synthesis) and verilator (simulation)
#
#     New RTL added before user_domain.sv:
#       ef_qspi_xip_ctrl/{DMC,EF_QSPI_XIP_CTRL,EF_QSPI_XIP_CTRL_AHBL}.v
#       user_rom.sv  (already inserted in prior runs — no-op if present)
#       spi_qspi_obi_wrap.sv
#
#     Verilator only (simulation model):
#       spiflash.v   (inserted before tb_croc_soc.sv)
# ----------------------------------------------------------------
step "11/15" "Patching filelists (yosys + verilator)..."

# Insert in reverse order — each line uses the previously inserted line as its
# anchor, so only ../rtl/user_domain.sv (always present in the ref flow) is
# ever used as the initial anchor.  All insert_before calls are idempotent.
#
# Final order in flist:
#   ef_qspi_xip_ctrl/DMC.v
#   ef_qspi_xip_ctrl/EF_QSPI_XIP_CTRL.v
#   ef_qspi_xip_ctrl/EF_QSPI_XIP_CTRL_AHBL.v
#   user_rom.sv
#   spi_qspi_obi_wrap.sv
#   user_domain.sv   ← original anchor
for FLIST in "$REF/yosys/src/croc.flist" "$REF/verilator/croc.f"; do
    insert_before "$FLIST" \
        "../rtl/user_domain/spi_qspi_obi_wrap.sv" \
        "../rtl/user_domain.sv"
    insert_before "$FLIST" \
        "../rtl/user_domain/user_rom.sv" \
        "../rtl/user_domain/spi_qspi_obi_wrap.sv"
    insert_before "$FLIST" \
        "../rtl/user_domain/ef_qspi_xip_ctrl/EF_QSPI_XIP_CTRL_AHBL.v" \
        "../rtl/user_domain/user_rom.sv"
    insert_before "$FLIST" \
        "../rtl/user_domain/ef_qspi_xip_ctrl/EF_QSPI_XIP_CTRL.v" \
        "../rtl/user_domain/ef_qspi_xip_ctrl/EF_QSPI_XIP_CTRL_AHBL.v"
    insert_before "$FLIST" \
        "../rtl/user_domain/ef_qspi_xip_ctrl/DMC.v" \
        "../rtl/user_domain/ef_qspi_xip_ctrl/EF_QSPI_XIP_CTRL.v"
    echo "  patched $(basename "$(dirname "$FLIST")")/$(basename "$FLIST")"
done

# spiflash.v is sim-only: add to verilator flist only
VL_FLIST="$REF/verilator/croc.f"
insert_before "$VL_FLIST" \
    "../rtl/test/spiflash.v" \
    "../rtl/test/tb_croc_soc.sv"
echo "  patched verilator/croc.f  (spiflash.v, sim-only)"

# ----------------------------------------------------------------
# 12. Pad ring — CSV pad placement from croc, site name fixed for CMOS5L
#    bondpad_centroids.csv encodes pad positions for the 2416 um chip.
#    padring.tcl: sg13g2_ioSite -> sg13cmos5l_ioSite (only name differs).
# ----------------------------------------------------------------
step "12/15" "Porting pad ring layout..."
cp "$CROC/openroad/src/bondpad_centroids.csv" "$REF/openroad/src/bondpad_centroids.csv"
echo "  copied openroad/src/bondpad_centroids.csv"
cp "$CROC/openroad/src/padring.tcl" "$REF/openroad/src/padring.tcl"
sed -i 's/sg13g2_ioSite/sg13cmos5l_ioSite/g' "$REF/openroad/src/padring.tcl"
echo "  copied openroad/src/padring.tcl  (sg13g2_ioSite -> sg13cmos5l_ioSite)"

# ----------------------------------------------------------------
# 13. Floorplan — larger chip (2416 um), 512x64 macro (for 1024x32 via
#    bit-interleaving), SRAM banks split top-center / bottom-center
#    to open routing channels on both sides instead of a side-by-side wall.
#    Keep reference_flow's floorplan structure; patch only the differences.
# ----------------------------------------------------------------
step "13/15" "Patching OpenROAD floorplan + power grid + routing..."
FLOORPLAN="$REF/openroad/scripts/01_floorplan.tcl"

patch_file "$FLOORPLAN" "set chipW    1916" "set chipW    2416"
echo "  floorplan: chipW 1916 -> 2416"

sed -i 's/512x32/512x64/g' "$FLOORPLAN"
echo "  floorplan: SRAM macro 512x32 -> 512x64"

cp "$CROC/openroad/src/instances.tcl" "$REF/openroad/src/instances.tcl"
echo "  copied openroad/src/instances.tcl  (gen_1024x32xBx1.i_cut)"

FLOORPLAN="$FLOORPLAN" python3 << 'PYEOF'
import sys, os, re

floorplan = os.environ['FLOORPLAN']
with open(floorplan) as f:
    content = f.read()

NEW_PLACEMENT = (
    '# Bank0: top-center, pins facing down (R0)\n'
    '# Bank1: bottom-center, pins facing up (MX) -- wide routing channels on both sides\n'
    'set sramCenterX [expr {int($floor_midpointX - $RamSize512x64_W / 2)}]\n'
    '\n'
    'placeInstance $bank0_sram0 $sramCenterX [expr {int($floor_topY - $RamSize512x64_H)}] R0\n'
    'placeInstance $bank1_sram0 $sramCenterX [expr {int($floor_bottomY)}] MX\n'
    '\n'
    'utl::report "SRAM macro box: width ${RamSize512x64_W} height ${RamSize512x64_H}"\n'
    'utl::report "SRAM bank0: center-top  x=$sramCenterX y=[expr {int($floor_topY - $RamSize512x64_H)}] R0"\n'
    'utl::report "SRAM bank1: center-bot  x=$sramCenterX y=$floor_bottomY MX"\n'
    'utl::report "SRAM side channels: [expr {$sramCenterX - $core_leftX}] um on each side"'
)

if 'Bank0: top-center' in content:
    print('  floorplan: SRAM placement already top-center/bottom-center, skipping')
    sys.exit(0)

old_pattern = re.compile(
    r'# Bank0:.*?\n'
    r'set bank0X.*?\n'
    r'set bankY.*?\n'
    r'placeInstance \$bank0_sram0.*?\n'
    r'\n'
    r'# Bank1:.*?\n'
    r'set bank1X.*?\n'
    r'placeInstance \$bank1_sram0.*?\n'
    r'\n'
    r'utl::report.*?\n'
    r'utl::report.*?\n'
    r'utl::report.*?\n'
    r'utl::report.*?\n'
    r'utl::report.*?(?=\n)',
    re.DOTALL
)
m = old_pattern.search(content)
if not m:
    print('ERROR: could not locate SRAM placement block', file=sys.stderr)
    sys.exit(1)
with open(floorplan, 'w') as f:
    f.write(content[:m.start()] + NEW_PLACEMENT + content[m.end():])
print('  floorplan: SRAM placement -> top-center (R0) + bottom-center (MX)')
PYEOF

PWRGRID="$REF/openroad/scripts/power_grid.tcl"
sed -i 's|"sram_512x32".*"RM_IHPSG13_1P_512x32_c2_bm_bist"|"sram_512x64"  "RM_IHPSG13_1P_512x64_c2_bm_bist"|' "$PWRGRID"
echo "  power_grid: sram_power reference 512x32 -> 512x64"

DEF2GDS="$REF/klayout/def2gds-croc"
patch_file "$DEF2GDS" \
    "RM_IHPSG13_1P_512x32_c2_bm_bist.gds" \
    "RM_IHPSG13_1P_512x64_c2_bm_bist.gds"
patch_file "$DEF2GDS" \
    "klayout -zz -rd design_name" \
    "oseda -2026.04 klayout -zz -rd design_name"
insert_before "$DEF2GDS" \
    "        -rd lef_files='' \\" \
    "        -rd seal_file=''"
echo "  def2gds-croc: SRAM GDS 512x32 -> 512x64, oseda prefix, lef_files=''"

ROUTING="$REF/openroad/scripts/04_routing.tcl"
patch_file "$ROUTING" "-droute_end_iter 20" "-droute_end_iter 30"
echo "  04_routing.tcl: -droute_end_iter 20 -> 30 (more iterations before giving up)"

# ----------------------------------------------------------------
# 14. .cockpitrc — select 512x64 macro so icdesign generates the right
#    liberty/LEF files.  Must happen BEFORE icdesign runs (step 15).
# ----------------------------------------------------------------
step "14/15" "Patching .cockpitrc macro selection..."
COCKPITRC="$REF/.cockpitrc"
if grep -qF "macros  = RM_IHPSG13_1P_512x64_c2_bm_bist" "$COCKPITRC"; then
    echo "  already using 512x64 macro, no change"
else
    sed -i 's|macros  = RM_IHPSG13_1P_512x32_c2_bm_bist|macros  = RM_IHPSG13_1P_512x64_c2_bm_bist|' "$COCKPITRC"
    echo "  .cockpitrc: macro 512x32 -> 512x64"
fi

# ----------------------------------------------------------------
# 15. Regenerate technology files
#     Reads the patched .cockpitrc and produces LEF/lib for 512x64.
# ----------------------------------------------------------------
step "15/15" "Regenerating technology files (this takes a few minutes)..."
(cd "$REF" && icdesign ihp13 -update all -nogui)
echo "  technology files up to date"

# ----------------------------------------------------------------
# Add reference_flow/ to .gitignore if not already there
# ----------------------------------------------------------------
GITIGNORE="$CROC/.gitignore"
if ! grep -qxF "reference_flow" "$GITIGNORE" && ! grep -qxF "reference_flow/" "$GITIGNORE"; then
    echo "reference_flow/" >> "$GITIGNORE"
    echo ""
    echo "  Added reference_flow/ to .gitignore"
fi

# ----------------------------------------------------------------
# Write Makefile into reference_flow/
#     Targets are designed to run from inside oseda bash.
#     Run: oseda bash -> make backend
# ----------------------------------------------------------------
cat > "$REF/Makefile" << 'MAKEOF'
# Backend + simulation Makefile for reference_flow/
#
# All targets must be run from inside the oseda container:
#   oseda bash              # enter the container
#   make backend            # synthesis -> P&R -> GDS -> DRC
#   make sim                # build SW + run all verilator simulations
#   make sim-flash          # build SW + run flash-boot sim for every program
#
# Individual targets:
#   make submodules         git submodule update
#   make synth              Yosys synthesis
#   make pnr                OpenROAD place-and-route
#   make gds                KLayout DEF->GDS
#   make drc                KLayout DRC
#   make sim                build SW + verilator: print_config, all tests + helloworld, XiP exec, flash-boot
#   make sim-flash          build SW + verilator: flash-boot variant of every program

.PHONY: all backend submodules synth pnr gds drc sim sim-flash

YOSYS_DIR    := yosys
OPENROAD_DIR := openroad
KLAYOUT_DIR  := klayout
SW_DIR       := sw
VL_DIR       := verilator

all: backend

backend: submodules synth pnr gds drc

submodules:
	git submodule update --init --recursive

synth:
	cd $(YOSYS_DIR) && ./run_synthesis.sh --synth

pnr:
	cd $(OPENROAD_DIR) && ./run_backend.sh --all

gds:
	cd $(KLAYOUT_DIR) && ./def2gds-croc

drc: gds
	cd $(KLAYOUT_DIR) && ./run_drc-croc

sim:
	@echo "=== [1/5] Building software ==="
	cd $(SW_DIR) && make all
	@echo ""
	@echo "=== [2/5] Core configuration — print_config (also compiles verilator model) ==="
	cd $(VL_DIR) && ./run_verilator.sh --build --run ../$(SW_DIR)/bin/test/print_config.hex
	@echo ""
	@echo "=== [3/5] Running all tests (including helloworld) ==="
	@pass=0; fail=0; \
	for hex in $(SW_DIR)/bin/helloworld.hex $(SW_DIR)/bin/test/*.hex; do \
	    name=$$(basename $$hex .hex); \
	    case "$$name" in flash_*|test_idma|test_xip) continue ;; esac; \
	    extra=""; \
	    [ "$$name" = "test_spi_flash" ] && extra="--flash ../$(SW_DIR)/test/spi_hello.hex"; \
	    printf "  %-38s" "$$name"; \
	    if (cd $(VL_DIR) && ./run_verilator.sh --run ../$$hex $$extra) > /tmp/vl_last.log 2>&1; then \
	        echo " PASS"; pass=$$((pass + 1)); \
	    else \
	        echo " FAIL"; \
	        grep -i "error\|assert\|exception\|FAILED" /tmp/vl_last.log | sed 's/^/    /' || sed 's/^/    /' /tmp/vl_last.log; \
	        fail=$$((fail + 1)); \
	    fi; \
	done; \
	echo ""; \
	echo "  Results: $$pass passed, $$fail failed"
	@echo ""
	@echo "=== [4/5] JTAG boot → XiP flash execution (test_xip + flash_helloworld) ==="
	cd $(VL_DIR) && ./run_verilator.sh \
	    --run   ../$(SW_DIR)/bin/test/test_xip.hex \
	    --flash ../$(SW_DIR)/test/spi_xip_payload.hex
	@echo ""
	@echo "=== [5/5] Autonomous flash-boot (all flash programs) ==="
	@pass=0; fail=0; \
	for hex in $(SW_DIR)/bin/flash_*.hex $(SW_DIR)/bin/test/flash_*.hex; do \
	    [ -f "$$hex" ] || continue; \
	    name=$$(basename $$hex .hex); \
	    case "$$name" in flash_test_idma|flash_test_xip|flash_test_gpio) continue ;; esac; \
	    printf "  %-38s" "$$name"; \
	    if (cd $(VL_DIR) && ./run_verilator.sh --flash-boot ../$$hex) > /tmp/vl_last.log 2>&1; then \
	        echo " PASS"; pass=$$((pass + 1)); \
	    else \
	        echo " FAIL"; \
	        grep -i "error\|assert\|exception\|FAILED" /tmp/vl_last.log | sed 's/^/    /' || sed 's/^/    /' /tmp/vl_last.log; \
	        fail=$$((fail + 1)); \
	    fi; \
	done; \
	echo ""; \
	echo "  Results: $$pass passed, $$fail failed"

sim-flash:
	@echo "=== [1/2] Building software (includes flash_* hex targets) ==="
	cd $(SW_DIR) && make all
	@echo ""
	@echo "=== [2/2] Flash-boot simulation for every program ==="
	@pass=0; fail=0; \
	for hex in $(SW_DIR)/bin/flash_*.hex $(SW_DIR)/bin/test/flash_*.hex; do \
	    [ -f "$$hex" ] || continue; \
	    name=$$(basename $$hex .hex); \
	    printf "  %-38s" "$$name"; \
	    if (cd $(VL_DIR) && ./run_verilator.sh --flash-boot ../$$hex) > /tmp/vl_last.log 2>&1; then \
	        echo " PASS"; pass=$$((pass + 1)); \
	    else \
	        echo " FAIL"; \
	        grep -i "error\|assert\|exception\|FAILED" /tmp/vl_last.log | sed 's/^/    /' || sed 's/^/    /' /tmp/vl_last.log; \
	        fail=$$((fail + 1)); \
	    fi; \
	done; \
	echo ""; \
	echo "  Results: $$pass passed, $$fail failed"
MAKEOF
echo "  wrote reference_flow/Makefile  (added sim-flash target)"

# ----------------------------------------------------------------
# Done — drop user into reference_flow/
# ----------------------------------------------------------------
echo ""
echo "========================================================"
echo " Setup complete!"
echo ""
echo " Files NOT ported (technology-specific, kept from ref flow):"
echo "   rtl/croc_chip.sv        sg13cmos5l IO pad cell names"
echo "                           (GPIO[8] c2p_en patched to 1'b0 above)"
echo "   ihp13/tc_sram_impl.sv   already has gen_1024x32xBx1 case"
echo "   ihp13/tc_clk.sv         CMOS5L clock cells"
echo "   openroad/scripts/init_tech.tcl   cell/LEF names for CMOS5L"
echo ""
echo " All make targets run from inside oseda bash:"
echo "   oseda bash          <- enter the oseda container"
echo "   make backend        <- synth + P&R + GDS + DRC"
echo "   make sim            <- build SW + run all verilator tests"
echo "   make sim-flash      <- build SW + run flash-boot sim for every program"
echo "========================================================"
echo ""
echo " Entering reference_flow/ ..."
cd "$REF"
exec bash
