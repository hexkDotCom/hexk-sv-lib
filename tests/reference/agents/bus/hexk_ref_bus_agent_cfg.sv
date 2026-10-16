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

   // The mode and the wait for ack, on one line.
   function string convert2string();
      return $sformatf("%s max_wait_cycles=%0d", is_active.name(), max_wait_cycles);
   endfunction : convert2string

endclass : hexk_ref_bus_agent_cfg

`endif  // HEXK_REF_BUS_AGENT_CFG_SV
