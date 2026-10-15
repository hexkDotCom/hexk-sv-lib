// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_server.sv
//
// UVM report server with a configurable line layout, stack traces and marker lines on
// selected messages, message listeners, and an end-of-test summary table per severity and ID.
// Install it once, before run_test(), with hexk_report_server::install(cfg). Without a cfg
// the message lines look exactly as UVM prints them; what the default cfg adds is a stack
// trace for fatals and for warnings, errors and fatals of UVM itself, and the summary table
// after UVM's summary. Everything else in UVM reporting keeps working: verbosity, actions,
// severity and ID overrides, report catchers, log files.
// Layouts: HEXK_FMT_UVM is UVM's own text; HEXK_FMT_COMPACT is severity, time, file:line,
// ID, context and message in fixed-width columns; HEXK_FMT_CUSTOM takes the columns from
// cfg.fields. See docs/api/hexk_report_server.md for examples of each.
// The column texts that repeat from message to message (severity, time in one time step,
// file:line, ID, context) and the trigger decisions on an ID are built once and kept; each
// store is emptied when it reaches STORE_LIMIT entries, and set_cfg forgets them all.
//
//! @module    hexk_report_server
//! @since     0.7.0
//! @stability experimental
//! @serves    MSG-8 MSG-9
//! @emits     HEXK_REPORT_SUMMARY:info
//! @plusargs  (none)

`ifndef HEXK_REPORT_SERVER_SV
`define HEXK_REPORT_SERVER_SV

