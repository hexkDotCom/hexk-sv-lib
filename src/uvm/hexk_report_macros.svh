// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_macros.svh
//
// Report macros for the places where the `uvm_* report macros do not work or do not fit:
// static methods of UVM classes, modules and interfaces, and classes derived from
// uvm_report_catcher. Everywhere else, use `uvm_info, `uvm_warning, `uvm_error and `uvm_fatal.
// The macros call the report functions of uvm_pkg by their full name, so the message always
// goes through the root reporter of UVM: it is filtered by the global verbosity, seen by
// report catchers and counted by the report server, and it carries file and line. It does
// not carry the hierarchical name of a component.
// Each macro is one complete statement, like the `uvm_* macros: write no semicolon after
// it. Include this file through hexk_macros.svh.
//
//! @module    hexk_report_macros
//! @since     0.7.0
//! @stability experimental
//! @serves    MSG-1 MSG-2 IFC-7
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_REPORT_MACROS_SVH
`define HEXK_REPORT_MACROS_SVH

// Reports an info with the given verbosity through the root reporter of UVM.
`define hexk_static_info(ID, MSG, VERBOSITY) \
   begin \
      if (uvm_pkg::uvm_report_enabled(VERBOSITY, uvm_pkg::UVM_INFO, ID) != 0) begin \
         uvm_pkg::uvm_report_info(ID, MSG, VERBOSITY, `uvm_file, `uvm_line, "", 1); \
      end \
   end

// Reports a warning through the root reporter of UVM.
`define hexk_static_warning(ID, MSG) \
   begin \
      if (uvm_pkg::uvm_report_enabled(uvm_pkg::UVM_NONE, uvm_pkg::UVM_WARNING, ID) != 0) begin \
         uvm_pkg::uvm_report_warning(ID, MSG, uvm_pkg::UVM_NONE, `uvm_file, `uvm_line, "", 1); \
      end \
   end

// Reports an error through the root reporter of UVM.
`define hexk_static_error(ID, MSG) \
   begin \
      if (uvm_pkg::uvm_report_enabled(uvm_pkg::UVM_NONE, uvm_pkg::UVM_ERROR, ID) != 0) begin \
         uvm_pkg::uvm_report_error(ID, MSG, uvm_pkg::UVM_NONE, `uvm_file, `uvm_line, "", 1); \
      end \
   end

// Reports a fatal through the root reporter of UVM; the simulation ends unless a catcher demotes it.
`define hexk_static_fatal(ID, MSG) \
   begin \
      if (uvm_pkg::uvm_report_enabled(uvm_pkg::UVM_NONE, uvm_pkg::UVM_FATAL, ID) != 0) begin \
         uvm_pkg::uvm_report_fatal(ID, MSG, uvm_pkg::UVM_NONE, `uvm_file, `uvm_line, "", 1); \
      end \
   end

`endif  // HEXK_REPORT_MACROS_SVH
