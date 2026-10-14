# hexk_regex

## 1. Summary

Regular expression matching on strings, and an include/exclude filter object.

## 2. When to use / when not to use

Use `hexk_regex::match` for a one-off "does this text match this pattern" in UVM testbench
code, and a filter object where a list of things is selected by one pattern and trimmed by
another: message IDs that trigger a stack trace, component paths that get extra checks,
plusarg-driven selections. The report server and the report catcher of this library use it.

Do not use it in code without UVM; `hexk_str` has literal search (`find`, `contains`,
`starts_with`). Do not match an expression with operators per transaction in a hot path:
each such match goes through `uvm_re_match`, which compiles the expression again unless UVM
2020 keeps compiled expressions (see the cost in section 4); a plain name in a filter object
costs only a string comparison. Do not rely on anything outside the supported subset below.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/data/hexk_regex.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/data/hexk_regex.sv`:

```systemverilog
// Creates a filter from an include and an exclude expression; an empty expression is "not given".
function new(string include_re = "", string exclude_re = "");
// True when s matches the include expression (or there is none) and not the exclude expression.
function bit is_match(string s);
// True when the regular expression re matches s; a match anywhere in s counts.
static function bit match(string re, string s);
// Expression that matches exactly the strings the glob matches (* any text, ? any one character).
static function string glob_to_regex(string glob);
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- Matching is done by UVM's `uvm_re_match`, which uses POSIX extended regular expressions
  through UVM's DPI code. Nothing else in C is involved.
