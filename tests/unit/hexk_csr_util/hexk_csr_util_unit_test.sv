// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_csr_util_unit_test.sv
//
// SVUnit tests of hexk_csr_util on a small register model without a bus agent: every
// register has a frontdoor of this file that reads and writes a register file of this module,
// the "DUT", which keeps only the bits of the fields and obeys their access (RW, RO, WO, W1C).
// The frontdoor takes access_latency per access and answers UVM_NOT_OK at fail_address.
// Block ut_csr_blk has the registers ctrl, status, id, cmd and intr in its default map, and
// ctrl alone in a second map; block ut_csr_excl_blk is a second instance at other addresses
// for the tests of exclusions, which are resources of UVM and stay for the whole simulation.
// Errors are demoted by a report catcher and counted; a second catcher keeps the text of the
// latest message. One test is left out on Verilator (see there). Results are compared as text
// (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_csr_util.

`include "svunit_defines.svh"
`include "uvm_macros.svh"
`include "hexk_macros.svh"

module hexk_csr_util_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_csr_util;
   import hexk_uvm_pkg::hexk_csr_check_e;
   import hexk_uvm_pkg::HEXK_CSR_RESET_CHECK;
   import hexk_uvm_pkg::HEXK_CSR_BIT_BASH;
   import hexk_uvm_pkg::HEXK_CSR_ALL_CHECKS;
   import hexk_uvm_pkg::hexk_report_catcher;
   import hexk_uvm_pkg::hexk_check_stats;

   // IDs of the errors of the object and of the tests, which are demoted and counted.
   localparam string MESSAGE_IDS[8] = '{
       "HEXK_CSR_STATUS",
       "HEXK_CSR_NULL",
       "HEXK_CSR_RESET",
       "UT_CSR_ID",
       "UT_CSR_MODE",
       "UT_CSR_DONE",
       "UT_CSR_NULL",
       "UT_CSR_CTRL"
   };

   // Addresses of the second and the third block in the register file.
   localparam int unsigned EXCL_BASE = 'h100;
   localparam int unsigned KILL_BASE = 'h200;
   localparam int unsigned TOP_BASE = 'h400;

   // The register file of the DUT by address, and per address the bits of RW fields, of W1C fields and of all fields.
   bit          [31:0] dut_words      [int unsigned];
   bit          [31:0] rw_bits        [int unsigned];
   bit          [31:0] w1c_bits       [int unsigned];
   bit          [31:0] field_bits     [int unsigned];

   // Time of every access of the frontdoor, the address whose accesses fail (-1 for none), and their status; with
   // UVM_HAS_X the access is still carried out.
   realtime            access_latency;
   int                 fail_address;
   uvm_status_e        fail_status;

   // Number of reads of the frontdoor.
   int unsigned        dut_reads;

   // Names of the parent sequences of the accesses of the frontdoor, in order; "-" for none.
   string              parents;

   // A sequence that makes register accesses through the object of the test, as the parent of the accesses.
   class hexk_ut_caller_seq extends uvm_sequence #(uvm_sequence_item);
      `uvm_object_utils(hexk_ut_caller_seq)

      function new(string seq_name = "hexk_ut_caller_seq");
         super.new(seq_name);
      endfunction : new
   endclass : hexk_ut_caller_seq

   // Frontdoor of one register: reads and writes the register file of the DUT at its address.
   class hexk_ut_frontdoor extends uvm_reg_frontdoor;
      int unsigned address;

      `uvm_object_utils(hexk_ut_frontdoor)

      function new(string fd_name = "hexk_ut_frontdoor");
         super.new(fd_name);
      endfunction : new

      task body();
         bit [31:0] data = 32'(rw_info.value[0]);
         parents = {parents, (rw_info.parent == null) ? "-" : rw_info.parent.get_name(), " "};
         // No zero delay: a thousand of them in one time step stop a simulation on Verilator.
         if (access_latency > 0ns) begin
            #(access_latency);
         end
         rw_info.status = (int'(address) == fail_address) ? fail_status : UVM_IS_OK;
         if (rw_info.status == UVM_NOT_OK) begin
            return;
         end
         if (rw_info.kind == UVM_WRITE) begin
            dut_words[address] = (dut_words[address] & ~rw_bits[address]) | (data & rw_bits[address]);
            dut_words[address] = dut_words[address] & ~(data & w1c_bits[address]);
         end else begin
            dut_reads++;
            data             = dut_words[address] & field_bits[address];
            rw_info.value[0] = 64'(data);
         end
      endtask : body
   endclass : hexk_ut_frontdoor

   // A register of 32 bits with up to two fields, configured by the block: first and second in the order they
   // were added.
   class hexk_ut_reg extends uvm_reg;
      uvm_reg_field first;
      uvm_reg_field second;

      `uvm_object_utils(hexk_ut_reg)

      function new(string reg_name = "hexk_ut_reg");
         super.new(reg_name, 32, UVM_NO_COVERAGE);
      endfunction : new

      // Adds a field: name, width, lowest bit, access, reset value, volatile.
      function uvm_reg_field new_field(string field_name, int unsigned width, int unsigned lsb, string access,
                                       uvm_reg_data_t reset_value, bit volatile_field = 0);
         uvm_reg_field field = uvm_reg_field::type_id::create(field_name);
         field.configure(this, width, lsb, access, volatile_field, reset_value, 1, 1, 0);
         if (volatile_field) begin
            field.set_compare(UVM_NO_CHECK);
         end
         if (first == null) begin
            first = field;
         end else begin
            second = field;
         end
         return field;
      endfunction : new_field
   endclass : hexk_ut_reg

   // The block: ctrl (en RW [0], mode RW [3:1] reset 2), status (busy RO volatile [0], done RO [1]),
   // id (value RO [15:0] reset 'h1234), cmd (go WO [0]), intr (flags W1C [3:0]); ctrl also in map2, and intr
   // with write-only rights.
   class hexk_ut_block extends uvm_reg_block;
      hexk_ut_reg ctrl;
      hexk_ut_reg status;
      hexk_ut_reg ident;
      hexk_ut_reg cmd;
      hexk_ut_reg intr;
      uvm_reg_map map2;

      // Address of the first register in the register file of the DUT.
      local int unsigned base_address;

      `uvm_object_utils(hexk_ut_block)

      function new(string block_name = "hexk_ut_block");
         super.new(block_name, UVM_NO_COVERAGE);
      endfunction : new

      // Creates the registers at base in the register file of the DUT; as a sub-block (top 0) without map2 and
      // without locking the model, which its parent does.
      function void build_at(int unsigned base, bit top = 1);
         base_address = base;
         default_map  = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
         default_map.set_auto_predict(1);
         if (top) begin
            map2 = create_map("map2", 'h1000, 4, UVM_LITTLE_ENDIAN);
            map2.set_auto_predict(1);
         end
         ctrl = new_reg("ctrl", base + 'h0);
         void'(ctrl.new_field("en", 1, 0, "RW", 0));
         void'(ctrl.new_field("mode", 3, 1, "RW", 2));
         if (top) begin
            map2.add_reg(ctrl, 'h0, "RW");
         end
         status = new_reg("status", base + 'h4);
         void'(status.new_field("busy", 1, 0, "RO", 0, 1));
         void'(status.new_field("done", 1, 1, "RO", 0));
         ident = new_reg("id", base + 'h8);
         void'(ident.new_field("value", 16, 0, "RO", 'h1234));
         cmd = new_reg("cmd", base + 'hC);
         void'(cmd.new_field("go", 1, 0, "WO", 0));
         intr = new_reg("intr", base + 'h10);
         void'(intr.new_field("flags", 4, 0, "W1C", 0));
         if (top) begin
            map2.add_reg(intr, 'h10, "WO");
            lock_model();
            set_frontdoors();
         end
      endfunction : build_at

      // Gives every register its frontdoor, in each of its maps. After lock_model(): UVM warns that a map is not
      // initialized when a frontdoor is set before.
      function void set_frontdoors();
         ctrl.set_frontdoor(frontdoor_at(base_address + 'h0));
         status.set_frontdoor(frontdoor_at(base_address + 'h4));
         ident.set_frontdoor(frontdoor_at(base_address + 'h8));
         cmd.set_frontdoor(frontdoor_at(base_address + 'hC));
         intr.set_frontdoor(frontdoor_at(base_address + 'h10));
         if (map2 != null) begin
            ctrl.set_frontdoor(frontdoor_at(base_address + 'h0), map2);
            intr.set_frontdoor(frontdoor_at(base_address + 'h10), map2);
         end
      endfunction : set_frontdoors

      // A register of the default map at an address of the register file.
      local function hexk_ut_reg new_reg(string reg_name, int unsigned address);
         hexk_ut_reg rg = hexk_ut_reg::type_id::create(reg_name);
         rg.configure(this);
         default_map.add_reg(rg, uvm_reg_addr_t'(address), "RW");
         return rg;
      endfunction : new_reg

      local function hexk_ut_frontdoor frontdoor_at(int unsigned address);
         hexk_ut_frontdoor fd = hexk_ut_frontdoor::type_id::create($sformatf("fd_%0h", address));
         fd.address = address;
         return fd;
      endfunction : frontdoor_at
   endclass : hexk_ut_block

   // A block of two sub-blocks of the class above, at TOP_BASE and TOP_BASE + 'h100.
   class hexk_ut_top_block extends uvm_reg_block;
      hexk_ut_block first;
      hexk_ut_block second;

      `uvm_object_utils(hexk_ut_top_block)

      function new(string block_name = "hexk_ut_top_block");
         super.new(block_name, UVM_NO_COVERAGE);
      endfunction : new

      function void build_top();
         default_map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
         default_map.set_auto_predict(1);
         first = hexk_ut_block::type_id::create("first");
         first.configure(this);
         first.build_at(TOP_BASE, 0);
         default_map.add_submap(first.default_map, 'h0);
         second = hexk_ut_block::type_id::create("second");
         second.configure(this);
         second.build_at(TOP_BASE + 'h100, 0);
         default_map.add_submap(second.default_map, 'h0);
         lock_model();
         first.set_frontdoors();
         second.set_frontdoors();
      endfunction : build_top
   endclass : hexk_ut_top_block

   // Keeps the ID and the text of the latest message of the tests and of the object, and the latest text per ID.
   class hexk_ut_text_catcher extends uvm_report_catcher;
      string id;
      string text;
      string texts[string];

      function new(string catcher_name = "hexk_ut_text_catcher");
         super.new(catcher_name);
      endfunction : new

      function action_e catch();
         if (hexk_core_pkg::hexk_str::starts_with(
                 get_id(), "HEXK_CSR"
             ) || hexk_core_pkg::hexk_str::starts_with(
                 get_id(), "UT_CSR"
             )) begin
            id        = get_id();
            text      = get_message();
            texts[id] = text;
         end
         return THROW;
      endfunction : catch
   endclass : hexk_ut_text_catcher

   string               name = "hexk_csr_util_ut";
   svunit_testcase      svunit_ut;

   hexk_report_catcher  catcher;
   hexk_ut_text_catcher text_catcher;
   hexk_ut_block        blk;
   hexk_ut_block        excl_blk;
   hexk_ut_block        kill_blk;
   hexk_ut_top_block    top_blk;
   hexk_csr_util        csr;
   uvm_reg_data_t       value;
   bit                  seen;
   string               result;
   process              background;
   process              second_background;
   realtime             test_start;

   function automatic void build();
      svunit_ut    = new(name);
      catcher      = hexk_report_catcher::add_global();
      text_catcher = new();
      uvm_report_cb::add(null, text_catcher);
      blk = new("ut_csr_blk");
      blk.build_at(0);
      excl_blk = new("ut_csr_excl_blk");
      excl_blk.build_at(EXCL_BASE);
      kill_blk = new("ut_csr_kill_blk");
      kill_blk.build_at(KILL_BASE);
      top_blk = new("ut_csr_top");
      top_blk.build_top();
   endfunction : build

   // Every test gets a fresh object, a DUT at its reset values and a model whose mirror is reset.
   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      foreach (MESSAGE_IDS[i]) begin
         catcher.expect_msg({"^", MESSAGE_IDS[i], "$"}, UVM_ERROR, "", 0, -1, UVM_INFO);
      end
      hexk_check_stats::reset_for_test();
      csr               = hexk_csr_util::type_id::create("csr");
      access_latency    = 10ns;
      fail_address      = -1;
      fail_status       = UVM_NOT_OK;
      dut_reads         = 0;
      parents           = "";
      text_catcher.id   = "";
      text_catcher.text = "";
      text_catcher.texts.delete();
      test_start = $realtime;
      reset_dut(0);
      reset_dut(EXCL_BASE);
      reset_dut(KILL_BASE);
      reset_dut(TOP_BASE);
      reset_dut(TOP_BASE + 'h100);
      blk.reset();
      excl_blk.reset();
      top_blk.reset();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      if (background != null) begin
         background.kill();
         background = null;
      end
      if (second_background != null) begin
         second_background.kill();
         second_background = null;
      end
      catcher.clear();
   endtask : teardown

   // The register file of one block at its reset values, with the bits of its fields.
   function automatic void reset_dut(int unsigned base);
      dut_words[base+'h0]   = 'h4;
      rw_bits[base+'h0]     = 'hF;
      w1c_bits[base+'h0]    = 0;
      field_bits[base+'h0]  = 'hF;
      dut_words[base+'h4]   = 0;
      rw_bits[base+'h4]     = 0;
      w1c_bits[base+'h4]    = 0;
      field_bits[base+'h4]  = 'h3;
      dut_words[base+'h8]   = 'h1234;
      rw_bits[base+'h8]     = 0;
      w1c_bits[base+'h8]    = 0;
      field_bits[base+'h8]  = 'hFFFF;
      dut_words[base+'hC]   = 0;
      rw_bits[base+'hC]     = 'h1;
      w1c_bits[base+'hC]    = 0;
      field_bits[base+'hC]  = 0;
      dut_words[base+'h10]  = 0;
      rw_bits[base+'h10]    = 0;
      w1c_bits[base+'h10]   = 'hF;
      field_bits[base+'h10] = 'hF;
   endfunction : reset_dut

   // Changes a word of the DUT behind the back of the model.
   function automatic void poke(int unsigned address, bit [31:0] word);
      dut_words[address] = word;
   endfunction : poke

   // A word of the DUT, in hexadecimal.
   function automatic string dut(int unsigned address);
      return $sformatf("%0h", dut_words[address]);
   endfunction : dut

   // value, in hexadecimal.
   function automatic string value_text();
      return $sformatf("%0h", value);
   endfunction : value_text

   // Number of errors with this ID in this test; the ID is one of MESSAGE_IDS.
   function automatic string count_of(string id);
      return $sformatf("%0d", catcher.get_count({"^", id, "$"}));
   endfunction : count_of

   // "<passed> <failed>" of a check ID in hexk_check_stats.
   function automatic string checks(string id);
      return $sformatf("%0d %0d", hexk_check_stats::num_passed(id), hexk_check_stats::num_failed(id));
   endfunction : checks

   // The latest message of the tests: "<id>: <text>".
   function automatic string last_message();
      return {text_catcher.id, ": ", text_catcher.text};
   endfunction : last_message

   // The text of the latest message with this ID in this test.
   function automatic string text_of(string id);
      return text_catcher.texts.exists(id) ? text_catcher.texts[id] : "";
   endfunction : text_of

   // The time since the start of the test in nanoseconds.
   function automatic string now_ns();
      return $sformatf("%0d", int'(($realtime - test_start) / 1ns));
   endfunction : now_ns

   // Sets a register field of the DUT after a delay, in the background.
   task automatic set_later(realtime delay, int unsigned address, bit [31:0] word);
      fork
         begin
            background = process::self();
            #(delay);
            dut_words[address] = word;
         end
      join_none
      wait (background != null);
   endtask : set_later

   // Starts a read of ctrl of a block in the background.
   task automatic read_in_background(hexk_ut_block target);
      fork
         begin
            uvm_reg_data_t ignored;
            background = process::self();
            csr.read(target.ctrl, ignored);
         end
      join_none
      wait (background != null);
   endtask : read_in_background

   // Makes every access at an address fail.
   function automatic void fail_at(int address);
      fail_address = address;
   endfunction : fail_at

   // Makes every access at an address end with the status UVM_HAS_X, and still be carried out.
   function automatic void fail_with_x_at(int address);
      fail_address = address;
      fail_status  = UVM_HAS_X;
   endfunction : fail_with_x_at

   // Sets the time limit and the poll interval of the spin-waits, given as times of this module.
   function automatic void set_times(realtime timeout, realtime poll_interval);
      csr.timeout_ps       = `hexk_ps(timeout);
      csr.poll_interval_ps = `hexk_ps(poll_interval);
   endfunction : set_times

   // Sets the time of every access.
   function automatic void set_latency(realtime latency);
      access_latency = latency;
   endfunction : set_latency

   // Kills the process of the background.
   function automatic void kill_background();
      background.kill();
      background = null;
   endfunction : kill_background

   // Makes the object work through the second map, which holds ctrl only.
   function automatic void use_map2();
      csr.map = blk.map2;
   endfunction : use_map2

   // Makes bit 2 of ctrl of the DUT keep its value whatever is written.
   function automatic void stick_bit_2_of_ctrl();
      rw_bits['h0] = 'hB;
   endfunction : stick_bit_2_of_ctrl

   // Gives the volatile field status.busy a check (on) or takes it away again (off).
   function automatic void check_busy(bit on);
      blk.status.first.set_compare(on ? UVM_CHECK : UVM_NO_CHECK);
   endfunction : check_busy

   // Gives the field mode of ctrl a check (on) or takes it away (off).
   function automatic void check_mode(bit on);
      blk.ctrl.second.set_compare(on ? UVM_CHECK : UVM_NO_CHECK);
   endfunction : check_mode

   // 1 or 0 for the resources NO_REG_TESTS, NO_REG_HW_RESET_TEST and NO_REG_BIT_BASH_TEST of a full name.
   function automatic string resources_of(string full_name);
      string scope = {"REG::", full_name};
      return $sformatf(
          "%0b%0b%0b",
          uvm_resource_db#(bit)::get_by_name(
              scope, "NO_REG_TESTS", 0
          ) != null,
          uvm_resource_db#(bit)::get_by_name(
              scope, "NO_REG_HW_RESET_TEST", 0
          ) != null,
          uvm_resource_db#(bit)::get_by_name(
              scope, "NO_REG_BIT_BASH_TEST", 0
          ) != null
      );
   endfunction : resources_of

   // Starts a spin-wait on status.done in the background.
   task automatic spinwait_in_background();
      fork
         begin
            bit done_seen;
            background = process::self();
            csr.spinwait_field(blk.status.second, 1, "UT_CSR_DONE", done_seen);
         end
      join_none
      wait (background != null);
   endtask : spinwait_in_background

   // Starts a read of id in the background, beside the one of read_in_background().
   task automatic read_id_in_background();
      fork
         begin
            uvm_reg_data_t ignored;
            second_background = process::self();
            csr.read(blk.ident, ignored);
         end
      join_none
      wait (second_background != null);
   endtask : read_id_in_background

   // Lets time pass.
   task automatic advance(realtime amount);
      #(amount);
   endtask : advance

   // A spin-wait on status.done for 1, then "<seen> <now in ns>".
   task automatic spinwait_done();
      csr.spinwait_field(blk.status.second, 1, "UT_CSR_DONE", seen);
      result = $sformatf("%0b %s", seen, now_ns());
   endtask : spinwait_done

   // busy_reason() without the time.
   function automatic string busy();
      string reason = csr.busy_reason();
      int    since = hexk_core_pkg::hexk_str::find(reason, " since");
      if (since >= 0) begin
         reason = reason.substr(0, since - 1);
      end
      return $sformatf("%0d %0d %s", csr.is_busy(), csr.outstanding(), reason);
   endfunction : busy

   // Runs the bit-bash sequence of UVM on the block and gives the number of its errors.
   task automatic bit_bash_errors();
      catcher.expect_msg("^uvm_reg_bit_bash_seq$", UVM_ERROR, "", 0, -1, UVM_INFO);
      csr.bit_bash(blk);
      result = $sformatf("%0d", catcher.get_count("^uvm_reg_bit_bash_seq$"));
   endtask : bit_bash_errors

   // "none" for a count of "0", otherwise "some".
   function automatic string some_or_none(string count);
      return (count == "0") ? "none" : "some";
   endfunction : some_or_none

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // A write, a read, a read check and a field check named with a sequence, then a write and a read without one
   // while the member parent is another sequence, then a spin-wait named with the first: the parents seen.
   task automatic access_parents();
      hexk_ut_caller_seq caller = hexk_ut_caller_seq::type_id::create("caller");
      hexk_ut_caller_seq member = hexk_ut_caller_seq::type_id::create("member");
      csr.write(blk.ctrl, 'h3, caller);
      csr.read(blk.ctrl, value, caller);
      csr.read_check(blk.ctrl, 'h3, "UT_CSR_CTRL", '1, caller);
      csr.read_field_check(blk.ctrl.first, 1, "UT_CSR_CTRL", caller);
      csr.parent = member;
      csr.write(blk.ctrl, 'h3);
      csr.read(blk.ctrl, value);
      csr.spinwait(blk.ctrl, 'h3, '1, "UT_CSR_CTRL", seen, caller);
      csr.parent = null;
   endtask : access_parents

   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(write_then_read_gives_the_value_and_takes_the_time_of_the_accesses)
      csr.write(blk.ctrl, 'hB);
      `FAIL_UNLESS_STR_EQUAL(dut('h0), "b")
      csr.read(blk.ctrl, value);
      `FAIL_UNLESS_STR_EQUAL(value_text(), "b")
      `FAIL_UNLESS_STR_EQUAL(now_ns(), "20")
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_STATUS"), "0")
   `SVTEST_END

   `SVTEST(an_access_belongs_to_the_sequence_it_names_and_else_to_the_member_parent)
      access_parents();
      `FAIL_UNLESS_STR_EQUAL(parents, "caller caller caller caller member member caller ")
   `SVTEST_END

   `SVTEST(read_check_passes_and_counts_the_check)
      csr.read_check(blk.ident, 'h1234, "UT_CSR_ID");
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_ID"), "1 0")
      `FAIL_UNLESS_STR_EQUAL(count_of("UT_CSR_ID"), "0")
   `SVTEST_END

   `SVTEST(read_check_reports_a_difference_with_the_id_of_the_caller)
      csr.read_check(blk.ident, 'h1235, "UT_CSR_ID");
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_ID"), "0 1")
      `FAIL_UNLESS_STR_EQUAL(last_message(), "UT_CSR_ID: ut_csr_blk.id: read 'h1234, expected 'h1235")
   `SVTEST_END

   `SVTEST(read_check_compares_only_the_bits_of_the_mask)
      csr.read_check(blk.ident, 'h12FF, "UT_CSR_ID", 'hFF00);
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_ID"), "1 0")
      csr.read_check(blk.ident, 'h13FF, "UT_CSR_ID", 'hFF00);
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "UT_CSR_ID: ut_csr_blk.id: read 'h1234, expected 'h13ff under the mask 'hff00")
   `SVTEST_END

   `SVTEST(read_field_and_read_field_check_look_at_the_field_only)
      poke('h0, 'hB);
      csr.read_field(blk.ctrl.second, value);
      `FAIL_UNLESS_STR_EQUAL(value_text(), "5")
      csr.read_field_check(blk.ctrl.second, 5, "UT_CSR_MODE");
      csr.read_field_check(blk.ctrl.second, 4, "UT_CSR_MODE");
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_MODE"), "1 1")
      `FAIL_UNLESS_STR_EQUAL(last_message(), "UT_CSR_MODE: ut_csr_blk.ctrl.mode: read 'h5, expected 'h4")
   `SVTEST_END

   `SVTEST(a_field_check_compares_with_all_bits_of_the_expected_value)
      csr.read_field_check(blk.ctrl.first, 2, "UT_CSR_MODE");
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_MODE"), "0 1")
      `FAIL_UNLESS_STR_EQUAL(last_message(), "UT_CSR_MODE: ut_csr_blk.ctrl.en: read 'h0, expected 'h2")
   `SVTEST_END

   `SVTEST(a_field_spinwait_on_a_value_that_does_not_fit_is_an_error_without_a_read)
      csr.spinwait_field(blk.status.second, 2, "UT_CSR_DONE", seen);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0b %0d %s", seen, dut_reads, now_ns()), "0 0 0")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "UT_CSR_DONE: ut_csr_blk.status.done: 'h2 does not fit the 1 bits of the field")
   `SVTEST_END

   `SVTEST(write_field_keeps_the_other_fields)
      csr.write(blk.ctrl, 'h1);
      csr.write_field(blk.ctrl.second, 6);
      `FAIL_UNLESS_STR_EQUAL(dut('h0), "d")
   `SVTEST_END

   `SVTEST(a_failed_access_is_an_error_and_a_failed_check)
      fail_at('h8);
      csr.read_check(blk.ident, 'h1234, "UT_CSR_ID");
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_ID"), "0 1")
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_STATUS"), "1")
      `FAIL_UNLESS_STR_EQUAL(count_of("UT_CSR_ID"), "0")
      `FAIL_UNLESS_STR_EQUAL(last_message(), "HEXK_CSR_STATUS: read of ut_csr_blk.id: status UVM_NOT_OK")
      csr.write(blk.ident, 0);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_STATUS"), "2")
   `SVTEST_END

   `SVTEST(a_status_with_x_is_an_error_also_with_the_expected_value)
      fail_with_x_at('h8);
      csr.read_check(blk.ident, 'h1234, "UT_CSR_ID");
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_ID"), "0 1")
      `FAIL_UNLESS_STR_EQUAL(last_message(), "HEXK_CSR_STATUS: read of ut_csr_blk.id: status UVM_HAS_X")
      csr.spinwait(blk.ident, 'h1234, '1, "UT_CSR_ID", seen);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0b %s", seen, count_of("HEXK_CSR_STATUS")), "0 2")
   `SVTEST_END

   `SVTEST(a_null_register_is_an_error)
      csr.read_check(null, 0, "UT_CSR_NULL");
      `FAIL_UNLESS_STR_EQUAL(last_message(), "HEXK_CSR_NULL: read_check: the register is null")
      `FAIL_UNLESS_STR_EQUAL(checks("UT_CSR_NULL"), "0 1")
   `SVTEST_END

   `SVTEST(a_spinwait_polls_until_the_field_has_the_value)
      set_times(0, 20ns);
      set_later(55ns, 'h4, 'h2);
      spinwait_done();
      `FAIL_UNLESS_STR_EQUAL(result, "1 70")
      `FAIL_UNLESS_STR_EQUAL(count_of("UT_CSR_DONE"), "0")
   `SVTEST_END

   // With the default poll interval of 100 ns: reads at 0 and after 110 ns, each taking 10 ns.
   `SVTEST(a_spinwait_on_a_register_compares_the_bits_of_the_mask)
      set_later(25ns, 'h4, 'h3);
      csr.spinwait(blk.status, 'h2, 'h2, "UT_CSR_DONE", seen);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0b %s", seen, now_ns()), "1 120")
   `SVTEST_END

   `SVTEST(a_spinwait_that_reaches_the_time_limit_is_an_error_with_the_id_of_the_caller)
      set_times(100ns, 30ns);
      spinwait_done();
      `FAIL_UNLESS_STR_EQUAL(result, "0 110")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "UT_CSR_DONE: ut_csr_blk.status.done: 'h1 was not read within 100000; the last read gave 'h0")
   `SVTEST_END

   // Left out on Verilator: the zero delays inside the reads of UVM end its simulation (DIDNOTCONVERGE) before the
   // object sees that time cannot pass.
`ifndef VERILATOR
   `SVTEST(a_spinwait_where_time_cannot_pass_is_an_error)
      set_latency(0ns);
      set_times(1ms, 0ns);
      spinwait_done();
      `FAIL_UNLESS_STR_EQUAL(result, "0 0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", dut_reads), $sformatf("%0d", hexk_csr_util::MAX_READS_PER_STEP))
      `FAIL_UNLESS_STR_EQUAL(count_of("UT_CSR_DONE"), "1")
   `SVTEST_END
`endif

   `SVTEST(a_spinwait_ends_at_a_failed_read)
      fail_at('h4);
      spinwait_done();
      `FAIL_UNLESS_STR_EQUAL(result, "0 10")
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_STATUS"), "1")
   `SVTEST_END

   `SVTEST(an_access_in_flight_keeps_the_object_busy)
      set_latency(20ns);
      read_in_background(blk);
      advance(5ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 1 read of ut_csr_blk.ctrl")
      advance(20ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 0 ")
   `SVTEST_END

   `SVTEST(two_accesses_in_flight_are_tracked_apart)
      set_latency(20ns);
      read_in_background(blk);
      advance(10ns);
      read_id_in_background();
      advance(5ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 2 read of ut_csr_blk.ctrl")
      advance(10ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 1 read of ut_csr_blk.id")
      advance(10ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 0 ")
   `SVTEST_END

   `SVTEST(a_spinwait_is_in_flight_also_between_its_reads)
      set_times(0, 30ns);
      spinwait_in_background();
      advance(15ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 1 spin-wait on ut_csr_blk.status.done")
      advance(20ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 1 spin-wait on ut_csr_blk.status.done")
      poke('h4, 'h2);
      advance(30ns);
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 0 ")
   `SVTEST_END

   // The killed read leaves the register unusable for the rest of the simulation (UVM reports UVM/REG/ZOMBIE at the
   // next access), so it is one of a block of its own.
   `SVTEST(clear_forgets_an_access_whose_process_was_killed)
      set_latency(20ns);
      read_in_background(kill_blk);
      advance(5ns);
      kill_background();
      `FAIL_UNLESS_STR_EQUAL(busy(), "1 1 read of ut_csr_kill_blk.ctrl")
      csr.clear();
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 0 ")
   `SVTEST_END

   `SVTEST(the_reset_check_reads_every_register_with_a_readable_reset_value)
      csr.check_reset_values(blk);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "0")
      `FAIL_UNLESS_STR_EQUAL(checks("HEXK_CSR_RESET"), "4 0")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_blk: 4 registers checked, 0 with a wrong reset value, 1 left out")
   `SVTEST_END

   `SVTEST(the_reset_check_names_every_wrong_field_of_a_register)
      poke('h0, 'h7);
      poke('h4, 'h1);
      csr.check_reset_values(blk);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "1")
      `FAIL_UNLESS_STR_EQUAL(checks("HEXK_CSR_RESET"), "3 1")
      `FAIL_UNLESS_STR_EQUAL(text_of("HEXK_CSR_RESET"),
         "ut_csr_blk.ctrl: read 'h7; en is 'h1, reset 'h0; mode is 'h3, reset 'h2")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_blk: 4 registers checked, 1 with a wrong reset value, 1 left out")
   `SVTEST_END

   `SVTEST(a_volatile_field_is_left_out_of_the_reset_check_also_with_a_check)
      poke('h4, 'h1);
      check_busy(1);
      csr.check_reset_values(blk);
      check_busy(0);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "0")
   `SVTEST_END

   `SVTEST(with_include_volatile_a_volatile_field_is_checked_against_its_reset_value)
      poke('h4, 'h1);
      csr.check_reset_values(blk, 1);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "1")
      `FAIL_UNLESS_STR_EQUAL(checks("HEXK_CSR_RESET"), "3 1")
      `FAIL_UNLESS_STR_EQUAL(text_of("HEXK_CSR_RESET"), "ut_csr_blk.status: read 'h1; busy is 'h1, reset 'h0")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_blk: 4 registers checked, 1 with a wrong reset value, 1 left out")
   `SVTEST_END

   `SVTEST(include_volatile_does_not_bring_in_a_field_that_is_not_volatile_and_has_no_check)
      poke('h0, 'h6);
      check_mode(0);
      csr.check_reset_values(blk, 1);
      check_mode(1);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "0")
      `FAIL_UNLESS_STR_EQUAL(checks("HEXK_CSR_RESET"), "4 0")
   `SVTEST_END

   `SVTEST(a_field_without_a_check_is_left_out_of_the_reset_check)
      poke('h0, 'h7);
      check_mode(0);
      csr.check_reset_values(blk);
      check_mode(1);
      `FAIL_UNLESS_STR_EQUAL(text_of("HEXK_CSR_RESET"), "ut_csr_blk.ctrl: read 'h7; en is 'h1, reset 'h0")
   `SVTEST_END

   `SVTEST(a_failed_read_in_the_reset_check_counts_as_a_wrong_register)
      fail_at('h8);
      csr.check_reset_values(blk);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_STATUS"), "1")
      `FAIL_UNLESS_STR_EQUAL(checks("HEXK_CSR_RESET"), "3 1")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_blk: 4 registers checked, 1 with a wrong reset value, 1 left out")
   `SVTEST_END

   `SVTEST(the_reset_check_leaves_out_the_registers_that_are_not_in_the_map)
      use_map2();
      csr.check_reset_values(blk);
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_blk: 1 registers checked, 0 with a wrong reset value, 4 left out")
   `SVTEST_END

   `SVTEST(exclusions_leave_out_registers_fields_and_blocks)
      hexk_csr_util::exclude("ut_csr_excl_blk.ctrl", HEXK_CSR_RESET_CHECK);
      hexk_csr_util::exclude("ut_csr_excl_blk.id.value", HEXK_CSR_RESET_CHECK);
      poke(EXCL_BASE + 'h0, 'h7);
      poke(EXCL_BASE + 'h8, 'h1);
      csr.check_reset_values(excl_blk);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "0")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_excl_blk: 2 registers checked, 0 with a wrong reset value, 3 left out")
   `SVTEST_END

   `SVTEST(is_excluded_sees_exclude_and_the_resources_of_uvm)
      hexk_csr_util::exclude("ut_csr_excl_blk.st*", HEXK_CSR_BIT_BASH);
      uvm_resource_db#(bit)::set("REG::ut_csr_excl_blk.cmd", "NO_REG_TESTS", 1);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0b%0b %0b%0b %0b%0b",
         hexk_csr_util::is_excluded("ut_csr_excl_blk.status", HEXK_CSR_BIT_BASH),
         hexk_csr_util::is_excluded("ut_csr_excl_blk.status", HEXK_CSR_RESET_CHECK),
         hexk_csr_util::is_excluded("ut_csr_excl_blk.cmd", HEXK_CSR_BIT_BASH),
         hexk_csr_util::is_excluded("ut_csr_excl_blk.cmd", HEXK_CSR_RESET_CHECK),
         hexk_csr_util::is_excluded("ut_csr_excl_blk.intr", HEXK_CSR_ALL_CHECKS),
         hexk_csr_util::is_excluded("ut_csr_blk.status", HEXK_CSR_BIT_BASH)), "10 11 00")
   `SVTEST_END

   `SVTEST(exclude_from_all_checks_also_sets_the_resources_of_the_single_checks)
      hexk_csr_util::exclude("ut_csr_excl_blk.intr.flags");
      hexk_csr_util::exclude("ut_csr_excl_blk.ctrl.mode", HEXK_CSR_BIT_BASH);
      `FAIL_UNLESS_STR_EQUAL(resources_of("ut_csr_excl_blk.intr.flags"), "111")
      `FAIL_UNLESS_STR_EQUAL(resources_of("ut_csr_excl_blk.ctrl.mode"), "001")
   `SVTEST_END

   `SVTEST(the_reset_check_goes_through_the_sub_blocks_and_leaves_out_an_excluded_one)
      poke(TOP_BASE, 'h7);
      poke(TOP_BASE + 'h100, 'h7);
      csr.check_reset_values(top_blk);
      `FAIL_UNLESS_STR_EQUAL(count_of("HEXK_CSR_RESET"), "2")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_top: 8 registers checked, 2 with a wrong reset value, 2 left out")
      hexk_csr_util::exclude("ut_csr_top.second", HEXK_CSR_RESET_CHECK);
      csr.check_reset_values(top_blk);
      `FAIL_UNLESS_STR_EQUAL(text_of("HEXK_CSR_RESET"),
         "ut_csr_top.first.ctrl: read 'h7; en is 'h1, reset 'h0; mode is 'h3, reset 'h2")
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_top: 4 registers checked, 1 with a wrong reset value, 6 left out")
      hexk_csr_util::exclude("ut_csr_top", HEXK_CSR_RESET_CHECK);
      csr.check_reset_values(top_blk);
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_top: 0 registers checked, 0 with a wrong reset value, 10 left out")
   `SVTEST_END

   `SVTEST(an_excluded_block_leaves_out_all_its_registers)
      hexk_csr_util::exclude("ut_csr_excl_blk", HEXK_CSR_ALL_CHECKS);
      csr.check_reset_values(excl_blk);
      `FAIL_UNLESS_STR_EQUAL(last_message(),
         "HEXK_CSR_RESET_DONE: ut_csr_excl_blk: 0 registers checked, 0 with a wrong reset value, 5 left out")
   `SVTEST_END

   `SVTEST(bit_bash_runs_the_sequence_of_uvm_on_the_block)
      bit_bash_errors();
      `FAIL_UNLESS_STR_EQUAL(result, "0")
      `FAIL_UNLESS_STR_EQUAL(busy(), "0 0 ")
   `SVTEST_END

   `SVTEST(bit_bash_finds_a_bit_that_does_not_keep_its_value)
      stick_bit_2_of_ctrl();
      bit_bash_errors();
      `FAIL_UNLESS_STR_EQUAL(some_or_none(result), "some")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_csr_util_unit_test
