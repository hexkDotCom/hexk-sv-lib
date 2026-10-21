// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_base_test.sv
//
// Optional common base test: the level between uvm_test and the base test of a block. It
// sets up what every test of every block needs and nothing that belongs to one block:
// the report server, if the testbench top did not install it; the knobs, with the knobs
// perf_mode, coverage and hexk_require_checks; the objection aggregator, the end-of-test
// registry and the watchdog; phase objections that do not propagate; the check statistics
// in the log; and one last line, TEST PASSED or TEST FAILED, where passing needs no error, no
// failed check beyond those that hexk_check_stats::expect_failures() allowed (also when the
// message of the check was demoted or switched off) and, unless switched off, at least one
// executed check: a check macro, a comparison of a scoreboard, or what another checker counts
// with hexk_check_stats::record_pass() and record_fail().
// The verdict counts UVM reports and checks only: a $error or $fatal of a module, an interface,
// an assertion or the core package, and an error of the simulator, are not among them. A
// regression therefore also checks the log, as scripts/hexk_check_run.py does (guide TST-6).
// report_banner(), which hexk_tb_top_inc.svh calls when the simulation ends, prints the verdict in
// block letters: PASSED, FAILED, or ABORTED when the simulation ended before final_phase.
// Every test has a global report catcher (catcher); a negative test expects the errors of one
// component with a catcher of hexk_report_catcher::add_to(), and check_phase checks every
// catcher that the test did not check itself. Every test also has a warning audit (warnings) on
// the report server: with fail_on_warnings (or +hexk_fail_on_warnings=1), a warning that the test
// did not allow with allow_warning() is the error HEXK_TEST_WARNING in the report phase.
// Each policy can be switched in the constructor of a block base test: install_report_server
// keeps a report server of the project, stop_objection_propagation keeps the propagation of UVM,
// require_checks lets a test without counted checks pass, fail_on_warnings makes a clean log a
// condition of passing.
// A block base test extends it and overrides the hooks do_type_overrides(), define_knobs() and
// create_cfg(), which returns the cfg of the block; build_phase randomizes that cfg between the
// hooks modify_cfg() and modify_randomized_cfg() (guide CFG-10, TST-2). The block base test builds
// its env in its own build_phase after super.build_phase(). A test gives its stimulus in
// create_stimulus(), which main_phase randomizes and starts under one objection; main_phase returns
// when the stimulus has ended, and a derived test that extends it calls super.main_phase() first.
//
//! @module    hexk_base_test
//! @since     0.7.0
//! @stability experimental
//! @serves    TST-1 TST-2 TST-6 CFG-10 OBJ-5 OBJ-7 MSG-9
//! @emits     HEXK_TEST_RESULT:info HEXK_TEST_CHECKS:info HEXK_TEST_NO_CHECKS:error HEXK_TEST_CHECK_FAILED:error
//! @emits     HEXK_TEST_WARNING:error HEXK_TEST_RAND:fatal
//! @plusargs  +perf_mode +coverage +hexk_require_checks +hexk_fail_on_warnings

`ifndef HEXK_BASE_TEST_SV
`define HEXK_BASE_TEST_SV

