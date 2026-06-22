// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

package tb_croc_pkg;

  // Clocks
  localparam realtime ClkPeriodSys  = 50ns;    // 20 MHz
  localparam realtime ClkPeriodJtag = 50ns;    // 20 MHz
  localparam realtime ClkPeriodRef  = 30518ns; // 32 KiHz

  // Number of clock cycles the reset is applied
  // for at the beginnig of the simulation
  localparam int unsigned RstCycles = 1;

  // UART
  localparam int unsigned UartBaudRate  = 115200;
  localparam int unsigned UartParityEna = 0;

  // Base address of the SRAM banks
  localparam bit [31:0] SramBaseAddr = croc_pkg::get_croc_start_addr(croc_pkg::XbarBank0);

  // Soc control registers addresses
  localparam bit [31:0] SocCtrlBaseAddr = croc_pkg::get_periph_start_addr(croc_pkg::PeriphSocCtrl);
  localparam bit [31:0] BootAddrAddr    = SocCtrlBaseAddr + soc_ctrl_regs_pkg::SOC_CTRL_BOOTADDR_OFFSET;
  localparam bit [31:0] FetchEnAddr     = SocCtrlBaseAddr + soc_ctrl_regs_pkg::SOC_CTRL_FETCHEN_OFFSET;
  localparam bit [31:0] CoreStatusAddr  = SocCtrlBaseAddr + soc_ctrl_regs_pkg::SOC_CTRL_CORESTATUS_OFFSET;

  // CLINT base address (msip register is at offset 0)
  localparam bit [31:0] ClintBaseAddr   = croc_pkg::get_periph_start_addr(croc_pkg::PeriphClint);

  // -------------------------------------------------------------------------
  // SPI QSPI XiP controller (spi_qspi_obi_wrap in user_domain)
  //
  // Address layout within the UserDesign window (UserBaseAddr+0x1000):
  //   UserBaseAddr+0x1000 .. +0x1FFF  — SPI config registers (addr[13]=0)
  //   UserBaseAddr+0x2000 ..          — XiP flash reads      (addr[13]=1)
  //
  // Config register offsets from SpiCfgBase:
  //   0x00 SckPin, 0x04 CsnPin, 0x08 Io0Pin, 0x0C Io1Pin, 0x10 Io2Pin, 0x14 Io3Pin
  // -------------------------------------------------------------------------

  localparam bit [31:0] SpiCfgBase   = croc_pkg::UserBaseAddr + 32'h0000_1000;
  localparam bit [31:0] SpiCfgSckPin = SpiCfgBase + 32'h00;
  localparam bit [31:0] SpiCfgCsnPin = SpiCfgBase + 32'h04;
  localparam bit [31:0] SpiCfgIo0Pin = SpiCfgBase + 32'h08;
  localparam bit [31:0] SpiCfgIo1Pin = SpiCfgBase + 32'h0C;
  localparam bit [31:0] SpiCfgIo2Pin = SpiCfgBase + 32'h10;
  localparam bit [31:0] SpiCfgIo3Pin = SpiCfgBase + 32'h14;

  // OBI addr 0x2000_2000 → HADDR[23:0]=0x002000 → flash byte 0x002000
  // Test pattern is loaded at flash byte 0x002000 (FlashTestAddr in testbench).
  localparam bit [31:0] SpiXipFlashBase = croc_pkg::UserBaseAddr + 32'h0000_2000;

  // GPIO pin assignments for the SPI flash model (match spi_qspi_obi_wrap reset defaults)
  localparam int unsigned SpiPinSck = 0;
  localparam int unsigned SpiPinCsn = 1;
  localparam int unsigned SpiPinIo0 = 2; // MOSI / quad D0
  localparam int unsigned SpiPinIo1 = 3; // MISO / quad D1
  localparam int unsigned SpiPinIo2 = 4; // WP   / quad D2
  localparam int unsigned SpiPinIo3 = 5; // HOLD / quad D3

endpackage
