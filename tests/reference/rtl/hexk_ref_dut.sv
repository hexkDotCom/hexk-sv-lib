// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_dut.sv
//
// DUT of the reference testbench: a packet store. Plain RTL that uses nothing of the library,
// so that the library checks it from outside and not itself.
//
// Words of 32 bits arrive on a valid/ready channel and are grouped into packets of CTRL.LEN
// words (1 to 16; 0 means 16). For every packet the DUT computes the CRC-32 of IEEE 802.3
// (reflected, init and final XOR 'hFFFF_FFFF) over the bytes of the words as received, byte 0
// (bits 7:0) of a word first. With CTRL.SCRAMBLE each word is XORed with {state, state} of a
// 16-bit Galois LFSR (taps 'hB400, bit i stands for x^(i+1); seeded 'hACE1 at the first word of
// a packet; it steps once before each word). Each word is stored at word address BASE + i (mod
// 64) of a RAM of 64 words, as a 39-bit SECDED code word: position 0 the overall parity, the
// check bits at the powers of two, the data bits in ascending order at the other positions.
//
// Timing: a word accepted at a rising edge is committed to the RAM three rising edges later,
// shown on the commit port during the cycle before that edge. IRQ.DONE is set at the edge after
// the last commit of a packet; CYCLES counts the rising edges after the one that accepted the
// first word, up to and including the one that sets DONE. irq is IRQ.DONE && CTRL.IRQ_EN.
// Reset (rst_n low, asynchronous assert): every register to its reset value below, partial packet
// and pipeline dropped; the RAM keeps its content. The RAM has no reset value: a word that nothing
// has written holds an unknown code word (X in simulation), and so do RAW_LO and RAW_HI for it.
//
// Registers (byte addresses; a 32-bit bus with byte strobes; a write to a read-only register
// does nothing; an unmapped address reads 0). Reset values in parentheses; bits not named are 0:
//   0x00 ID        RO  'h4845_5852
//   0x04 CTRL      RW  [0] EN, [1] SCRAMBLE, [2] IRQ_EN, [7:4] LEN ('h40: LEN 4, the rest 0)
//   0x08 BASE      RW  [5:0] word address of the next packet (0)
//   0x0C STATUS    RO  [0] BUSY, [15:8] PKT_COUNT (0)
//   0x10 IRQ       W1C [0] DONE (0)
//   0x14 CRC       RO  CRC of the last packet (0)
//   0x18 CYCLES    RO  [15:0] cycles of the last packet (0)
//   0x1C ERR       RO  [7:0] corrected, [15:8] uncorrectable decodes of MEM accesses, reads and
//                      writes alike (saturating at 255; 0)
//   0x20 DEBUG     RW  [0] CORRUPT_READ (bit 0 of MEM read data inverted after correction),
//                      [1] HANG (DONE is never set) (0)
//   0x24 INJ_LO    RW  bits 31:0 of an error mask for the next committed code word (0)
//   0x28 INJ_HI    RW  [6:0] bits 38:32 of that mask (0)
//   0x2C INJ_CTRL  RW  [0] ARM: the mask is XORed into the next committed code word, then ARM
//                      clears (0)
//   0x30 RAW_ADDR  RW  [5:0] (0)
//   0x34 RAW_LO    RO  bits 31:0 of the code word at RAW_ADDR (no reset value: the RAM's)
//   0x38 RAW_HI    RO  [6:0] bits 38:32 of that code word (no reset value: the RAM's)
//   0x100-0x1FC MEM RW the 64 words (no reset value). Every access decodes the stored code word
//                      and counts what it corrected or could not correct in ERR; a read returns
//                      the corrected data; a write merges its enabled bytes into it and stores
//                      the code word of the result.

`ifndef HEXK_REF_DUT_SV
`define HEXK_REF_DUT_SV

