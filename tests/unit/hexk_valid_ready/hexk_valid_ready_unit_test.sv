// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_unit_test.sv
//
// SVUnit tests of the valid/ready agent with its interface, for words of 8 bits.
// One interface with a clock of 10 ns lives through all tests. A test builds the agents it
// needs on it, runs their build and connect phases by hand and starts run_phase of their
// drivers and monitors in threads that teardown ends. The side of the channel that no agent
// drives is driven by the test, between clock edges, through the inputs of the interface
// that a DUT would drive. An always block notes one character
// per rising edge, as a DUT would see the channel: "T" a transfer, "v" valid without ready,
// "r" ready without valid, "." neither, "_" reset; it also notes the word of every transfer.
// A test acts at falling edges and compares these notes, so the result does not depend on
// the order in which a simulator runs the threads of one time step.
// One interface is enough for an initiator and a responder, and Verilator 5.046 simulates
// one instance of an interface correctly. The tests of the protocol assertions run on the
// other simulators: assertions are not switched on in the Verilator build of the tests.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_valid_ready.

`include "svunit_defines.svh"

module hexk_valid_ready_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_delay_cfg;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_handshake_cycle_t;
   import hexk_uvm_pkg::HEXK_DELAY_NONE;
   import hexk_uvm_pkg::HEXK_DELAY_CONSTANT;
   import hexk_uvm_pkg::HEXK_DELAY_UNIFORM;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent;
   import hexk_valid_ready_pkg::hexk_valid_ready_agent_cfg;
   import hexk_valid_ready_pkg::hexk_valid_ready_item;
   import hexk_valid_ready_pkg::hexk_valid_ready_random_seq;
   import hexk_valid_ready_pkg::hexk_valid_ready_data_seq;
   import hexk_valid_ready_pkg::HEXK_VALID_READY_INITIATOR;
   import hexk_valid_ready_pkg::HEXK_VALID_READY_RESPONDER;
   `include "uvm_macros.svh"

   localparam int unsigned WIDTH = 8;

   // Number of items of the test with random delays on both sides, and the clock cycles it may take.
   localparam int unsigned RANDOM_ITEMS = 20;
   localparam int unsigned RANDOM_CYCLES = 400;

   typedef hexk_valid_ready_agent#(WIDTH) hexk_ut_agent_t;
   typedef hexk_valid_ready_agent_cfg#(WIDTH) hexk_ut_cfg_t;
   typedef hexk_valid_ready_item#(WIDTH) hexk_ut_item_t;
   typedef hexk_valid_ready_random_seq#(WIDTH) hexk_ut_random_seq_t;
   typedef hexk_valid_ready_data_seq#(WIDTH) hexk_ut_data_seq_t;

   // A delay cfg of a derived class, to see that a clone keeps the class.
   class hexk_ut_delay_cfg extends hexk_delay_cfg;
      `uvm_object_utils(hexk_ut_delay_cfg)

      function new(string cfg_name = "hexk_ut_delay_cfg");
         super.new(cfg_name);
      endfunction : new
   endclass : hexk_ut_delay_cfg

   // Sequence that sends two words and keeps both items, to look at them afterwards.
   class hexk_ut_pair_seq extends uvm_sequence #(hexk_ut_item_t);
      hexk_ut_item_t first;
      hexk_ut_item_t second;

      `uvm_object_utils(hexk_ut_pair_seq)

      function new(string seq_name = "hexk_ut_pair_seq");
         super.new(seq_name);
      endfunction : new

      task body();
         first              = hexk_ut_item_t::type_id::create("first");
         first.data         = 8'hA1;
         first.delay_cycles = 0;
         start_item(first);
         finish_item(first);
         second              = hexk_ut_item_t::type_id::create("second");
         second.data         = 8'hA2;
         second.delay_cycles = 0;
         start_item(second);
         finish_item(second);
      endtask : body
   endclass : hexk_ut_pair_seq

   string          name = "hexk_valid_ready_ut";
   svunit_testcase svunit_ut;

   logic           clk = 1'b0;
   logic           rst_n = 1'b1;

   always #5ns clk = !clk;

   hexk_valid_ready_if #(
       .DATA_WIDTH(WIDTH)
   ) vr_if (
       .clk  (clk),
       .rst_n(rst_n)
   );

   // What the test drives in place of a DUT; the channel follows it on the side that no agent drives.
   logic             hand_valid_value = 1'b0;
   logic             hand_ready_value = 1'b0;
   logic [WIDTH-1:0] hand_data_value = '0;

   assign vr_if.ext_valid = hand_valid_value;
   assign vr_if.ext_data  = hand_data_value;
   assign vr_if.ext_ready = hand_ready_value;

   hexk_report_catcher                             catcher;
   hexk_ut_cfg_t                                   initiator_cfg;
   hexk_ut_cfg_t                                   responder_cfg;
   hexk_ut_cfg_t                                   passive_cfg;
   hexk_ut_agent_t                                 initiator;
   hexk_ut_agent_t                                 responder;
   hexk_ut_agent_t                                 observer;
   uvm_tlm_analysis_fifo #(hexk_ut_item_t)         seen;
   // The records of cycle_ap of the initiator, for a subscriber next to the coverage of the agent.
   uvm_tlm_analysis_fifo #(hexk_handshake_cycle_t) cycles_seen;
   hexk_ut_pair_seq                                pair_seq;
   hexk_ut_data_seq_t                              data_seq;
   process                                         threads       [$];
   int unsigned                                    created;
   bit                                             seq_done;
   string                                          result;

   // What a DUT sees of the channel: one character per rising edge and the words of the transfers.
   bit                                             logging;
   string                                          wave;
   string                                          words;
   int unsigned                                    num_transfers;

   always @(posedge clk) begin
      if (logging) begin
         if (rst_n !== 1'b1) begin
            wave = {wave, "_"};
         end else if (vr_if.valid === 1'b1 && vr_if.ready === 1'b1) begin
            wave  = {wave, "T"};
            words = {words, $sformatf("%h ", vr_if.data)};
            num_transfers++;
         end else if (vr_if.valid === 1'b1) begin
            wave = {wave, "v"};
         end else if (vr_if.ready === 1'b1) begin
            wave = {wave, "r"};
         end else begin
            wave = {wave, "."};
         end
      end
   end

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   // Every test gets fresh cfgs on the interface of this module, without delays; it starts the agents itself.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_VALID_READY_CFG$", UVM_FATAL, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_COPY_TYPE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_VALID_READY_VALID_DROPPED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_VALID_READY_DATA_CHANGED$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_VALID_READY_UNKNOWN$", UVM_ERROR, "", 0, -1, UVM_INFO);
      initiator_cfg         = new_cfg("initiator_cfg");
      responder_cfg         = new_cfg("responder_cfg");
      passive_cfg           = new_cfg("passive_cfg");
      responder_cfg.role    = HEXK_VALID_READY_RESPONDER;
      passive_cfg.is_active = UVM_PASSIVE;
      initiator             = null;
      responder             = null;
      observer              = null;
      pair_seq              = null;
      data_seq              = null;
      seq_done              = 0;
      result                = "";
      // Tests act at falling edges; the notes start with the next rising edge.
      @(negedge clk);
      wave          = "";
      words         = "";
      num_transfers = 0;
      logging       = 1;
   endtask : setup

   // Ends the threads of the agents and leaves the channel idle and out of reset.
   // A reset comes first: it ends the threads that a driver has forked for the transfer that is going on, which
   // one tool does not end together with the thread of the driver.
   task automatic teardown();
      svunit_ut.teardown();
      logging = 0;
      rst_n   = 1'b0;
      #1ns;
      foreach (threads[i]) begin
         threads[i].kill();
      end
      threads.delete();
      rst_n = 1'b1;
      drive_idle_by_hand();
      @(negedge clk);
      vr_if.set_checks(1'b1);
      catcher.clear();
   endtask : teardown

   // Gives both sides of the channel back to the test, idle: an agent that starts takes its side over.
   task automatic drive_idle_by_hand();
      hand_valid_value <= 1'b0;
      hand_data_value  <= '0;
      hand_ready_value <= 1'b0;
      vr_if.set_driver(1'b1, 1'b0);
      vr_if.set_driver(1'b0, 1'b0);
   endtask : drive_idle_by_hand

   // A cfg on the interface of this module whose driver takes no delay from it.
   function automatic hexk_ut_cfg_t new_cfg(string cfg_name);
      hexk_ut_cfg_t cfg = hexk_ut_cfg_t::type_id::create(cfg_name);
      cfg.vif            = vr_if;
      cfg.delay_cfg.mode = HEXK_DELAY_NONE;
      return cfg;
   endfunction : new_cfg

   // Gives a cfg constant delays, or uniform ones of 0 to the value.
   function automatic void set_delay(hexk_ut_cfg_t cfg, string kind, int unsigned value);
      if (kind == "constant") begin
         cfg.delay_cfg.mode        = HEXK_DELAY_CONSTANT;
         cfg.delay_cfg.fixed_value = value;
      end else begin
         cfg.delay_cfg.mode = HEXK_DELAY_UNIFORM;
         cfg.delay_cfg.lo   = 0;
         cfg.delay_cfg.hi   = value;
      end
   endfunction : set_delay

   // Clears one of the switches of a cfg that are set by default.
   function automatic void clear_flag(hexk_ut_cfg_t cfg, string which);
      case (which)
         "idle_data_x": cfg.idle_data_x = 0;
         "has_checks":  cfg.has_checks = 0;
         default:       cfg.has_coverage = 0;
      endcase
   endfunction : clear_flag

   // Builds an agent with a cfg and runs its phases up to the start of simulation.
   function automatic hexk_ut_agent_t build_agent(hexk_ut_cfg_t cfg);
      hexk_ut_agent_t agent;
      created++;
      agent     = hexk_ut_agent_t::type_id::create($sformatf("ut_valid_ready_agent_%0d", created), null);
      agent.cfg = cfg;
      agent.build_phase(null);
      if (agent.mon == null) begin
         return agent;
      end
      agent.mon.connect_phase(null);
      if (agent.drv != null) begin
         agent.drv.connect_phase(null);
      end
      agent.connect_phase(null);
      if (agent.drv != null) begin
         agent.drv.seq_item_port.resolve_bindings();
      end
      agent.start_of_simulation_phase(null);
      return agent;
   endfunction : build_agent

   // Starts run_phase of the monitor and, if there is one, of the driver of an agent.
   // The ports of the monitor are resolved here, after the test connected its own subscribers to the agent:
   // the monitor writes through the ports of the agent, and resolving its ports resolves the whole chain.
   task automatic run_agent(hexk_ut_agent_t agent);
      process monitor_thread;
      process driver_thread;
      agent.mon.ap.resolve_bindings();
      agent.mon.cycle_ap.resolve_bindings();
      fork
         begin
            monitor_thread = process::self();
            agent.mon.run_phase(null);
         end
      join_none
      wait (monitor_thread != null);
      threads.push_back(monitor_thread);
      if (agent.drv != null) begin
         fork
            begin
               driver_thread = process::self();
               agent.drv.run_phase(null);
            end
         join_none
         wait (driver_thread != null);
         threads.push_back(driver_thread);
      end
   endtask : run_agent

   // Starts the initiator with its cfg; the words that its monitor sees go to the FIFO seen.
   task automatic start_initiator();
      initiator   = build_agent(initiator_cfg);
      seen        = new($sformatf("ut_valid_ready_seen_%0d", created), null);
      cycles_seen = new($sformatf("ut_valid_ready_cycles_%0d", created), null);
      initiator.ap.connect(seen.analysis_export);
      initiator.cycle_ap.connect(cycles_seen.analysis_export);
      run_agent(initiator);
   endtask : start_initiator

   // Starts the responder with its cfg.
   task automatic start_responder();
      responder = build_agent(responder_cfg);
      run_agent(responder);
   endtask : start_responder

   // Starts a passive agent; the words that its monitor sees go to the FIFO seen.
   task automatic start_observer();
      observer = build_agent(passive_cfg);
      seen     = new($sformatf("ut_valid_ready_seen_%0d", created), null);
      observer.ap.connect(seen.analysis_export);
      run_agent(observer);
   endtask : start_observer

   // Lets clock cycles pass; returns at a falling edge.
   task automatic step(int unsigned cycles = 1);
      repeat (cycles) begin
         @(negedge clk);
      end
   endtask : step

   // The test drives ready, between clock edges.
   task automatic hand_ready(bit value);
      hand_ready_value <= value;
   endtask : hand_ready

   // The test drives valid and data, between clock edges.
   task automatic hand_valid(logic value, logic [WIDTH-1:0] word = '0);
      hand_valid_value <= value;
      hand_data_value  <= word;
   endtask : hand_valid

   // Asserts (0) or releases (1) the reset, between clock edges.
   task automatic hand_reset(bit value);
      rst_n = value;
      // The drivers answer in this time step; the caller looks at the channel after it.
      #1ns;
   endtask : hand_reset

   // Asserts the reset and releases it again before the next rising edge of the clock.
   task automatic hand_reset_pulse();
      rst_n = 1'b0;
      #1ns;
      rst_n = 1'b1;
      #1ns;
   endtask : hand_reset_pulse

   // Calls receive() of the interface as a responder would, between two clock edges: "<word> <waited>" in result.
   task automatic receive_by_hand(int unsigned delay);
      logic        [WIDTH-1:0] word;
      int unsigned             waited;
      vr_if.set_driver(1'b0, 1'b1);
      vr_if.idle_responder();
      vr_if.receive(delay, word, waited);
      vr_if.idle_responder();
      result = $sformatf("%h %0d", word, waited);
   endtask : receive_by_hand

   // Starts a sequence that sends words, given in hexadecimal and separated by blanks, on an agent; it runs in
   // the background, and seq_done is 1 when it has ended. The members are assigned after a plain randomize().
   task automatic send(hexk_ut_agent_t agent, string hex_words, int delay_cycles = -1);
      string texts[$];
      data_seq = hexk_ut_data_seq_t::type_id::create("data_seq");
      if (data_seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      hexk_str::split(hex_words, texts, " ");
      foreach (texts[i]) begin
         data_seq.words.push_back(WIDTH'(texts[i].atohex()));
      end
      data_seq.delay_cycles = delay_cycles;
      seq_done              = 0;
      fork
         begin
            data_seq.start(agent.sqr);
            seq_done = 1;
         end
      join_none
   endtask : send

   // Starts the sequence that keeps its two items, in the background.
   task automatic send_pair();
      pair_seq = hexk_ut_pair_seq::type_id::create("pair_seq");
      seq_done = 0;
      fork
         begin
            pair_seq.start(initiator.sqr);
            seq_done = 1;
         end
      join_none
   endtask : send_pair

   // Sends RANDOM_ITEMS random words from the initiator to the responder and waits for the last transfer:
   // "<transfers> <the monitor saw the words of the channel> <clock cycles were enough>".
   task automatic run_random_traffic();
      hexk_ut_random_seq_t seq = hexk_ut_random_seq_t::type_id::create("seq");
      int unsigned cycles = 0;
      if (seq.randomize() != 1) begin
         result = "randomization failed";
         return;
      end
      seq.num_items = RANDOM_ITEMS;
      fork
         begin
            seq.start(initiator.sqr);
            seq_done = 1;
         end
      join_none
      while (!seq_done && cycles < RANDOM_CYCLES) begin
         step();
         cycles++;
      end
      step();
      result = $sformatf("%0d %0b %0b", num_transfers, seen_words(0) == words, seq_done);
   endtask : run_random_traffic

   // The words that the monitor behind the FIFO seen wrote so far, each followed by a blank and, with waits,
   // by the clock cycles it waited in parentheses; "-" when there is none.
   function automatic string seen_words(bit with_waits = 1);
      hexk_ut_item_t item;
      string text;
      while (seen.try_get(
          item
      )) begin
         text = {text, with_waits ? $sformatf("%h(%0d) ", item.data, item.wait_cycles) : $sformatf("%h ", item.data)};
      end
      return (text.len() == 0 && with_waits) ? "-" : text;
   endfunction : seen_words

   // Errors of the protocol assertions in this test, as "<valid dropped> <data changed> <unknown>".
   function automatic string protocol_errors();
      return $sformatf(
          "%0d %0d %0d",
          catcher.get_count(
              "^HEXK_VALID_READY_VALID_DROPPED$"
          ),
          catcher.get_count(
              "^HEXK_VALID_READY_DATA_CHANGED$"
          ),
          catcher.get_count(
              "^HEXK_VALID_READY_UNKNOWN$"
          )
      );
   endfunction : protocol_errors

   // "<is_busy> <busy_reason>" of an agent as a hexk_objectable.
   function automatic string busy(hexk_ut_agent_t agent);
      hexk_objectable member = agent;
      return $sformatf("%0d %s", member.is_busy(), member.busy_reason());
   endfunction : busy

   // What the last item of the data sequence holds: "<word> <wait_cycles> <aborted>".
   function automatic string last_item();
      return $sformatf("%h %0d %0b", data_seq.req.data, data_seq.req.wait_cycles, data_seq.req.aborted);
   endfunction : last_item

   // Builds an agent without a cfg, or with a cfg without an interface: "<fatals> <monitor created>".
   function automatic string build_without(string what);
      hexk_ut_cfg_t   broken = (what == "cfg") ? null : hexk_ut_cfg_t::type_id::create("broken");
      hexk_ut_agent_t agent = build_agent(broken);
      return $sformatf("%0d %0d", catcher.get_count("^HEXK_VALID_READY_CFG$", UVM_FATAL), agent.mon != null);
   endfunction : build_without

   // Builds an agent whose cfg is in uvm_config_db, and with assign_too a cfg assigned as well: "<fatals> <the
   // agent has the cfg of uvm_config_db> <the agent has the assigned cfg>".
   function automatic string build_from_config_db(bit assign_too);
      hexk_ut_cfg_t   from_db = new_cfg("from_db");
      hexk_ut_cfg_t   assigned = new_cfg("assigned");
      hexk_ut_agent_t agent;
      from_db.is_active  = UVM_PASSIVE;
      assigned.is_active = UVM_PASSIVE;
      // The agent that build_agent() creates next.
      uvm_config_db#(hexk_ut_cfg_t)::set(null, $sformatf("ut_valid_ready_agent_%0d", created + 1), "cfg", from_db);
      agent = build_agent(assign_too ? assigned : null);
      return $sformatf(
          "%0d %0d %0d",
          catcher.get_count(
              "^HEXK_VALID_READY_CFG$", UVM_FATAL
          ),
          agent.cfg == from_db,
          agent.cfg == assigned
      );
   endfunction : build_from_config_db

   // The records of cycle_ap of the initiator so far, as "<records> <in reset> <reset began> <transfers>".
   function automatic string cycle_records();
      hexk_handshake_cycle_t cycle;
      int unsigned           counts[4];
      while (cycles_seen.try_get(
          cycle
      )) begin
         counts[0]++;
         counts[1] += cycle.in_reset;
         counts[2] += cycle.reset_began;
         counts[3] += (!cycle.in_reset && cycle.valid && cycle.ready);
      end
      return $sformatf("%0d %0d %0d %0d", counts[0], counts[1], counts[2], counts[3]);
   endfunction : cycle_records

   // The ports of an agent that was only constructed: "<full name of ap> <full name of cycle_ap>", with the name of
   // the agent written as "agent".
   function automatic string ports_after_construction();
      hexk_ut_agent_t agent;
      string          names;
      created++;
      agent = hexk_ut_agent_t::type_id::create($sformatf("ut_valid_ready_agent_%0d", created), null);
      if (agent.ap == null || agent.cycle_ap == null) begin
         return "no ports";
      end
      names = {agent.ap.get_full_name(), " ", agent.cycle_ap.get_full_name()};
      return hexk_str::replace(names, agent.get_name(), "agent");
   endfunction : ports_after_construction

   // What an agent has built: "<driver> <sequencer> <monitor> <coverage>".
   function automatic string parts_of(hexk_ut_agent_t agent);
      return $sformatf("%0d %0d %0d %0d", agent.drv != null, agent.sqr != null, agent.mon != null, agent.cov != null);
   endfunction : parts_of

   // An item as text, and whether a copy compares equal before and after its word and after its timing changed.
   function automatic string item_texts();
      hexk_ut_item_t item = hexk_ut_item_t::type_id::create("item");
      hexk_ut_item_t copy;
      string texts[$];
      item.data = 8'h00;
      texts.push_back(item.convert2string());
      item.data         = 8'h5A;
      item.delay_cycles = 3;
      item.wait_cycles  = 2;
      item.aborted      = 1;
      texts.push_back(item.convert2string());
      void'($cast(copy, item.clone()));
      texts.push_back(copy.convert2string());
      copy.wait_cycles = 9;
      texts.push_back($sformatf("%0b", item.compare(copy)));
      copy.data = 8'h5B;
      texts.push_back($sformatf("%0b", item.compare(copy)));
      return hexk_str::join_str(texts, " | ");
   endfunction : item_texts

   // What a comparer like that of hexk_scoreboard noted when expected.compare(actual) found a difference; the lines
   // are joined with " | ".
   function automatic string miscompares(uvm_object expected, uvm_object actual);
      uvm_comparer comparer = new();
      comparer.show_max  = 0;
      comparer.verbosity = UVM_DEBUG;
      void'(expected.compare(actual, comparer));
      return hexk_str::replace(hexk_str::strip(comparer.miscompares), "\n", " | ");
   endfunction : miscompares

   // The type name of an object and its fields as the line printer shows them, from the opening brace on; the
   // instance number before it differs from run to run.
   function automatic string printed_fields(uvm_object object);
      uvm_line_printer printer = new();
      string           text = object.sprint(printer);
      return {object.get_type_name(), " ", hexk_str::strip(text.substr(hexk_str::find(text, "{"), text.len() - 1))};
   endfunction : printed_fields

   // An item as the printer shows it, and the text of a new item into which a packed copy of it was unpacked.
   function automatic string printed_and_unpacked();
      hexk_ut_item_t item = hexk_ut_item_t::type_id::create("item");
      hexk_ut_item_t unpacked = hexk_ut_item_t::type_id::create("unpacked");
      bit            bits                                                   [];
      item.data         = 8'h5A;
      item.delay_cycles = -2;
      item.wait_cycles  = 7;
      item.aborted      = 1;
      void'(item.pack(bits));
      void'(unpacked.unpack(bits));
      return {printed_fields(item), " | ", unpacked.convert2string()};
   endfunction : printed_and_unpacked

   // The difference of two items whose words differ, as the comparer notes it.
   function automatic string item_difference();
      hexk_ut_item_t expected = hexk_ut_item_t::type_id::create("expected");
      hexk_ut_item_t actual = hexk_ut_item_t::type_id::create("actual");
      expected.data = 8'h5A;
      actual.data   = 8'h5B;
      return miscompares(expected, actual);
   endfunction : item_difference

   // The delays of a cfg after a plain randomize(), and whether a clone has a delay_cfg of its own with the
   // same settings.
   function automatic string randomized_cfg();
      hexk_ut_cfg_t cfg = hexk_ut_cfg_t::type_id::create("cfg");
      hexk_ut_cfg_t copy;
      if (cfg.randomize() != 1) begin
         return "randomization failed";
      end
      cfg.delay_cfg.hi = 7;
      if (!$cast(copy, cfg.clone())) begin
         return "clone failed";
      end
      return $sformatf(
          "%s | %0b %0d", cfg.delay_cfg.convert2string(), copy.delay_cfg != cfg.delay_cfg, copy.delay_cfg.hi
      );
   endfunction : randomized_cfg

   // Clones of a cfg without a delay cfg and of one with a derived delay cfg, and a copy from an object of another
   // class: "<delay cfg of the first clone> <class of the delay cfg of the second> <copy errors> <text of the
   // first clone>".
   function automatic string nested_copies();
      hexk_ut_cfg_t     without = new_cfg("without");
      hexk_ut_cfg_t     derived = new_cfg("derived");
      hexk_ut_cfg_t     first;
      hexk_ut_cfg_t     second;
      hexk_ut_delay_cfg special = new("special");
      without.delay_cfg = null;
      derived.delay_cfg = special;
      if (!$cast(first, without.clone()) || !$cast(second, derived.clone())) begin
         return "clone failed";
      end
      second.copy(special);
      return $sformatf(
          "%s %s %0d %s",
          (first.delay_cfg == null) ? "null" : "set",
          second.delay_cfg.get_type_name(),
          catcher.get_count(
              "^HEXK_COPY_TYPE$"
          ),
          hexk_str::replace(
              first.convert2string(), "UVM_ACTIVE ", ""
          )
      );
   endfunction : nested_copies

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(an_initiator_without_delays_sends_back_to_back)
      hand_ready(1);
      start_initiator();
      send(initiator, "a1 a2 a3");
      step(6);
      `FAIL_UNLESS_STR_EQUAL(wave, "rTTTrr")
      `FAIL_UNLESS_STR_EQUAL(words, "a1 a2 a3 ")
      `FAIL_UNLESS_STR_EQUAL(seen_words(), "a1(0) a2(0) a3(0) ")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0b", seq_done), "1")
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 0")
   `SVTEST_END

   `SVTEST(the_delay_of_the_cfg_puts_gaps_before_valid)
      set_delay(initiator_cfg, "constant", 2);
      hand_ready(1);
      start_initiator();
      send(initiator, "b1 b2");
      step(8);
      `FAIL_UNLESS_STR_EQUAL(wave, "rrrTrrTr")
      `FAIL_UNLESS_STR_EQUAL(words, "b1 b2 ")
   `SVTEST_END

   `SVTEST(a_delay_of_an_item_replaces_the_delay_of_the_cfg)
      set_delay(initiator_cfg, "constant", 3);
      hand_ready(1);
      start_initiator();
      send(initiator, "c1 c2", 1);
      step(6);
      `FAIL_UNLESS_STR_EQUAL(wave, "rrTrTr")
   `SVTEST_END

   `SVTEST(valid_and_data_wait_for_ready)
      start_initiator();
      send(initiator, "b7");
      step(4);
      `FAIL_UNLESS_STR_EQUAL(busy(initiator),
         "1 the driver holds an item; valid has waited for ready for 3 clock cycles")
      hand_ready(1);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(wave, ".vvvTr")
      `FAIL_UNLESS_STR_EQUAL(seen_words(), "b7(3) ")
      `FAIL_UNLESS_STR_EQUAL(last_item(), "b7 3 0")
      `FAIL_UNLESS_STR_EQUAL(busy(initiator), "0 valid has waited for ready for 0 clock cycles")
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 0")
   `SVTEST_END

   `SVTEST(the_agent_is_busy_while_its_driver_holds_an_item_in_its_delay)
      hand_ready(1);
      start_initiator();
      send(initiator, "d1", 5);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(busy(initiator),
         "1 the driver holds an item; valid has waited for ready for 0 clock cycles")
      step(6);
      `FAIL_UNLESS_STR_EQUAL(seen_words(), "d1(0) ")
      `FAIL_UNLESS_STR_EQUAL(busy(initiator), "0 valid has waited for ready for 0 clock cycles")
   `SVTEST_END

   `SVTEST(without_idle_data_x_the_data_keeps_the_last_word)
      clear_flag(initiator_cfg, "idle_data_x");
      hand_ready(1);
      start_initiator();
      send(initiator, "c9");
      step(4);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %h", vr_if.valid, vr_if.data), "0 c9")
   `SVTEST_END

   // Variables have two states on Verilator: an X is a 0 there.
`ifndef VERILATOR
   `SVTEST(the_data_of_an_idle_initiator_is_x)
      hand_ready(1);
      start_initiator();
      send(initiator, "c9");
      step(4);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %h", vr_if.valid, vr_if.data), "0 xx")
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 0")
   `SVTEST_END
`endif

   `SVTEST(a_responder_without_delays_keeps_ready_high)
      start_responder();
      step(2);
      hand_valid(1, 8'hC3);
      step(1);
      hand_valid(0);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(wave, ".rTrr")
      `FAIL_UNLESS_STR_EQUAL(words, "c3 ")
   `SVTEST_END

   `SVTEST(the_delay_of_the_cfg_keeps_ready_low_before_every_transfer)
      set_delay(responder_cfg, "constant", 2);
      hand_valid(1, 8'hD1);
      start_responder();
      step(7);
      `FAIL_UNLESS_STR_EQUAL(wave, "vvvTvvT")
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 0")
   `SVTEST_END

   `SVTEST(an_item_of_a_responder_sets_one_delay_and_returns_the_word)
      set_delay(responder_cfg, "constant", 3);
      hand_valid(1, 8'hE5);
      start_responder();
      step(1);
      send(responder, "00", 1);
      step(10);
      `FAIL_UNLESS_STR_EQUAL(wave, "vvvvTvTvvvT")
      `FAIL_UNLESS_STR_EQUAL(last_item(), "e5 1 0")
   `SVTEST_END

   `SVTEST(an_initiator_and_a_responder_with_random_delays_move_every_word)
      set_delay(initiator_cfg, "uniform", 3);
      set_delay(responder_cfg, "uniform", 3);
      start_initiator();
      start_responder();
      run_random_traffic();
      `FAIL_UNLESS_STR_EQUAL(result, "20 1 1")
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 0")
   `SVTEST_END

   `SVTEST(a_reset_ends_the_item_of_an_initiator_and_the_next_one_follows_the_release)
      start_initiator();
      send_pair();
      step(2);
      hand_reset(0);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b", vr_if.valid), "0")
      step(2);
      hand_ready(1);
      hand_reset(1);
      step(3);
      `FAIL_UNLESS_STR_EQUAL(wave, ".v__rTr")
      `FAIL_UNLESS_STR_EQUAL(words, "a2 ")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0b %0b", pair_seq.first.aborted, pair_seq.second.aborted), "1 0")
      `FAIL_UNLESS_STR_EQUAL(seen_words(), "a2(0) ")
   `SVTEST_END

   `SVTEST(a_reset_takes_ready_back_and_the_responder_answers_again_after_it)
      start_responder();
      step(2);
      hand_reset(0);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b", vr_if.ready), "0")
      step(1);
      hand_reset(1);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(wave, ".r_.r")
   `SVTEST_END

   `SVTEST(a_reset_between_two_clock_edges_ends_the_wait_that_the_monitor_counts)
      start_observer();
      step(1);
      hand_valid(1, 8'h71);
      step(3);
      hand_reset_pulse();
      step(1);
      hand_ready(1);
      step(1);
      hand_valid(0);
      step(1);
      // Three edges before the reset and one after it: the item counts the one after it.
      `FAIL_UNLESS_STR_EQUAL(wave, ".vvvvTr")
      `FAIL_UNLESS_STR_EQUAL(seen_words(), "71(1) ")
   `SVTEST_END

   `SVTEST(a_responder_that_starts_between_two_edges_counts_the_edge_at_which_valid_waits)
      hand_valid(1, 8'hE5);
      step(1);
      receive_by_hand(0);
      `FAIL_UNLESS_STR_EQUAL(result, "e5 1")
      step(1);
      receive_by_hand(2);
      `FAIL_UNLESS_STR_EQUAL(result, "e5 3")
   `SVTEST_END

   `SVTEST(a_passive_agent_has_a_monitor_only_and_sees_every_transfer)
      hand_ready(1);
      start_observer();
      `FAIL_UNLESS_STR_EQUAL(parts_of(observer), "0 0 1 1")
      step(1);
      hand_valid(1, 8'h71);
      step(1);
      hand_valid(1, 8'h72);
      step(1);
      hand_valid(0);
      step(1);
      `FAIL_UNLESS_STR_EQUAL(seen_words(), "71(0) 72(0) ")
   `SVTEST_END

   `SVTEST(the_coverage_is_sampled_once_per_clock_cycle_out_of_reset)
      start_initiator();
      `FAIL_UNLESS_STR_EQUAL(parts_of(initiator), "1 1 1 1")
      step(3);
      hand_reset(0);
      step(2);
      hand_reset(1);
      step(2);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", initiator.cov.num_samples()), "5")
   `SVTEST_END

   `SVTEST(a_second_subscriber_of_cycle_ap_gets_every_rising_edge_next_to_the_coverage)
      start_initiator();
      send(initiator, "b1");
      hand_ready(1);
      step(3);
      hand_reset(0);
      step(2);
      hand_reset(1);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(cycle_records(), "7 2 1 1")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", initiator.cov.num_samples()), "5")
   `SVTEST_END

   `SVTEST(the_ports_belong_to_the_agent_from_its_construction)
      `FAIL_UNLESS_STR_EQUAL(ports_after_construction(), "agent.ap agent.cycle_ap")
   `SVTEST_END

   `SVTEST(without_has_coverage_the_agent_has_no_coverage_component)
      clear_flag(initiator_cfg, "has_coverage");
      start_initiator();
      `FAIL_UNLESS_STR_EQUAL(parts_of(initiator), "1 1 1 0")
      send(initiator, "a1");
      hand_ready(1);
      step(3);
      `FAIL_UNLESS_STR_EQUAL(words, "a1 ")
   `SVTEST_END

   // The assertions of the interface are not switched on in the Verilator build of the unit tests.
`ifndef VERILATOR
   `SVTEST(a_valid_that_is_taken_back_before_its_transfer_is_an_error)
      start_observer();
      hand_valid(1, 8'h11);
      step(2);
      hand_valid(0, 8'h11);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "1 0 0")
   `SVTEST_END

   `SVTEST(data_that_changes_while_valid_waits_is_an_error)
      start_observer();
      hand_valid(1, 8'h22);
      step(2);
      hand_valid(1, 8'h33);
      step(2);
      hand_ready(1);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 1 0")
   `SVTEST_END

   `SVTEST(an_unknown_valid_is_an_error_in_every_clock_cycle)
      start_observer();
      hand_valid(1'bx);
      step(2);
      hand_valid(0);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 2")
   `SVTEST_END

   `SVTEST(without_has_checks_the_assertions_are_off)
      clear_flag(passive_cfg, "has_checks");
      start_observer();
      hand_valid(1, 8'h11);
      step(2);
      hand_valid(0, 8'h11);
      step(2);
      `FAIL_UNLESS_STR_EQUAL(protocol_errors(), "0 0 0")
   `SVTEST_END
`endif

   `SVTEST(an_agent_without_a_cfg_or_an_interface_is_a_fatal)
      `FAIL_UNLESS_STR_EQUAL(build_without("cfg"), "1 0")
      `FAIL_UNLESS_STR_EQUAL(build_without("vif"), "2 0")
   `SVTEST_END

   `SVTEST(an_agent_takes_an_assigned_cfg_first_and_else_that_of_the_config_db)
      `FAIL_UNLESS_STR_EQUAL(build_from_config_db(0), "0 1 0")
      `FAIL_UNLESS_STR_EQUAL(build_from_config_db(1), "0 0 1")
   `SVTEST_END

   `SVTEST(an_item_prints_its_word_and_timing_and_compares_the_word)
      `FAIL_UNLESS_STR_EQUAL(item_texts(),
         {"data=0x0 delay_cycles=-1 wait_cycles=0 | data=0x5a delay_cycles=3 wait_cycles=2 aborted | ",
          "data=0x5a delay_cycles=3 wait_cycles=2 aborted | 1 | 0"})
   `SVTEST_END

   `SVTEST(an_item_prints_its_fields_and_unpacks_what_it_packed)
      `FAIL_UNLESS_STR_EQUAL(printed_and_unpacked(),
         {"hexk_valid_ready_item { data: 'h5a  delay_cycles: -2  wait_cycles: 'd7  aborted: 'b1  } | ",
          "data=0x5a delay_cycles=-2 wait_cycles=7 aborted"})
   `SVTEST_END

   `SVTEST(a_difference_of_two_items_names_the_field_data)
      `FAIL_UNLESS_STR_EQUAL(item_difference(), "expected.data: lhs = 'h5a : rhs = 'h5b")
   `SVTEST_END

   `SVTEST(convert2string_of_the_cfg_lists_the_settings)
      `FAIL_UNLESS_STR_EQUAL(responder_cfg.convert2string(),
         {"UVM_ACTIVE HEXK_VALID_READY_RESPONDER idle_data_x=1 has_checks=1 has_coverage=1 delays: ",
          "mode=HEXK_DELAY_NONE"})
   `SVTEST_END

   // Constrained randomization on Verilator needs an external SMT solver (z3) on the PATH.
   `SVTEST(a_clone_keeps_a_missing_or_derived_delay_cfg_and_a_copy_from_another_class_is_an_error)
      `FAIL_UNLESS_STR_EQUAL(nested_copies(),
         {"null hexk_ut_delay_cfg 1 HEXK_VALID_READY_INITIATOR idle_data_x=1 has_checks=1 has_coverage=1 ",
          "delays: none"})
   `SVTEST_END

   `SVTEST(a_plain_randomize_keeps_the_default_delays_and_a_clone_has_its_own_delay_cfg)
      `FAIL_UNLESS_STR_EQUAL(randomized_cfg(), "mode=HEXK_DELAY_UNIFORM lo=0 hi=7 | 1 7")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_valid_ready_unit_test
