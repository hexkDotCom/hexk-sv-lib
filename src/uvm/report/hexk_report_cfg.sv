// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_cfg.sv
//
// Configuration of hexk_report_server: layout of a report line, column widths, time unit,
// and the triggers for stack traces and marker lines.
// Create one, set the fields, optionally call apply_plusargs() so the command line can
// override them, and hand it to hexk_report_server::install. The server takes a copy when the
// cfg is installed; change the fields and call hexk_report_server::set_cfg again to apply changes.
// A trigger is a regular expression that is matched against the message ID and the message
// text, or, when it ends in ":<number>", a file name and line ("my_driver.sv:120").
//
//! @module    hexk_report_server
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_REPORT_CFG:warning HEXK_COPY_TYPE:fatal
//! @plusargs  +hexk_report_style +hexk_report_fields +hexk_report_time_unit +hexk_report_color
//! @plusargs  +hexk_stacktrace +hexk_marker

`ifndef HEXK_REPORT_CFG_SV
`define HEXK_REPORT_CFG_SV

// Layout of a report line: UVM's own, the fixed-column layout of the library, or the fields listed in the cfg.
typedef enum bit [1:0] {
   HEXK_FMT_UVM,
   HEXK_FMT_COMPACT,
   HEXK_FMT_CUSTOM
} hexk_report_style_e;

// One column of a report line.
typedef enum bit [2:0] {
   HEXK_FLD_SEVERITY,
   HEXK_FLD_COUNTER,
   HEXK_FLD_TIME,
   HEXK_FLD_FILE_LINE,
   HEXK_FLD_ID,
   HEXK_FLD_CONTEXT,
   HEXK_FLD_MESSAGE
} hexk_report_field_e;

// Unit of the time column of a report line.
typedef enum bit [2:0] {
   HEXK_TIME_FS,
   HEXK_TIME_PS,
   HEXK_TIME_NS,
   HEXK_TIME_US,
   HEXK_TIME_MS,
   HEXK_TIME_S
} hexk_time_unit_e;