- A match anywhere in the string counts. Anchor with `^` and `$` to match the whole string.
- Matching is case-sensitive.
- Supported subset, the only syntax the contract promises and the unit tests use:
  literal characters, `.`, character classes `[abc]`, `[a-z]`, `[^abc]`, the quantifiers
  `*`, `+`, `?`, alternation `|`, groups `( )`, the anchors `^` and `$`, and `\` to take the
  next character literally. Shorthand classes (`\d`, `\w`), back-references, lazy quantifiers
  and look-around are not part of it.
- In a SystemVerilog string literal a backslash is written twice: `"file\\.sv"`.
- Filter object: an empty include expression means "everything", an empty exclude expression
  means "nothing". `is_match(s)` is `(include empty or include matches s) and not (exclude
  given and exclude matches s)`.
- `glob_to_regex` returns an anchored expression: `*` becomes `.*`, `?` becomes `.`, and
  every other character matches itself, including characters that are special in a regular
  expression.
- Without the regex DPI code (`+define+UVM_NO_DPI` or `+define+UVM_REGEX_NO_DPI`), UVM's
  `uvm_re_match` only understands globs: `*`, `?`, matched against the whole string. `match`
  and the filter then take globs instead of regular expressions, and code that goes through
  `glob_to_regex` keeps working. UVM's glob matcher removes one `^` at the start of its
  expression and takes an empty expression as "matches everything"; `glob_to_regex`
  therefore returns the glob with a `^` in front, which is the one that is removed. So a
  glob that starts with `^` keeps that character, and an empty glob matches only the empty
  string, as with the DPI code. The define must be given to the whole compilation, because
  the library looks at it too. Simulated once on Questa 2024.1 (2026-10-14), with UVM 1.2
  and `+define+UVM_REGEX_NO_DPI` and with UVM 2020.3.1 and `+define+UVM_NO_DPI`; UVM
  2020.3.1 does not compile with `UVM_REGEX_NO_DPI` alone. It is not part of the gates.
- A filter object looks at its two expressions once, when it is created. An expression
  without an operator, with or without `^` at its start and `$` at its end, is matched by a
  string comparison inside the class: "contains", "starts with", "ends with" or "equals".
  Every other expression goes to UVM at each `is_match`. The answers are the same; only the
  cost differs. An expression that starts with `/` always goes to UVM, which removes a `/`
  at both ends. Without the regex DPI code everything goes to UVM. The static `match` always
  goes to UVM.
- Nothing is reported. An expression that UVM cannot compile simply does not match, and UVM
  may print its own message.
- **Cost.** For an expression with operators the cost is that of `uvm_re_match`. UVM 1.2
  compiles the expression again at every call, and so does UVM 2020 unless it is compiled
  with `+define+UVM_ENABLE_RE_MATCH_CACHE`, which makes it keep compiled expressions. An
  expression without operators in a filter object costs a string comparison. Measured on
  2026-10-14 with UVM 2020.3.1 without that define, one million calls of `is_match` with an
  include and an exclude expression, per expression:

  | Simulator | Text | With operators | Without operators |
  |---|---|---|---|
  | Questa 2024.1 (Windows) | 21 characters | 14 us | 0.05 us |
  | Questa 2024.1 (Windows) | 105 characters | 30 us | 0.25 us |
  | VCS X-2025.06 (Linux) | 21 characters | 6.8 us | 0.15 us |
  | VCS X-2025.06 (Linux) | 105 characters | 6.5 us | 0.65 us |

  With the define, an expression with operators took about 7 us on Questa (measured
  2026-10-13). Nothing was measured with UVM 1.2.

## 5. Configuration

None of its own. UVM's `UVM_NO_DPI` and `UVM_REGEX_NO_DPI` switch to glob matching, and
`UVM_ENABLE_RE_MATCH_CACHE` of UVM 2020 makes repeated matches cheaper; see section 4.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_regex/hexk_regex_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_regex_example.sv
//
// Minimal use of hexk_regex: an include/exclude filter on message IDs, a one-off match,
// and a glob turned into a regular expression. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_regex_example;
   timeunit 1ns / 1ps;

   import hexk_uvm_pkg::hexk_regex;

   hexk_regex trace_filter;

   initial begin
      // Every scoreboard ID, except the leftover report.
      trace_filter = new("^SB_", "LEFTOVER");
      $info("SB_MISMATCH passes: %0b", trace_filter.is_match("SB_MISMATCH"));
      $info("SB_LEFTOVER passes: %0b", trace_filter.is_match("SB_LEFTOVER"));
      $info("DRV_TIMEOUT passes: %0b", trace_filter.is_match("DRV_TIMEOUT"));

      $info("WR_17 is a transfer name: %0b", hexk_regex::match("^(RD|WR)_[0-9]+$", "WR_17"));
      $info("glob as expression: %s", hexk_regex::glob_to_regex("uvm_test_top.env.*"));
   end

endmodule : hexk_regex_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Expecting a whole-string match.** `match("SB", "MY_SB_X")` is true. Write `"^SB$"`, or
  build the expression with `glob_to_regex`.
- **A single backslash in the literal.** `"file\.sv"` is not legal SystemVerilog and tools
  differ in what they do with it. Write `"file\\.sv"`.
- **Testing the return value of `uvm_re_match` directly.** It returns 0 for a match, which
  reads the wrong way round in an `if`. `hexk_regex::match` returns 1 for a match.
- **Regular expressions when UVM is compiled with `UVM_NO_DPI`.** They silently become
  globs. If a flow needs `UVM_NO_DPI`, write globs and pass them through `glob_to_regex`.
- **An operator where plain text would do.** `"^SB_.*"` says the same as `"^SB_"` and
  `"SB_MISMATCH.*"` the same as `"SB_MISMATCH"`, but the first of each pair goes to UVM at
  every match and costs about a hundred times more (section 4). In a filter that sees every
  message of a simulation, write the ID or its beginning as plain text.
- **Many filters with operators on every message without the cache of UVM.** Such a filter
  compiles its expressions every time. Compile UVM 2020 with
  `+define+UVM_ENABLE_RE_MATCH_CACHE` (section 4), or keep such filters few.
- **Perl syntax.** `\d+`, `(?i)`, `.*?` are not POSIX extended syntax. Use `[0-9]+`, and
  match case explicitly.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
