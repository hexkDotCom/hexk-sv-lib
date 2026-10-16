// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_catcher_rule.sv
//
// One rule of hexk_report_catcher: which messages it matches, what happens to them, and how
// many matched. Internal to hexk_report_catcher; users go through expect_msg() and demote().
//
//! @module    hexk_report_catcher
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_REPORT_CATCHER_RULE_SV
`define HEXK_REPORT_CATCHER_RULE_SV

class hexk_report_catcher_rule;

   // Regular expression on the message ID, as given by the user.
   string id_regex;

   // The ID itself, when the rule compares it as text and not as an expression (expect_check()); else empty.
   string id_literal;

   // Regular expression on the message text; empty means any text.
   string msg_regex;

   // Filters built from the two expressions.
   hexk_regex id_filter;
   hexk_regex msg_filter;

   // Severity a message must have to match, and the severity it gets.
   uvm_severity from_severity;
   uvm_severity to_severity;

   // Set for an expectation (counted and checked), clear for a plain demotion.
   bit is_expectation;

   // Limits of an expectation; a max_count below 0 means no upper limit.
   int unsigned min_count;
   int max_count;

   // Number of messages that matched this rule.
   int unsigned hits;

endclass : hexk_report_catcher_rule

`endif  // HEXK_REPORT_CATCHER_RULE_SV
