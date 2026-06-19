// Copyright 2024 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Behavioral QSPI flash model for simulation.
//
// Supports:
//   - Software-reset commands 0x66 (RSTEN) and 0x99 (RST)
//   - 0xEB Quad IO Fast Read with continuous-read mode (mode byte A5)
//
// The model exposes separate SIO_in / SIO_out / SIO_oen ports instead of
// inout, so it works with both vsim and Verilator.  The testbench is
// responsible for the tristate merge.
//
// SIO outputs are driven OUTPUT_DELAY_NS after SCK falls, modelling the
// real-flash tV spec and ensuring correct capture through the SoC's 2-FF
// GPIO synchronizer.
//
// Memory can be loaded after time 0:
//   initial #1 $readmemh("file.hex", i_flash.memory);

`timescale 1ns/1ps

module spi_flash_model #(
  parameter int unsigned MEM_BYTES       = 1024 * 1024, // 1 MB
  parameter int          OUTPUT_DELAY_NS = 2             // tV: output valid after SCK fall
) (
  input  wire       SCK,
  input  wire       CSN,
  input  wire [3:0] SIO_in,  // driven by master (SoC) on SIO[3:0]
  output reg  [3:0] SIO_out, // our drive onto SIO[3:0]
  output reg        SIO_oen  // 1 = SIO_out is valid / driving
);

  // ---------------------------------------------------------------------------
  // Memory – byte-addressable, all-ones (erased) by default
  // ---------------------------------------------------------------------------
  reg [7:0] memory [0:MEM_BYTES-1];

  integer init_i;
  initial begin
    for (init_i = 0; init_i < MEM_BYTES; init_i = init_i + 1)
      memory[init_i] = 8'hFF;
  end

  // ---------------------------------------------------------------------------
  // State machine
  // ---------------------------------------------------------------------------
  typedef enum logic [2:0] {
    ST_IDLE,
    ST_CMD,    // 8-bit command, SPI single mode (SIO_in[0] only)
    ST_ADDR,   // 24-bit address, QUAD (6 nibbles, MSN first)
    ST_MODE,   // 8-bit mode byte, QUAD (2 nibbles)
    ST_DUMMY,  // 4 dummy QUAD clocks (master drives, we ignore)
    ST_DATA    // QUAD data output (we drive SIO_out)
  } state_e;

  state_e    state;
  reg        cont_read;   // continuous-read mode active (mode[5]=1 seen)

  reg [7:0]  cmd_sr;      // command shift register (SPI single)
  reg [3:0]  phase_cnt;   // nibble / bit counter within each phase
  reg [23:0] addr_r;      // latched byte address for this transaction
  reg [23:0] byte_ptr;    // pointer into memory for current nibble
  reg        hi_nibble;   // 1 = MSN, 0 = LSN of current output byte

  // ---------------------------------------------------------------------------
  // CSN rising: deselect
  // ---------------------------------------------------------------------------
  always @(posedge CSN) begin
    SIO_oen <= 1'b0;
    state   <= ST_IDLE;
  end

  // ---------------------------------------------------------------------------
  // CSN falling: begin transaction
  // ---------------------------------------------------------------------------
  always @(negedge CSN) begin
    phase_cnt <= 4'd0;
    cmd_sr    <= 8'd0;
    addr_r    <= 24'd0;
    state     <= cont_read ? ST_ADDR : ST_CMD;
  end

  // ---------------------------------------------------------------------------
  // SCK rising: shift in master data, advance state
  // ---------------------------------------------------------------------------
  always @(posedge SCK) begin
    if (!CSN) begin
      case (state)

        // --- 8-bit command byte, SPI single mode on SIO_in[0] ---
        ST_CMD: begin
          cmd_sr    <= {cmd_sr[6:0], SIO_in[0]};
          phase_cnt <= phase_cnt + 4'd1;
          if (phase_cnt == 4'd7) begin
            phase_cnt <= 4'd0;
            case ({cmd_sr[6:0], SIO_in[0]})
              8'hEB:   state <= ST_ADDR;  // Quad IO Fast Read
              8'h99: begin
                cont_read <= 1'b0;        // RST exits continuous-read mode
                state     <= ST_IDLE;
              end
              default: state <= ST_IDLE;  // 0x66 RSTEN and others: accept, wait for CSN
            endcase
          end
        end

        // --- 24-bit address, QUAD (6 nibbles, MSN first) ---
        ST_ADDR: begin
          addr_r    <= {addr_r[19:0], SIO_in[3:0]};
          phase_cnt <= phase_cnt + 4'd1;
          if (phase_cnt == 4'd5) begin   // 6 nibbles = 24 bits
            phase_cnt <= 4'd0;
            state     <= ST_MODE;
          end
        end

        // --- Mode byte, QUAD (2 nibbles) ---
        // Mode[5] = M5 = continuous-read bit; it lives in bit 1 of the first nibble
        // (mode = {nibble0[3:0], nibble1[3:0]}, mode[5] = nibble0[1])
        ST_MODE: begin
          if (phase_cnt == 4'd0)
            cont_read <= SIO_in[1];      // latch M5 from first mode nibble
          phase_cnt <= phase_cnt + 4'd1;
          if (phase_cnt == 4'd1) begin
            phase_cnt <= 4'd0;
            state     <= ST_DUMMY;
          end
        end

        // --- 4 dummy QUAD clocks ---
        ST_DUMMY: begin
          phase_cnt <= phase_cnt + 4'd1;
          if (phase_cnt == 4'd3) begin
            phase_cnt <= 4'd0;
            byte_ptr  <= addr_r;
            hi_nibble <= 1'b1;           // first output will be MSN
            state     <= ST_DATA;
          end
        end

        // --- Data phase: advance byte pointer between nibbles ---
        ST_DATA: begin
          if (!hi_nibble) begin
            // We just finished the LSN; move to the next byte
            byte_ptr  <= byte_ptr + 24'd1;
            hi_nibble <= 1'b1;
          end else begin
            hi_nibble <= 1'b0;
          end
        end

        default: ;
      endcase
    end
  end

  // ---------------------------------------------------------------------------
  // SCK falling: drive output nibble with OUTPUT_DELAY_NS tV delay
  // ---------------------------------------------------------------------------
  always @(negedge SCK) begin
    if (!CSN && state == ST_DATA) begin
      #OUTPUT_DELAY_NS;
      SIO_out <= hi_nibble ? memory[byte_ptr][7:4] : memory[byte_ptr][3:0];
      SIO_oen <= 1'b1;
    end else begin
      #OUTPUT_DELAY_NS;
      SIO_oen <= 1'b0;
    end
  end

endmodule
