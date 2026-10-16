// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_regs_vseq.sv
//
// The registers after reset and bit by bit, with hexk_csr_util: every readable field with a reset
// value against it, except the volatile ones, which the DUT changes by itself and which
// check_reset_values() leaves out by default (STATUS, IRQ, CRC, CYCLES, ERR, INJ_CTRL;
// hexk_ref_warm_reset_vseq checks them too, with include_volatile), then the bit-bash sequence of
// UVM, which leaves out what the starter excluded with hexk_csr_util::exclude().
// Before the bit bash, what it does not reach, with plain bus accesses: a register write changes
// only its enabled bytes (CTRL with byte 0 disabled keeps its value, INJ_LO takes only its enabled
// bytes), and an address outside the map reads 0 and changes nothing when written.

`ifndef HEXK_REF_REGS_VSEQ_SV
`define HEXK_REF_REGS_VSEQ_SV

class hexk_ref_regs_vseq extends hexk_ref_scenario_vseq;

   // Addresses outside the register map: after the last register, a hole before the RAM, the last one before it.
   localparam bit [8:0] UNMAPPED[3] = '{9'h03C, 9'h080, 9'h0FC};

   `uvm_object_utils(hexk_ref_regs_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_regs_vseq");
      super.new(name);
   endfunction : new

   // Reset values, byte enables, unmapped addresses, the reset values again, then the bit bash.
   task body();
      env.csr.check_reset_values(env.regs, 0, this);
      check_byte_enables();
      check_unmapped();
      env.csr.check_reset_values(env.regs, 0, this);
      env.csr.bit_bash(env.regs, this);
   endtask : body

   // A register write changes only its enabled bytes.
   task check_byte_enables();
      // All of CTRL is in byte 0: with byte 0 disabled the write changes nothing.
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, hexk_ref_regs::CTRL_OFFSET, 32'hFFFF_FFFF, 4'b1110);
      env.csr.read_check(env.regs.ctrl, 'h40, "REF_REG_STROBE", '1, this);
      // INJ_LO takes its bytes one by one.
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, hexk_ref_regs::INJ_LO_OFFSET, 32'hFFFF_FFFF, 4'b1111);
      hexk_ref_bus_seq::write(this, env.bus_agent.sqr, hexk_ref_regs::INJ_LO_OFFSET, 32'h1234_5678, 4'b0101);
      env.csr.read_check(env.regs.inj_lo, 32'hFF34_FF78, "REF_REG_STROBE", '1, this);
      env.csr.write(env.regs.inj_lo, 0, this);
   endtask : check_byte_enables

   // An address outside the map reads 0, and a write to it changes no register (the reset values are checked again
   // afterwards).
   task check_unmapped();
      logic [31:0] value;
      foreach (UNMAPPED[i]) begin
         hexk_ref_bus_seq::write(this, env.bus_agent.sqr, UNMAPPED[i], 32'hFFFF_FFFF);
         hexk_ref_bus_seq::read(this, env.bus_agent.sqr, UNMAPPED[i], value);
         `hexk_check_eq(value, 32'd0, "REF_REG_UNMAPPED", $sformatf("read of the unmapped address 'h%03h", UNMAPPED[i]))
      end
   endtask : check_unmapped

endclass : hexk_ref_regs_vseq

`endif  // HEXK_REF_REGS_VSEQ_SV
