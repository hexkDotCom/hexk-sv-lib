// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_item.sv
//
// Item of the clock and reset agent: one thing the driver does to the reset or the clock,
// or one change of the reset that the monitor saw.
// The sequences of the agent fill it; a test rarely creates one itself. op selects which
// members count. All times are whole picoseconds.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    TRN-2 TRN-5
//! @emits     HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_ITEM_SV
`define HEXK_CLK_RST_ITEM_SV

class hexk_clk_rst_item extends uvm_sequence_item;

   // What the driver does.
   rand hexk_clk_rst_op_e op;

   // HEXK_CLK_RST_RESET: the reset is held for hold_cycles rising edges of the clock and then for hold_ps.
   // HEXK_CLK_RST_STOP: with hold_ps above 0 the clock starts again after that time.
   rand int unsigned      hold_cycles;
   rand longint unsigned  hold_ps;

   // HEXK_CLK_RST_RESET: 1 asserts the reset at the next rising edge of the clock, 0 at once.
   rand bit               sync_assert;

   // HEXK_CLK_RST_RESET: 1 releases the reset at a rising edge of the clock, 0 when the hold is over.
   rand bit               sync_release;

   // HEXK_CLK_RST_CLOCK: period, share of the high time and jitter of the clock; all three are applied.
   rand longint unsigned  period_ps;
   rand int unsigned      duty_percent;
   rand longint unsigned  jitter_ps;

   // Set by the monitor: 1 in the item of an assertion of the reset, 0 in the item of a release.
   bit                    reset_active;

   // Set by the monitor: the clock count at the change of the reset.
   longint unsigned       clk_count;

   // What a clock item must hold to be worth sending; the driver checks the rest.
   constraint clock_cstr {
      (op == HEXK_CLK_RST_CLOCK) ->
      (period_ps >= 2 && duty_percent inside {[1 : 99]});
   }

   `uvm_object_utils(hexk_clk_rst_item)

   // Creates an item that asks for a reset without a hold.
   function new(string name = "hexk_clk_rst_item");
      super.new(name);
   endfunction : new

   // The operation and the members it uses, on one line.
   function string convert2string();
      case (op)
         HEXK_CLK_RST_RESET: begin
            return $sformatf(
                "%s hold_cycles=%0d hold_ps=%0d sync_assert=%0b sync_release=%0b reset_active=%0b clk_count=%0d",
                op.name(),
                hold_cycles,
                hold_ps,
                sync_assert,
                sync_release,
                reset_active,
                clk_count
            );
         end
         HEXK_CLK_RST_CLOCK: begin
            return $sformatf("%s period_ps=%0d duty_percent=%0d jitter_ps=%0d", op.name(), period_ps, duty_percent,
                             jitter_ps);
         end
         HEXK_CLK_RST_STOP: return $sformatf("%s hold_ps=%0d", op.name(), hold_ps);
         default:           return op.name();
      endcase
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member.
   function void do_copy(uvm_object rhs);
      hexk_clk_rst_item other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      op           = other.op;
      hold_cycles  = other.hold_cycles;
      hold_ps      = other.hold_ps;
      sync_assert  = other.sync_assert;
      sync_release = other.sync_release;
      period_ps    = other.period_ps;
      duty_percent = other.duty_percent;
      jitter_ps    = other.jitter_ps;
      reset_active = other.reset_active;
      clk_count    = other.clk_count;
   endfunction : do_copy

   // UVM hook of compare(): the operation and what it asks for or reports; the clock count is not compared.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_clk_rst_item other;
      bit same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      // Through the comparer, so that a mismatch names the field.
      if (!comparer.compare_field_int("op", 64'(op), 64'(other.op), $bits(op))) begin
         return 0;
      end
      same = 1;
      case (op)
         HEXK_CLK_RST_RESET: begin
            same &= comparer.compare_field_int("hold_cycles", 64'(hold_cycles), 64'(other.hold_cycles), 32);
            same &= comparer.compare_field_int("hold_ps", hold_ps, other.hold_ps, 64);
            same &= comparer.compare_field_int("sync_assert", 64'(sync_assert), 64'(other.sync_assert), 1);
            same &= comparer.compare_field_int("sync_release", 64'(sync_release), 64'(other.sync_release), 1);
            same &= comparer.compare_field_int("reset_active", 64'(reset_active), 64'(other.reset_active), 1);
         end
         HEXK_CLK_RST_CLOCK: begin
            same &= comparer.compare_field_int("period_ps", period_ps, other.period_ps, 64);
            same &= comparer.compare_field_int("duty_percent", 64'(duty_percent), 64'(other.duty_percent), 32);
            same &= comparer.compare_field_int("jitter_ps", jitter_ps, other.jitter_ps, 64);
         end
         HEXK_CLK_RST_STOP: same &= comparer.compare_field_int("hold_ps", hold_ps, other.hold_ps, 64);
         default:           ;
      endcase
      return same;
   endfunction : do_compare

   // UVM hook of print() and sprint(): the operation and the members it uses, as convert2string() shows them.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_generic("op", "hexk_clk_rst_op_e", $bits(op), op.name());
      case (op)
         HEXK_CLK_RST_RESET: begin
            printer.print_field_int("hold_cycles", 64'(hold_cycles), 32, UVM_DEC);
            printer.print_field_int("hold_ps", hold_ps, 64, UVM_DEC);
            printer.print_field_int("sync_assert", 64'(sync_assert), 1, UVM_BIN);
            printer.print_field_int("sync_release", 64'(sync_release), 1, UVM_BIN);
            printer.print_field_int("reset_active", 64'(reset_active), 1, UVM_BIN);
            printer.print_field_int("clk_count", clk_count, 64, UVM_DEC);
         end
         HEXK_CLK_RST_CLOCK: begin
            printer.print_field_int("period_ps", period_ps, 64, UVM_DEC);
            printer.print_field_int("duty_percent", 64'(duty_percent), 32, UVM_DEC);
            printer.print_field_int("jitter_ps", jitter_ps, 64, UVM_DEC);
         end
         HEXK_CLK_RST_STOP: printer.print_field_int("hold_ps", hold_ps, 64, UVM_DEC);
         default:           ;
      endcase
   endfunction : do_print

   // UVM hook of pack(): every member, in the order of the declarations, whatever the operation uses.
   function void do_pack(uvm_packer packer);
      super.do_pack(packer);
      packer.pack_field_int(64'(op), $bits(op));
      packer.pack_field_int(64'(hold_cycles), 32);
      packer.pack_field_int(hold_ps, 64);
      packer.pack_field_int(64'(sync_assert), 1);
      packer.pack_field_int(64'(sync_release), 1);
      packer.pack_field_int(period_ps, 64);
      packer.pack_field_int(64'(duty_percent), 32);
      packer.pack_field_int(jitter_ps, 64);
      packer.pack_field_int(64'(reset_active), 1);
      packer.pack_field_int(clk_count, 64);
   endfunction : do_pack

   // UVM hook of unpack(): the members in the order in which do_pack() wrote them.
   function void do_unpack(uvm_packer packer);
      super.do_unpack(packer);
      op           = hexk_clk_rst_op_e'(packer.unpack_field_int($bits(op)));
      hold_cycles  = 32'(packer.unpack_field_int(32));
      hold_ps      = packer.unpack_field_int(64);
      sync_assert  = packer.unpack_field_int(1) [0];
      sync_release = packer.unpack_field_int(1) [0];
      period_ps    = packer.unpack_field_int(64);
      duty_percent = 32'(packer.unpack_field_int(32));
      jitter_ps    = packer.unpack_field_int(64);
      reset_active = packer.unpack_field_int(1) [0];
      clk_count    = packer.unpack_field_int(64);
   endfunction : do_unpack

endclass : hexk_clk_rst_item

`endif  // HEXK_CLK_RST_ITEM_SV
