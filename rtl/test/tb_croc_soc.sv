// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Philippe Sauter <phsauter@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

`define TRACE_WAVE

module tb_croc_soc #(
  parameter int unsigned GpioCount = 32
);

  import tb_croc_pkg::*;

  // Signals fully controlled by the VIP
  // use VIP functions/tasks to manipulate these signals
  logic rst_n;
  logic sys_clk;
  logic ref_clk;

  logic jtag_tck;
  logic jtag_trst_n;
  logic jtag_tms;
  logic jtag_tdi;
  logic jtag_tdo;

  logic uart_rx;
  logic uart_tx;

  // VIP drives gpio_in_vip; we merge flash SIO back in for SPI pins
  logic [GpioCount-1:0] gpio_in_vip;
  logic [GpioCount-1:0] gpio_in;
  logic [GpioCount-1:0] gpio_out;
  logic [GpioCount-1:0] gpio_out_en;

  /////////////////////////////
  //  Command Line Arguments //
  /////////////////////////////

  string binary_path;
  string flash_hex_path;
  bit    run_flash_test;

  initial begin
    if ($value$plusargs("binary=%s", binary_path)) begin
      $display("Running program: %s", binary_path);
    end else begin
      $display("No binary path provided. Running helloworld.");
      binary_path = "../sw/bin/helloworld.hex";
    end
    run_flash_test = $test$plusargs("flash_test");
    if (run_flash_test) $display("SPI flash XiP test enabled.");
    if (!$value$plusargs("flash=%s", flash_hex_path))
      flash_hex_path = "";
  end

  ////////////
  //  VIP   //
  ////////////
  // Verification IP
  // - drives clocks and resets
  // - provides helper tasks and functions for JTAG, namely:
  //   - jtag_load_hex: loads a hex file into the DUT's memory
  //   - jtag_write_reg32: write 32-bit value to DUT
  //   - jtag_read_reg32: read 32-bit value from DUT
  //   - jtag_halt / jtag_resume: control core execution
  //   - jtag_wait_for_eoc: wait for end of code execution (core writes non-zero to status register)
  // - prints UART output to console (you can also write via uart_write_byte)
  // - internal GPIO loopback for helloworld test

  croc_vip #(
    .GpioCount ( GpioCount )
  ) i_vip (
    .rst_no        ( rst_n       ),
    .sys_clk_o     ( sys_clk     ),
    .ref_clk_o     ( ref_clk     ),
    .jtag_tck_o    ( jtag_tck    ),
    .jtag_trst_no  ( jtag_trst_n ),
    .jtag_tms_o    ( jtag_tms    ),
    .jtag_tdi_o    ( jtag_tdi    ),
    .jtag_tdo_i    ( jtag_tdo    ),
    .uart_rx_o     ( uart_rx     ),
    .uart_tx_i     ( uart_tx     ),
    .gpio_out_en_i ( gpio_out_en ),
    .gpio_out_i    ( gpio_out    ),
    .gpio_in_o     ( gpio_in_vip )  // VIP drives intermediate signal
  );

  /////////////////////
  //  SPI Flash Model //
  /////////////////////
  // Uses spiflash (PicoRV32 / greyhound model) with real inout tristate wires,
  // identical to greyhound_soc_tb.sv.  The SoC drives flash_io[i] when its
  // gpio_out_en=1; the flash model drives via its internal io_oe (#1 delay).
  // Tristate resolution in vsim picks whichever side is actively driving.
  // gpio_in[SpiPinIo_i] is driven directly from the flash_io wire; it then
  // passes through the croc GPIO 2-FF synchronizer before reaching din in
  // spi_qspi_obi_wrap — the synchronizer latency (2 sys_clk = 1 SCK cycle)
  // aligns exactly with the FLASH_READER_QSPI capture timing.

  wire flash_sck = gpio_out[SpiPinSck];
  // CSN: SoC drives low during a transaction, otherwise high (deselected)
  wire flash_csn = gpio_out_en[SpiPinCsn] ? gpio_out[SpiPinCsn] : 1'b1;

  // Bidirectional SIO lines — SoC drives when gpio_out_en=1, tristate otherwise
  wire flash_io0 = gpio_out_en[SpiPinIo0] ? gpio_out[SpiPinIo0] : 1'bz;
  wire flash_io1 = gpio_out_en[SpiPinIo1] ? gpio_out[SpiPinIo1] : 1'bz;
  wire flash_io2 = gpio_out_en[SpiPinIo2] ? gpio_out[SpiPinIo2] : 1'bz;
  wire flash_io3 = gpio_out_en[SpiPinIo3] ? gpio_out[SpiPinIo3] : 1'bz;

  spiflash i_flash (
    .csb ( flash_csn ),
    .clk ( flash_sck ),
    .io0 ( flash_io0 ),
    .io1 ( flash_io1 ),
    .io2 ( flash_io2 ),
    .io3 ( flash_io3 )
  );

  // Feed flash_io wires back into the SoC GPIO inputs.
  // When neither side drives (Z), hold 0 to suppress X propagation through
  // the synchronizer during phases when din is not being sampled.
  always_comb begin
    gpio_in = gpio_in_vip;
    gpio_in[SpiPinIo0] = (flash_io0 === 1'bz) ? 1'b0 : flash_io0;
    gpio_in[SpiPinIo1] = (flash_io1 === 1'bz) ? 1'b0 : flash_io1;
    gpio_in[SpiPinIo2] = (flash_io2 === 1'bz) ? 1'b0 : flash_io2;
    gpio_in[SpiPinIo3] = (flash_io3 === 1'bz) ? 1'b0 : flash_io3;
  end

  // Flash memory initialisation.
  // spiflash starts with memory[*] = 0xFF (erased state).
  // If +flash=<file.hex> is given, load the whole image from that file.
  // Otherwise write a recognisable test pattern at flash byte 0x002000,
  // which maps to OBI address SpiXipFlashBase (UserBaseAddr + 0x2000).
  //
  // Expected word at SpiXipFlashBase:
  //   {flash[0x2003], flash[0x2002], flash[0x2001], flash[0x2000]}
  //   = {8'h44, 8'h33, 8'h22, 8'h11} = 32'h4433_2211
  localparam bit [31:0] FlashTestWord = 32'h4433_2211;
  localparam bit [23:0] FlashTestAddr = 24'h002000; // matches SpiXipFlashBase[23:0]

  initial begin
    #2; // wait for spiflash's own initial block to finish
    if (flash_hex_path != "") begin
      $display("@%t | [FLASH] Loading %s into flash memory", $time, flash_hex_path);
      $readmemh(flash_hex_path, i_flash.memory);
    end else begin
      $display("@%t | [FLASH] Writing test pattern at flash byte 0x%06h", $time, FlashTestAddr);
      i_flash.memory[FlashTestAddr + 0] = 8'h11;
      i_flash.memory[FlashTestAddr + 1] = 8'h22;
      i_flash.memory[FlashTestAddr + 2] = 8'h33;
      i_flash.memory[FlashTestAddr + 3] = 8'h44;
    end
  end

  ////////////
  //  DUT   //
  ////////////

  `ifdef TARGET_NETLIST_YOSYS
  \croc_soc$croc_chip.i_croc_soc i_croc_soc (
  `else
  croc_soc #(
    .GpioCount ( GpioCount )
  ) i_croc_soc (
  `endif
    .clk_i         ( sys_clk     ),
    .rst_ni        ( rst_n       ),
    .ref_clk_i     ( ref_clk     ),
    .testmode_i    ( 1'b0        ),
    .status_o      (             ),
    .jtag_tck_i    ( jtag_tck    ),
    .jtag_tdi_i    ( jtag_tdi    ),
    .jtag_tdo_o    ( jtag_tdo    ),
    .jtag_tms_i    ( jtag_tms    ),
    .jtag_trst_ni  ( jtag_trst_n ),
    .uart_rx_i     ( uart_rx     ),
    .uart_tx_o     ( uart_tx     ),
    .gpio_i        ( gpio_in     ),
    .gpio_o        ( gpio_out    ),
    .gpio_out_en_o ( gpio_out_en )
  );

  /////////////////////
  //  SPI XiP Test   //
  /////////////////////
  // GPIO pins for SPI are fixed at compile time (spi_qspi_obi_wrap parameters);
  // no config register writes are needed.  Reads the first word from the XiP
  // flash window and checks it against the expected value.  A long sbbusy poll
  // loop is used because the first access triggers the flash software-reset
  // sequence (~1000 clock cycles) followed by a cache-line fetch (~156 cycles).
  task automatic spi_xip_test;
    automatic logic [31:0] rd_data;

    $display("@%t | [SPI] Reading first XiP word (triggers flash reset + cache fill)...", $time);
    begin : xip_read
      automatic dm::sbcs_t sbcs;
      // Initiate system-bus read with sbreadonaddr
      sbcs = dm::sbcs_t'{sbreadonaddr: 1'b1, sbaccess: 2, default: '0};
      i_vip.jtag_write(dm::SBCS, sbcs, 0, 0);
      // Write address – this triggers the OBI read and starts the flash FSM.
      // Use wait_sba=1 to poll sbbusy until the transaction completes.
      // The flash reset takes ~1000 sys_clk cycles; the cache-line fetch
      // takes ~156 cycles.  Both are handled transparently by the OBI stall.
      i_vip.jtag_write(dm::SBAddress0, SpiXipFlashBase, 0, 1); // wait_sba=1
      i_vip.jtag_dbg.read_dmi_exp_backoff(dm::SBData0, rd_data);
    end

    $display("@%t | [SPI] Read  0x%08h from XiP address 0x%08h", $time, rd_data, SpiXipFlashBase);
    $display("@%t | [SPI] Expect 0x%08h", $time, FlashTestWord);
    if (rd_data === FlashTestWord) begin
      $display("@%t | [SPI] PASS: data matches expected value", $time);
    end else begin
      $error  ("@%t | [SPI] FAIL: got 0x%08h, expected 0x%08h", $time, rd_data, FlashTestWord);
    end

    // Second read to the same address: should hit the cache (fast path)
    $display("@%t | [SPI] Second read (should hit D-mapped cache)...", $time);
    i_vip.jtag_read_reg32(SpiXipFlashBase, rd_data, 20);
    if (rd_data === FlashTestWord)
      $display("@%t | [SPI] Cache hit PASS", $time);
    else
      $error  ("@%t | [SPI] Cache hit FAIL: 0x%08h", $time, rd_data);

    // Read next word in the same cache line (offset +4)
    $display("@%t | [SPI] Reading word at offset +4 (same cache line)...", $time);
    i_vip.jtag_read_reg32(SpiXipFlashBase + 4, rd_data, 20);
    $display("@%t | [SPI] Word+4 = 0x%08h", $time, rd_data);
  endtask

  /////////////////
  //  Testbench  //
  /////////////////

  logic [31:0] tb_data;

  initial begin
    $timeformat(-9, 0, "ns", 12); // 1: scale (ns=-9), 2: decimals, 3: suffix, 4: print-field width

    // wait for reset
    #ClkPeriodSys;

    // init jtag
    i_vip.jtag_init();

    // -----------------------------------------------------------------------
    // Optional: SPI XiP flash test
    // -----------------------------------------------------------------------
    if (run_flash_test) begin
      spi_xip_test();
      repeat(20) @(posedge sys_clk);
    end

    // -----------------------------------------------------------------------
    // Standard binary-load and run test
    // -----------------------------------------------------------------------
    // write test value to sram
    i_vip.jtag_write_reg32(SramBaseAddr, 32'h1234_5678, 1'b1);

    // load binary to sram
    i_vip.jtag_load_hex(binary_path);

    // wake core from WFI by writing to CLINT msip
    $display("@%t | [CORE] Waking core via CLINT msip", $time);
    i_vip.jtag_write_reg32(ClintBaseAddr, 32'h1);

    // halt core
    i_vip.jtag_halt();

    // resume core
    i_vip.jtag_resume();

    // wait for non-zero return value (written into core status register)
    $display("@%t | [CORE] Wait for end of code...", $time);
    i_vip.jtag_wait_for_eoc(tb_data);

    // finish simulation
    repeat(50) @(posedge sys_clk);
    $finish();
  end

  ////////////////
  //  Waveform  //
  ////////////////
  // start waveform dump at time 0, independent of stimuli
  initial begin
    `ifdef TRACE_WAVE
      `ifdef VERILATOR
        $dumpfile("croc.fst");
        $dumpvars(1, i_croc_soc);
      `else
        $dumpfile("croc.vcd");
        $dumpvars(1, i_croc_soc);
      `endif
    `endif
  end

  // flush waveform dump when simulation ends
  final begin
    `ifdef TRACE_WAVE
      $dumpflush;
    `endif
  end

endmodule