module hexk_ref_dut (
    input  logic        clk,
    input  logic        rst_n,
    // Input channel; ready_allow comes from the testbench and holds ready at 0 when it is 0.
    input  logic        in_valid,
    output logic        in_ready,
    input  logic [31:0] in_data,
    input  logic        ready_allow,
    // Register bus: a request is held until ack, which comes one cycle after the request is seen.
    input  logic        bus_req,
    input  logic        bus_we,
    input  logic [ 8:0] bus_addr,
    input  logic [31:0] bus_wdata,
    input  logic [ 3:0] bus_wstrb,
    output logic        bus_ack,
    output logic [31:0] bus_rdata,
    output logic        irq,
    // Commit port: the code word that the next rising edge writes to the RAM.
    output logic        commit,
    output logic [ 5:0] commit_addr,
    output logic [38:0] commit_code
);
   timeunit 1ns; timeprecision 1ps;

   localparam logic [31:0] ID_VALUE  = 32'h4845_5852;
   localparam logic [15:0] LFSR_TAPS = 16'hB400;
   localparam logic [15:0] LFSR_SEED = 16'hACE1;
   localparam logic [31:0] CRC_POLY  = 32'hEDB8_8320;

   // Registers.
   logic        en;
   logic        scramble;
   logic        irq_en;
   logic [ 3:0] len;
   logic [ 5:0] base;
   logic [ 7:0] pkt_count;
   logic        done;
   logic [31:0] crc_reg;
   logic [15:0] cycles_reg;
   logic [ 7:0] corr_count;
   logic [ 7:0] uncorr_count;
   logic        corrupt_read;
   logic        hang;
   logic [31:0] inj_lo;
   logic [ 6:0] inj_hi;
   logic        inj_arm;
   logic [ 5:0] raw_addr;

   logic [38:0] ram          [64];

   // Packet assembly at the input.
   logic [ 4:0] word_index;
   logic [ 5:0] word_addr;
   logic [15:0] lfsr;
   logic [31:0] crc_run;

   // Rising edges since the reset, and the count at the edge that accepted the first word of the packet
   // being received. Each word carries the start of its packet through the pipeline, so that packets
   // that follow each other closely each get their own CYCLES.
   logic [15:0] edge_count;
   logic [15:0] pkt_start;

   // Pipeline: stage 1 holds an accepted word, scrambled when CTRL.SCRAMBLE is set; stage 2 passes it on;
   // stage 3 holds its code word, which the RAM takes at the next edge.
   logic s1_valid, s2_valid, s3_valid;
   logic [31:0] s1_data, s2_data;
   logic [5:0] s1_addr, s2_addr, s3_addr;
   logic s1_last, s2_last, s3_last;
   logic [31:0] s3_crc, s2_crc, s1_crc;
   logic [15:0] s1_start, s2_start, s3_start;
   logic [38:0] s3_code;
   logic        done_next;
   logic [31:0] crc_next_done;
   logic [15:0] start_next_done;

   // CRC-32 of one byte added to a running CRC, reflected.
   function automatic logic [31:0] crc_byte(logic [31:0] crc, logic [7:0] data);
      logic [31:0] value = crc ^ {24'd0, data};
      for (int bit_i = 0; bit_i < 8; bit_i++) begin
         value = value[0] ? ((value >> 1) ^ CRC_POLY) : (value >> 1);
      end
      return value;
   endfunction : crc_byte

   // CRC-32 of the four bytes of a word, byte 0 first.
   function automatic logic [31:0] crc_word(logic [31:0] crc, logic [31:0] data);
      logic [31:0] value = crc;
      for (int byte_i = 0; byte_i < 4; byte_i++) begin
         value = crc_byte(value, data[8*byte_i+:8]);
      end
      return value;
   endfunction : crc_word

   // One step of the Galois LFSR: shift right; when a 1 was shifted out, XOR the taps in.
   function automatic logic [15:0] lfsr_step(logic [15:0] state);
      return state[0] ? ((state >> 1) ^ LFSR_TAPS) : (state >> 1);
   endfunction : lfsr_step

   // SECDED code word of 32 data bits.
   function automatic logic [38:0] ecc_encode(logic [31:0] data);
      logic [38:0] code = '0;
      int unsigned next_data = 0;
      for (int pos = 1; pos < 39; pos++) begin
         if ((pos & (pos - 1)) != 0) begin
            code[pos] = data[next_data];
            next_data++;
         end
      end
      for (int check = 0; check < 6; check++) begin
         logic parity = 1'b0;
         for (int pos = 1; pos < 39; pos++) begin
            if ((pos & (pos - 1)) != 0 && pos[check]) begin
               parity ^= code[pos];
            end
         end
         code[1<<check] = parity;
      end
      code[0] = ^code[38:1];
      return code;
   endfunction : ecc_encode

   // Decodes a code word: the corrected data; corrected or uncorrectable when an error was found.
   function automatic logic [31:0] ecc_decode(logic [38:0] code, output logic corrected, output logic uncorrectable);
      logic        [ 5:0] syndrome = '0;
      logic               parity = ^code;
      logic        [38:0] fixed = code;
      logic        [31:0] data = '0;
      int unsigned        next_data = 0;
      for (int pos = 1; pos < 39; pos++) begin
         if (code[pos]) begin
            syndrome ^= 6'(pos);
         end
      end
      corrected     = 1'b0;
      uncorrectable = 1'b0;
      if (parity) begin
         // One bit is wrong; the syndrome is its position, 0 for the overall parity bit.
         if (syndrome < 39) begin
            fixed[syndrome] = ~fixed[syndrome];
            corrected       = 1'b1;
         end else begin
            uncorrectable = 1'b1;
         end
      end else if (syndrome != 0) begin
         uncorrectable = 1'b1;
      end
      for (int pos = 1; pos < 39; pos++) begin
         if ((pos & (pos - 1)) != 0) begin
            data[next_data] = fixed[pos];
            next_data++;
         end
      end
      return data;
   endfunction : ecc_decode

   // Byte enables as a bit mask.
   function automatic logic [31:0] strobe_mask(logic [3:0] wstrb);
      return {{8{wstrb[3]}}, {8{wstrb[2]}}, {8{wstrb[1]}}, {8{wstrb[0]}}};
   endfunction : strobe_mask

   // Packet length in words: 1 to 16, the field value 0 means 16.
   function automatic logic [4:0] packet_len(logic [3:0] field);
      return (field == 0) ? 5'd16 : {1'b0, field};
   endfunction : packet_len

   assign in_ready = rst_n && en && ready_allow;
   assign irq = done && irq_en;
   assign commit = s3_valid;
   assign commit_addr = s3_addr;
   assign commit_code = s3_code ^ (inj_arm ? {inj_hi, inj_lo} : 39'd0);

   wire accept = in_valid && in_ready;

   // The LFSR state and the running CRC after the word on the input; a packet starts again at word 0.
   logic [15:0] lfsr_next;
   logic [31:0] crc_next;
   always_comb begin
      lfsr_next = lfsr_step((word_index == 0) ? LFSR_SEED : lfsr);
      crc_next  = crc_word((word_index == 0) ? 32'hFFFF_FFFF : crc_run, in_data);
   end

   // Input, packet assembly and the pipeline.
   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         word_index <= '0;
         word_addr  <= '0;
         lfsr       <= LFSR_SEED;
         crc_run    <= '1;
         edge_count <= '0;
         pkt_start  <= '0;
         s1_valid   <= 1'b0;
         s2_valid   <= 1'b0;
         s3_valid   <= 1'b0;
         done_next  <= 1'b0;
      end else begin
         edge_count <= edge_count + 16'd1;
         s1_valid   <= accept;
         if (accept) begin
            lfsr      <= lfsr_next;
            crc_run   <= crc_next;
            s1_data   <= scramble ? (in_data ^ {lfsr_next, lfsr_next}) : in_data;
            s1_addr   <= (word_index == 0) ? base : word_addr;
            word_addr <= ((word_index == 0) ? base : word_addr) + 6'd1;
            s1_crc    <= crc_next ^ 32'hFFFF_FFFF;
            s1_start  <= (word_index == 0) ? edge_count : pkt_start;
            if (word_index == 0) begin
               pkt_start <= edge_count;
            end
            if (word_index + 5'd1 == packet_len(len)) begin
               s1_last    <= 1'b1;
               word_index <= '0;
            end else begin
               s1_last    <= 1'b0;
               word_index <= word_index + 5'd1;
            end
         end
         s2_valid        <= s1_valid;
         s2_data         <= s1_data;
         s2_addr         <= s1_addr;
         s2_last         <= s1_valid && s1_last;
         s2_crc          <= s1_crc;
         s2_start        <= s1_start;
         s3_valid        <= s2_valid;
         s3_code         <= ecc_encode(s2_data);
         s3_addr         <= s2_addr;
         s3_last         <= s2_valid && s2_last;
         s3_crc          <= s2_crc;
         s3_start        <= s2_start;
         // The last commit of a packet: DONE follows at the next edge.
         done_next       <= s3_valid && s3_last;
         crc_next_done   <= s3_crc;
         start_next_done <= s3_start;
      end
   end

   // Registers and the bus. The access of the MEM window decodes and, for a write, encodes again.
   logic read_corrected, read_uncorrectable;
   logic [31:0] read_data;
   logic        mem_access;
   logic [ 5:0] mem_index;
   assign mem_access = bus_addr[8];
   assign mem_index  = bus_addr[7:2];
   // A function with output arguments may not drive a continuous assignment.
   always_comb read_data = ecc_decode(ram[mem_index], read_corrected, read_uncorrectable);

   always_ff @(posedge clk or negedge rst_n) begin
      if (!rst_n) begin
         en           <= 1'b0;
         scramble     <= 1'b0;
         irq_en       <= 1'b0;
         len          <= 4'd4;
         base         <= '0;
         pkt_count    <= '0;
         done         <= 1'b0;
         crc_reg      <= '0;
         cycles_reg   <= '0;
         corr_count   <= '0;
         uncorr_count <= '0;
         corrupt_read <= 1'b0;
         hang         <= 1'b0;
         inj_lo       <= '0;
         inj_hi       <= '0;
         inj_arm      <= 1'b0;
         raw_addr     <= '0;
         bus_ack      <= 1'b0;
         bus_rdata    <= '0;
      end else begin
         // The commit of the pipeline; a write of the bus to the same word in the same cycle comes after it.
         if (s3_valid) begin
            ram[s3_addr] <= commit_code;
            inj_arm      <= 1'b0;
         end
         if (done_next) begin
            pkt_count  <= pkt_count + 8'd1;
            crc_reg    <= crc_next_done;
            // The edges after the one that accepted the first word, up to and including this one.
            cycles_reg <= edge_count - start_next_done;
            if (!hang) begin
               done <= 1'b1;
            end
         end
         bus_ack <= 1'b0;
         if (bus_req && !bus_ack) begin
            bus_ack   <= 1'b1;
            bus_rdata <= '0;
            if (mem_access) begin
               if (read_corrected && corr_count != 8'hFF) begin
                  corr_count <= corr_count + 8'd1;
               end
               if (read_uncorrectable && uncorr_count != 8'hFF) begin
                  uncorr_count <= uncorr_count + 8'd1;
               end
               if (bus_we) begin
                  ram[mem_index] <=
                      ecc_encode((read_data & ~strobe_mask(bus_wstrb)) | (bus_wdata & strobe_mask(bus_wstrb)));
               end else begin
                  bus_rdata <= read_data ^ {31'd0, corrupt_read};
               end
            end else if (bus_we) begin
               write_register(bus_addr[7:0], bus_wdata & strobe_mask(bus_wstrb), strobe_mask(bus_wstrb));
            end else begin
               bus_rdata <= register_value(bus_addr[7:0]);
            end
         end
      end
   end

   // The value of a register for a read.
   function automatic logic [31:0] register_value(logic [7:0] addr);
      logic [38:0] raw = ram[raw_addr];
      case (addr)
         8'h00:   return ID_VALUE;
         8'h04:   return {24'd0, len, 1'b0, irq_en, scramble, en};
         8'h08:   return {26'd0, base};
         8'h0C:   return {16'd0, pkt_count, 7'd0, busy()};
         8'h10:   return {31'd0, done};
         8'h14:   return crc_reg;
         8'h18:   return {16'd0, cycles_reg};
         8'h1C:   return {16'd0, uncorr_count, corr_count};
         8'h20:   return {30'd0, hang, corrupt_read};
         8'h24:   return inj_lo;
         8'h28:   return {25'd0, inj_hi};
         8'h2C:   return {31'd0, inj_arm};
         8'h30:   return {26'd0, raw_addr};
         8'h34:   return raw[31:0];
         8'h38:   return {25'd0, raw[38:32]};
         default: return '0;
      endcase
   endfunction : register_value

   // 1 while a packet is being received or a word is in the pipeline.
   function automatic logic busy();
      return word_index != 0 || s1_valid || s2_valid || s3_valid || done_next;
   endfunction : busy

   // A register write; data holds the written bytes, mask says which bytes were written.
   task automatic write_register(logic [7:0] addr, logic [31:0] data, logic [31:0] mask);
      case (addr)
         8'h04: begin
            if (mask[0]) begin
               en       <= data[0];
               scramble <= data[1];
               irq_en   <= data[2];
               len      <= data[7:4];
            end
         end
         8'h08:   if (mask[0]) base <= data[5:0];
         8'h10:   if (mask[0] && data[0]) done <= 1'b0;
         8'h20: begin
            if (mask[0]) begin
               corrupt_read <= data[0];
               hang         <= data[1];
            end
         end
         8'h24:   inj_lo <= (inj_lo & ~mask) | data;
         8'h28:   if (mask[0]) inj_hi <= data[6:0];
         8'h2C:   if (mask[0]) inj_arm <= data[0];
         8'h30:   if (mask[0]) raw_addr <= data[5:0];
         default: ;
      endcase
   endtask : write_register

endmodule : hexk_ref_dut

`endif  // HEXK_REF_DUT_SV
