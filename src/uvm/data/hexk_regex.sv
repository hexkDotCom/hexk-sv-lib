// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_regex.sv
//
// Regular expression matching on strings, and an include/exclude filter object.
// hexk_regex::match(re, s) is one call for "does this expression match this string".
// An object made with new(include_re, exclude_re) is a filter: is_match(s) is true when s
// matches the include expression (or there is none) and does not match the exclude
// expression. Used for trigger lists such as "stack trace on these IDs but not those".
// Expressions are POSIX extended regular expressions, matched by UVM's uvm_re_match; a match
// may be anywhere in the string unless the expression is anchored with ^ and $.
// When UVM is compiled without its regex DPI code (UVM_NO_DPI or UVM_REGEX_NO_DPI), UVM
// only matches globs (* and ?), and so does this class: see docs/api/hexk_regex.md.
// UVM compiles an expression again for every match. A filter object therefore looks at its
// expressions once, when it is made: an expression without operators, such as "SB_MISMATCH"
// or "^HEXK_SB_", is matched by a string comparison and never reaches UVM.
//
//! @module    hexk_regex
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_REGEX_SV
`define HEXK_REGEX_SV

class hexk_regex;

   // How a filter matches one of its expressions.
   typedef enum {
      HEXK_REGEX_NOT_GIVEN,
      HEXK_REGEX_BY_UVM,
      HEXK_REGEX_CONTAINS,
      HEXK_REGEX_STARTS_WITH,
      HEXK_REGEX_ENDS_WITH,
      HEXK_REGEX_EQUALS
   } kind_e;

   // Characters that are operators of an extended regular expression.
   localparam string OPERATORS = ".[]()*+?{}|^$\\";

   // The expressions as given, how each is matched, and the text to compare with when UVM is not needed.
   local string include_pattern;
   local string exclude_pattern;
   local kind_e include_kind;
   local kind_e exclude_kind;
   local string include_text;
   local string exclude_text;

   // Creates a filter from an include and an exclude expression; an empty expression is "not given".
   function new(string include_re = "", string exclude_re = "");
      include_pattern = include_re;
      exclude_pattern = exclude_re;
      include_kind    = classify(include_re, include_text);
      exclude_kind    = classify(exclude_re, exclude_text);
   endfunction : new

   // True when s matches the include expression (or there is none) and not the exclude expression.
   function bit is_match(string s);
      if (include_kind != HEXK_REGEX_NOT_GIVEN && !match_as(include_kind, include_pattern, include_text, s)) begin
         return 0;
      end
      return exclude_kind == HEXK_REGEX_NOT_GIVEN || !match_as(exclude_kind, exclude_pattern, exclude_text, s);
   endfunction : is_match

   // True when the regular expression re matches s; a match anywhere in s counts.
   static function bit match(string re, string s);
      return uvm_re_match(re, s) == 0;
   endfunction : match

   // Expression that matches exactly the strings the glob matches (* any text, ? any one character).
   static function string glob_to_regex(string glob);
`ifdef HEXK_UVM_REGEX_NO_DPI
      // Without the regex DPI code UVM matches globs itself, so the glob is the expression. UVM removes
      // one leading "^" and takes an empty expression as "matches everything": the "^" added here is the
      // one it removes, so a glob that starts with "^" keeps it and an empty glob matches the empty string.
      return {"^", glob};
`else
      string result = "^";
      foreach (glob[i]) begin
         case (glob[i])
            "*": result = {result, ".*"};
            "?": result = {result, "."};
            ".", "+", "(", ")", "[", "]", "{", "}", "^", "$", "|", "\\": result = {result, "\\", string'(glob[i])};
            default: result = {result, string'(glob[i])};
         endcase
      end
      return {result, "$"};
`endif
   endfunction : glob_to_regex

   // How to match re, and in text the characters to compare with when that is a string comparison.
   local static function kind_e classify(string re, output string text);
      int first = 0;
      int last = re.len() - 1;
      bit at_start;
      bit at_end;
      text = re;
      if (re.len() == 0) begin
         return HEXK_REGEX_NOT_GIVEN;
      end
`ifdef HEXK_UVM_REGEX_NO_DPI
      return HEXK_REGEX_BY_UVM;
`else
      // UVM removes a "/" at both ends before it compiles the expression.
      if (re[0] == "/") begin
         return HEXK_REGEX_BY_UVM;
      end
      if (re[first] == "^") begin
         at_start = 1;
         first++;
      end
      if (last >= first && re[last] == "$") begin
         at_end = 1;
         last--;
      end
      for (int i = first; i <= last; i++) begin
         if (is_operator(re[i])) begin
            return HEXK_REGEX_BY_UVM;
         end
      end
      text = re.substr(first, last);
      if (at_start && at_end) begin
         return HEXK_REGEX_EQUALS;
      end
      if (at_start) begin
         return HEXK_REGEX_STARTS_WITH;
      end
      return at_end ? HEXK_REGEX_ENDS_WITH : HEXK_REGEX_CONTAINS;
`endif
   endfunction : classify

   // True when c is an operator of an extended regular expression.
   local static function bit is_operator(byte c);
      string operators = OPERATORS;
      foreach (operators[i]) begin
         if (operators[i] == c) begin
            return 1;
         end
      end
      return 0;
   endfunction : is_operator

   // True when s matches the expression re of the given kind; text is what classify() returned for re.
   local static function bit match_as(kind_e kind, string re, string text, string s);
      case (kind)
         HEXK_REGEX_CONTAINS:    return hexk_str::contains(s, text);
         HEXK_REGEX_STARTS_WITH: return hexk_str::starts_with(s, text);
         HEXK_REGEX_ENDS_WITH:   return hexk_str::ends_with(s, text);
         HEXK_REGEX_EQUALS:      return s == text;
         default:                return match(re, s);
      endcase
   endfunction : match_as

endclass : hexk_regex

`endif  // HEXK_REGEX_SV
