#!/usr/bin/env bash
# setup_reference_flow.sh
#
# One-shot setup script ? run once after cloning the croc repo on an ETH VLSI2
# machine.  It:
#   1. Installs the ETH reference flow into croc/reference_flow/
#   2. Ports all your custom changes (SIMD extension, user ROM, software,
#      chip layout) into the reference flow
#   3. Regenerates the technology files via icdesign
#
# After it finishes, cd into reference_flow/ and run the backend:
#   cd reference_flow && make nonfree
#
# The script is idempotent ? safe to re-run after updating your RTL.

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
step "1/11" "Installing ETH reference flow..."
if [ -d "$REF" ]; then
    echo "  reference_flow/ already exists ? skipping install"
else
    (cd "$CROC" && "$INSTALL_SH")
    [ -d "$REF" ] || die "install.sh ran but reference_flow/ was not created"
    echo "  installed reference_flow/"
fi

# ----------------------------------------------------------------
# 2. SIMD extension ? all modified cve2 files (tech-independent)
# ----------------------------------------------------------------
step "2/11" "Copying SIMD extension (rtl/cve2/)..."
for f in cve2_pkg.sv cve2_alu.sv cve2_core.sv cve2_core_tracing.sv \
          cve2_decoder.sv cve2_ex_block.sv cve2_id_stage.sv; do
    [ -f "$CROC/rtl/cve2/$f" ] || die "Missing: $CROC/rtl/cve2/$f"
    cp "$CROC/rtl/cve2/$f" "$REF/rtl/cve2/$f"
    echo "  rtl/cve2/$f"
done

# ----------------------------------------------------------------
# 3. User domain ? ROM module, package, instantiation
# ----------------------------------------------------------------
step "3/11" "Copying user domain RTL..."
cp "$CROC/rtl/user_domain/user_rom.sv" "$REF/rtl/user_domain/user_rom.sv"
echo "  rtl/user_domain/user_rom.sv"
cp "$CROC/rtl/user_pkg.sv"    "$REF/rtl/user_pkg.sv"
echo "  rtl/user_pkg.sv"
cp "$CROC/rtl/user_domain.sv" "$REF/rtl/user_domain.sv"
echo "  rtl/user_domain.sv"

# ----------------------------------------------------------------
# 4. Core configuration ? SIMD enable, RV32M/B, SramBankNumWords=1024
#    NOT copied: croc_chip.sv (pad cell names are sg13cmos5l-specific)
#    NOT copied: tc_sram_impl.sv (reference_flow already has gen_1024x32xBx1
#                which maps 1024x32 onto the 512x64 physical macro)
# ----------------------------------------------------------------
step "4/11" "Copying core configuration RTL..."
cp "$CROC/rtl/core_wrap.sv" "$REF/rtl/core_wrap.sv"
echo "  rtl/core_wrap.sv  (RV32M, RV32B, RV32SIMD enabled)"
cp "$CROC/rtl/croc_pkg.sv"  "$REF/rtl/croc_pkg.sv"
echo "  rtl/croc_pkg.sv   (SramBankNumWords=1024, CoreRV32SIMDEnable=1)"

# ----------------------------------------------------------------
# 5. Software ? SIMD intrinsics header, extended print, test programs
# ----------------------------------------------------------------
step "5/11" "Copying software..."
cp "$CROC/sw/lib/inc/simd.h"  "$REF/sw/lib/inc/simd.h"
echo "  sw/lib/inc/simd.h"
cp "$CROC/sw/lib/src/print.c" "$REF/sw/lib/src/print.c"
echo "  sw/lib/src/print.c"
for f in read_rom.c show_impro.c test_simd8.c test_simd16.c test_simd32.c test_simd_matmul.c; do
    cp "$CROC/sw/test/$f" "$REF/sw/test/$f"
    echo "  sw/test/$f"
done

# ----------------------------------------------------------------
# 6. Simulation/synthesis filelists ? add user_rom.sv before user_domain.sv
# ----------------------------------------------------------------
step "6/11" "Patching filelists (yosys + verilator)..."
for FLIST in "$REF/yosys/src/croc.flist" "$REF/verilator/croc.f"; do
    insert_before "$FLIST" "../rtl/user_domain/user_rom.sv" "../rtl/user_domain.sv"
    echo "  patched $(basename "$(dirname "$FLIST")")/$(basename "$FLIST")"
done

