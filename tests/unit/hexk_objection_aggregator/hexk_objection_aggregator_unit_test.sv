// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_objection_aggregator_unit_test.sv
//
// SVUnit tests of hexk_objection_aggregator, hexk_objectable and hexk_busy_group.
// The UVM phases do not run in a unit test simulation, so each test plays the phaser: it
// calls phase_started, phase_ready_to_end and phase_ended of a fresh aggregator with the
// real phase nodes of the UVM schedule (run, main, shutdown) and reads the objection count
// the aggregator holds on each node. Two objects that implement hexk_objectable stand for
// a scoreboard and a model; a fresh hexk_busy_group holds the same two. Expected errors are
// demoted by a report catcher and counted.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_objection_aggregator.

`include "svunit_defines.svh"
`include "hexk_macros.svh"

module hexk_objection_aggregator_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_objectable;
   import hexk_uvm_pkg::hexk_busy_group;
   import hexk_uvm_pkg::hexk_wait_util;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   // Object that is busy while its count is not 0.
   class hexk_ut_busy implements hexk_objectable;
      int unsigned outstanding;
      string       reason;

      virtual function bit is_busy();
         return outstanding != 0;
      endfunction : is_busy

      virtual function string busy_reason();
         return reason;
      endfunction : busy_reason
   endclass : hexk_ut_busy

   string                    name = "hexk_objection_aggregator_ut";
   string                    result;
   svunit_testcase           svunit_ut;

   hexk_report_catcher       catcher;
   hexk_objection_aggregator aggregator;
   hexk_ut_busy              scoreboard;
   hexk_ut_busy              model;
   hexk_ut_busy              stranger;
   hexk_busy_group           group;
   uvm_phase                 build_node;
   uvm_phase                 run_node;
   uvm_phase                 main_node;
   uvm_phase                 shutdown_node;
   int unsigned              created;

   function automatic void build();
      uvm_domain common = uvm_domain::get_common_domain();
      uvm_domain runtime = uvm_domain::get_uvm_domain();
      svunit_ut     = new(name);
      catcher       = hexk_report_catcher::add_global();
      build_node    = common.find(uvm_build_phase::get());
      run_node      = common.find(uvm_run_phase::get());
      main_node     = runtime.find(uvm_main_phase::get());
      shutdown_node = runtime.find(uvm_shutdown_phase::get());
   endfunction : build

   // Every test gets a fresh aggregator with two registered objects.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_OBJECTION_REGISTER$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_OBJECTION_UNKNOWN$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_OBJECTION_IMBALANCE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_OBJECTION_POLL$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_BUSY_REGISTER$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_BUSY_POLL$", UVM_ERROR, "", 0, -1, UVM_INFO);
      // UVM warns when a test takes the objections of a phase away, as a phase jump does.
      catcher.demote("^OBJTN_CLEAR$", UVM_WARNING, UVM_INFO);
      scoreboard = new();
      model      = new();
      stranger   = new();
      use_new_aggregator();
      aggregator.register(scoreboard, "sb");
      aggregator.register(model, "model");
      group = hexk_busy_group::type_id::create("group");
      group.register(scoreboard, "sb");
      group.register(model, "model");
   endtask : setup

   // Ends the phases a test left open, so that no objection stays on a node.
   task automatic teardown();
      svunit_ut.teardown();
      scoreboard.outstanding = 0;
      model.outstanding      = 0;
      jump(run_node);
      jump(main_node);
      jump(shutdown_node);
      catcher.clear();
   endtask : teardown

   // Replaces the aggregator by one with nothing registered. Components cannot be deleted,
   // so each one gets its own name.
   function automatic void use_new_aggregator();
      created++;
      aggregator                  = new($sformatf("ut_objections_%0d", created), null);
      aggregator.poll_interval_ps = `hexk_ps(10ns);
   endfunction : use_new_aggregator

   // What UVM does to a phase that ends by a jump: the objections go, then phase_ended is called.
   function automatic void jump(uvm_phase node);
      uvm_objection objection = node.get_objection();
      if (node.get_objection_count(aggregator) != 0) begin
         objection.clear(aggregator);
      end
      aggregator.phase_ended(node);
   endfunction : jump

   // Objections the aggregator holds, as "run=<n> main=<n> shutdown=<n>".
   function automatic string held();
      int run_count = run_node.get_objection_count(aggregator);
      int main_count = main_node.get_objection_count(aggregator);
      int shutdown_count = shutdown_node.get_objection_count(aggregator);
      return $sformatf("run=%0d main=%0d shutdown=%0d", run_count, main_count, shutdown_count);
   endfunction : held

   // Errors of the aggregator in this test, as "register=<n> unknown=<n> imbalance=<n> poll=<n>".
   function automatic string errors();
      int unsigned register_count = catcher.get_count("^HEXK_OBJECTION_REGISTER$");
      int unsigned unknown_count = catcher.get_count("^HEXK_OBJECTION_UNKNOWN$");
      int unsigned imbalance_count = catcher.get_count("^HEXK_OBJECTION_IMBALANCE$");
      int unsigned poll_count = catcher.get_count("^HEXK_OBJECTION_POLL$");
      return $sformatf(
          "register=%0d unknown=%0d imbalance=%0d poll=%0d", register_count, unknown_count, imbalance_count, poll_count
      );
   endfunction : errors

   // report_busy() on one line, with " | " for every line break.
   function automatic string busy_report();
      return hexk_str::replace(aggregator.report_busy(), "\n", " | ");
   endfunction : busy_report

   // Makes an object busy or idle.
   function automatic void set_outstanding(hexk_ut_busy obj, int unsigned count, string reason = "");
      obj.outstanding = count;
      obj.reason      = reason;
   endfunction : set_outstanding

   // Sets the time between two polls, given as a time of this module.
   function automatic void set_poll_interval(realtime interval);
      aggregator.poll_interval_ps = `hexk_ps(interval);
   endfunction : set_poll_interval

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // wait_idle() of the group with the ID UT_IDLE: "<idle> <picoseconds it took> <errors UT_IDLE>".
   task automatic wait_group_idle(longint unsigned timeout_ps);
      longint unsigned start_ps = hexk_wait_util::now_ps();
      bit              idle;
      group.wait_idle(timeout_ps, "UT_IDLE", idle);
      result = $sformatf("%0b %0d %0d", idle, hexk_wait_util::now_ps() - start_ps, catcher.get_count("^UT_IDLE$"));
   endtask : wait_group_idle

   // Makes an object idle after a time, in a thread of its own.
   task automatic idle_after(hexk_ut_busy obj, realtime delay);
      fork
         begin
            #(delay);
            obj.outstanding = 0;
         end
      join_none
   endtask : idle_after

   // The group: "<members> <busy> <reason>", the reason on one line with " | " for every line break.
   function automatic string group_state();
      string reason = hexk_str::replace(group.busy_reason(), "\n", " | ");
      return $sformatf("%0d %0b %s", group.size(), group.is_busy(), reason);
   endfunction : group_state

   // Replaces the group by one without members.
   function automatic void use_empty_group();
      group = hexk_busy_group::type_id::create("group");
   endfunction : use_empty_group

   // Sets the time between two looks of the group, given as a time of this module.
   function automatic void set_group_poll(realtime interval);
      group.poll_interval_ps = `hexk_ps(interval);
   endfunction : set_group_poll

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(an_aggregator_without_objects_holds_nothing)
      use_new_aggregator();
      aggregator.phase_started(run_node);
      aggregator.phase_ready_to_end(run_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      `FAIL_UNLESS_STR_EQUAL(busy_report(), "nothing is busy")
   `SVTEST_END

   `SVTEST(idle_objects_do_not_hold_the_end_of_a_phase)
      aggregator.phase_started(run_node);
      aggregator.phase_ready_to_end(run_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_raise_holds_every_executing_task_phase)
      aggregator.phase_started(run_node);
      aggregator.phase_started(main_node);
      aggregator.raise(scoreboard, "3 items");
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=1 shutdown=0")
      aggregator.drop(scoreboard, "drained");
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=0 poll=0")
   `SVTEST_END

   `SVTEST(many_raises_are_one_objection_until_the_last_drop)
      aggregator.phase_started(run_node);
      aggregator.raise(scoreboard);
      aggregator.raise(model);
      aggregator.raise(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      aggregator.drop(scoreboard);
      aggregator.drop(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      aggregator.drop(model);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_raise_before_a_phase_holds_it_from_its_start)
      aggregator.raise(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      aggregator.phase_started(run_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      aggregator.drop(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_raise_is_carried_over_a_phase_jump_into_the_next_phase)
      aggregator.phase_started(run_node);
      aggregator.phase_started(main_node);
      aggregator.raise(scoreboard);
      jump(main_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      aggregator.phase_started(shutdown_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=1")
      aggregator.drop(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=0 poll=0")
   `SVTEST_END

   `SVTEST(phases_that_are_not_task_phases_are_ignored)
      aggregator.raise(scoreboard);
      aggregator.phase_started(build_node);
      aggregator.phase_ready_to_end(build_node);
      aggregator.phase_ended(build_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      aggregator.drop(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=0 poll=0")
   `SVTEST_END

   `SVTEST(a_drop_without_a_raise_is_an_error)
      aggregator.phase_started(run_node);
      aggregator.drop(scoreboard);
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=1 poll=0")
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_raise_that_is_never_dropped_is_an_error_in_check_phase)
      aggregator.raise(scoreboard);
      aggregator.raise(scoreboard);
      aggregator.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=1 poll=0")
      aggregator.drop(scoreboard);
      aggregator.drop(scoreboard);
      aggregator.check_phase(null);
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=1 poll=0")
   `SVTEST_END

   `SVTEST(objects_that_are_not_registered_are_rejected)
      aggregator.phase_started(run_node);
      aggregator.raise(stranger);
      aggregator.drop(stranger);
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=2 imbalance=0 poll=0")
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_null_handle_and_a_second_registration_are_errors)
      aggregator.register(null, "nothing");
      aggregator.register(scoreboard, "sb_again");
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=2 unknown=0 imbalance=0 poll=0")
   `SVTEST_END

   `SVTEST(a_busy_object_holds_the_end_of_the_phase_until_it_is_idle)
      aggregator.phase_started(run_node);
      set_outstanding(scoreboard, 2);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      aggregator.phase_ready_to_end(run_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      advance(25ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      set_outstanding(scoreboard, 0);
      advance(10ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(the_phase_is_held_again_when_an_object_is_busy_at_the_next_end)
      aggregator.phase_started(run_node);
      set_outstanding(scoreboard, 1);
      aggregator.phase_ready_to_end(run_node);
      set_outstanding(scoreboard, 0);
      advance(15ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      set_outstanding(model, 1);
      aggregator.phase_ready_to_end(run_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      set_outstanding(model, 0);
      advance(15ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_raise_keeps_the_phase_after_the_busy_objects_are_idle)
      aggregator.phase_started(run_node);
      set_outstanding(scoreboard, 1);
      aggregator.phase_ready_to_end(run_node);
      aggregator.raise(model);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      set_outstanding(scoreboard, 0);
      advance(15ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      aggregator.drop(model);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_drop_while_an_object_is_busy_leaves_the_phase_held)
      aggregator.phase_started(run_node);
      aggregator.raise(model);
      set_outstanding(scoreboard, 1);
      // A real phase is not ready to end while an objection is raised; the call is made to start the polling.
      aggregator.phase_ready_to_end(run_node);
      aggregator.drop(model);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=1 main=0 shutdown=0")
      set_outstanding(scoreboard, 0);
      advance(15ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_phase_jump_ends_the_polling_without_an_error)
      aggregator.phase_started(main_node);
      set_outstanding(scoreboard, 1);
      aggregator.phase_ready_to_end(main_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=1 shutdown=0")
      jump(main_node);
      aggregator.phase_started(shutdown_node);
      advance(25ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      aggregator.phase_ready_to_end(shutdown_node);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=1")
      set_outstanding(scoreboard, 0);
      advance(15ns);
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=0 poll=0")
   `SVTEST_END

   `SVTEST(report_busy_says_who_is_busy_and_why)
      aggregator.raise(scoreboard, "3 items");
      aggregator.raise(scoreboard, "4 items");
      aggregator.raise(model);
      `FAIL_UNLESS_STR_EQUAL(busy_report(), "sb: raised 2 times: 4 items | model: raised")
      aggregator.drop(scoreboard);
      aggregator.drop(scoreboard);
      aggregator.drop(model);
      `FAIL_UNLESS_STR_EQUAL(busy_report(), "nothing is busy")
   `SVTEST_END

   `SVTEST(report_busy_indents_the_lines_of_a_long_reason)
      set_outstanding(scoreboard, 1);
      set_outstanding(model, 2, "ids 17, 18\nsince 40 ns");
      `FAIL_UNLESS_STR_EQUAL(busy_report(), "sb: busy | model: busy: ids 17, 18 |     since 40 ns")
   `SVTEST_END

   `SVTEST(report_busy_indents_the_lines_of_a_long_raise_reason)
      aggregator.raise(model, "ids 17, 18\nsince 40 ns");
      `FAIL_UNLESS_STR_EQUAL(busy_report(), "model: raised: ids 17, 18 |     since 40 ns")
      aggregator.drop(model);
   `SVTEST_END

   `SVTEST(a_poll_interval_of_zero_is_an_error_and_holds_nothing)
      set_poll_interval(0);
      aggregator.phase_started(run_node);
      set_outstanding(scoreboard, 1);
      aggregator.phase_ready_to_end(run_node);
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=0 poll=1")
      `FAIL_UNLESS_STR_EQUAL(held(), "run=0 main=0 shutdown=0")
   `SVTEST_END

   `SVTEST(a_busy_group_is_busy_while_a_member_is_and_names_the_busy_ones)
      `FAIL_UNLESS_STR_EQUAL(group_state(), "2 0 ")
      set_outstanding(model, 2, "ids 17, 18\nsince 40 ns");
      `FAIL_UNLESS_STR_EQUAL(group_state(), "2 1 model: ids 17, 18 |     since 40 ns")
      set_outstanding(scoreboard, 1, "3 items");
      `FAIL_UNLESS_STR_EQUAL(group_state(), "2 1 sb: 3 items | model: ids 17, 18 |     since 40 ns")
   `SVTEST_END

   `SVTEST(wait_idle_of_an_idle_group_returns_at_once)
      wait_group_idle(`hexk_ps(1us));
      `FAIL_UNLESS_STR_EQUAL(result, "1 0 0")
      use_empty_group();
      wait_group_idle(`hexk_ps(1us));
      `FAIL_UNLESS_STR_EQUAL(result, "1 0 0")
   `SVTEST_END

   `SVTEST(wait_idle_returns_at_the_first_look_after_the_members_became_idle)
      set_outstanding(model, 1, "a word");
      idle_after(model, 25ns);
      wait_group_idle(`hexk_ps(1us));
      `FAIL_UNLESS_STR_EQUAL(result, "1 30000 0")
      set_group_poll(4ns);
      set_outstanding(scoreboard, 1, "an item");
      idle_after(scoreboard, 9ns);
      wait_group_idle(`hexk_ps(1us));
      `FAIL_UNLESS_STR_EQUAL(result, "1 12000 0")
   `SVTEST_END

   `SVTEST(wait_idle_after_the_limit_is_an_error_with_the_id_of_the_caller_naming_the_busy_members)
      catcher.expect_msg("^UT_IDLE$", UVM_ERROR, "model: stuck", 0, -1, UVM_INFO);
      set_outstanding(model, 1, "stuck");
      // The last look comes at the limit, 25 ns, not at the next poll after it.
      wait_group_idle(`hexk_ps(25ns));
      `FAIL_UNLESS_STR_EQUAL(result, "0 25000 1")
   `SVTEST_END

   `SVTEST(wait_idle_without_a_limit_waits_until_the_group_is_idle)
      set_outstanding(model, 1, "stuck for a while");
      idle_after(model, 2us);
      wait_group_idle(0);
      `FAIL_UNLESS_STR_EQUAL(result, "1 2000000 0")
   `SVTEST_END

   `SVTEST(a_busy_group_with_a_poll_interval_of_zero_is_an_error_and_does_not_wait)
      set_group_poll(0);
      wait_group_idle(`hexk_ps(1us));
      `FAIL_UNLESS_STR_EQUAL(result, "1 0 0")
      set_outstanding(model, 1, "stuck");
      wait_group_idle(`hexk_ps(1us));
      `FAIL_UNLESS_STR_EQUAL($sformatf("%s %0d", result, catcher.get_count("^HEXK_BUSY_POLL$")), "0 0 0 1")
   `SVTEST_END

   `SVTEST(a_busy_group_rejects_a_null_handle_itself_and_a_second_registration)
      group.register(null, "nothing");
      group.register(group, "itself");
      group.register(model, "model again");
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d %0d", group.size(), catcher.get_count("^HEXK_BUSY_REGISTER$")), "2 3")
   `SVTEST_END

   `SVTEST(a_busy_group_registered_with_the_aggregator_names_its_members)
      use_new_aggregator();
      aggregator.register(group, "drain");
      set_outstanding(model, 1, "a word");
      `FAIL_UNLESS_STR_EQUAL(busy_report(), "drain: busy: model: a word")
      `FAIL_UNLESS_STR_EQUAL(errors(), "register=0 unknown=0 imbalance=0 poll=0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_objection_aggregator_unit_test
