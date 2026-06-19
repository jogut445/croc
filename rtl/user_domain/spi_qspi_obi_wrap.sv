// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// OBI subordinate wrapper for EF_QSPI_XIP_CTRL_AHBL.
//
// Address map (within the UserDesign window, base = UserBaseAddr + 0x1000):
//   Offset 0x0000 – 0x0FFF  Config registers (addr[13:12] == 2'b01)
//     0x00  CFG_SCK_PIN  [PIN_W-1:0]  GPIO pin number for SPI clock
//     0x04  CFG_CSN_PIN  [PIN_W-1:0]  GPIO pin number for chip select (active-low)
//     0x08  CFG_IO0_PIN  [PIN_W-1:0]  GPIO pin number for SPI IO[0] (MOSI / quad D0)
//     0x0C  CFG_IO1_PIN  [PIN_W-1:0]  GPIO pin number for SPI IO[1] (MISO / quad D1)
//     0x10  CFG_IO2_PIN  [PIN_W-1:0]  GPIO pin number for SPI IO[2] (quad D2 / WP)
//     0x14  CFG_IO3_PIN  [PIN_W-1:0]  GPIO pin number for SPI IO[3] (quad D3 / HOLD)
//     0x18  CFG_CTRL     [0]          1 = SPI overrides selected GPIO pins
//   Offset 0x1000+           XiP execute-in-place reads (addr[13] == 1)
//
// GPIO behaviour: when CFG_CTRL[0]=1 the wrapper drives gpio_out_o / gpio_oen_o
// for the pins selected by CFG_*_PIN. Software must not configure the same pins
// in the core GPIO peripheral simultaneously.
// gpio_in_sync_i feeds the four IO pins back into the flash controller DIN bus.

module spi_qspi_obi_wrap
  import croc_pkg::*;
