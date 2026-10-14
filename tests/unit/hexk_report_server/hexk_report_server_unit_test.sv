// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_server_unit_test.sv
//
// SVUnit tests of hexk_report_server, hexk_report_cfg and hexk_msg_listener.
// Line layouts are compared with golden text; the message is built by hand and composed by a
// server that is not installed, so the tests do not depend on what else is printed. Counts,
// summary, listeners and triggers are driven through execute_report_message with messages
// whose action is "nothing", so no line is printed and a fatal does not end the run. One
// test installs the server, reports through UVM and puts the previous server back. Results are compared as text (see
// tests/unit/README.md). Needs UVM. Runs on Verilator with UVM 2020:
// make test SIM=verilator TEST=hexk_report_server.

`include "svunit_defines.svh"

module hexk_report_server_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_server;
   import hexk_uvm_pkg::hexk_report_cfg;
   import hexk_uvm_pkg::hexk_msg_listener;
   import hexk_uvm_pkg::HEXK_FMT_UVM;
   import hexk_uvm_pkg::HEXK_FMT_CUSTOM;
   import hexk_uvm_pkg::HEXK_FLD_SEVERITY;
   import hexk_uvm_pkg::HEXK_FLD_COUNTER;
   import hexk_uvm_pkg::HEXK_FLD_TIME;
   import hexk_uvm_pkg::HEXK_FLD_ID;
   import hexk_uvm_pkg::HEXK_FLD_MESSAGE;
   import hexk_uvm_pkg::hexk_time_unit_e;
   import hexk_uvm_pkg::HEXK_TIME_FS;
   import hexk_uvm_pkg::HEXK_TIME_PS;
   import hexk_uvm_pkg::HEXK_TIME_NS;
   import hexk_uvm_pkg::HEXK_TIME_US;
   import hexk_uvm_pkg::HEXK_TIME_MS;
   import hexk_uvm_pkg::HEXK_TIME_S;
   import hexk_core_pkg::hexk_str;
   import hexk_uvm_pkg::hexk_report_catcher;
   `include "uvm_macros.svh"

   // Listener that records the IDs it is told about.
   class hexk_ut_listener implements hexk_msg_listener;
      string seen[$];
      virtual function void on_message(uvm_report_message msg);
         seen.push_back(msg.get_id());
      endfunction : on_message
   endclass : hexk_ut_listener

   localparam string REPORTER = "uvm_test_top.env.sb";
   localparam string SOURCE_FILE = "/work/tb/env/my_scoreboard.sv";
   localparam int SOURCE_LINE = 120;

   string              name = "hexk_report_server_ut";
   // Demotes and counts the errors that tests provoke on purpose.
   hexk_report_catcher catcher;
   string              times_result;
   svunit_testcase     svunit_ut;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
   endtask : teardown

   // A report message that was not issued by anything; its action is "nothing".
   function automatic uvm_report_message make_message(uvm_severity severity, string id, string text,
                                                      string file = SOURCE_FILE, int line = SOURCE_LINE);
      uvm_report_message message = uvm_report_message::new_report_message();
      message.set_report_message(severity, id, text, UVM_NONE, file, line, "");
      return message;
   endfunction : make_message

   // A cfg with one change from the defaults, selected by variant.
   function automatic hexk_report_cfg make_cfg(string variant);
      hexk_report_cfg cfg = hexk_report_cfg::type_id::create("cfg");
      case (variant)
         "uvm":          cfg.style = HEXK_FMT_UVM;
         "narrow": begin
            cfg.file_line_width = 12;
            cfg.id_width        = 8;
            cfg.context_width   = 6;
         end
         "unlimited": begin
            cfg.file_line_width = 0;
            cfg.id_width        = 0;
            cfg.context_width   = 0;
         end
         "custom": begin
            cfg.style  = HEXK_FMT_CUSTOM;
            cfg.fields = '{HEXK_FLD_ID, HEXK_FLD_MESSAGE};
         end
         "custom_counter": begin
            cfg.style  = HEXK_FMT_CUSTOM;
            cfg.fields = '{HEXK_FLD_SEVERITY, HEXK_FLD_COUNTER, HEXK_FLD_ID};
         end
         "custom_empty": cfg.style = HEXK_FMT_CUSTOM;
         "names": begin
            cfg.file_line_width = 0;
            cfg.id_width        = 0;
            cfg.context_width   = 0;
            cfg.severity_letter = 0;
         end
         "unnumbered": begin
            cfg.style    = HEXK_FMT_CUSTOM;
            cfg.fields   = '{HEXK_FLD_SEVERITY, HEXK_FLD_ID};
            cfg.numbered = 0;
         end
         "color": begin
            cfg.style  = HEXK_FMT_CUSTOM;
            cfg.fields = '{HEXK_FLD_SEVERITY, HEXK_FLD_ID};
            cfg.color  = 1;
         end
         "keep_top": begin
            cfg.file_line_width = 0;
            cfg.id_width        = 0;
            cfg.context_width   = 0;
            cfg.strip_test_top  = 0;
         end
         "triggers": begin
            cfg.stacktrace_on_fatal        = 0;
            cfg.stacktrace_on_uvm_internal = 0;
            cfg.stacktrace_triggers        = '{"^SB_", "my_driver.sv:12"};
            cfg.marker_triggers            = '{"WATCH", "expected [0-9]+"};
         end
         "trace_errors": cfg.stacktrace_on_error = 1;
         "location_like": begin
            cfg.stacktrace_on_fatal        = 0;
            cfg.stacktrace_on_uvm_internal = 0;
            cfg.marker_triggers            = '{"a:b:7", "x.sv:", "y.sv:4a", ":42"};
         end
         "custom_time": begin
            cfg.style  = HEXK_FMT_CUSTOM;
            cfg.fields = '{HEXK_FLD_TIME};
         end
         "ids": begin
            cfg.style    = HEXK_FMT_CUSTOM;
            cfg.fields   = '{HEXK_FLD_ID};
            cfg.id_width = 0;
         end
         default:        ;
      endcase
      return cfg;
   endfunction : make_cfg

   // A server that is not installed, with the cfg variant.
   function automatic hexk_report_server make_server(string variant);
      hexk_report_server server = hexk_report_server::type_id::create("server");
      server.set_cfg(make_cfg(variant));
      return server;
   endfunction : make_server

   // The line a server with the cfg variant composes for one message. All unit test suites
   // share one simulation, so the time is not 0 here: the time column is replaced by the one
   // for time 0, which the tests of the layout expect.
   function automatic string line_of(string variant, uvm_severity severity = UVM_ERROR, string id = "SB_MISMATCH",
                                     string text = "expected 5, got 4");
      hexk_report_server server = make_server(variant);
      string             line = server.compose_report_message(make_message(severity, id, text), REPORTER);
      return hexk_str::replace(line, hexk_str::pad(time_of(HEXK_TIME_NS, 3), 14), "       0.000ns", 0);
   endfunction : line_of

   // The line UVM's own server composes for the same message.
   function automatic string uvm_line();
      uvm_default_report_server server = new();
      return server.compose_report_message(make_message(UVM_ERROR, "SB_MISMATCH", "expected 5, got 4"), REPORTER);
   endfunction : uvm_line

   // Style of a server on which set_cfg was never called.
   function automatic string new_server_style();
      hexk_report_server server = hexk_report_server::type_id::create("server");
      hexk_report_cfg    cfg = server.get_cfg();
      return cfg.style.name();
   endfunction : new_server_style

   // What a server does with the message "SB_MISMATCH" after its cfg object was changed behind its back, and then
   // after set_cfg was called again: "<line> <marker> / <line> <marker>".
   function automatic string after_a_cfg_change();
      hexk_report_cfg    cfg = make_cfg("custom");
      hexk_report_server server = hexk_report_server::type_id::create("server");
      uvm_report_message message = make_message(UVM_ERROR, "SB_MISMATCH", "text");
      string             stale;
      server.set_cfg(cfg);
      cfg.fields = '{HEXK_FLD_ID};
      cfg.marker_triggers.push_back("^SB_");
      stale = $sformatf("%s %0b", server.compose_report_message(message, REPORTER), server.gets_marker(message));
      server.set_cfg(cfg);
      return $sformatf(
          "%s / %s %0b",
          stale,
          hexk_str::strip(
              server.compose_report_message(message, REPORTER)
          ),
          server.gets_marker(
              message
          )
      );
   endfunction : after_a_cfg_change

   // Style of the cfg in use after the object that get_cfg() returned was changed.
   function automatic string style_after_changing_what_get_cfg_returned();
      hexk_report_server server = make_server("custom");
      hexk_report_cfg    cfg = server.get_cfg();
      cfg.style = HEXK_FMT_UVM;
      cfg       = server.get_cfg();
      return cfg.style.name();
   endfunction : style_after_changing_what_get_cfg_returned

   // Waits until the simulation time is target; the suites that run earlier end long before it.
   task automatic advance_to(realtime target);
      if (target > $realtime) begin
         #(target - $realtime);
      end
   endtask : advance_to

   // The time column for the current time, without the padding.
   function automatic string time_of(hexk_time_unit_e unit, int unsigned precision);
      hexk_report_cfg    cfg = make_cfg("");
      hexk_report_server server = hexk_report_server::type_id::create("server");
      cfg.style          = HEXK_FMT_CUSTOM;
      cfg.fields         = '{HEXK_FLD_TIME};
      cfg.time_unit      = unit;
      cfg.time_precision = precision;
      server.set_cfg(cfg);
      return hexk_str::strip(server.compose_report_message(make_message(UVM_INFO, "T", ""), REPORTER));
   endfunction : time_of

   // Feeds a fixed set of messages to server through execute_report_message.
   function automatic void feed(hexk_report_server server);
      server.execute_report_message(make_message(UVM_INFO, "MON_ITEM", "item"), "");
      server.execute_report_message(make_message(UVM_INFO, "MON_ITEM", "item"), "");
      server.execute_report_message(make_message(UVM_WARNING, "agent_1.DRV_RETRY", "retry"), "");
      server.execute_report_message(make_message(UVM_WARNING, "agent_2.DRV_RETRY", "retry"), "");
      server.execute_report_message(make_message(UVM_WARNING, "agent_10.DRV_RETRY", "retry"), "");
      server.execute_report_message(make_message(UVM_ERROR, "SB_MISMATCH", "first text"), "");
      server.execute_report_message(make_message(UVM_ERROR, "SB_MISMATCH", "second text"), "");
      server.execute_report_message(make_message(UVM_FATAL, "SB_GIVE_UP", "too many"), "");
   endfunction : feed

   // Counts of a fed server as "<info MON_ITEM> <warning agent_2> <error SB> <fatal SB_GIVE_UP> <unknown>".
   function automatic string counts_after_feed();
      hexk_report_server server = make_server("");
      feed(server);
      return $sformatf(
          "%0d %0d %0d %0d %0d",
          server.get_count(
              UVM_INFO, "MON_ITEM"
          ),
          server.get_count(
              UVM_WARNING, "agent_2.DRV_RETRY"
          ),
          server.get_count(
              UVM_ERROR, "SB_MISMATCH"
          ),
          server.get_count(
              UVM_FATAL, "SB_GIVE_UP"
          ),
          server.get_count(
              UVM_ERROR, "MON_ITEM"
          )
      );
   endfunction : counts_after_feed

   // Line number index (0-based) of the summary of a fed server; "" beyond the end.
   function automatic string summary_line(int unsigned index, bit fed = 1);
      hexk_report_server server = make_server("");
      string             lines                    [$];
      if (fed) begin
         feed(server);
      end
      hexk_str::split(server.summary(), lines, "\n");
      return (index < lines.size()) ? lines[index] : "";
   endfunction : summary_line

   // IDs a listener is told about when the fixed set of messages is fed, joined with ",".
   function automatic string listener_ids();
      hexk_report_server server = make_server("");
      hexk_ut_listener   listener = new();
      server.add_listener(listener);
      server.add_listener(null);
      feed(server);
      return hexk_str::join_str(listener.seen, ",");
   endfunction : listener_ids

   // Lines of one server with the cfg variant "unlimited" for messages that differ in ID, file, line and reporter,
   // one after the other and then the first again, without the time column: "<line> | <line> | <line>".
   function automatic string lines_of_different_messages();
      hexk_report_server server = make_server("unlimited");
      string             lines                             [$];
      lines.push_back(server.compose_report_message(make_message(UVM_INFO, "MON_ITEM", "a"), REPORTER));
      lines.push_back(server.compose_report_message(
                      make_message(UVM_INFO, "DRV", "b", "/x/drv.sv", 7), "uvm_test_top.env.drv"));
      lines.push_back(server.compose_report_message(make_message(UVM_INFO, "MON_ITEM", "a"), REPORTER));
      foreach (lines[i]) begin
         lines[i] = hexk_str::replace(lines[i], hexk_str::pad(time_of(HEXK_TIME_NS, 3), 14), "T", 0);
      end
      return hexk_str::join_str(lines, " | ");
   endfunction : lines_of_different_messages

   // The time column of one server for a message now and for the same message 1 ns later, each compared with
   // the time that a new server prints at that moment: "same" when both agree and differ from each other.
   task automatic times_of_two_steps(output string result);
      hexk_report_server server = make_server("custom_time");
      uvm_report_message message = make_message(UVM_INFO, "M", "");
      string             first = hexk_str::strip(server.compose_report_message(message, REPORTER));
      string             first_expected = time_of(HEXK_TIME_NS, 3);
      string             second;
      string             second_expected;
      #1ns;
      second          = hexk_str::strip(server.compose_report_message(message, REPORTER));
      second_expected = time_of(HEXK_TIME_NS, 3);
      // An if and not ?:, which pads the shorter of two strings on one tool.
      if (first == first_expected && second == second_expected && first != second) begin
         result = "same";
      end else begin
         result = {first, " ", first_expected, " ", second, " ", second_expected};
      end
   endtask : times_of_two_steps

   // The ID column of one server after more different IDs than a store keeps, for the first ID again.
   function automatic string id_column_after_many_ids();
      hexk_report_server server = make_server("ids");
      for (int i = 0; i <= int'(hexk_report_server::STORE_LIMIT); i++) begin
         void'(server.compose_report_message(make_message(UVM_INFO, $sformatf("ID_%0d", i), "x"), REPORTER));
      end
      return server.compose_report_message(make_message(UVM_INFO, "ID_0", "x"), REPORTER);
   endfunction : id_column_after_many_ids

   // Marker decisions of one server with the cfg variant "triggers" for two messages with one ID, the first with
   // a text that a trigger matches, the second without: "<marker> <marker>".
   function automatic string markers_of_one_id();
      hexk_report_server server = make_server("triggers");
      uvm_report_message first = make_message(UVM_INFO, "DRV", "WATCH this");
      uvm_report_message second = make_message(UVM_INFO, "DRV", "plain");
      return $sformatf("%0b %0b", server.gets_marker(first), server.gets_marker(second));
   endfunction : markers_of_one_id

   // Whether report_summarize() of a server writes its table to a file it is given, where UVM 2020 also writes
   // its own summary: the line of the table that starts it, or "missing".
   function automatic string summary_in_a_file();
      hexk_report_server server = make_server("");
      string             file_name = "hexk_report_server_ut_summary.txt";
      int                handle = $fopen(file_name, "w");
      string             line;
      string             found = "missing";
      server.report_summarize(handle);
      $fclose(handle);
      handle = $fopen(file_name, "r");
      while ($fgets(
          line, handle
      ) != 0) begin
         if (hexk_str::starts_with(line, "Messages by severity and ID:")) begin
            found = hexk_str::strip(line);
         end
      end
      $fclose(handle);
      return found;
   endfunction : summary_in_a_file

   // "<stack trace><marker>" decisions of a server with the cfg variant for one message, as two digits.
   function automatic string decisions(string variant, uvm_severity severity, string id, string text,
                                       string file = SOURCE_FILE, int line = SOURCE_LINE);
      hexk_report_server server = make_server(variant);
      uvm_report_message message = make_message(severity, id, text, file, line);
      return {server.gets_stacktrace(message) ? "1" : "0", server.gets_marker(message) ? "1" : "0"};
   endfunction : decisions

   // Fields of a default cfg after apply_plusargs, as text.
   function automatic string cfg_after_plusargs();
      hexk_report_cfg cfg = make_cfg("");
      cfg.apply_plusargs();
      return $sformatf(
          "%s %0d %s %0b %s %s",
          cfg.style.name(),
          cfg.fields.size(),
          hexk_report_cfg::time_unit_text(
              cfg.time_unit
          ),
          cfg.color,
          hexk_str::join_str(
              cfg.stacktrace_triggers, "|"
          ),
          hexk_str::join_str(
              cfg.marker_triggers, "|"
          )
      );
   endfunction : cfg_after_plusargs

   // Counts of one ID that is issued with three severities, as "<info> <warning> <error> <fatal>", and the number
   // of lines of the summary that end with the ID.
   function automatic string counts_of_a_shared_id();
      hexk_report_server server = make_server("");
      string             lines                    [$];
      int unsigned       named;
      server.execute_report_message(make_message(UVM_INFO, "SHARED", "first"), "");
      server.execute_report_message(make_message(UVM_WARNING, "SHARED", "second"), "");
      server.execute_report_message(make_message(UVM_WARNING, "SHARED", "third"), "");
      server.execute_report_message(make_message(UVM_ERROR, "SHARED", "fourth"), "");
      hexk_str::split(server.summary(), lines, "\n");
      foreach (lines[i]) begin
         if (hexk_str::ends_with(lines[i], "  SHARED")) begin
            named++;
         end
      end
      return $sformatf(
          "%0d %0d %0d %0d lines=%0d",
          server.get_count(
              UVM_INFO, "SHARED"
          ),
          server.get_count(
              UVM_WARNING, "SHARED"
          ),
          server.get_count(
              UVM_ERROR, "SHARED"
          ),
          server.get_count(
              UVM_FATAL, "SHARED"
          ),
          named
      );
   endfunction : counts_of_a_shared_id

   // "kept <errors>" when copy() from an object of another class leaves a cfg as it was and reports it.
   function automatic string cfg_after_a_copy_from_another_class();
      hexk_report_cfg   cfg = make_cfg("");
      uvm_sequence_item other = new("other");
      string            result = "changed";
      catcher.expect_msg("^HEXK_COPY_TYPE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      cfg.time_unit = HEXK_TIME_PS;
      cfg.copy(other);
      if (cfg.time_unit == HEXK_TIME_PS) begin
         result = "kept";
      end
      result = $sformatf("%s %0d", result, catcher.get_count("^HEXK_COPY_TYPE$"));
      catcher.clear();
      return result;
   endfunction : cfg_after_a_copy_from_another_class

   // convert2string of a clone of a changed cfg.
   function automatic string cloned_cfg();
      hexk_report_cfg cfg = make_cfg("narrow");
      hexk_report_cfg copy;
      cfg.time_unit = HEXK_TIME_PS;
      cfg.marker_triggers.push_back("X");
      $cast(copy, cfg.clone());
      return copy.convert2string();
   endfunction : cloned_cfg

   // Installs a server with the default cfg, reports through UVM, and returns what the server counted.
   function automatic string installed_counts();
      uvm_report_server  previous = uvm_report_server::get_server();
      hexk_report_server server = hexk_report_server::install(make_cfg("narrow"));
      bit                is_current = (hexk_report_server::get_installed() == server);
      `uvm_info("UT_INSTALLED", "reported through the installed server", UVM_NONE)
      `uvm_warning("UT_INSTALLED", "a warning through the installed server")
      // The UVM suites share one simulation: give the others their report server back.
      uvm_report_server::set_server(previous);
      return $sformatf(
          "%0b %0d %0d",
          is_current,
          server.get_count(
              UVM_INFO, "UT_INSTALLED"
          ),
          server.get_count(
              UVM_WARNING, "UT_INSTALLED"
          )
      );
   endfunction : installed_counts

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(uvm_style_is_the_text_of_the_uvm_server)
      `FAIL_UNLESS_STR_EQUAL(line_of("uvm"), uvm_line())
   `SVTEST_END

   `SVTEST(a_new_server_uses_the_uvm_style)
      `FAIL_UNLESS_STR_EQUAL(new_server_style(), "HEXK_FMT_UVM")
   `SVTEST_END

   `SVTEST(compact_style_has_fixed_columns)
      `FAIL_UNLESS_STR_EQUAL(line_of("narrow"),
         {"E1   ", " ", "       0.000ns", " ", "..ard.sv:120", " ", "SB_MIS..", " ", "env.sb", " ",
          "expected 5, got 4"})
      `FAIL_UNLESS_STR_EQUAL(line_of("narrow", UVM_INFO, "MON", "item"),
         {"I    ", " ", "       0.000ns", " ", "..ard.sv:120", " ", "MON     ", " ", "env.sb", " ", "item"})
   `SVTEST_END

   `SVTEST(default_widths_are_28_24_and_40)
      `FAIL_UNLESS_STR_EQUAL(line_of(""),
         {"E1   ", " ", "       0.000ns", " ", hexk_str::pad("my_scoreboard.sv:120", 28, 1), " ",
          hexk_str::pad("SB_MISMATCH", 24, 1), " ", hexk_str::pad("env.sb", 40, 1), " ", "expected 5, got 4"})
   `SVTEST_END

   `SVTEST(a_width_of_zero_means_as_long_as_needed)
      `FAIL_UNLESS_STR_EQUAL(line_of("unlimited"),
         "E1           0.000ns my_scoreboard.sv:120 SB_MISMATCH env.sb expected 5, got 4")
   `SVTEST_END

   `SVTEST(severity_can_be_the_uvm_name)
      `FAIL_UNLESS_STR_EQUAL(line_of("names"),
         "UVM_ERROR          0.000ns my_scoreboard.sv:120 SB_MISMATCH env.sb expected 5, got 4")
      `FAIL_UNLESS_STR_EQUAL(line_of("names", UVM_WARNING, "W", "w"),
         "UVM_WARNING        0.000ns my_scoreboard.sv:120 W env.sb w")
   `SVTEST_END

   `SVTEST(the_test_top_prefix_can_be_kept)
      `FAIL_UNLESS_STR_EQUAL(line_of("keep_top"),
         "E1           0.000ns my_scoreboard.sv:120 SB_MISMATCH uvm_test_top.env.sb expected 5, got 4")
   `SVTEST_END

   `SVTEST(custom_style_prints_the_listed_fields)
      `FAIL_UNLESS_STR_EQUAL(line_of("custom"), {hexk_str::pad("SB_MISMATCH", 24, 1), " expected 5, got 4"})
      `FAIL_UNLESS_STR_EQUAL(line_of("custom_counter"), {"E1   ", " 1 ", hexk_str::pad("SB_MISMATCH", 24, 1)})
   `SVTEST_END

   `SVTEST(custom_style_without_fields_is_the_compact_layout)
      `FAIL_UNLESS_STR_EQUAL(line_of("custom_empty"), line_of(""))
   `SVTEST_END

   `SVTEST(the_running_number_can_be_switched_off)
      `FAIL_UNLESS_STR_EQUAL(line_of("unnumbered"), {"E    ", " ", hexk_str::pad("SB_MISMATCH", 24, 1)})
   `SVTEST_END

   `SVTEST(color_wraps_the_severity_column)
      `FAIL_UNLESS_STR_EQUAL(line_of("color"),
         {"\033[31m", "E1   ", "\033[0m", " ", hexk_str::pad("SB_MISMATCH", 24, 1)})
      `FAIL_UNLESS_STR_EQUAL(line_of("color", UVM_INFO), {"I    ", " ", hexk_str::pad("SB_MISMATCH", 24, 1)})
   `SVTEST_END

   `SVTEST(time_is_printed_in_the_configured_unit_and_precision)
      // One literal with all ten digits loses the last one on Questa 2024.1.
      advance_to(5ms + 1234567ps);
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_NS, 3), "5001234.567ns")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_NS, 0), "5001235ns")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_PS, 0), "5001234567ps")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_US, 3), "5001.235us")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_US, 6), "5001.234567us")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_MS, 6), "5.001235ms")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_FS, 0), "5001234567000fs")
   `SVTEST_END

   `SVTEST(a_time_unit_that_is_no_member_of_the_enum_is_shown_as_ns)
      `FAIL_UNLESS_STR_EQUAL(time_of(hexk_time_unit_e'(99), 3), "5001234.567ns")
   `SVTEST_END

   `SVTEST(a_time_precision_below_one_fs_is_cut_to_what_the_unit_has)
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_NS, 64), "5001234.567000ns")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_FS, 3), "5001234567000fs")
      `FAIL_UNLESS_STR_EQUAL(time_of(HEXK_TIME_S, 15), "0.005001234567000s")
   `SVTEST_END

   `SVTEST(a_change_of_the_cfg_object_has_no_effect_until_set_cfg)
      `FAIL_UNLESS_STR_EQUAL(after_a_cfg_change(),
         {hexk_str::pad("SB_MISMATCH", 24, 1), " text 0 / SB_MISMATCH 1"})
      `FAIL_UNLESS_STR_EQUAL(style_after_changing_what_get_cfg_returned(), "HEXK_FMT_CUSTOM")
   `SVTEST_END

   `SVTEST(messages_are_counted_by_severity_and_id)
      `FAIL_UNLESS_STR_EQUAL(counts_after_feed(), "2 1 2 1 0")
   `SVTEST_END

   `SVTEST(an_id_with_several_severities_has_a_count_for_each)
      `FAIL_UNLESS_STR_EQUAL(counts_of_a_shared_id(), "1 2 1 0 lines=3")
   `SVTEST_END

   `SVTEST(the_summary_lists_counts_from_fatal_to_info)
      `FAIL_UNLESS_STR_EQUAL(summary_line(0), "Messages by severity and ID:")
      `FAIL_UNLESS_STR_EQUAL(summary_line(1), "  UVM_FATAL         1  SB_GIVE_UP")
      `FAIL_UNLESS_STR_EQUAL(summary_line(2), "  UVM_ERROR         2  SB_MISMATCH")
      `FAIL_UNLESS_STR_EQUAL(summary_line(3), "  UVM_WARNING       1  agent_1.DRV_RETRY")
      `FAIL_UNLESS_STR_EQUAL(summary_line(4), "  UVM_WARNING       1  agent_2.DRV_RETRY")
      `FAIL_UNLESS_STR_EQUAL(summary_line(5), "  UVM_WARNING       1  agent_10.DRV_RETRY")
      `FAIL_UNLESS_STR_EQUAL(summary_line(6), "  UVM_INFO          2  MON_ITEM")
   `SVTEST_END

   `SVTEST(the_summary_groups_the_noisiest_ids_by_denumbered_name)
      `FAIL_UNLESS_STR_EQUAL(summary_line(7),
         "Noisiest IDs: agent_#.DRV_RETRY (3), MON_ITEM (2), SB_MISMATCH (2), SB_GIVE_UP (1)")
   `SVTEST_END

   `SVTEST(the_summary_shows_the_first_error)
      `FAIL_UNLESS_STR_EQUAL(summary_line(8), "First error: @ 5001234.567ns [SB_MISMATCH] first text")
      `FAIL_UNLESS_STR_EQUAL(summary_line(9), "")
   `SVTEST_END

   `SVTEST(the_summary_of_a_quiet_run_says_none)
      `FAIL_UNLESS_STR_EQUAL(summary_line(1, 0), "Noisiest IDs: none")
      `FAIL_UNLESS_STR_EQUAL(summary_line(2, 0), "First error: none")
   `SVTEST_END

   `SVTEST(listeners_see_warnings_errors_and_fatals)
      `FAIL_UNLESS_STR_EQUAL(listener_ids(),
         "agent_1.DRV_RETRY,agent_2.DRV_RETRY,agent_10.DRV_RETRY,SB_MISMATCH,SB_MISMATCH,SB_GIVE_UP")
   `SVTEST_END

   `SVTEST(triggers_match_the_id_or_the_text)
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_INFO, "SB_ITEM", "plain"), "10")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_INFO, "MY_SB_ITEM", "plain"), "00")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_INFO, "DRV", "WATCH this"), "01")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_ERROR, "DRV", "expected 5, got 4"), "01")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_ERROR, "SB_WATCH", "x"), "11")
   `SVTEST_END

   `SVTEST(the_kept_columns_follow_each_message)
      `FAIL_UNLESS_STR_EQUAL(lines_of_different_messages(),
         {"I     T my_scoreboard.sv:120 MON_ITEM env.sb a | I     T drv.sv:7 DRV env.drv b | ",
          "I     T my_scoreboard.sv:120 MON_ITEM env.sb a"})
   `SVTEST_END

   `SVTEST(the_time_column_follows_the_time_of_each_message)
      times_of_two_steps(times_result);
      `FAIL_UNLESS_STR_EQUAL(times_result, "same")
   `SVTEST_END

   `SVTEST(a_full_store_of_columns_is_emptied_and_built_again)
      `FAIL_UNLESS_STR_EQUAL(id_column_after_many_ids(), "ID_0")
   `SVTEST_END

   `SVTEST(a_trigger_on_the_text_is_checked_for_every_message_of_an_id)
      `FAIL_UNLESS_STR_EQUAL(markers_of_one_id(), "1 0")
   `SVTEST_END

   `SVTEST(triggers_match_a_file_and_line)
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_INFO, "DRV", "x", "/a/b/my_driver.sv", 12), "10")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_INFO, "DRV", "x", "/a/b/my_driver.sv", 13), "00")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_INFO, "DRV", "x", "/a/b/other.sv", 12), "00")
   `SVTEST_END

   `SVTEST(report_summarize_writes_the_table_to_a_file_it_is_given)
      `FAIL_UNLESS_STR_EQUAL(summary_in_a_file(), "Messages by severity and ID:")
   `SVTEST_END

   `SVTEST(a_location_trigger_is_a_name_a_colon_and_digits)
      `FAIL_UNLESS_STR_EQUAL(decisions("location_like", UVM_INFO, "DRV", "x", "/w/a:b", 7), "01")
      `FAIL_UNLESS_STR_EQUAL(decisions("location_like", UVM_INFO, "DRV", "x", "/w/a:b", 8), "00")
      `FAIL_UNLESS_STR_EQUAL(decisions("location_like", UVM_INFO, "DRV", "at x.sv: here", "/w/z.sv", 1), "01")
      `FAIL_UNLESS_STR_EQUAL(decisions("location_like", UVM_INFO, "DRV", "line :42", "/w/z.sv", 42), "01")
      `FAIL_UNLESS_STR_EQUAL(decisions("location_like", UVM_INFO, "DRV", "plain", "/w/z.sv", 42), "00")
   `SVTEST_END

   `SVTEST(stack_traces_follow_the_severity_switches)
      `FAIL_UNLESS_STR_EQUAL(decisions("", UVM_FATAL, "X", "x"), "10")
      `FAIL_UNLESS_STR_EQUAL(decisions("", UVM_ERROR, "X", "x"), "00")
      `FAIL_UNLESS_STR_EQUAL(decisions("trace_errors", UVM_ERROR, "X", "x"), "10")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_FATAL, "X", "x"), "00")
   `SVTEST_END

   `SVTEST(stack_traces_are_printed_for_messages_from_uvm_sources)
      `FAIL_UNLESS_STR_EQUAL(decisions("", UVM_WARNING, "X", "x", "/tools/uvm/src/base/uvm_objection.svh", 7), "10")
      `FAIL_UNLESS_STR_EQUAL(decisions("", UVM_INFO, "X", "x", "/tools/uvm/src/base/uvm_objection.svh", 7), "00")
      `FAIL_UNLESS_STR_EQUAL(decisions("", UVM_WARNING, "X", "x", "/work/tb/my_uvm_env.sv", 7), "00")
      `FAIL_UNLESS_STR_EQUAL(decisions("triggers", UVM_WARNING, "X", "x", "/tools/uvm/src/base/uvm_root.svh", 7), "00")
   `SVTEST_END

   `SVTEST(apply_plusargs_overrides_the_cfg)
      `FAIL_UNLESS_STR_EQUAL(cfg_after_plusargs(), "HEXK_FMT_CUSTOM 2 us 1 ^SB_|my_driver.sv:12 WATCH_ME")
   `SVTEST_END

   `SVTEST(a_cfg_can_be_cloned)
      `FAIL_UNLESS_STR_EQUAL(cloned_cfg(),
         "style=HEXK_FMT_COMPACT time=3 digits ps widths file_line=12 id=8 context=6 triggers stacktrace=0 marker=1")
   `SVTEST_END

   `SVTEST(a_cfg_ignores_a_copy_from_an_object_of_another_class)
      `FAIL_UNLESS_STR_EQUAL(cfg_after_a_copy_from_another_class(), "kept 1")
   `SVTEST_END

   `SVTEST(install_makes_it_the_report_server_of_the_simulation)
      `FAIL_UNLESS_STR_EQUAL(installed_counts(), "1 1 1")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_report_server_unit_test