# ----------------------------------------------------------------
# 7. Pad ring ? CSV pad placement from croc, site name fixed for CMOS5L
#    bondpad_centroids.csv encodes pad positions for the 2416 um chip.
#    padring.tcl: sg13g2_ioSite -> sg13cmos5l_ioSite (only name differs).
# ----------------------------------------------------------------
step "7/11" "Porting pad ring layout..."
cp "$CROC/openroad/src/bondpad_centroids.csv" "$REF/openroad/src/bondpad_centroids.csv"
echo "  copied openroad/src/bondpad_centroids.csv"
cp "$CROC/openroad/src/padring.tcl" "$REF/openroad/src/padring.tcl"
sed -i 's/sg13g2_ioSite/sg13cmos5l_ioSite/g' "$REF/openroad/src/padring.tcl"
echo "  copied openroad/src/padring.tcl  (sg13g2_ioSite -> sg13cmos5l_ioSite)"

# ----------------------------------------------------------------
# 8. Floorplan ? larger chip (2416 um), 512x64 macro (for 1024x32 via
#    bit-interleaving), SRAM banks split top-center / bottom-center
#    to open routing channels on both sides instead of a side-by-side wall.
#    Keep reference_flow's floorplan structure; patch only the differences.
# ----------------------------------------------------------------
step "8/11" "Patching OpenROAD floorplan + power grid + routing..."
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
# 9. .cockpitrc ? select 512x64 macro so icdesign generates the right
#    liberty/LEF files.  Must happen BEFORE icdesign runs (step 10).
# ----------------------------------------------------------------
step "9/11" "Patching .cockpitrc macro selection..."
COCKPITRC="$REF/.cockpitrc"
if grep -qF "macros  = RM_IHPSG13_1P_512x64_c2_bm_bist" "$COCKPITRC"; then
    echo "  already using 512x64 macro, no change"
else
    sed -i 's|macros  = RM_IHPSG13_1P_512x32_c2_bm_bist|macros  = RM_IHPSG13_1P_512x64_c2_bm_bist|' "$COCKPITRC"
    echo "  .cockpitrc: macro 512x32 -> 512x64"
fi

# ----------------------------------------------------------------
# 10. Regenerate technology files
#     Reads the patched .cockpitrc and produces LEF/lib for 512x64.
# ----------------------------------------------------------------
step "10/11" "Regenerating technology files (this takes a few minutes)..."
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
# 11. Write Makefile into reference_flow/
#     Targets are designed to run from inside oseda bash.
#     Run: oseda bash -> make backend
# ----------------------------------------------------------------
step "11/11" "Writing Makefile..."
cat > "$REF/Makefile" << 'MAKEOF'
# Backend + simulation Makefile for reference_flow/
#
# All targets must be run from inside the oseda container:
#   oseda bash        # enter the container
#   make backend      # synthesis -> P&R -> GDS -> DRC
#   make sim          # build SW + run all verilator simulations
#
# Individual targets:
#   make submodules        git submodule update
#   make synth             Yosys synthesis
#   make pnr               OpenROAD place-and-route
#   make gds               KLayout DEF->GDS
#   make drc               KLayout DRC
#   make sim               build SW + verilator: helloworld, all tests, print_config

.PHONY: all backend submodules synth pnr gds drc sim

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
	@echo "=== [1/4] Building software ==="
	cd $(SW_DIR) && make all
	@echo ""
	@echo "=== [2/4] helloworld (also compiles verilator model) ==="
	cd $(VL_DIR) && ./run_verilator.sh --build --run ../$(SW_DIR)/bin/helloworld.hex
	@echo ""
	@echo "=== [3/4] Running tests ==="
	@pass=0; fail=0; \
	for hex in $(SW_DIR)/bin/test/*.hex; do \
	    name=$$(basename $$hex .hex); \
	    printf "  %-38s" "$$name"; \
	    if (cd $(VL_DIR) && ./run_verilator.sh --run ../$$hex) > /tmp/vl_last.log 2>&1; then \
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
	@echo "=== [4/4] Core configuration (print_config) ==="
	cd $(VL_DIR) && ./run_verilator.sh --run ../$(SW_DIR)/bin/test/print_config.hex
MAKEOF
echo "  wrote reference_flow/Makefile"

# ----------------------------------------------------------------
# Done ? drop user into reference_flow/
# ----------------------------------------------------------------
echo ""
echo "========================================================"
echo " Setup complete!"
echo ""
echo " Files NOT ported (technology-specific, kept from ref flow):"
echo "   rtl/croc_chip.sv        sg13cmos5l IO pad cell names"
echo "   ihp13/tc_sram_impl.sv   already has gen_1024x32xBx1 case"
echo "   ihp13/tc_clk.sv         CMOS5L clock cells"
echo "   openroad/scripts/init_tech.tcl   cell/LEF names for CMOS5L"
echo ""
echo " All make targets run from inside oseda bash:"
echo "   oseda bash       <- enter the oseda container"
echo "   make backend     <- synth + P&R + GDS + DRC"
echo "   make sim         <- build SW + run all verilator tests"
echo "========================================================"
echo ""
echo " Entering reference_flow/ ..."
cd "$REF"
exec bash
