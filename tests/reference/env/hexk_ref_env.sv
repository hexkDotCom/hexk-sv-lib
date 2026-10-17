// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_env.sv
//
// Environment of the reference testbench. The clock and reset agent drives clock and reset; the
// valid/ready agent sends the words; the bus agent carries the register accesses of hexk_csr_util
// through the register model, which is predicted from the bus monitor. The predictor turns what
// the monitors saw into expected results and commits; result_sb compares the packet results that
// the test collects, commit_sb every code word at the edge at which the DUT commits it. At every
// reset the predictor and both scoreboards forget what was in flight (guide rule CHK-6). The
// monitor of the clock and reset agent checks the period of the clock (check_period of its cfg).

`ifndef HEXK_REF_ENV_SV
`define HEXK_REF_ENV_SV

// The environment: agents, register model, predictor, models, checkers and scoreboards, connected.
class hexk_ref_env extends uvm_env;

   // Configuration; assigned by the test before the build phase.
   hexk_ref_env_cfg                        cfg;

   // From the test (hexk_base_test): the objection aggregator and the watchdog.
   hexk_objection_aggregator               aggregator;
   hexk_watchdog                           watchdog;

   // The agents: clock and reset, the input channel of the DUT, the register bus.
   hexk_clk_rst_agent                      clk_rst_agent;
   hexk_valid_ready_agent #(32)            in_agent;
   hexk_ref_bus_agent                      bus_agent;

   // The register model, kept up to date from the bus monitor by reg_predictor (the predictor of UVM's
   // register layer), and csr, through which the tests and sequences access the registers.
   hexk_ref_regs                           regs;
   uvm_reg_predictor #(hexk_ref_bus_item)  reg_predictor;
   hexk_csr_util                           csr;

   // The reference model of the DUT, and the scoreboards that compare the DUT with it: packet results, and
   // the code words that the DUT commits to its RAM.
   hexk_ref_predictor                      predictor;
   hexk_ref_result_sb                      result_sb;
   hexk_scoreboard #(hexk_ref_commit_item) commit_sb;

   // What can be busy, in two groups: drained, the input agent and the predictor (every word sent is accepted and
   // committed); quiet, those and the register accesses (nothing is in flight, so a reset loses nothing). A result
   // that the test has not collected yet is left out on purpose.
   hexk_busy_group                         drained;
   hexk_busy_group                         quiet;

   // Packets and words that the sequences sent; the tests compare them with what the scoreboards matched.
   int unsigned                            packets_sent;
   int unsigned                            words_sent;

   `uvm_component_utils(hexk_ref_env)

   // Creates the environment; the children are created in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: creates the agents, the register model, the models and the scoreboards.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null) begin
         `uvm_fatal("REF_ENV_CFG", "cfg is null; the test assigns it before the build phase")
         return;
      end
      clk_rst_agent     = hexk_clk_rst_agent::type_id::create("clk_rst_agent", this);
      clk_rst_agent.cfg = cfg.clk_rst_cfg;
      in_agent          = hexk_valid_ready_agent#(32)::type_id::create("in_agent", this);
      in_agent.cfg      = cfg.in_cfg;
      bus_agent         = hexk_ref_bus_agent::type_id::create("bus_agent", this);
      bus_agent.cfg     = cfg.bus_cfg;
      // A parent that has a register model of its own assigns it before the build phase (guide rule REG-2).
      if (regs == null) begin
         regs = hexk_ref_regs::type_id::create("regs", this);
         regs.build();
         regs.lock_model();
      end
      reg_predictor        = uvm_reg_predictor#(hexk_ref_bus_item)::type_id::create("reg_predictor", this);
      csr                  = hexk_csr_util::type_id::create("csr", this);
      csr.timeout_ps       = cfg.done_timeout_ps;
      csr.reporter         = this;
      predictor            = hexk_ref_predictor::type_id::create("predictor", this);
      predictor.watchdog   = watchdog;
      result_sb            = hexk_ref_result_sb::type_id::create("result_sb", this);
      result_sb.cfg        = cfg.result_sb_cfg;
      result_sb.aggregator = aggregator;
      commit_sb            = hexk_scoreboard#(hexk_ref_commit_item)::type_id::create("commit_sb", this);
      commit_sb.cfg        = cfg.commit_sb_cfg;
      commit_sb.aggregator = aggregator;
      drained              = hexk_busy_group::type_id::create("drained");
      quiet                = hexk_busy_group::type_id::create("quiet");
   endfunction : build_phase

   // UVM callback: connects monitors to models and scoreboards, the register model to the bus, and
   // registers what can keep the test busy.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      if (bus_agent.get_is_active() == UVM_ACTIVE) begin
         regs.default_map.set_sequencer(bus_agent.sqr, bus_agent.adapter);
      end
      regs.default_map.set_auto_predict(0);
      reg_predictor.map     = regs.default_map;
      reg_predictor.adapter = bus_agent.adapter;
      bus_agent.ap.connect(reg_predictor.bus_in);
      bus_agent.ap.connect(predictor.bus_export);
      in_agent.ap.connect(predictor.word_export);
      in_agent.cycle_ap.connect(predictor.cycle_export);
      predictor.result_ap.connect(result_sb.expected_export);
      predictor.commit_ap.connect(commit_sb.expected_export);
      bus_agent.commit_ap.connect(commit_sb.actual_export);
      hexk_eot_registry::get().register(predictor.mem, "the RAM model of the predictor");
      drained.register(in_agent, in_agent.get_full_name());
      drained.register(predictor, predictor.get_full_name());
      quiet.register(drained, "words in flight");
      quiet.register(csr, "register accesses");
      if (bus_agent.drv != null) begin
         quiet.register(bus_agent.drv, bus_agent.drv.get_full_name());
      end
      if (aggregator != null) begin
         aggregator.register(in_agent, in_agent.get_full_name());
         aggregator.register(csr, "register accesses");
         if (bus_agent.drv != null) begin
            aggregator.register(bus_agent.drv, bus_agent.drv.get_full_name());
         end
         aggregator.register(predictor, predictor.get_full_name());
      end
   endfunction : connect_phase

   // UVM callback: the settings of the scoreboards, for the log.
   function void end_of_elaboration_phase(uvm_phase phase);
      super.end_of_elaboration_phase(phase);
      `uvm_info("REF_ENV_CFG", {
                "results: ", result_sb.cfg.convert2string(), "\ncommits: ", commit_sb.cfg.convert2string()}, UVM_MEDIUM)
   endfunction : end_of_elaboration_phase

   // ERR counts every correction the DUT made and every word it could not correct: it must be what the predictor
   // expects, so that an error that a read corrected unnoticed does not pass. The base test checks it after the
   // traffic of every test. A sequence that calls it gives itself as seq, the parent of the read.
   task check_error_counters(uvm_sequence_base seq = null);
      csr.read_check(regs.err, {16'd0, 8'(predictor.uncorrectable), 8'(predictor.corrected)}, "REF_ERR_COUNTS", '1,
                     seq);
   endtask : check_error_counters

   // UVM callback: a clock that was never checked is an error.
   function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      `hexk_check_ne(clk_rst_agent.mon.num_checked(), 0, "REF_CLOCK_CHECKED", "intervals of the clock checked")
   endfunction : check_phase

   // UVM callback: at every reset the predictor, both scoreboards and the register model forget what
   // was in flight; the RAM keeps its content, so the RAM model keeps its too.
   task run_phase(uvm_phase phase);
      super.run_phase(phase);
      forever begin
         clk_rst_agent.status.reset_asserted.wait_trigger();
         predictor.on_reset();
         result_sb.on_reset();
         commit_sb.on_reset();
         regs.reset();
      end
   endtask : run_phase

endclass : hexk_ref_env

`endif  // HEXK_REF_ENV_SV