class hexk_report_cfg extends uvm_object;

   // Layout of a report line.
   hexk_report_style_e style = HEXK_FMT_COMPACT;

   // Columns of the custom layout, in order; when empty the compact columns are used.
   hexk_report_field_e fields[$];

   // Width of the file:line column; 0 means as long as needed. Long values keep their right end.
   int unsigned file_line_width = 28;

   // Width of the ID column; 0 means as long as needed. Long values keep their left end.
   int unsigned id_width = 24;

   // Width of the context column; 0 means as long as needed. Long values keep their right end.
   int unsigned context_width = 40;

   // Unit of the time column.
   hexk_time_unit_e time_unit = HEXK_TIME_NS;

   // Number of digits after the decimal point in the time column; digits below 1 fs are not shown.
   int unsigned time_precision = 3;

   // Severity as one letter (I, W, E, F) instead of the UVM name.
   bit severity_letter = 1;

   // Append the running number of the warning, error or fatal to the severity letter: E3, W12.
   bit numbered = 1;

   // Drop the leading "uvm_test_top." from the context column.
   bit strip_test_top = 1;

   // Colour the severity column with ANSI escape codes, for terminals.
   bit color;

   // Print a stack trace for every fatal message.
   bit stacktrace_on_fatal = 1;

   // Print a stack trace for every error message.
   bit stacktrace_on_error;

   // Print a stack trace for warnings, errors and fatals that come from the UVM library itself.
   bit stacktrace_on_uvm_internal = 1;

   // Messages that get a stack trace: regular expressions on ID or text, or "file:line".
   string stacktrace_triggers[$];

   // Messages that get a marker line in front of them: regular expressions on ID or text, or "file:line".
   string marker_triggers[$];

   `uvm_object_utils(hexk_report_cfg)

   // Creates a cfg with the default values listed above.
   function new(string name = "hexk_report_cfg");
      super.new(name);
   endfunction : new

   // Overrides fields from the command line; see the plusarg table in docs/api/hexk_report_server.md.
   function void apply_plusargs();
      string items[$];
      // A plusarg that is given, also with an empty value, is checked; one that is absent changes nothing.
      if (hexk_plusarg::has("hexk_report_style")) begin
         apply_style(hexk_plusarg::get_str("hexk_report_style", ""));
      end
      hexk_plusarg::get_list("hexk_report_fields", items);
      apply_fields(items);
      if (hexk_plusarg::has("hexk_report_time_unit")) begin
         apply_time_unit(hexk_plusarg::get_str("hexk_report_time_unit", ""));
      end
      apply_color();
      hexk_plusarg::get_list("hexk_stacktrace", items);
      foreach (items[i]) begin
         stacktrace_triggers.push_back(items[i]);
      end
      hexk_plusarg::get_list("hexk_marker", items);
      foreach (items[i]) begin
         marker_triggers.push_back(items[i]);
      end
   endfunction : apply_plusargs

   // Text of a unit as the time column shows it, such as "ns".
   static function string time_unit_text(hexk_time_unit_e unit);
      case (unit)
         HEXK_TIME_FS: return "fs";
         HEXK_TIME_PS: return "ps";
         HEXK_TIME_US: return "us";
         HEXK_TIME_MS: return "ms";
         HEXK_TIME_S:  return "s";
         default:      return "ns";
      endcase
   endfunction : time_unit_text

   // The unit with this short name (fs, ps, ns, us, ms, s, in any case); 0 when the text names no unit.
   static function bit time_unit_of(string text, output hexk_time_unit_e unit);
      hexk_time_unit_e names                [string];
      string           key = text.toupper();
      unit = HEXK_TIME_NS;
      hexk_enum_util#(hexk_time_unit_e)::to_map(names, 1);
      if (!names.exists(key)) begin
         return 0;
      end
      unit = names[key];
      return 1;
   endfunction : time_unit_of

   // Power of ten of a unit in seconds: -9 for HEXK_TIME_NS. The one table of the units.
   static function int unit_exponent(hexk_time_unit_e unit);
      case (unit)
         HEXK_TIME_FS: return -15;
         HEXK_TIME_PS: return -12;
         HEXK_TIME_US: return -6;
         HEXK_TIME_MS: return -3;
         HEXK_TIME_S:  return 0;
         default:      return -9;
      endcase
   endfunction : unit_exponent

   // Number of picoseconds in one of a unit: 0.001 for HEXK_TIME_FS.
   static function real ps_per_unit(hexk_time_unit_e unit);
      return 10.0 ** (unit_exponent(unit) + 12);
   endfunction : ps_per_unit

   // One-line summary of the layout settings, for log messages.
   function string convert2string();
      return $sformatf(
          "style=%s time=%0d digits %s widths file_line=%0d id=%0d context=%0d triggers stacktrace=%0d marker=%0d",
          style.name(),
          time_precision,
          time_unit_text(
              time_unit
          ),
          file_line_width,
          id_width,
          context_width,
          stacktrace_triggers.size(),
          marker_triggers.size()
      );
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member.
   function void do_copy(uvm_object rhs);
      hexk_report_cfg other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      style                      = other.style;
      fields                     = other.fields;
      file_line_width            = other.file_line_width;
      id_width                   = other.id_width;
      context_width              = other.context_width;
      time_unit                  = other.time_unit;
      time_precision             = other.time_precision;
      severity_letter            = other.severity_letter;
      numbered                   = other.numbered;
      strip_test_top             = other.strip_test_top;
      color                      = other.color;
      stacktrace_on_fatal        = other.stacktrace_on_fatal;
      stacktrace_on_error        = other.stacktrace_on_error;
      stacktrace_on_uvm_internal = other.stacktrace_on_uvm_internal;
      stacktrace_triggers        = other.stacktrace_triggers;
      marker_triggers            = other.marker_triggers;
   endfunction : do_copy

   // UVM hook of compare(): compares every member.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_report_cfg other;
      bit same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      same = 1;
      same &= comparer.compare_field_int("style", 64'(style), 64'(other.style), $bits(style));
      same &= comparer.compare_field_int("fields.size()", 64'(fields.size()), 64'(other.fields.size()), 32);
      if (fields.size() == other.fields.size()) begin
         foreach (fields[i]) begin
            same &= comparer.compare_field_int($sformatf("fields[%0d]", i), 64'(fields[i]), 64'(other.fields[i]),
                                               $bits(fields[i]));
         end
      end
      same &= comparer.compare_field_int("file_line_width", 64'(file_line_width), 64'(other.file_line_width), 32);
      same &= comparer.compare_field_int("id_width", 64'(id_width), 64'(other.id_width), 32);
      same &= comparer.compare_field_int("context_width", 64'(context_width), 64'(other.context_width), 32);
      same &= comparer.compare_field_int("time_unit", 64'(time_unit), 64'(other.time_unit), $bits(time_unit));
      same &= comparer.compare_field_int("time_precision", 64'(time_precision), 64'(other.time_precision), 32);
      same &= comparer.compare_field_int("severity_letter", 64'(severity_letter), 64'(other.severity_letter), 1);
      same &= comparer.compare_field_int("numbered", 64'(numbered), 64'(other.numbered), 1);
      same &= comparer.compare_field_int("strip_test_top", 64'(strip_test_top), 64'(other.strip_test_top), 1);
      same &= comparer.compare_field_int("color", 64'(color), 64'(other.color), 1);
      same &= comparer.compare_field_int(
          "stacktrace_on_fatal", 64'(stacktrace_on_fatal), 64'(other.stacktrace_on_fatal), 1
      );
      same &= comparer.compare_field_int(
          "stacktrace_on_error", 64'(stacktrace_on_error), 64'(other.stacktrace_on_error), 1
      );
      same &= comparer.compare_field_int(
          "stacktrace_on_uvm_internal", 64'(stacktrace_on_uvm_internal), 64'(other.stacktrace_on_uvm_internal), 1
      );
      same &= comparer.compare_field_int(
          "stacktrace_triggers.size()", 64'(stacktrace_triggers.size()), 64'(other.stacktrace_triggers.size()), 32
      );
      if (stacktrace_triggers.size() == other.stacktrace_triggers.size()) begin
         foreach (stacktrace_triggers[i]) begin
            same &= comparer.compare_string($sformatf("stacktrace_triggers[%0d]", i), stacktrace_triggers[i],
                                            other.stacktrace_triggers[i]);
         end
      end
      same &= comparer.compare_field_int(
          "marker_triggers.size()", 64'(marker_triggers.size()), 64'(other.marker_triggers.size()), 32
      );
      if (marker_triggers.size() == other.marker_triggers.size()) begin
         foreach (marker_triggers[i]) begin
            same &= comparer.compare_string($sformatf("marker_triggers[%0d]", i), marker_triggers[i],
                                            other.marker_triggers[i]);
         end
      end
      return same;
   endfunction : do_compare

   // UVM hook of print() and sprint(): every member.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_string("style", style.name());
      printer.print_field_int("fields.size()", 64'(fields.size()), 32, UVM_DEC);
      foreach (fields[i]) begin
         printer.print_string($sformatf("fields[%0d]", i), fields[i].name());
      end
      printer.print_field_int("file_line_width", 64'(file_line_width), 32, UVM_DEC);
      printer.print_field_int("id_width", 64'(id_width), 32, UVM_DEC);
      printer.print_field_int("context_width", 64'(context_width), 32, UVM_DEC);
      printer.print_string("time_unit", time_unit.name());
      printer.print_field_int("time_precision", 64'(time_precision), 32, UVM_DEC);
      printer.print_field_int("severity_letter", 64'(severity_letter), 1, UVM_BIN);
      printer.print_field_int("numbered", 64'(numbered), 1, UVM_BIN);
      printer.print_field_int("strip_test_top", 64'(strip_test_top), 1, UVM_BIN);
      printer.print_field_int("color", 64'(color), 1, UVM_BIN);
      printer.print_field_int("stacktrace_on_fatal", 64'(stacktrace_on_fatal), 1, UVM_BIN);
      printer.print_field_int("stacktrace_on_error", 64'(stacktrace_on_error), 1, UVM_BIN);
      printer.print_field_int("stacktrace_on_uvm_internal", 64'(stacktrace_on_uvm_internal), 1, UVM_BIN);
      printer.print_field_int("stacktrace_triggers.size()", 64'(stacktrace_triggers.size()), 32, UVM_DEC);
      foreach (stacktrace_triggers[i]) begin
         printer.print_string($sformatf("stacktrace_triggers[%0d]", i), stacktrace_triggers[i]);
      end
      printer.print_field_int("marker_triggers.size()", 64'(marker_triggers.size()), 32, UVM_DEC);
      foreach (marker_triggers[i]) begin
         printer.print_string($sformatf("marker_triggers[%0d]", i), marker_triggers[i]);
      end
   endfunction : do_print

   // Sets style from its short name (uvm, compact, custom); another text, also an empty one, is a warning.
   local function void apply_style(string text);
      hexk_report_style_e names[string];
      string key = text.toupper();
      hexk_enum_util#(hexk_report_style_e)::to_map(names, 1);
      if (!names.exists(key)) begin
         `uvm_warning("HEXK_REPORT_CFG", $sformatf("+hexk_report_style=%s is not uvm, compact or custom; keeping %s",
                                                   text, style.name()))
         return;
      end
      style = names[key];
   endfunction : apply_style

   // Sets time_unit from its short name (fs, ps, ns, us, ms, s); another text, also an empty one, is a warning.
   local function void apply_time_unit(string text);
      hexk_time_unit_e unit;
      string           kept = time_unit_text(time_unit);
      if (!time_unit_of(text, unit)) begin
         `uvm_warning("HEXK_REPORT_CFG",
                      $sformatf("+hexk_report_time_unit=%s is not fs, ps, ns, us, ms or s; keeping %s", text, kept))
         return;
      end
      time_unit = unit;
   endfunction : apply_time_unit

   // Sets color from +hexk_report_color (1) or +hexk_report_color=<bit value>; another value is a warning.
   local function void apply_color();
      bit    value;
      string given = hexk_plusarg::get_str("hexk_report_color", "");
      case (hexk_plusarg::try_get_bit(
          "hexk_report_color", value
      ))
         hexk_plusarg::HEXK_PLUSARG_VALID: color = value;
         hexk_plusarg::HEXK_PLUSARG_INVALID: begin
            `uvm_warning("HEXK_REPORT_CFG", $sformatf(
                         "+hexk_report_color=%s is not a bit value; keeping %0b", given, color))
         end
         default: ;
      endcase
   endfunction : apply_color

   // Sets fields from their short names (severity, counter, time, ...); an empty list changes nothing.
   local function void apply_fields(ref string items[$]);
      hexk_report_field_e names [string];
      hexk_report_field_e parsed[$];
      string              key;
      if (items.size() == 0) begin
         return;
      end
      hexk_enum_util#(hexk_report_field_e)::to_map(names, 1);
      foreach (items[i]) begin
         key = items[i].toupper();
         if (!names.exists(key)) begin
            `uvm_warning("HEXK_REPORT_CFG",
                         $sformatf("+hexk_report_fields: '%s' is not a field; the fields are not changed", items[i]))
            return;
         end
         parsed.push_back(names[key]);
      end
      fields = parsed;
   endfunction : apply_fields

endclass : hexk_report_cfg

`endif  // HEXK_REPORT_CFG_SV
