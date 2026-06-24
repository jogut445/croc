// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// OBI subordinate wrapper for EF_QSPI_XIP_CTRL_AHBL.
//
// Address map within the UserDesign OBI window (base = UserBaseAddr+0x1000):
//
//   [base + 0x000 .. base + 0xFFF]  —  SPI config registers  (addr[13] = 0)
//   [base + 0x1000 ..]              —  XiP flash reads        (addr[13] = 1)
//                                      (SpiXipFlashBase = UserBaseAddr+0x2000)
//
// Config register offsets (word-addressed):
//   0x00  SckPin  — SCK   GPIO pin index  (reset = SckPin parameter)
//   0x04  CsnPin  — CSN   GPIO pin index  (reset = CsnPin parameter)
//   0x08  Io0Pin  — IO[0] GPIO pin index  (reset = Io0Pin parameter)
//   0x0C  Io1Pin  — IO[1] GPIO pin index  (reset = Io1Pin parameter)
//   0x10  Io2Pin  — IO[2] GPIO pin index  (reset = Io2Pin parameter)
//   0x14  Io3Pin  — IO[3] GPIO pin index  (reset = Io3Pin parameter)
//
// The parameter values serve as hardware reset defaults so the controller
// works out-of-reset without any software configuration.

module spi_qspi_obi_wrap
  import croc_pkg::*;