#(
  parameter int unsigned GpioCount    = 16,
  parameter int unsigned NUM_LINES    = 16,
  parameter int unsigned LINE_SIZE    = 32,
  parameter int unsigned RESET_CYCLES = 999
) (
  input  logic clk_i,
  input  logic rst_ni,

  // OBI subordinate port
  input  sbr_obi_req_t obi_req_i,
  output sbr_obi_rsp_t obi_rsp_o,

  // Synchronized GPIO inputs (used as SPI DIN based on CFG_IO*_PIN)
  input  logic [GpioCount-1:0] gpio_in_sync_i,
  // GPIO output values driven by SPI signals (valid when CFG_CTRL[0]=1)
  output logic [GpioCount-1:0] gpio_out_o,
  // GPIO output enables  (1 = drive output, 0 = high-Z / input)
  output logic [GpioCount-1:0] gpio_oen_o
);

  localparam int unsigned PIN_W = $clog2(GpioCount);

  // ---------------------------------------------------------------------------
  // Config registers
  // ---------------------------------------------------------------------------
  logic [PIN_W-1:0] cfg_sck_pin_q;
  logic [PIN_W-1:0] cfg_csn_pin_q;
  logic [PIN_W-1:0] cfg_io0_pin_q;
  logic [PIN_W-1:0] cfg_io1_pin_q;
  logic [PIN_W-1:0] cfg_io2_pin_q;
  logic [PIN_W-1:0] cfg_io3_pin_q;
  logic             cfg_enable_q;

  // ---------------------------------------------------------------------------
  // Raw SPI signals from AHBL wrapper
  // ---------------------------------------------------------------------------
  logic       spi_sck;
  logic       spi_csn;
  logic [3:0] spi_dout;
  logic [3:0] spi_douten;
  logic [3:0] spi_din;

  // ---------------------------------------------------------------------------
  // AHBL bridge to EF_QSPI_XIP_CTRL_AHBL
  // ---------------------------------------------------------------------------
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

  // ---------------------------------------------------------------------------
  // OBI state machine
  // ---------------------------------------------------------------------------
  // addr[13:12] == 2'b01  →  config register space (base offset 0x000–0xFFF)
  // otherwise             →  XiP flash access
  wire        addr_is_cfg = (obi_req_i.a.addr[13:12] == 2'b01);
  wire [2:0]  cfg_word    = obi_req_i.a.addr[4:2];

  typedef enum logic [1:0] {
    IDLE,
    CFG_RESP,
    XIP_FETCH,
    XIP_RESP
  } state_e;

  state_e state_q, state_d;

  logic [SbrObiCfg.IdWidth-1:0] tid_q;
  logic [31:0]                   cfg_rdata_q;

  // Config register read-data mux (combinational, uses current OBI address)
  logic [31:0] cfg_rdata;
  always_comb begin
    cfg_rdata = '0;
    case (cfg_word)
      3'd0: cfg_rdata[PIN_W-1:0] = cfg_sck_pin_q;
      3'd1: cfg_rdata[PIN_W-1:0] = cfg_csn_pin_q;
      3'd2: cfg_rdata[PIN_W-1:0] = cfg_io0_pin_q;
      3'd3: cfg_rdata[PIN_W-1:0] = cfg_io1_pin_q;
      3'd4: cfg_rdata[PIN_W-1:0] = cfg_io2_pin_q;
      3'd5: cfg_rdata[PIN_W-1:0] = cfg_io3_pin_q;
      3'd6: cfg_rdata[0]         = cfg_enable_q;
      default: cfg_rdata         = 32'hDEAD_BEEF;
    endcase
  end

  // Config register writes: accepted in IDLE alongside gnt
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cfg_sck_pin_q <= '0;
      cfg_csn_pin_q <= '0;
      cfg_io0_pin_q <= '0;
      cfg_io1_pin_q <= '0;
      cfg_io2_pin_q <= '0;
      cfg_io3_pin_q <= '0;
      cfg_enable_q  <= 1'b0;
    end else if (state_q == IDLE && obi_req_i.req && addr_is_cfg && obi_req_i.a.we) begin
      case (cfg_word)
        3'd0: cfg_sck_pin_q <= obi_req_i.a.wdata[PIN_W-1:0];
        3'd1: cfg_csn_pin_q <= obi_req_i.a.wdata[PIN_W-1:0];
        3'd2: cfg_io0_pin_q <= obi_req_i.a.wdata[PIN_W-1:0];
        3'd3: cfg_io1_pin_q <= obi_req_i.a.wdata[PIN_W-1:0];
        3'd4: cfg_io2_pin_q <= obi_req_i.a.wdata[PIN_W-1:0];
        3'd5: cfg_io3_pin_q <= obi_req_i.a.wdata[PIN_W-1:0];
        3'd6: cfg_enable_q  <= obi_req_i.a.wdata[0];
        default: ;
      endcase
    end
  end

  // Combinational state machine + OBI response
  always_comb begin
    state_d      = state_q;
    ahbl_hsel    = 1'b0;
    ahbl_haddr   = '0;
    ahbl_htrans  = 2'b00; // IDLE
    ahbl_hwrite  = 1'b0;
    ahbl_hready  = 1'b1;

    obi_rsp_o           = '0;
    obi_rsp_o.r.rid     = tid_q;
    obi_rsp_o.r.rdata   = cfg_rdata_q;

    case (state_q)
      IDLE: begin
        if (obi_req_i.req) begin
          obi_rsp_o.gnt = 1'b1;
          if (addr_is_cfg) begin
            // Config register access: accept and respond next cycle
            state_d = CFG_RESP;
          end else begin
            // XiP access: present address phase to AHBL wrapper
            ahbl_hsel   = 1'b1;
            ahbl_haddr  = obi_req_i.a.addr;
            ahbl_htrans = 2'b10; // NONSEQ
            ahbl_hwrite = 1'b0;
            ahbl_hready = 1'b1;
            state_d     = XIP_FETCH;
          end
        end
      end

      CFG_RESP: begin
        obi_rsp_o.rvalid  = 1'b1;
        obi_rsp_o.r.rdata = cfg_rdata_q;
        obi_rsp_o.r.err   = 1'b0;
        state_d = IDLE;
      end

      XIP_FETCH: begin
        // Wait for AHBL wrapper to complete the flash/cache lookup.
        // AHBL signals stay at defaults (HSEL=0, HTRANS=IDLE); the wrapper
        // advances its internal state independently of HSEL/HTRANS once the
        // address has been sampled.
        if (ahbl_hreadyout) begin
          state_d = XIP_RESP;
        end
      end

      XIP_RESP: begin
        obi_rsp_o.rvalid  = 1'b1;
        obi_rsp_o.r.rdata = ahbl_hrdata;
        obi_rsp_o.r.err   = 1'b0;
        state_d = IDLE;
      end

      default: state_d = IDLE;
    endcase
  end

  // Sequential: advance state and capture transaction metadata
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q      <= IDLE;
      tid_q        <= '0;
      cfg_rdata_q  <= '0;
    end else begin
      state_q <= state_d;
      if (state_q == IDLE && obi_req_i.req) begin
        tid_q       <= obi_req_i.a.aid;
        cfg_rdata_q <= cfg_rdata; // snapshot read data for CFG_RESP
      end
    end
  end

  // ---------------------------------------------------------------------------
  // SPI DIN: mux from GPIO inputs according to CFG_IO*_PIN
  // ---------------------------------------------------------------------------
  assign spi_din[0] = gpio_in_sync_i[cfg_io0_pin_q];
  assign spi_din[1] = gpio_in_sync_i[cfg_io1_pin_q];
  assign spi_din[2] = gpio_in_sync_i[cfg_io2_pin_q];
  assign spi_din[3] = gpio_in_sync_i[cfg_io3_pin_q];

  // ---------------------------------------------------------------------------
  // GPIO output mux: for each GPIO pin, check whether SPI has claimed it.
  // Priority order (highest first): SCK, CSN, IO0, IO1, IO2, IO3.
  // Software should assign distinct pins to avoid conflicts.
  // ---------------------------------------------------------------------------
  for (genvar g = 0; g < GpioCount; g++) begin : gen_gpio_mux
    always_comb begin
      gpio_out_o[g] = 1'b0;
      gpio_oen_o[g] = 1'b0;
      if (cfg_enable_q) begin
        if (PIN_W'(g) == cfg_sck_pin_q) begin
          gpio_out_o[g] = spi_sck;
          gpio_oen_o[g] = 1'b1;           // SCK is always an output
        end else if (PIN_W'(g) == cfg_csn_pin_q) begin
          gpio_out_o[g] = spi_csn;
          gpio_oen_o[g] = 1'b1;           // CSN is always an output
        end else if (PIN_W'(g) == cfg_io0_pin_q) begin
          gpio_out_o[g] = spi_dout[0];
          gpio_oen_o[g] = spi_douten[0];  // bidirectional: driven during cmd/addr
        end else if (PIN_W'(g) == cfg_io1_pin_q) begin
          gpio_out_o[g] = spi_dout[1];
          gpio_oen_o[g] = spi_douten[1];
        end else if (PIN_W'(g) == cfg_io2_pin_q) begin
          gpio_out_o[g] = spi_dout[2];
          gpio_oen_o[g] = spi_douten[2];
        end else if (PIN_W'(g) == cfg_io3_pin_q) begin
          gpio_out_o[g] = spi_dout[3];
          gpio_oen_o[g] = spi_douten[3];
        end
      end
    end
  end : gen_gpio_mux

endmodule
