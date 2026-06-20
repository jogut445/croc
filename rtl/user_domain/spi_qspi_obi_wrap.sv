// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// OBI subordinate wrapper for EF_QSPI_XIP_CTRL_AHBL.
//
// All OBI accesses within the UserDesign window are forwarded as XiP reads to
// the flash controller (AHBL address = OBI address, lower 24 bits used).
// GPIO pin assignments are fixed at compile time via parameters; there are no
// software-visible config registers.
//
// GPIO pin mapping (compile-time parameters, defaults match tb_croc_pkg.sv):
//   SckPin  — SPI clock output
//   CsnPin  — chip-select output (active-low)
//   Io0Pin  — IO[0] / MOSI / quad D0 (bidirectional)
//   Io1Pin  — IO[1] / MISO / quad D1 (bidirectional)
//   Io2Pin  — IO[2] / WP   / quad D2 (bidirectional)
//   Io3Pin  — IO[3] / HOLD / quad D3 (bidirectional)

module spi_qspi_obi_wrap
  import croc_pkg::*;
#(
  parameter int unsigned GpioCount    = 16,
  parameter int unsigned NUM_LINES    = 16,
  parameter int unsigned LINE_SIZE    = 32,
  parameter int unsigned RESET_CYCLES = 999,
  // Compile-time GPIO pin assignments (must all be < GpioCount and distinct)
  parameter int unsigned SckPin       = 0,
  parameter int unsigned CsnPin       = 1,
  parameter int unsigned Io0Pin       = 2,
  parameter int unsigned Io1Pin       = 3,
  parameter int unsigned Io2Pin       = 4,
  parameter int unsigned Io3Pin       = 5
) (
  input  logic clk_i,
  input  logic rst_ni,

  // OBI subordinate port
  input  sbr_obi_req_t obi_req_i,
  output sbr_obi_rsp_t obi_rsp_o,

  // Synchronized GPIO inputs (SPI DIN source)
  input  logic [GpioCount-1:0] gpio_in_sync_i,
  // GPIO outputs driven by SPI signals
  output logic [GpioCount-1:0] gpio_out_o,
  // GPIO output enables (1 = drive, 0 = tristate / input)
  output logic [GpioCount-1:0] gpio_oen_o
);

  // -------------------------------------------------------------------------
  // Raw SPI signals
  // -------------------------------------------------------------------------
  logic       spi_sck;
  logic       spi_csn;
  logic [3:0] spi_dout;
  logic [3:0] spi_douten;
  logic [3:0] spi_din;

  // -------------------------------------------------------------------------
  // AHBL signals
  // -------------------------------------------------------------------------
  logic        ahbl_hsel;
  logic [31:0] ahbl_haddr;
  logic [1:0]  ahbl_htrans;
  logic        ahbl_hwrite;
  logic        ahbl_hready;
  logic        ahbl_hreadyout;
  logic [31:0] ahbl_hrdata;

  EF_QSPI_XIP_CTRL_AHBL #(
    .NUM_LINES   ( NUM_LINES    ),
    .LINE_SIZE   ( LINE_SIZE    ),
    .RESET_CYCLES( RESET_CYCLES )
  ) i_xip_ctrl (
    .HCLK      ( clk_i          ),
    .HRESETn   ( rst_ni         ),
    .HSEL      ( ahbl_hsel      ),
    .HADDR     ( ahbl_haddr     ),
    .HTRANS    ( ahbl_htrans    ),
    .HWRITE    ( ahbl_hwrite    ),
    .HREADY    ( ahbl_hready    ),
    .HREADYOUT ( ahbl_hreadyout ),
    .HRDATA    ( ahbl_hrdata    ),
    .sck       ( spi_sck        ),
    .ce_n      ( spi_csn        ),
    .din       ( spi_din        ),
    .dout      ( spi_dout       ),
    .douten    ( spi_douten     )
  );

  // -------------------------------------------------------------------------
  // OBI → AHBL state machine (greyhound-style: no config registers)
  // -------------------------------------------------------------------------
  typedef enum logic [1:0] { IDLE, XIP_FETCH, XIP_RESP } state_e;

  state_e      state_q, state_d;
  logic  [7:0] tid_q;       // captured transaction ID (OBI rid must echo aid)
  logic [31:0] rdata_q;     // captured AHBL read data

  always_comb begin
    state_d     = state_q;
    ahbl_hsel   = 1'b0;
    ahbl_haddr  = '0;
    ahbl_htrans = 2'b00; // IDLE
    ahbl_hwrite = 1'b0;
    ahbl_hready = 1'b1;

    obi_rsp_o         = '0;
    obi_rsp_o.r.rid   = tid_q;
    obi_rsp_o.r.rdata = rdata_q;

    case (state_q)
      IDLE: begin
        if (obi_req_i.req) begin
          obi_rsp_o.gnt = 1'b1;
          ahbl_hsel     = 1'b1;
          ahbl_haddr    = obi_req_i.a.addr;
          ahbl_htrans   = 2'b10; // NONSEQ
          ahbl_hwrite   = 1'b0;
          state_d       = XIP_FETCH;
        end
      end

      XIP_FETCH: begin
        // Wait for the flash controller to finish the cache lookup / line fill.
        // HSEL is deasserted; the controller advances its FSM independently
        // after it latched the address in the previous cycle.
        if (ahbl_hreadyout) begin
          state_d = XIP_RESP;
        end
      end

      XIP_RESP: begin
        obi_rsp_o.rvalid  = 1'b1;
        obi_rsp_o.r.rdata = rdata_q;
        state_d           = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= IDLE;
      tid_q   <= '0;
      rdata_q <= '0;
    end else begin
      state_q <= state_d;
      if (state_q == IDLE && obi_req_i.req)
        tid_q <= 8'(obi_req_i.a.aid);
      if (state_q == XIP_FETCH && ahbl_hreadyout)
        rdata_q <= ahbl_hrdata;
    end
  end

  // -------------------------------------------------------------------------
  // GPIO: fixed compile-time pin assignments (constant bit-selects, no loop)
  // -------------------------------------------------------------------------
  always_comb begin
    gpio_out_o = '0;
    gpio_oen_o = '0;
    // SCK / CSN — always outputs
    gpio_out_o[SckPin] = spi_sck;       gpio_oen_o[SckPin] = 1'b1;
    gpio_out_o[CsnPin] = spi_csn;       gpio_oen_o[CsnPin] = 1'b1;
    // IO[0-3] — bidirectional (douten=1 during cmd/addr, 0 during data-in)
    gpio_out_o[Io0Pin] = spi_dout[0];   gpio_oen_o[Io0Pin] = spi_douten[0];
    gpio_out_o[Io1Pin] = spi_dout[1];   gpio_oen_o[Io1Pin] = spi_douten[1];
    gpio_out_o[Io2Pin] = spi_dout[2];   gpio_oen_o[Io2Pin] = spi_douten[2];
    gpio_out_o[Io3Pin] = spi_dout[3];   gpio_oen_o[Io3Pin] = spi_douten[3];
  end

  // SPI DIN from GPIO inputs — constant indexed, always connected
  assign spi_din[0] = gpio_in_sync_i[Io0Pin];
  assign spi_din[1] = gpio_in_sync_i[Io1Pin];
  assign spi_din[2] = gpio_in_sync_i[Io2Pin];
  assign spi_din[3] = gpio_in_sync_i[Io3Pin];

endmodule
