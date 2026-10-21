// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_agent_cfg.sv
//
// Configuration of the bus agent, in one object as the agents of the library have it: the mode,
// the bus, and how long the driver waits for ack. The environment's cfg creates it; the test
// gives it the interface, and the environment hands it to the agent before the build phase.

`ifndef HEXK_REF_BUS_AGENT_CFG_SV
`define HEXK_REF_BUS_AGENT_CFG_SV

class hexk_ref_bus_agent_cfg extends uvm_object;

   // UVM_ACTIVE drives the bus; UVM_PASSIVE has only the monitor and the adapter.
   uvm_active_passive_enum is_active       = UVM_ACTIVE;

   // The bus; mandatory.
   virtual hexk_ref_bus_if vif;

   // Longest wait of the driver for ack, in rising edges.
   int unsigned            max_wait_cycles = 50;

   `uvm_object_utils(hexk_ref_bus_agent_cfg)

   // Creates a cfg of an active agent.
   function new(string name = "hexk_ref_bus_agent_cfg");
      super.new(name);
   endfunction : new

   // UVM hook of copy() and clone(): copies every member; the copy shares the interface.
   function void do_copy(uvm_object rhs);
      hexk_ref_bus_agent_cfg other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("REF_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                               rhs.get_name(), rhs.get_type_name()))
         return;
      end
      is_active       = other.is_active;
      vif             = other.vif;
      max_wait_cycles = other.max_wait_cycles;
   endfunction : do_copy

   // UVM hook of compare(): compares every member; the interfaces must be the same.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_ref_bus_agent_cfg other;
      bit                    same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      same = 1;
      same &= comparer.compare_field_int("is_active", 64'(is_active), 64'(other.is_active), $bits(is_active));
      if (vif != other.vif) begin
         comparer.print_msg("vif: the two refer to different interfaces");
         same = 0;
      end
      same &= comparer.compare_field_int("max_wait_cycles", 64'(max_wait_cycles), 64'(other.max_wait_cycles), 32);
      return same;
   endfunction : do_compare

   // UVM hook of print() and sprint(): every member; the interface as set or null.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_string("is_active", is_active.name());
      printer.print_string("vif", (vif == null) ? "null" : "set");
      printer.print_field_int("max_wait_cycles", 64'(max_wait_cycles), 32, UVM_DEC);
   endfunction : do_print

   // The mode and the wait for ack, on one line.
   function string convert2string();
      return $sformatf("%s max_wait_cycles=%0d", is_active.name(), max_wait_cycles);
   endfunction : convert2string

endclass : hexk_ref_bus_agent_cfg

`endif  // HEXK_REF_BUS_AGENT_CFG_SV
