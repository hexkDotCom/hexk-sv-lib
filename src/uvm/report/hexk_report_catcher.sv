// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_catcher.sv
//
// Report catcher for negative tests: declare which errors, warnings or fatals a test expects,
// have them demoted to info, and check at the end that they really occurred.
// Create and register one with hexk_report_catcher::add_to(component), for the messages of the
// component that reports the expected errors (guide MSG-9), or with add_global(), for the
// messages of every reporter; then call expect_msg() for every message the test provokes on
// purpose, or expect_check() for a check that fails on purpose; without a maximum an
// expectation is exact. check_expectations() checks the counts; hexk_base_test calls
// check_unchecked() in its check phase, which does that for every catcher made by add_to() or
// add_global() that the test did not check itself. A catcher added to a component sees a
// message after the global catchers: a global rule that changes its severity hides it from the
// rules of that catcher, which match the severity the message has then. A message matches a rule when it has
// the rule's severity, its ID matches the rule's regular expression and, if one is given, its
// text matches the text expression. The first rule that matches wins. demote() changes the
// severity of matching messages; its rule counts them for get_count(), but
// check_expectations() does not check that count. Messages that match no rule pass through
// unchanged.
// Expressions are those of hexk_regex: a match anywhere counts, anchor with ^ and $.
//
//! @module    hexk_report_catcher
//! @since     0.7.0
//! @stability experimental
//! @serves    MSG-9
//! @emits     HEXK_CATCHER_MISSING:error HEXK_CATCHER_EXCESS:error
//! @plusargs  (none)

`ifndef HEXK_REPORT_CATCHER_SV
`define HEXK_REPORT_CATCHER_SV