class hexk_report_server extends uvm_default_report_server;

   // Width of the time column of the compact and custom layouts.
   localparam int unsigned TIME_WIDTH = 14;

   // Width of the severity column with one letter and a running number.
   localparam int unsigned LETTER_WIDTH = 5;

   // Width of the severity column with the UVM severity name.
   localparam int unsigned NAME_WIDTH = 11;

   // Number of IDs listed as the noisiest in the summary.
   localparam int unsigned TOP_COUNT = 5;

   // Number of severities: info, warning, error, fatal.
   localparam int unsigned SEVERITIES = 4;

   // Power of ten of the smallest time a simulation has, 1 fs, in seconds.
   localparam int FS_EXPONENT = -15;

   // Prefix of the hierarchical name of everything below the test.
   localparam string TEST_TOP_PREFIX = "uvm_test_top.";

   // Largest number of entries of a store of column texts or trigger decisions; a full store is emptied.
   localparam int unsigned STORE_LIMIT = 4096;

   // Number of messages of one ID, one counter per severity.
   typedef bit [SEVERITIES-1:0][31:0] id_counts_t;

   local hexk_report_cfg     active_cfg;
   local hexk_regex          stacktrace_filters            [         $];
   local string              stacktrace_locations          [         $];
   local hexk_regex          marker_filters                [         $];
   local string              marker_locations              [         $];
   local hexk_msg_listener   listeners                     [         $];
   local id_counts_t         id_counts[string];
   local string              first_error;

   // Values that follow from active_cfg; prepare() works them out once for all messages.
   local hexk_report_field_e layout                        [         $];
   local string              unit_text;
   local real                ticks_per_second;
   local longint unsigned    ticks_per_unit;

   // Column texts that were built before: the severity column without a running number, by severity; the
   // time column of the time step time_column_at; file:line by file and line; the ID and the context
   // columns by ID and by the name of the reporter. Emptied by prepare().
   local string              severity_columns              [SEVERITIES];
   local bit                 has_severity_column           [SEVERITIES];
   local string              time_column;
   local realtime            time_column_at;
   local bit                 has_time_column;
   local string              location_columns[string][int];
   local int unsigned        location_count;
   local string              id_columns[string];
   local string              context_columns[string];

   // Whether a marker or a stack trace trigger matches an ID, by ID. Emptied by prepare().
   local bit                 marker_by_id[string];
   local bit                 stacktrace_by_id[string];

   `uvm_object_utils(hexk_report_server)

   // Creates a server that prints UVM's own layout until set_cfg is called.
   function new(string name = "hexk_report_server");
      super.new(name);
      active_cfg       = hexk_report_cfg::type_id::create("active_cfg");
      active_cfg.style = HEXK_FMT_UVM;
      prepare();
   endfunction : new

   // Creates a server, gives it cfg (UVM layout when null) and makes it the report server of the simulation.
   static function hexk_report_server install(hexk_report_cfg cfg = null);
      hexk_report_server server = hexk_report_server::type_id::create("hexk_report_server");
      if (cfg != null) begin
         server.set_cfg(cfg);
      end
      uvm_report_server::set_server(server);
      return server;
   endfunction : install

   // The report server of the simulation if it is a hexk_report_server, otherwise null.
   static function hexk_report_server get_installed();
      hexk_report_server server;
      if (!$cast(server, uvm_report_server::get_server())) begin
         return null;
      end
      return server;
   endfunction : get_installed

   // Takes a copy of a configuration: a later change of cfg has no effect until set_cfg is called again.
   // A null cfg is ignored.
   function void set_cfg(hexk_report_cfg cfg);
      hexk_report_cfg taken;
      int unsigned    max_precision;
      string          unit;
      if (cfg == null || !$cast(taken, cfg.clone())) begin
         return;
      end
      unit = hexk_report_cfg::time_unit_text(taken.time_unit);
      // More digits would be below 1 fs, and the number of the time column would not fit 64 bits.
      max_precision = $unsigned(hexk_report_cfg::unit_exponent(taken.time_unit) - FS_EXPONENT);
      if (taken.time_precision > max_precision) begin
         `uvm_warning("HEXK_REPORT_CFG", $sformatf(
                                             "time_precision %0d shows digits below 1 fs for time_unit %s; using %0d",
                                             taken.time_precision, unit, max_precision))
         taken.time_precision = max_precision;
      end
      // Used from here on only, after the correction: the warning above is printed by the cfg in use until now.
      active_cfg = taken;
      split_triggers(taken.stacktrace_triggers, stacktrace_filters, stacktrace_locations);
      split_triggers(taken.marker_triggers, marker_filters, marker_locations);
      prepare();
   endfunction : set_cfg

   // Returns a copy of the configuration in use; change it and give it to set_cfg.
   function hexk_report_cfg get_cfg();
      hexk_report_cfg duplicate;
      void'($cast(duplicate, active_cfg.clone()));
      return duplicate;
   endfunction : get_cfg

   // Registers an object that is told about every warning, error and fatal message.
   function void add_listener(hexk_msg_listener listener);
      if (listener != null) begin
         listeners.push_back(listener);
      end
   endfunction : add_listener

   // Number of messages of this ID and severity that were issued.
   function int unsigned get_count(string id, uvm_severity severity);
      return id_counts.exists(id) ? id_counts[id][severity] : 0;
   endfunction : get_count

   // Text of the summary: one line per severity and ID, the noisiest IDs, and the first error.
   function string summary();
      string       lines    [$];
      string       ids      [$];
      string       line;
      uvm_severity severity;
      lines.push_back("Messages by severity and ID:");
      for (int level = int'(SEVERITIES) - 1; level >= 0; level--) begin
         severity = uvm_severity'(level);
         ids.delete();
         foreach (id_counts[id]) begin
            if (id_counts[id][severity] != 0) begin
               ids.push_back(id);
            end
         end
         hexk_str::natural_sort(ids);
         foreach (ids[i]) begin
            line = hexk_str::pad(severity.name(), NAME_WIDTH, 1);
            line = $sformatf("  %s %7d  %s", line, get_count(ids[i], severity), ids[i]);
            lines.push_back(line);
         end
      end
      lines.push_back({"Noisiest IDs: ", noisiest_ids()});
      lines.push_back({"First error: ", (first_error.len() == 0) ? "none" : first_error});
      return hexk_str::join_str(lines, "\n");
   endfunction : summary

   // True when the cfg asks for a stack trace on this message.
   function bit gets_stacktrace(uvm_report_message report_message);
      uvm_severity severity = report_message.get_severity();
      if (severity == UVM_FATAL && active_cfg.stacktrace_on_fatal) begin
         return 1;
      end
      if (severity == UVM_ERROR && active_cfg.stacktrace_on_error) begin
         return 1;
      end
      if (severity != UVM_INFO && active_cfg.stacktrace_on_uvm_internal && is_uvm_internal(report_message)) begin
         return 1;
      end
      return is_triggered(report_message, stacktrace_filters, stacktrace_locations, stacktrace_by_id);
   endfunction : gets_stacktrace

   // True when the cfg asks for a marker line in front of this message.
   function bit gets_marker(uvm_report_message report_message);
      return is_triggered(report_message, marker_filters, marker_locations, marker_by_id);
   endfunction : gets_marker

   // Builds the text of one report line in the configured layout.
   function string compose_report_message(uvm_report_message report_message, string report_object_name = "");
      string line;
      if (active_cfg.style == HEXK_FMT_UVM) begin
         return super.compose_report_message(report_message, report_object_name);
      end
      foreach (layout[i]) begin
         if (i != 0) begin
            line = {line, " "};
         end
         line = {line, field_text(layout[i], report_message, report_object_name)};
      end
      return line;
   endfunction : compose_report_message

   // Counts the message, adds marker line and stack trace, tells the listeners, then lets UVM act on it.
   function void execute_report_message(uvm_report_message report_message, string composed_message);
      uvm_severity severity = report_message.get_severity();
      string       id = report_message.get_id();
      string       text = composed_message;
      if (!id_counts.exists(id)) begin
         id_counts[id] = '0;
      end
      id_counts[id][severity]++;
      if (severity != UVM_INFO) begin
         if (first_error.len() == 0 && severity != UVM_WARNING) begin
            first_error = $sformatf("@ %s [%s] %s", time_text(), report_message.get_id(), report_message.get_message());
         end
         foreach (listeners[i]) begin
            listeners[i].on_message(report_message);
         end
      end
      if (gets_marker(report_message)) begin
         text = {"HEXK_MARKER: ", report_message.get_id(), "\n", text};
      end
      // A fatal message ends the simulation inside the call below, so the trace comes first.
      if (gets_stacktrace(report_message)) begin
         `HEXK_STACKTRACE;
      end
      super.execute_report_message(report_message, text);
   endfunction : execute_report_message

   // Prints UVM's summary and then the summary table of this server; with a file other than the default, the
   // table is also written to that file.
   function void report_summarize(UVM_FILE file = `HEXK_UVM_SUMMARY_FILE);
      super.report_summarize(file);
      `uvm_info("HEXK_REPORT_SUMMARY", {"\n", summary()}, UVM_NONE)
      if (file != `HEXK_UVM_SUMMARY_FILE) begin
         $fdisplay(file, "%s", summary());
      end
   endfunction : report_summarize

   // Works out what follows from active_cfg alone: the columns of a line and the numbers of the time column.
   local function void prepare();
      int shift = int'(active_cfg.time_precision) - hexk_report_cfg::unit_exponent(active_cfg.time_unit);
      if (active_cfg.style == HEXK_FMT_CUSTOM && active_cfg.fields.size() != 0) begin
         layout = active_cfg.fields;
      end else begin
         layout = '{
             HEXK_FLD_SEVERITY,
             HEXK_FLD_TIME,
             HEXK_FLD_FILE_LINE,
             HEXK_FLD_ID,
             HEXK_FLD_CONTEXT,
             HEXK_FLD_MESSAGE
         };
      end
      unit_text           = hexk_report_cfg::time_unit_text(active_cfg.time_unit);
      ticks_per_second    = 10.0 ** shift;
      ticks_per_unit      = 64'd10 ** active_cfg.time_precision;
      // The columns and the trigger decisions depend on the cfg.
      has_severity_column = '{default: 0};
      has_time_column     = 0;
      location_columns.delete();
      location_count = 0;
      id_columns.delete();
      context_columns.delete();
      marker_by_id.delete();
      stacktrace_by_id.delete();
   endfunction : prepare

   // Text of one column for a message.
   local function string field_text(hexk_report_field_e field, uvm_report_message report_message,
                                    string report_object_name);
      uvm_severity severity = report_message.get_severity();
      case (field)
         HEXK_FLD_SEVERITY:  return severity_column(severity);
         HEXK_FLD_COUNTER:   return $sformatf("%0d", get_severity_count(severity) + 1);
         HEXK_FLD_TIME:      return time_column_now();
         HEXK_FLD_FILE_LINE: return location_column(report_message);
         HEXK_FLD_ID:        return id_column(report_message.get_id());
         HEXK_FLD_CONTEXT:   return context_column(report_message, report_object_name);
         default:            return message_of(report_message);
      endcase
   endfunction : field_text

   // Severity column; kept per severity when it has no running number, which changes with every message.
   local function string severity_column(uvm_severity severity);
      int level = int'(severity);
      if (active_cfg.severity_letter && active_cfg.numbered && severity != UVM_INFO) begin
         return severity_text(severity);
      end
      if (!has_severity_column[level]) begin
         severity_columns[level]    = severity_text(severity);
         has_severity_column[level] = 1;
      end
      return severity_columns[level];
   endfunction : severity_column

   // Time column; built once per time step.
   local function string time_column_now();
      // $realtime and not $time: it tells time steps apart that are less than 1 ps apart.
      if (!has_time_column || time_column_at != $realtime) begin
         time_column     = hexk_str::pad(time_text(), TIME_WIDTH);
         time_column_at  = $realtime;
         has_time_column = 1;
      end
      return time_column;
   endfunction : time_column_now

   // file:line column; kept per file and line.
   local function string location_column(uvm_report_message report_message);
      string file = report_message.get_filename();
      int    line = report_message.get_line();
      if (location_columns.exists(file) && location_columns[file].exists(line)) begin
         return location_columns[file][line];
      end
      if (location_count >= STORE_LIMIT) begin
         location_columns.delete();
         location_count = 0;
      end
      location_columns[file][line] = fit(location_of(report_message), active_cfg.file_line_width, 1);
      location_count++;
      return location_columns[file][line];
   endfunction : location_column

   // ID column; kept per ID.
   local function string id_column(string id);
      if (!id_columns.exists(id)) begin
         if (id_columns.size() >= STORE_LIMIT) begin
            id_columns.delete();
         end
         id_columns[id] = fit(id, active_cfg.id_width, 0);
      end
      return id_columns[id];
   endfunction : id_column

   // Context column; kept per reporter for messages without a context string of their own.
   local function string context_column(uvm_report_message report_message, string report_object_name);
      uvm_report_handler handler = report_message.get_report_handler();
      string             reporter = report_object_name;
      if (report_message.get_context().len() != 0) begin
         return fit(context_of(report_message, report_object_name), active_cfg.context_width, 1);
      end
      if (reporter.len() == 0 && handler != null) begin
         reporter = handler.get_full_name();
      end
      if (!context_columns.exists(reporter)) begin
         if (context_columns.size() >= STORE_LIMIT) begin
            context_columns.delete();
         end
         context_columns[reporter] = fit(context_of(report_message, report_object_name), active_cfg.context_width, 1);
      end
      return context_columns[reporter];
   endfunction : context_column

   // Severity column: letter or UVM name, running number, colour.
   local function string severity_text(uvm_severity severity);
      string text = severity.name();
      int unsigned width = NAME_WIDTH;
      if (active_cfg.severity_letter) begin
         text  = severity_letter(severity);
         width = LETTER_WIDTH;
         if (active_cfg.numbered && severity != UVM_INFO) begin
            text = $sformatf("%s%0d", text, get_severity_count(severity) + 1);
         end
      end
      text = hexk_str::pad(text, width, 1);
      if (active_cfg.color && severity != UVM_INFO) begin
         text = {color_code(severity), text, "\033[0m"};
      end
      return text;
   endfunction : severity_text

   // One-letter name of a severity.
   local function string severity_letter(uvm_severity severity);
      case (severity)
         UVM_INFO:    return "I";
         UVM_WARNING: return "W";
         UVM_ERROR:   return "E";
         default:     return "F";
      endcase
   endfunction : severity_letter

   // ANSI escape code that starts the colour of a severity.
   local function string color_code(uvm_severity severity);
      case (severity)
         UVM_WARNING: return "\033[33m";
         UVM_ERROR:   return "\033[31m";
         default:     return "\033[1;31m";
      endcase
   endfunction : color_code

   // Current simulation time in the configured unit and precision, such as "120.500ns".
   local function string time_text();
      // Dividing by 1s gives seconds whatever the time unit of this package is.
      real             scaled = ($realtime / 1s) * ticks_per_second;
      longint unsigned ticks = longint'(scaled);
      string           fraction;
      if (active_cfg.time_precision == 0) begin
         return $sformatf("%0d%s", ticks, unit_text);
      end
      fraction = hexk_str::pad($sformatf("%0d", ticks % ticks_per_unit), active_cfg.time_precision, 0, "0");
      return $sformatf("%0d.%s%s", ticks / ticks_per_unit, fraction, unit_text);
   endfunction : time_text

   // "file:line" of a message without the directory, or "" when the message has no file.
   local function string location_of(uvm_report_message report_message);
      string file = hexk_str::basename(report_message.get_filename());
      if (file.len() == 0) begin
         return "";
      end
      return $sformatf("%s:%0d", file, report_message.get_line());
   endfunction : location_of

   // Context column: hierarchical name of the reporter, plus the context string if the message has one.
   local function string context_of(uvm_report_message report_message, string report_object_name);
      uvm_report_handler handler = report_message.get_report_handler();
      string             text = report_object_name;
      string             prefix = TEST_TOP_PREFIX;
      if (text.len() == 0 && handler != null) begin
         text = handler.get_full_name();
      end
      if (active_cfg.strip_test_top && hexk_str::starts_with(text, prefix)) begin
         text = text.substr(prefix.len(), text.len() - 1);
      end
      if (report_message.get_context().len() != 0) begin
         text = {text, "@@", report_message.get_context()};
      end
      return text;
   endfunction : context_of

   // Message column: the text, followed by the message elements if there are any.
   local function string message_of(uvm_report_message report_message);
      uvm_report_message_element_container elements = report_message.get_element_container();
      if (elements == null || elements.size() == 0) begin
         return report_message.get_message();
      end
      return {report_message.get_message(), "\n", elements.sprint()};
   endfunction : message_of

   // Pads or shortens text to width; a width of 0 leaves it alone.
   local function string fit(string text, int unsigned width, bit keep_right);
      if (width == 0) begin
         return text;
      end
      return hexk_str::pad(hexk_str::truncate(text, width, keep_right), width, 1);
   endfunction : fit

   // Sorts trigger strings into regular expression filters and "file:line" locations.
   local function void split_triggers(ref string triggers[$], ref hexk_regex filters[$], ref string locations[$]);
      hexk_regex filter;
      filters.delete();
      locations.delete();
      foreach (triggers[i]) begin
         if (is_location(triggers[i])) begin
            locations.push_back(triggers[i]);
         end else begin
            filter = new(triggers[i]);
            filters.push_back(filter);
         end
      end
   endfunction : split_triggers

   // 1 when a trigger is a location: a name, a colon and decimal digits at the end. A small parser and not a
   // regular expression, which UVM matches as a glob when it is compiled without its DPI code.
   local function bit is_location(string trigger);
      int colon = hexk_str::rfind(trigger, ":");
      if (colon < 1 || colon == trigger.len() - 1) begin
         return 0;
      end
      for (int i = colon + 1; i < trigger.len(); i++) begin
         if (trigger[i] < "0" || trigger[i] > "9") begin
            return 0;
         end
      end
      return 1;
   endfunction : is_location

   // True when the ID, the text or the location of the message matches one of the triggers. Whether a
   // filter matches the ID is kept per ID in by_id; the text changes from message to message.
   local function bit is_triggered(uvm_report_message report_message, ref hexk_regex filters[$],
                                   ref string locations[$], ref bit by_id[string]);
      string location;
      string id;
      string text;
      if (locations.size() != 0) begin
         location = location_of(report_message);
         foreach (locations[i]) begin
            if (locations[i] == location) begin
               return 1;
            end
         end
      end
      if (filters.size() == 0) begin
         return 0;
      end
      id = report_message.get_id();
      if (!by_id.exists(id)) begin
         if (by_id.size() >= STORE_LIMIT) begin
            by_id.delete();
         end
         by_id[id] = 0;
         foreach (filters[i]) begin
            if (filters[i].is_match(id)) begin
               by_id[id] = 1;
               break;
            end
         end
      end
      if (by_id[id]) begin
         return 1;
      end
      text = report_message.get_message();
      foreach (filters[i]) begin
         if (filters[i].is_match(text)) begin
            return 1;
         end
      end
      return 0;
   endfunction : is_triggered

   // True when the message was issued from a source file of the UVM library (a file named uvm_*).
   local function bit is_uvm_internal(uvm_report_message report_message);
      return hexk_str::starts_with(hexk_str::basename(report_message.get_filename()), "uvm_");
   endfunction : is_uvm_internal

   // The TOP_COUNT IDs with the most messages, with numbers in IDs replaced by "#", as "ID (count), ...".
   local function string noisiest_ids();
      int unsigned totals[string];
      string       picked[$];
      string       best;
      string       group;
      foreach (id_counts[id]) begin
         group = hexk_str::denumber(id);
         if (!totals.exists(group)) begin
            totals[group] = 0;
         end
         for (int unsigned level = 0; level < SEVERITIES; level++) begin
            totals[group] += id_counts[id][level];
         end
      end
      repeat (TOP_COUNT) begin
         best = "";
         foreach (totals[id]) begin
            if (best.len() == 0 || totals[id] > totals[best]) begin
               best = id;
            end
         end
         if (totals.size() == 0) begin
            break;
         end
         picked.push_back($sformatf("%s (%0d)", best, totals[best]));
         totals.delete(best);
      end
      return (picked.size() == 0) ? "none" : hexk_str::join_str(picked, ", ");
   endfunction : noisiest_ids

endclass : hexk_report_server

`endif  // HEXK_REPORT_SERVER_SV
