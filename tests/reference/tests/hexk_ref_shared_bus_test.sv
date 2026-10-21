// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_shared_bus_test.sv
//
// The environment below a parent that has the bus agent (guide CFG-8, REU-2): the cfg turns the
// bus agent of the environment off, and the test, standing for the parent, builds the agent
// itself and connects it as a parent would. Its ports go to bus_export and commit_export of the
// environment, its sequencer and adapter to the register map, its driver to the busy group quiet
// and to the objection aggregator. The scenario is the default random packets; every check of the
// environment must hold as with its own bus agent.

`ifndef HEXK_REF_SHARED_BUS_TEST_SV
`define HEXK_REF_SHARED_BUS_TEST_SV

class hexk_ref_shared_bus_test extends hexk_ref_base_test;

   // The bus agent of the parent, on the cfg of the environment's bus agent.
   hexk_ref_bus_agent shared_bus_agent;

   `uvm_component_utils(hexk_ref_shared_bus_test)

   // Creates the test.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: the bus agent of the parent, with the interface that the environment does not fetch.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `hexk_vif_get_or_fatal(hexk_ref_bus_if, "bus_vif", env_cfg.bus_cfg.vif)
      shared_bus_agent     = hexk_ref_bus_agent::type_id::create("shared_bus_agent", this);
      shared_bus_agent.cfg = env_cfg.bus_cfg;
   endfunction : build_phase

   // UVM callback: the bus agent of the parent connected to the environment.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      shared_bus_agent.ap.connect(env.bus_export);
      shared_bus_agent.commit_ap.connect(env.commit_export);
      env.regs.default_map.set_sequencer(shared_bus_agent.sqr, shared_bus_agent.adapter);
      env.quiet.register(shared_bus_agent.drv, shared_bus_agent.drv.get_full_name());
      objections.register(shared_bus_agent.drv, shared_bus_agent.drv.get_full_name());
   endfunction : connect_phase

   // UVM callback: the environment really ran without a bus agent of its own.
   function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      `hexk_check_eq(env.bus_agent == null, 1'b1, "REF_SHARED_BUS", "the environment built no bus agent")
   endfunction : check_phase

   // Hook of hexk_base_test: the environment builds no bus agent.
   virtual function void modify_randomized_cfg();
      super.modify_randomized_cfg();
      env_cfg.has_bus_agent = 0;
   endfunction : modify_randomized_cfg

endclass : hexk_ref_shared_bus_test

`endif  // HEXK_REF_SHARED_BUS_TEST_SV