class hexk_report_catcher extends uvm_report_catcher;

   // max_count of expect_msg(): no upper limit.
   localparam int NO_LIMIT = -1;
   // max_count of expect_msg(), the default: the same as min_count, so that the shortest call expects an exact count.
   localparam int SAME_AS_MIN = -2;

   local hexk_report_catcher_rule rules[$];

   // Set by check_expectations() and cleared by clear(): check_unchecked() leaves this catcher alone.
   local bit checked;

   // The catchers created by add_to() and add_global(), for check_unchecked().
   local static hexk_report_catcher registered[$];

   // Number of catchers that add_to() created: each gets a name of its own, since UVM 1.2 warns about a callback whose
   // name a component has already, which a global catcher gives it.
   local static int unsigned num_added_to;

   `uvm_object_utils(hexk_report_catcher)

   // Creates a catcher that is not registered anywhere; add_to() and add_global() are the usual ways to get one.
   function new(string name = "hexk_report_catcher");
      super.new(name);
   endfunction : new

   // Creates a catcher and registers it for the messages of every reporter.
   static function hexk_report_catcher add_global();
      hexk_report_catcher catcher = hexk_report_catcher::type_id::create("catcher");
      uvm_report_cb::add(null, catcher);
      registered.push_back(catcher);
      return catcher;
   endfunction : add_global

   // Creates a catcher and registers it for the messages of one component (or other reporter) only, so that an
   // expected error counts only when that component reports it. A null client registers for every reporter, as
   // add_global() does.
   static function hexk_report_catcher add_to(uvm_report_object client);
      hexk_report_catcher catcher = hexk_report_catcher::type_id::create($sformatf("catcher_%0d", num_added_to));
      num_added_to++;
      uvm_report_cb::add(client, catcher);
      registered.push_back(catcher);
      return catcher;
   endfunction : add_to

   // Expects min_count to max_count messages of severity sev, matching the expressions; they become demote_to.
   // max_count is min_count unless given: the shortest call expects exactly one message. NO_LIMIT has no maximum.
   function void expect_msg(string id_regex, uvm_severity sev = UVM_ERROR, string msg_regex = "",
                            int unsigned min_count = 1, int max_count = SAME_AS_MIN, uvm_severity demote_to = UVM_INFO);
      hexk_report_catcher_rule rule = add_rule(id_regex, msg_regex, sev, demote_to);
      rule.is_expectation = 1;
      rule.min_count      = min_count;
      rule.max_count      = (max_count == SAME_AS_MIN) ? int'(min_count) : max_count;
   endfunction : expect_msg

   // Expects a check with this ID to fail exactly count times, with messages of severity sev: they are demoted to
   // info and counted as an expectation, and hexk_check_stats allows the failures. One call instead of
   // expect_msg() and hexk_check_stats::expect_failures(). id is the ID itself, not an expression: the rule compares
   // it as text, so an ID with characters such as "." or "[" matches only itself.
   function void expect_check(string id, int unsigned count = 1, uvm_severity sev = UVM_ERROR);
      expect_msg({"^", id, "$"}, sev, "", count, int'(count));
      rules[rules.size()-1].id_literal = id;
      hexk_check_stats::expect_failures(id, count);
   endfunction : expect_check

   // Changes the severity of matching messages from one severity to another; they are not counted as expected.
   function void demote(string id_regex, uvm_severity from, uvm_severity to, string msg_regex = "");
      void'(add_rule(id_regex, msg_regex, from, to));
   endfunction : demote

   // Reports every expectation that saw fewer messages than its minimum or more than its maximum.
   // The verdicts go through the root reporter of UVM: the `uvm_error of a catcher would report through the
   // reporter of the last message that UVM gave to a catcher, with the actions of that reporter.
   function void check_expectations();
      checked = 1;
      foreach (rules[i]) begin
         if (!rules[i].is_expectation) begin
            continue;
         end
         if (rules[i].hits < rules[i].min_count) begin
            `hexk_static_error("HEXK_CATCHER_MISSING", $sformatf("expected at least %0d of %s, saw %0d",
                                                                 rules[i].min_count, describe(rules[i]), rules[i].hits))
         end
         if (rules[i].max_count != NO_LIMIT && rules[i].hits > $unsigned(rules[i].max_count)) begin
            `hexk_static_error("HEXK_CATCHER_EXCESS", $sformatf("expected at most %0d of %s, saw %0d",
                                                                rules[i].max_count, describe(rules[i]), rules[i].hits))
         end
      end
   endfunction : check_expectations

   // Number of messages caught so far by the rules registered with this ID expression and severity.
   function int unsigned get_count(string id_regex, uvm_severity sev = UVM_ERROR);
      int unsigned total;
      foreach (rules[i]) begin
         if (rules[i].id_regex == id_regex && rules[i].from_severity == sev) begin
            total += rules[i].hits;
         end
      end
      return total;
   endfunction : get_count

   // Removes every rule and count; the catcher stays registered, and check_unchecked() checks it again.
   function void clear();
      rules.delete();
      checked = 0;
   endfunction : clear

   // Calls check_expectations() of every catcher created by add_to() or add_global() whose expectations were not
   // checked since its last clear(); hexk_base_test calls it in its check phase, so that a test cannot forget it.
   static function void check_unchecked();
      foreach (registered[i]) begin
         if (!registered[i].checked) begin
            registered[i].check_expectations();
         end
      end
   endfunction : check_unchecked

   // Applies the first matching rule to the message being reported; the message is always passed on.
   function action_e catch();
      uvm_report_object client = get_client();
      string            id = get_id();
      // The verdicts of check_expectations(), of this catcher or of another one, pass every rule untouched.
      if (id == "HEXK_CATCHER_MISSING" || id == "HEXK_CATCHER_EXCESS") begin
         return THROW;
      end
      foreach (rules[i]) begin
         if (get_severity() != rules[i].from_severity) begin
            continue;
         end
         if (!id_matches(rules[i], id) || !rules[i].msg_filter.is_match(get_message())) begin
            continue;
         end
         rules[i].hits++;
         set_severity(rules[i].to_severity);
         // The actions were chosen for the old severity; an error demoted to info must not count as one.
         if (client != null) begin
            set_action(client.get_report_action(rules[i].to_severity, get_id()));
         end
         break;
      end
      return THROW;
   endfunction : catch

   // 1 when the ID of a message matches a rule: as text for a rule of expect_check(), else as an expression.
   local function bit id_matches(hexk_report_catcher_rule rule, string id);
      if (rule.id_literal.len() != 0) begin
         return id == rule.id_literal;
      end
      return rule.id_filter.is_match(id);
   endfunction : id_matches

   // Appends a rule and returns it.
   local function hexk_report_catcher_rule add_rule(string id_regex, string msg_regex, uvm_severity from,
                                                    uvm_severity to);
      hexk_report_catcher_rule rule = new();
      rule.id_regex      = id_regex;
      rule.msg_regex     = msg_regex;
      rule.id_filter     = new(id_regex);
      rule.msg_filter    = new(msg_regex);
      rule.from_severity = from;
      rule.to_severity   = to;
      rules.push_back(rule);
      return rule;
   endfunction : add_rule

   // Text that names a rule in a message, such as "UVM_ERROR with ID matching 'SB_.*'".
   local function string describe(hexk_report_catcher_rule rule);
      string text = $sformatf("%s with ID matching '%s'", rule.from_severity.name(), rule.id_regex);
      if (rule.msg_regex.len() != 0) begin
         text = {text, $sformatf(" and text matching '%s'", rule.msg_regex)};
      end
      return text;
   endfunction : describe

endclass : hexk_report_catcher

`endif  // HEXK_REPORT_CATCHER_SV
