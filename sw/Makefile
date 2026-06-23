# Copyright (c) 2024 ETH Zurich and University of Bologna.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
# Authors:
# - Paul Scheffler <paulsc@iis.ee.ethz.ch>
# - Philippe Sauter <phsauter@iis.ee.ethz.ch>

# Toolchain
RISCV_XLEN    ?= 32
RISCV_MARCH   ?= rv$(RISCV_XLEN)i_zicsr
RISCV_MABI    ?= ilp32
RISCV_PREFIX  ?= riscv64-unknown-elf-
RISCV_CC      ?= $(RISCV_PREFIX)gcc
RISCV_CXX     ?= $(RISCV_PREFIX)g++
RISCV_OBJDUMP ?= $(RISCV_PREFIX)objdump
RISCV_OBJCOPY ?= $(RISCV_PREFIX)objcopy
RISCV_AS      ?= $(RISCV_PREFIX)as
RISCV_AR      ?= $(RISCV_PREFIX)ar
RISCV_LD      ?= $(RISCV_PREFIX)ld
RISCV_STRIP   ?= $(RISCV_PREFIX)strip

# Compiler and linker flags
RISCV_FLAGS ?= -march=$(RISCV_MARCH) -mabi=$(RISCV_MABI) -mcmodel=medany \
	-static -std=gnu99 -Os -nostdlib -fno-builtin -ffreestanding
RISCV_CCFLAGS ?= $(RISCV_FLAGS) -Iinclude -I$(INCDIR) -I$(CURDIR)
RISCV_LDFLAGS ?= -static -nostartfiles -lm -lgcc $(RISCV_FLAGS)


# Directory defaults
BINDIR   ?= bin
BUILDDIR ?= build
CRT0       ?= crt0.S
LINK       ?= link.ld
CRT0_FLASH ?= crt0_flash.S
LINK_FLASH ?= link_flash.ld
SRCDIR   ?= lib/src
INCDIR   ?= lib/inc

# Collecting source files
LIB_SOURCES  := $(wildcard $(SRCDIR)/*.[cS])
TOP_SOURCES  := $(filter-out $(CRT0) $(CRT0_FLASH), $(wildcard *.[cS]))
TEST_SOURCES := $(wildcard test/*.[cS])
PROG_SOURCES := $(TOP_SOURCES) $(TEST_SOURCES)

PROG_NAMES   := $(basename $(PROG_SOURCES))

# Creating object fiel list from source files
CRT0_OBJ       := $(BUILDDIR)/$(basename $(CRT0)).o
CRT0_FLASH_OBJ := $(BUILDDIR)/$(basename $(CRT0_FLASH)).o
LIB_OBJS  := $(addsuffix .o, $(addprefix $(BUILDDIR)/, \
	         $(basename $(LIB_SOURCES))))
PROG_OBJS := $(addsuffix .o, $(addprefix $(BUILDDIR)/, \
	         $(basename $(PROG_SOURCES))))

# Everything to be built
ALL_TARGETS := $(PROG_NAMES:%=$(BINDIR)/%.elf) \
	           $(PROG_NAMES:%=$(BINDIR)/%.dump) \
	           $(PROG_NAMES:%=$(BINDIR)/%.hex)

# Flash variants: same programs re-linked with link_flash.ld + crt0_flash.S.
# Hex addresses are LMA (flash byte addresses), ready for $readmemh.
# e.g. helloworld → bin/flash_helloworld.hex
#      test/test_xip → bin/test/flash_test_xip.hex
flash_elf   = $(BINDIR)/$(patsubst ./%,%,$(dir $(1)))flash_$(notdir $(1)).elf
FLASH_ELFS  := $(foreach p,$(PROG_NAMES),$(call flash_elf,$(p)))
FLASH_DUMPS := $(FLASH_ELFS:.elf=.dump)
FLASH_HEXS  := $(FLASH_ELFS:.elf=.hex)
ALL_TARGETS += $(FLASH_ELFS) $(FLASH_DUMPS) $(FLASH_HEXS)

# Dependency files for automatic rebuilds
DEPFILES := $(CRT0_OBJ:.o=.d) $(CRT0_FLASH_OBJ:.o=.d) $(LIB_OBJS:.o=.d) $(PROG_OBJS:.o=.d)

# Ensure intermediate object files are not deleted after linking
.SECONDARY: $(CRT0_OBJ) $(CRT0_FLASH_OBJ) $(LIB_OBJS) $(PROG_OBJS)

all: compile

$(BINDIR):
	mkdir -p $(BINDIR)

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

# Assembly to object compilation
$(BUILDDIR)/%.o: %.S
	mkdir -p $(dir $@)
	$(RISCV_CC) $(RISCV_CCFLAGS) -MMD -MP -c $< -o $@

# C to object compilation
$(BUILDDIR)/%.o: %.c
	mkdir -p $(dir $@)
	$(RISCV_CC) $(RISCV_CCFLAGS) -MMD -MP -c $< -o $@

# Linking
$(BINDIR)/%.elf: $(BUILDDIR)/%.o $(CRT0_OBJ) $(LIB_OBJS) $(LINK)
	mkdir -p $(dir $@)
	$(RISCV_CC) -o $@ $(filter-out $(LINK), $^) $(RISCV_LDFLAGS) -T$(LINK)

# Flash ELF: same .o files, different crt0 + linker script.
# One rule is generated per program via $(eval $(call ...)) so the stem can
# include a subdirectory (e.g. test/test_xip → build/test/test_xip.o).
define flash_link_rule
$(call flash_elf,$(1)): $(BUILDDIR)/$(1).o $(CRT0_FLASH_OBJ) $(LIB_OBJS) $(LINK_FLASH)
	mkdir -p $$(dir $$@)
	$(RISCV_CC) -o $$@ $$(filter-out $(LINK_FLASH), $$^) $(RISCV_LDFLAGS) -T$(LINK_FLASH)
endef
$(foreach p,$(PROG_NAMES),$(eval $(call flash_link_rule,$(p))))

# Flash disassembly
$(FLASH_DUMPS): %.dump: %.elf
	mkdir -p $(dir $@)
	$(RISCV_OBJDUMP) -D -s $< >$@

# Flash hex — objcopy uses LMA, producing flash byte addresses (@002000...)
$(FLASH_HEXS): %.hex: %.elf
	mkdir -p $(dir $@)
	$(RISCV_OBJCOPY) -O verilog $< $@

# Dump ELF data and disassembly
$(BINDIR)/%.dump: $(BINDIR)/%.elf
	mkdir -p $(dir $@)
	$(RISCV_OBJDUMP) -D -s $< >$@

# Convert ELF to hex format for easy loading into simulators or hardware
$(BINDIR)/%.hex: $(BINDIR)/%.elf
	mkdir -p $(dir $@)
	$(RISCV_OBJCOPY) -O verilog $< $@

# Phonies
.PHONY: all clean compile

clean:
	rm -rf $(BINDIR) $(BUILDDIR)

compile: $(BINDIR) $(BUILDDIR) $(ALL_TARGETS)

-include $(DEPFILES)