class hexk_base_test extends uvm_test;

   // How the simulation of a test ended, for the banner of report_banner().
   typedef enum bit [1:0] {
      HEXK_TEST_PASSED,
      HEXK_TEST_FAILED,
      HEXK_TEST_ABORTED
   } verdict_e;

   // The knobs of the simulation; locked at the end of build_phase.
   hexk_knobs                  knobs;

   // Keeps the run-time phases alive while registered objects are busy.
   hexk_objection_aggregator   objections;

   // Runs the end-of-test checks of objects that are not components.
   hexk_eot_registry           eot_registry;

   // Ends a test that hangs; its limits can be set in build_phase of a derived test.
   hexk_watchdog               watchdog;

   // Global report catcher of the test, created in build_phase, for messages whose reporter does not matter; a negative
   // test expects an error of one component with a catcher of hexk_report_catcher::add_to(). check_phase checks both.
   hexk_report_catcher         catcher;

   // Collects the warnings that the test did not allow; on the report server from build_phase on.
   hexk_warning_audit          warnings;

   // The cfg of the block, as create_cfg() returned it; build_phase randomizes it between modify_cfg() and
   // modify_randomized_cfg(). null when the block base test creates none.
   uvm_object                  block_cfg;

   // When 1, a warning that the test did not allow with allow_warning() fails the test (HEXK_TEST_WARNING in
   // report_phase); +hexk_fail_on_warnings overrides it. Needs hexk_report_server.
   bit                         fail_on_warnings           = 0;

   // When 1, a test passes only if at least one check was executed; +hexk_require_checks overrides it.
   bit                         require_checks             = 1;

   // When 1, build_phase installs hexk_report_server unless it is installed already; 0 keeps any report server.
   bit                         install_report_server      = 1;

   // When 1, start_of_simulation_phase stops the objections of the run phase and of the run-time phases from
   // propagating up the hierarchy; 0 leaves the propagation of UVM as it is. Without propagation, the raised,
   // dropped and all_dropped callbacks and the objection counts of the components above the one that objects
   // see nothing: set 0 when the testbench relies on them (guide OBJ-5).
   bit                         stop_objection_propagation = 1;

   // The test of the simulation, recorded in its build_phase; null when no hexk_base_test was built.
   local static hexk_base_test started_test;

   // 1 when final_phase of started_test has run: without it, the simulation ended early and the test is aborted.
   local static bit            final_phase_reached;

   `uvm_component_utils(hexk_base_test)

   // Creates the test and its warning audit, so that allow_warning() works from the constructor on; everything else
   // happens in build_phase.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      warnings = new();
   endfunction : new

   // UVM callback: sets up report server, catcher, warning audit, knobs, aggregator, registry and watchdog, and calls
   // the hooks.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      started_test        = this;
      final_phase_reached = 0;
      do_type_overrides();
      if (install_report_server && hexk_report_server::get_installed() == null) begin
         hexk_report_cfg report_cfg = hexk_report_cfg::type_id::create("report_cfg");
         report_cfg.apply_plusargs();
         void'(hexk_report_server::install(report_cfg));
      end
      catcher = hexk_report_catcher::add_global();
      if (hexk_report_server::get_installed() != null) begin
         hexk_report_server::get_installed().add_listener(warnings);
      end
      knobs = hexk_knobs::get();
      if (!knobs.has("perf_mode")) begin
         knobs.add_bit("perf_mode", 0, "performance mode: every delay of the delay generators is 0");
      end
      if (!knobs.has("coverage")) begin
         knobs.add_bit("coverage", 1, "functional coverage: the covergroups of the library macro are created");
      end
      if (!knobs.has("hexk_require_checks")) begin
         knobs.add_bit("hexk_require_checks", require_checks, "a test passes only if at least one check was executed");
      end
      if (!knobs.has("hexk_fail_on_warnings")) begin
         knobs.add_bit("hexk_fail_on_warnings", fail_on_warnings, "a warning that the test did not allow fails it");
      end
      define_knobs();
      objections          = hexk_objection_aggregator::type_id::create("objections", this);
      watchdog            = hexk_watchdog::type_id::create("watchdog", this);
      watchdog.aggregator = objections;
      eot_registry        = hexk_eot_registry::get();
      knobs.lock();
      require_checks   = knobs.get_bit("hexk_require_checks");
      fail_on_warnings = knobs.get_bit("hexk_fail_on_warnings");
      if (fail_on_warnings && hexk_report_server::get_installed() == null) begin
         `uvm_error("HEXK_TEST_WARNING", "fail_on_warnings needs hexk_report_server, which is not installed")
      end
      block_cfg = create_cfg();
      modify_cfg();
      if (block_cfg != null) begin
         `hexk_randomize_or_fatal(block_cfg, "HEXK_TEST_RAND")
      end
      modify_randomized_cfg();
   endfunction : build_phase

   // UVM callback: stops the objections of the run-time phases from propagating up the hierarchy, unless
   // stop_objection_propagation is 0.
   function void start_of_simulation_phase(uvm_phase phase);
      uvm_domain common;
      uvm_domain runtime;
      super.start_of_simulation_phase(phase);
      common  = uvm_domain::get_common_domain();
      runtime = uvm_domain::get_uvm_domain();
      if (!stop_objection_propagation) begin
         return;
      end
      stop_propagation(common.find(uvm_run_phase::get()));
      stop_propagation(runtime.find(uvm_pre_reset_phase::get()));
      stop_propagation(runtime.find(uvm_reset_phase::get()));
      stop_propagation(runtime.find(uvm_post_reset_phase::get()));
      stop_propagation(runtime.find(uvm_pre_configure_phase::get()));
      stop_propagation(runtime.find(uvm_configure_phase::get()));
      stop_propagation(runtime.find(uvm_post_configure_phase::get()));
      stop_propagation(runtime.find(uvm_pre_main_phase::get()));
      stop_propagation(runtime.find(uvm_main_phase::get()));
      stop_propagation(runtime.find(uvm_post_main_phase::get()));
      stop_propagation(runtime.find(uvm_pre_shutdown_phase::get()));
      stop_propagation(runtime.find(uvm_shutdown_phase::get()));
      stop_propagation(runtime.find(uvm_post_shutdown_phase::get()));
   endfunction : start_of_simulation_phase

   // UVM callback: runs the stimulus of create_stimulus(), randomized, on stimulus_sequencer() under one objection, and
   // returns when it has ended; it returns at once without a stimulus. It is meant to be extended: a derived test with
   // a main_phase of its own calls super.main_phase() first, so that its own code runs after the stimulus (CMP-4).
   task main_phase(uvm_phase phase);
      uvm_sequence_base stimulus;
      super.main_phase(phase);
      stimulus = create_stimulus();
      if (stimulus == null) begin
         return;
      end
      phase.raise_objection(this, "stimulus of the test");
      `hexk_randomize_or_fatal(stimulus, "HEXK_TEST_RAND")
      stimulus.start(stimulus_sequencer());
      phase.drop_objection(this, "stimulus of the test done");
   endtask : main_phase

   // UVM callback: checks the expectations of the report catchers that nobody checked (guide MSG-9). The phase runs
   // bottom-up, so the check phases of the env, where scoreboards report their leftovers, came first.
   function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      hexk_report_catcher::check_unchecked();
   endfunction : check_phase

   // UVM callback: reports the warnings that the test did not allow and the statistics of the check macros.
   function void report_phase(uvm_phase phase);
      super.report_phase(phase);
      if (fail_on_warnings && warnings.num_unexpected() != 0) begin
         `uvm_error("HEXK_TEST_WARNING",
                    $sformatf("%0d warnings that the test did not allow (allow_warning() allows one by its ID):\n%s",
                              warnings.num_unexpected(), warnings.unexpected_text()))
      end
      `uvm_info("HEXK_TEST_CHECKS", {"\n", hexk_check_stats::summary()}, UVM_LOW)
   endfunction : report_phase

   // UVM callback: reports the last line of the test, TEST PASSED or TEST FAILED.
   function void final_phase(uvm_phase phase);
      super.final_phase(phase);
      if (num_errors() == 0 && require_checks && hexk_check_stats::num_checks() == 0) begin
         `uvm_error("HEXK_TEST_NO_CHECKS", {"no check was executed, so the test proved nothing; use the check macros, ",
                                            "or clear require_checks for a test that checks in another way"})
      end
      // A failed check whose error was demoted or switched off is still a failure, unless the test expected it.
      if (num_errors() == 0 && hexk_check_stats::num_unexpected_failures() != 0) begin
         `uvm_error("HEXK_TEST_CHECK_FAILED",
                    $sformatf(
                        "%0d checks failed although their messages counted no error; %s",
                        hexk_check_stats::num_unexpected_failures(),
                        "declare a failure that the test wants with expect_check(id, count) of hexk_report_catcher"))
      end
      `uvm_info("HEXK_TEST_RESULT", result_text(), UVM_NONE)
      if (started_test == this) begin
         final_phase_reached = 1;
      end
   endfunction : final_phase

   // Allows the warnings whose ID matches id_regex (as hexk_regex takes it; "^ID$" for one ID) with fail_on_warnings.
   function void allow_warning(string id_regex);
      warnings.allow(id_regex);
   endfunction : allow_warning

   // Hook: factory overrides of the test; called first in build_phase, before anything is created.
   virtual function void do_type_overrides();
   endfunction : do_type_overrides

   // Hook: knobs of the block or of the test; called in build_phase before the knobs are locked.
   virtual function void define_knobs();
   endfunction : define_knobs

   // Hook: creates the cfg of the block, through the factory, and returns it (null: no cfg); called after the factory
   // overrides and the knobs, so that an override of a derived test reaches the cfg. build_phase randomizes it.
   virtual function uvm_object create_cfg();
      return null;
   endfunction : create_cfg

   // Hook: changes to the cfg of the block before it is randomized, when knobs can be read. A test pins a rand knob
   // with rand_mode(0) and an assignment, or switches a constraint with constraint_mode(): a plain assignment to a
   // rand knob is overwritten by the randomization (guide CFG-10).
   virtual function void modify_cfg();
   endfunction : modify_cfg

   // Hook: changes to the cfg of the block after it was randomized, the last step of build_phase: plain assignments,
   // which no constraint checks, so only for values that no constraint relates to others.
   virtual function void modify_randomized_cfg();
   endfunction : modify_randomized_cfg

   // Hook: the stimulus of the test, created when main_phase starts (the env exists then); main_phase randomizes it
   // and starts it on stimulus_sequencer() under one objection. null, the default, starts nothing.
   virtual function uvm_sequence_base create_stimulus();
      return null;
   endfunction : create_stimulus

   // Hook: the sequencer that the stimulus starts on; null, the default, for a virtual sequence without a virtual
   // sequencer.
   virtual function uvm_sequencer_base stimulus_sequencer();
      return null;
   endfunction : stimulus_sequencer

   // 1 when there was no error or fatal so far, no failed check beyond the expected ones and, if require_checks is
   // set, at least one check was executed.
   function bit has_passed();
      return num_errors() == 0 && hexk_check_stats::num_unexpected_failures() == 0 &&
          (!require_checks || hexk_check_stats::num_checks() != 0);
   endfunction : has_passed

   // The last line of the test: "TEST PASSED" or "TEST FAILED" with the counts behind the verdict.
   function string result_text();
      return {has_passed() ? "TEST PASSED (" : "TEST FAILED (", counts_text(), ")"};
   endfunction : result_text

   // How the simulation of the test ended: 1 with the verdict when a hexk_base_test was built, else 0. ABORTED when
   // the simulation ended before final_phase of the test, as after a fatal or a $finish; otherwise PASSED or FAILED
   // as in the last line, by has_passed().
   static function bit get_verdict(output verdict_e verdict);
      verdict = HEXK_TEST_ABORTED;
      if (started_test == null) begin
         return 0;
      end
      if (final_phase_reached) begin
         verdict = started_test.has_passed() ? HEXK_TEST_PASSED : HEXK_TEST_FAILED;
      end
      return 1;
   endfunction : get_verdict

   // Prints the banner of the verdict with $display, after the last message: the verdict in block letters, then
   // "SIMULATION PASSED", "SIMULATION FAILED" or "SIMULATION FAILED - ABORTED" with the counts of the last line.
   // In colour, with a face picked at random, when the report server colours its messages (+hexk_report_color).
   // The final block of hexk_tb_top_inc.svh calls it; it prints nothing when no hexk_base_test was built.
   static function void report_banner();
      verdict_e          verdict;
      hexk_report_server server = hexk_report_server::get_installed();
      bit                color;
      if (!get_verdict(verdict)) begin
         return;
      end
      if (server != null) begin
         hexk_report_cfg report_cfg = server.get_cfg();
         color = report_cfg.color;
      end
      // MSG-1 waived: printed from a final block after the summary of UVM, where reporting has ended.
      $display("%s", banner_text(verdict, started_test.counts_text(), color, $urandom()));
   endfunction : report_banner

   // The banner of report_banner(): the verdict in block letters, then the line with counts, which are the counts of
   // the last line. With color, the letters are blocks in green or red, and face picks one of the faces of the
   // verdict (modulo their number) for the line before; without it, the letters are made of '#' and no face and
   // no escape code is printed.
   static function string banner_text(verdict_e verdict, string counts, bit color, int unsigned face = 0);
      string letters[$];
      string faces[$];
      string text;
      string verdict_line;
      // The two longest faces, each one string: Verilator 5.046 makes two elements of a queue out of a
      // concatenation of strings written as one element of the queue literal.
      string sunglasses = {
         "(\342\200\242_\342\200\242)\n( \342\200\242_\342\200\242)>\342\214\220\342\226\240-\342\226\240\n",
         "(\342\214\220\342\226\240_\342\226\240)"
      };
      string table_flip = {"(\342\225\257\302\260\342\226\241\302\260\357\274\211\342\225\257\357\270\265 ",
                           "\342\224\273\342\224\201\342\224\273"};
      case (verdict)
         HEXK_TEST_PASSED: begin
            letters = {
               "    ######   #####  ####### ####### ####### ######",
               "    ##   ## ##   ## ##      ##      ##      ##   ##",
               "    ######  ####### ####### ####### #####   ##   ##",
               "    ##      ##   ##      ##      ## ##      ##   ##",
               "    ##      ##   ## ####### ####### ####### ######"
            };
            faces = {
               sunglasses,
               "(\357\275\241\342\227\225\342\200\277\342\227\225\357\275\241)",
               "\312\230\342\200\277\312\230",
               "\342\231\245\342\200\277\342\231\245",
               "(\341\265\224\341\264\245\341\265\224)",
               "(\343\201\243\342\226\200\302\257\342\226\200)\343\201\244",
               "(\343\201\243\342\200\242\314\201\357\275\241\342\200\242\314\201)\342\231\252\342\231\254",
               "\342\212\202(\342\227\211\342\200\277\342\227\211)\343\201\244",
               "\342\230\272",
               "\342\234\214",
               "\360\237\230\215",
               "\360\237\206\222",
               "\360\237\221\214",
               "\360\237\221\215"
            };
            verdict_line = "SIMULATION PASSED";
         end
         HEXK_TEST_FAILED: begin
            letters = {
               "    #######  #####  ## ##      ####### ######",
               "    ##      ##   ## ## ##      ##      ##   ##",
               "    #####   ####### ## ##      #####   ##   ##",
               "    ##      ##   ## ## ##      ##      ##   ##",
               "    ##      ##   ## ## ####### ####### ######"
            };
            verdict_line = "SIMULATION FAILED";
         end
         default: begin
            letters = {
               "     #####  ######   ######  ######  ######## ####### ######",
               "    ##   ## ##   ## ##    ## ##   ##    ##    ##      ##   ##",
               "    ####### ######  ##    ## ######     ##    #####   ##   ##",
               "    ##   ## ##   ## ##    ## ##   ##    ##    ##      ##   ##",
               "    ##   ## ######   ######  ##   ##    ##    ####### ######"
            };
            verdict_line = "SIMULATION FAILED - ABORTED";
         end
      endcase
      if (verdict != HEXK_TEST_PASSED) begin
         faces = {
            "\302\257\\_(\343\203\204)_/\302\257",
            "\360\237\230\222",
            "\360\237\230\224",
            "\360\237\230\244",
            "\360\237\230\250",
            "\360\237\230\261",
            "\360\237\231\210",
            "\342\235\214",
            "\340\262\240_\340\262\240",
            "\342\212\231\357\271\217\342\212\231",
            "\343\203\237\342\227\217\357\271\217\342\230\211\343\203\237",
            "(\342\251\276\357\271\217\342\251\275)",
            "( \340\260\240 \315\237\312\226 \340\260\240 )",
            "(._.)",
            "\302\257\\(\302\260_o)/\302\257",
            "\302\257\\_(\342\212\231\357\270\277\342\212\231)_/\302\257",
            "( \340\260\240\340\265\240\340\260\240 )\357\276\211",
            table_flip,
            "\343\203\275\340\274\274 \340\262\240\347\233\212\340\262\240 \340\274\275\357\276\211",
            "\342\230\271"
         };
      end
      text = {"\n", hexk_str::join_str(letters, "\n"), "\n"};
      verdict_line = {verdict_line, " (", counts, ")"};
      if (!color) begin
         return {text, verdict_line};
      end
      // The blocks are U+2588 in UTF-8; green for a pass, red otherwise, in bold.
      text = hexk_str::replace(text, "#", "\342\226\210");
      return {
         (verdict == HEXK_TEST_PASSED) ? "\033[32m\033[1m" : "\033[31m\033[1m",
         text,
         "\033[0m",
         faces[face%faces.size()],
         "\n",
         verdict_line
      };
   endfunction : banner_text

   // The counts behind the verdict, as in the last line: errors, fatals, checks executed, and the failed checks that
   // counted no error.
   local function string counts_text();
      uvm_report_server server = uvm_report_server::get_server();
      int unsigned errors = server.get_severity_count(UVM_ERROR);
      int unsigned fatals = server.get_severity_count(UVM_FATAL);
      int unsigned unexpected = hexk_check_stats::num_unexpected_failures();
      string counts = $sformatf(
          "%0d errors, %0d fatals, %0d checks executed", errors, fatals, hexk_check_stats::num_checks()
      );
      // Only without errors and fatals did the failed checks count no error; it says why such a test failed.
      if (unexpected != 0 && errors == 0 && fatals == 0) begin
         counts = $sformatf("%s, %0d failed without an error", counts, unexpected);
      end
      return counts;
   endfunction : counts_text

   // Number of errors and fatals that the report server has counted.
   local function int num_errors();
      uvm_report_server server = uvm_report_server::get_server();
      return server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
   endfunction : num_errors

   // Switches the propagation of the objection of one phase off.
   local function void stop_propagation(uvm_phase node);
      uvm_objection objection;
      if (node == null) begin
         return;
      end
      objection = node.get_objection();
      if (objection != null) begin
         objection.set_propagate_mode(0);
      end
   endfunction : stop_propagation

endclass : hexk_base_test

`endif  // HEXK_BASE_TEST_SV
