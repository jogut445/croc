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
  // Base = UserBaseAddr + 0x1000, config regs at addr[13:12]==2'b01
  // -------------------------------------------------------------------------
  localparam bit [31:0] SpiXipBase      = croc_pkg::UserBaseAddr + 32'h0000_1000;
  localparam bit [31:0] SpiCfgSckPin    = SpiXipBase + 32'h00; // [PIN_W-1:0] GPIO pin for SCK
  localparam bit [31:0] SpiCfgCsnPin    = SpiXipBase + 32'h04; // [PIN_W-1:0] GPIO pin for CSN
  localparam bit [31:0] SpiCfgIo0Pin    = SpiXipBase + 32'h08; // [PIN_W-1:0] GPIO pin for SPI IO[0]
  localparam bit [31:0] SpiCfgIo1Pin    = SpiXipBase + 32'h0C; // [PIN_W-1:0] GPIO pin for SPI IO[1]
  localparam bit [31:0] SpiCfgIo2Pin    = SpiXipBase + 32'h10; // [PIN_W-1:0] GPIO pin for SPI IO[2]
  localparam bit [31:0] SpiCfgIo3Pin    = SpiXipBase + 32'h14; // [PIN_W-1:0] GPIO pin for SPI IO[3]
  localparam bit [31:0] SpiCfgCtrl      = SpiXipBase + 32'h18; // [0] = 1 enables SPI GPIO override

  // First XiP-accessible word: addr[13:12]==2'b10 → offset 0x2000 within user window
  // Flash byte address = OBI_addr[23:0], so flash offset 0x002000 is at OBI 0x2002_0000? No:
  // UserBaseAddr=0x2000_0000, XiP starts at 0x2000_2000 (UserBaseAddr+0x2000).
  // Flash byte address = HADDR[23:0] = 0x00_2000 for first XiP word.
  localparam bit [31:0] SpiXipFlashBase = croc_pkg::UserBaseAddr + 32'h0000_2000;

  // Default GPIO pin assignments for SPI (change to match your board layout)
  localparam int unsigned SpiPinSck = 0;
  localparam int unsigned SpiPinCsn = 1;
  localparam int unsigned SpiPinIo0 = 2; // MOSI / quad D0
  localparam int unsigned SpiPinIo1 = 3; // MISO / quad D1
  localparam int unsigned SpiPinIo2 = 4; // WP   / quad D2
  localparam int unsigned SpiPinIo3 = 5; // HOLD / quad D3

endpackage
