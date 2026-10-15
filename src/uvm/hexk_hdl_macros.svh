// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_hdl_macros.svh
//
// Access to signals by their HDL path as text, with the return code checked: read, deposit,
// force and release on top of the uvm_hdl_* functions of UVM, which return 0 when the path
// does not exist or the simulator gives no access to it, and which are easily called without
// a look at that return value.
// `hexk_hdl_read("top.dut.u_fifo.count", count, "MY_HDL") reads the signal into the variable
// count, and reports an error with the caller's message ID and the path when that fails;
// the variable is then left as it was. The other macros work the same way.
// `hexk_hdl_check_path_or_fatal(path, "MY_HDL") ends the simulation when a path cannot be
// reached, for use before the first access. Each macro is one complete statement like the
// `uvm_* macros: write no semicolon after it. The path is evaluated once.
// The simulation must be started with access to the signals for programming interfaces
// (read for the first macro, write for the others); how depends on the simulator.
// A value is an integral variable or expression of at most UVM_HDL_MAX_WIDTH bits.
// The macros declare local variables named hexk_hdl_path and hexk_hdl_value; an operand that
// is a variable of such a name reads or writes the local instead, so do not use those names.
// Include this file through hexk_macros.svh.
//
//! @module    hexk_hdl_macros
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_HDL_MACROS_SVH
`define HEXK_HDL_MACROS_SVH

// Internal: what every message says after the path.
`define HEXK_HDL_HINT "; check the path and that the simulator gives access to it"

// Internal: deposits or forces a value with the given UVM function and reports when that fails.
`define hexk_hdl_write(FUNCTION, VERB, PATH, VALUE, ID) \
   begin \
      var automatic string hexk_hdl_path = PATH; \
      var automatic uvm_pkg::uvm_hdl_data_t hexk_hdl_value = uvm_pkg::uvm_hdl_data_t'(VALUE); \
      if (uvm_pkg::FUNCTION(hexk_hdl_path, hexk_hdl_value) == 0) begin \
         `hexk_check_report(uvm_pkg::UVM_ERROR, ID, $sformatf("cannot %s 0x%0h on HDL path '%s'%s", VERB, \
            hexk_hdl_value, hexk_hdl_path, `HEXK_HDL_HINT)) \
      end \
   end

// Internal: the call that releases a path. With UVM_HDL_NO_DPI, UVM 1.2 declares its
// stand-in for uvm_hdl_release with a second argument.
`ifdef UVM_HDL_NO_DPI
`ifdef HEXK_UVM_VERSION_1_2
`define hexk_hdl_release_call(PATH, VALUE) uvm_pkg::uvm_hdl_release(PATH, VALUE)
`endif
`endif
`ifndef hexk_hdl_release_call
`define hexk_hdl_release_call(PATH, VALUE) uvm_pkg::uvm_hdl_release(PATH)
`endif

// Reads the signal at PATH into the variable VALUE; reports an error with ID when it cannot be read.
`define hexk_hdl_read(PATH, VALUE, ID) \
   begin \
      var automatic string hexk_hdl_path = PATH; \
      var automatic uvm_pkg::uvm_hdl_data_t hexk_hdl_value; \
      if (uvm_pkg::uvm_hdl_read(hexk_hdl_path, hexk_hdl_value) != 0) begin \
         VALUE = $bits(VALUE)'(hexk_hdl_value); \
      end else begin \
         `hexk_check_report(uvm_pkg::UVM_ERROR, ID, $sformatf("cannot read HDL path '%s'%s", hexk_hdl_path, \
            `HEXK_HDL_HINT)) \
      end \
   end

// Sets the signal at PATH to VALUE until its driver or a later deposit changes it; error with ID on failure.
`define hexk_hdl_deposit(PATH, VALUE, ID) `hexk_hdl_write(uvm_hdl_deposit, "deposit", PATH, VALUE, ID)

// Holds the signal at PATH at VALUE against its drivers until it is released; error with ID on failure.
`define hexk_hdl_force(PATH, VALUE, ID) `hexk_hdl_write(uvm_hdl_force, "force", PATH, VALUE, ID)

// Ends a force of the signal at PATH; reports an error with ID when that fails.
`define hexk_hdl_release(PATH, ID) \
   begin \
      var automatic string hexk_hdl_path = PATH; \
      var automatic uvm_pkg::uvm_hdl_data_t hexk_hdl_value; \
      if (`hexk_hdl_release_call(hexk_hdl_path, hexk_hdl_value) == 0) begin \
         `hexk_check_report(uvm_pkg::UVM_ERROR, ID, $sformatf("cannot release HDL path '%s'%s", hexk_hdl_path, \
            `HEXK_HDL_HINT)) \
      end \
   end

// Reports a fatal with ID when PATH does not exist or the simulator gives no access to it.
`define hexk_hdl_check_path_or_fatal(PATH, ID) \
   begin \
      var automatic string hexk_hdl_path = PATH; \
      if (uvm_pkg::uvm_hdl_check_path(hexk_hdl_path) == 0) begin \
         `hexk_check_report(uvm_pkg::UVM_FATAL, ID, $sformatf("HDL path '%s' cannot be reached%s", hexk_hdl_path, \
            `HEXK_HDL_HINT)) \
      end \
   end

`endif  // HEXK_HDL_MACROS_SVH