#(
  parameter int unsigned GpioCount    = 16,
  parameter int unsigned NUM_LINES    = 16,
  parameter int unsigned LINE_SIZE    = 32,
  parameter int unsigned RESET_CYCLES = 999,
  parameter int unsigned DIN_DELAY    = 1,
  // Reset-value defaults for the config registers
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

  localparam int unsigned PinW = $clog2(GpioCount);

  // -------------------------------------------------------------------------
  // Config registers (software-writable pin assignments)
  // -------------------------------------------------------------------------
  logic [PinW-1:0] sck_pin_q, csn_pin_q;
  logic [PinW-1:0] io0_pin_q, io1_pin_q, io2_pin_q, io3_pin_q;

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
    .RESET_CYCLES( RESET_CYCLES ),
    .DIN_DELAY   ( DIN_DELAY    )
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
  // OBI state machine
  // -------------------------------------------------------------------------
  typedef enum logic [2:0] { IDLE, CFG_RESP, XIP_ADDR, XIP_FETCH, XIP_RESP } state_e;

  state_e      state_q, state_d;
  logic  [7:0] tid_q;
  logic [31:0] rdata_q;
  logic [31:0] xip_addr_q; // registered HADDR offset, breaks decode→cache-lookup path

  // Latched request fields for the config-register path
  logic        cfg_wr_q;
  logic [31:0] cfg_wdata_q;
  logic  [2:0] cfg_reg_q;    // word index (addr[4:2])

  // addr[13]=0 → config regs; addr[13]=1 → XiP
  logic cfg_sel;
  assign cfg_sel = !obi_req_i.a.addr[13];

  // Combinatorial config-register read (uses incoming address in IDLE)
  logic [31:0] cfg_rdata;
  always_comb begin
    case (obi_req_i.a.addr[4:2])
      3'd0:    cfg_rdata = 32'(sck_pin_q);
      3'd1:    cfg_rdata = 32'(csn_pin_q);
      3'd2:    cfg_rdata = 32'(io0_pin_q);
      3'd3:    cfg_rdata = 32'(io1_pin_q);
      3'd4:    cfg_rdata = 32'(io2_pin_q);
      3'd5:    cfg_rdata = 32'(io3_pin_q);
      default: cfg_rdata = '0;
    endcase
  end

  // State-machine combinatorial logic
  always_comb begin
    state_d     = state_q;
    ahbl_hsel   = 1'b0;
    ahbl_haddr  = '0;
    ahbl_htrans = 2'b00;
    ahbl_hwrite = 1'b0;
    ahbl_hready = ahbl_hreadyout;

    obi_rsp_o         = '0;
    obi_rsp_o.r.rid   = tid_q;
    obi_rsp_o.r.rdata = rdata_q;

    case (state_q)
      IDLE: begin
        if (obi_req_i.req) begin
          obi_rsp_o.gnt = 1'b1;
          if (cfg_sel) begin
            state_d = CFG_RESP;
          end else begin
            state_d = XIP_ADDR; // address latched this cycle; present to IP next cycle
          end
        end
      end

      XIP_ADDR: begin
        ahbl_hsel   = 1'b1;
        ahbl_haddr  = xip_addr_q;
        ahbl_htrans = 2'b10; // NONSEQ
        ahbl_hwrite = 1'b0;
        state_d     = XIP_FETCH;
      end

      CFG_RESP: begin
        obi_rsp_o.rvalid  = 1'b1;
        obi_rsp_o.r.rdata = rdata_q;
        state_d           = IDLE;
      end

      XIP_FETCH: begin
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

  // State-machine sequential logic
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q     <= IDLE;
      tid_q       <= '0;
      rdata_q     <= '0;
      xip_addr_q  <= '0;
      cfg_wr_q    <= '0;
      cfg_wdata_q <= '0;
      cfg_reg_q   <= '0;
    end else begin
      state_q <= state_d;

      if (state_q == IDLE && obi_req_i.req) begin
        tid_q <= 8'(obi_req_i.a.aid);
        if (cfg_sel) begin
          rdata_q     <= cfg_rdata;             // latch read data now (regs stable)
          cfg_wr_q    <= obi_req_i.a.we;
          cfg_wdata_q <= obi_req_i.a.wdata;
          cfg_reg_q   <= obi_req_i.a.addr[4:2];
        end else begin
          // Register the byte offset into the XIP window; this breaks the long
          // combinatorial path from instruction-decode → cache lookup.
          xip_addr_q <= obi_req_i.a.addr - (UserBaseAddr + 32'h0000_2000);
        end
      end

      if (state_q == XIP_FETCH && ahbl_hreadyout)
        rdata_q <= ahbl_hrdata;
    end
  end

  // Config register writes (committed one cycle after grant, in CFG_RESP)
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sck_pin_q <= PinW'(SckPin);
      csn_pin_q <= PinW'(CsnPin);
      io0_pin_q <= PinW'(Io0Pin);
      io1_pin_q <= PinW'(Io1Pin);
      io2_pin_q <= PinW'(Io2Pin);
      io3_pin_q <= PinW'(Io3Pin);
    end else if (state_q == CFG_RESP && cfg_wr_q) begin
      case (cfg_reg_q)
        3'd0: sck_pin_q <= PinW'(cfg_wdata_q);
        3'd1: csn_pin_q <= PinW'(cfg_wdata_q);
        3'd2: io0_pin_q <= PinW'(cfg_wdata_q);
        3'd3: io1_pin_q <= PinW'(cfg_wdata_q);
        3'd4: io2_pin_q <= PinW'(cfg_wdata_q);
        3'd5: io3_pin_q <= PinW'(cfg_wdata_q);
        default: ;
      endcase
    end
  end

  // -------------------------------------------------------------------------
  // GPIO: dynamic pin assignments from config registers
  // -------------------------------------------------------------------------
  always_comb begin
    gpio_out_o = '0;
    gpio_oen_o = '0;
    for (int i = 0; i < GpioCount; i++) begin
      if (i == int'(sck_pin_q)) begin gpio_out_o[i] = spi_sck;     gpio_oen_o[i] = 1'b1;          end
      if (i == int'(csn_pin_q)) begin gpio_out_o[i] = spi_csn;     gpio_oen_o[i] = 1'b1;          end
      if (i == int'(io0_pin_q)) begin gpio_out_o[i] = spi_dout[0]; gpio_oen_o[i] = spi_douten[0]; end
      if (i == int'(io1_pin_q)) begin gpio_out_o[i] = spi_dout[1]; gpio_oen_o[i] = spi_douten[1]; end
      if (i == int'(io2_pin_q)) begin gpio_out_o[i] = spi_dout[2]; gpio_oen_o[i] = spi_douten[2]; end
      if (i == int'(io3_pin_q)) begin gpio_out_o[i] = spi_dout[3]; gpio_oen_o[i] = spi_douten[3]; end
    end
  end

  // SPI DIN from GPIO inputs via registered pin selects
  assign spi_din[0] = gpio_in_sync_i[io0_pin_q];
  assign spi_din[1] = gpio_in_sync_i[io1_pin_q];
  assign spi_din[2] = gpio_in_sync_i[io2_pin_q];
  assign spi_din[3] = gpio_in_sync_i[io3_pin_q];

endmodule
