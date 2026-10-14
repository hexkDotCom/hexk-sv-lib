// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_msg_listener.sv
//
// Interface class for objects that want to see every warning, error and fatal message.
// Implement on_message in a class, then register an object of it with
// hexk_report_server::add_listener. The server calls on_message after the report catchers
// and before the message is printed. Typical uses: a marker in the waveform, a signal on a
// debug interface, a machine-readable log. A listener must not report through UVM itself
// from on_message, and it must not change the message.
//
//! @module    hexk_report_server
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_MSG_LISTENER_SV
`define HEXK_MSG_LISTENER_SV

interface class hexk_msg_listener;

   // Called by hexk_report_server for every warning, error and fatal message that is issued.
   // The formatter breaks a pure virtual prototype over three lines.
   // verilog_format: off
   pure virtual function void on_message(uvm_report_message msg);
   // verilog_format: on

endclass : hexk_msg_listener

`endif  // HEXK_MSG_LISTENER_SV
