// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_warning_audit.sv
//
// A listener of hexk_report_server that collects the warnings a test did not allow: a test that
// wants a clean log names the warnings it allows by their ID (allow(), an expression as
// hexk_regex takes it) and fails on the others. It sees what the report server issues, after
// the report catchers: a warning that a catcher demoted is not a warning any more. It counts every
// unexpected warning and keeps the text of the first MAX_KEPT. It reports nothing itself;
// hexk_base_test reports what it collected when fail_on_warnings is set, and any other test can
// read num_unexpected() and unexpected_text().
//
//! @module    hexk_report_server
//! @since     0.9.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_WARNING_AUDIT_SV
`define HEXK_WARNING_AUDIT_SV

class hexk_warning_audit implements hexk_msg_listener;

   // Number of unexpected warnings whose text is kept; the others are counted only.
   localparam int unsigned MAX_KEPT = 20;

   // ID expressions of the allowed warnings.
   local string       allowed          [$];

   // Number of unexpected warnings, and the text of the first MAX_KEPT: "ID: message".
   local int unsigned unexpected_count;
   local string       kept             [$];

   // Allows the warnings whose ID matches id_regex, an expression as hexk_regex takes it ("^ID$" for one ID).
   function void allow(string id_regex);
      allowed.push_back(id_regex);
   endfunction : allow

   // Number of warnings that were not allowed, since the start or the last clear().
   function int unsigned num_unexpected();
      return unexpected_count;
   endfunction : num_unexpected

   // The unexpected warnings, one per line ("ID: message"), the first MAX_KEPT of them, then how many more came.
   function string unexpected_text();
      string lines[$] = kept;
      if (unexpected_count > kept.size()) begin
         lines.push_back($sformatf("and %0d more", unexpected_count - kept.size()));
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : unexpected_text

   // Forgets the unexpected warnings; the allowed IDs stay.
   function void clear();
      unexpected_count = 0;
      kept.delete();
   endfunction : clear

   // hexk_msg_listener: notes a warning unless its ID is allowed.
   virtual function void on_message(uvm_report_message msg);
      if (msg.get_severity() != UVM_WARNING) begin
         return;
      end
      foreach (allowed[i]) begin
         if (hexk_regex::match(allowed[i], msg.get_id())) begin
            return;
         end
      end
      unexpected_count++;
      if (kept.size() < MAX_KEPT) begin
         kept.push_back({msg.get_id(), ": ", msg.get_message()});
      end
   endfunction : on_message

endclass : hexk_warning_audit

`endif  // HEXK_WARNING_AUDIT_SV
