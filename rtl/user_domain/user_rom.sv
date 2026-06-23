// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Authors:
// - Cyril Koenig <cykoenig@iis.ee.ethz.ch>
// - Enrico Zelioli <ezelioli@iis.ee.ethz.ch>

// Simple ROM
module user_rom #(
  // The OBI configuration for all ports
  parameter obi_pkg::obi_cfg_t ObiCfg    = obi_pkg::ObiDefaultConfig,
  parameter type               obi_req_t = logic,
  parameter type               obi_rsp_t = logic
) (
  input  logic     clk_i,
  input  logic     rst_ni,
  input  obi_req_t obi_req_i,
  output obi_rsp_t obi_rsp_o
);

  // Define some registers to hold the requests fields
  logic req_d, req_q, req_q2;                           // Request valid
  logic we_d, we_q, we_q2;                              // Write enable
  logic [ObiCfg.AddrWidth-1:0] addr_d, addr_q, addr_q2; // Internal address of the word to read
  logic [ObiCfg.IdWidth-1:0] id_d, id_q, id_q2;         // Id of the request, must be same for the response

  // Signals used to create the response
  logic [ObiCfg.DataWidth-1:0] rsp_data; // Data field of the obi response
  logic rsp_err;                         // Error field of the obi response

  // Wire the registers holding the request
  assign req_d  = obi_req_i.req;
  assign id_d   = obi_req_i.a.aid;
  assign we_d   = obi_req_i.a.we;
  assign addr_d = obi_req_i.a.addr;

  // Flip-flops
  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (~rst_ni) begin
      req_q  <= '0;
      id_q   <= '0;
      we_q   <= '0;
      addr_q <= '0;
      req_q2  <= '0;
      id_q2   <= '0;
      we_q2   <= '0;
      addr_q2 <= '0;
    end else begin
      req_q  <= req_d;
      id_q   <= id_d;
      we_q   <= we_d;
      addr_q <= addr_d;
      req_q2  <= req_q;
      id_q2   <= id_q;
      we_q2   <= we_q;
      addr_q2 <= addr_q;
    end
  end

  // // Assign the OBI response data
  logic [6:0] word_addr;
  always_comb begin
    rsp_data = '0;
    rsp_err  = '0;
    word_addr = addr_q2[6:2];

    if(req_q2) begin
      if(~we_q2) begin
        case(word_addr)
          7'h00: rsp_data = 32'h4A; // 'J'
          7'h01: rsp_data = 32'h6F; // 'o'
          7'h02: rsp_data = 32'h6E; // 'n'
          7'h03: rsp_data = 32'h61; // 'a'
          7'h04: rsp_data = 32'h73; // 's'
          7'h05: rsp_data = 32'h20; // ' '
          7'h06: rsp_data = 32'h26; // '&'
          7'h07: rsp_data = 32'h20; // ' '
          7'h08: rsp_data = 32'h4D; // 'M'
          7'h09: rsp_data = 32'h65; // 'e'
          7'h0a: rsp_data = 32'h6C; // 'l'
          7'h0b: rsp_data = 32'h6F; // 'o'
          7'h0c: rsp_data = 32'h64; // 'd'
          7'h0d: rsp_data = 32'h69; // 'i'
          7'h0e: rsp_data = 32'h65; // 'e'
          7'h0f: rsp_data = 32'h2C; // ','
          7'h10: rsp_data = 32'h20; // ' '
          7'h11: rsp_data = 32'h56; // 'V'
          7'h12: rsp_data = 32'h4C; // 'L'
          7'h13: rsp_data = 32'h53; // 'S'
          7'h14: rsp_data = 32'h49; // 'I'
          7'h15: rsp_data = 32'h20; // ' '
          7'h16: rsp_data = 32'h32; // '2'
          7'h17: rsp_data = 32'h0D; // '\r'
          7'h18: rsp_data = 32'h0A; // '\n'
          7'h19: rsp_data = 32'h00; // '\0'
          default: rsp_data = 32'h0;
        endcase
      end else begin
        rsp_err = '1;
      end
    end
  end

  // Assign the OBI response signals
  // A channel
  assign obi_rsp_o.gnt = obi_req_i.req;
  // R channel
  assign obi_rsp_o.rvalid       = req_q2;
  assign obi_rsp_o.r.rdata      = rsp_data;
  assign obi_rsp_o.r.rid        = id_q2;
  assign obi_rsp_o.r.err        = rsp_err;
  assign obi_rsp_o.r.r_optional = '0;

endmodule