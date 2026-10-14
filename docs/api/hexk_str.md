# hexk_str

## 1. Summary

String utilities as static functions: split and join, strip, search, replace, pad,
truncate, path and scope helpers, digit-run helpers, natural ordering and hex dumps.

## 2. When to use / when not to use

Use it wherever testbench code handles names, paths and message text: taking a hierarchical
name apart, building fixed-width log columns, sorting instance names so that `agent_2` comes
before `agent_10`, grouping messages that differ only in a number. It has no UVM and no DPI
dependency, so it also works in modules, interfaces and on Verilator.

Do not use it for regular expressions; that is `hexk_regex` in the UVM layer. Do not use it on
text that is not ASCII: a character is one byte. Do not use `find` in a per-transaction hot
path on long strings; it is a plain scan.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/core/hexk_str.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/core/hexk_str.sv`:

```systemverilog
// Splits s at every sep into parts (cleared first), keeping empty fields; max_parts 0 means no limit.
static function void split(string s, ref string parts[$], input byte sep = " ", input int unsigned max_parts = 0);
// Returns the parts concatenated with sep between them.
static function string join_str(const ref string parts[$], input string sep = " ");
// Removes leading and trailing characters that are in chars.
static function string strip(string s, string chars = WHITESPACE);
// Removes leading characters that are in chars.
static function string lstrip(string s, string chars = WHITESPACE);
// Removes trailing characters that are in chars.
static function string rstrip(string s, string chars = WHITESPACE);
// True when s begins with prefix; an empty prefix always matches.
static function bit starts_with(string s, string prefix);
// True when s ends with suffix; an empty suffix always matches.
static function bit ends_with(string s, string suffix);
// True when sub occurs in s; an empty sub always does.
static function bit contains(string s, string sub);
// Position of the first occurrence of sub in s at or after start, or -1.
static function int find(string s, string sub, int unsigned start = 0);
// Position of the last occurrence of sub in s, or -1.
static function int rfind(string s, string sub);
// Replaces from by to, left to right without overlap; only the first occurrence when all is 0.
static function string replace(string s, string from, string to, bit all = 1);
// Pads s with fill to width characters, on the left unless left_align is set; never shortens s.
static function string pad(string s, int unsigned width, bit left_align = 0, byte fill = " ");
// Shortens s to max_len characters, marking the cut with ellipsis; keeps the right end if keep_right.
static function string truncate(string s, int unsigned max_len, bit keep_right = 0, string ellipsis = "..");
// Returns s repeated n times.
static function string repeat_str(string s, int unsigned n);
// Last component of a "/"-separated path, as POSIX basename: "a/b/c.sv" gives "c.sv".
static function string basename(string path);
// Path without its last component, as POSIX dirname: "a/b/c.sv" gives "a/b", "c.sv" gives ".".
static function string dirname(string path);
// Elements first to last (inclusive, 0-based, negative counts from the end) of a sep-separated scope.
static function string scope_slice(string scope, int first, int last, byte sep = ".");
// Collects every run of decimal digits in s as a number into nums (cleared first).
static function void get_numbers(string s, ref longint unsigned nums[$]);
// Replaces every run of decimal digits by placeholder: "agent_12.drv" gives "agent_#.drv".
static function string denumber(string s, string placeholder = "#");
// Orders a before b (-1), after b (1) or equal (0), comparing digit runs as numbers: "a2" < "a10".
static function int natural_cmp(string a, string b);
// Sorts list in natural order (see natural_cmp), descending when reverse is set; stable.
static function void natural_sort(ref string list[$], input bit reverse = 0);
// Hex dump of data: two lower-case digits per byte, space-separated, per_line bytes per line (0: one line).
static function string bytes_to_hex(const ref byte unsigned data[$], input int unsigned per_line = 16);
// Shortens a $typename() result: drops a leading "class " and everything from " extends " on.
static function string simplify_typename(string type_name);
```
<!-- HEXK_GEN:END api -->

Call the functions through the class name, for example `hexk_str::split(...)`. The class is
abstract and holds no state.

## 4. Behaviour and invariants

General:

- Every function is pure: the result depends only on the arguments, and arguments other than
  the `ref` outputs are not modified.
- Positions are 0-based. `-1` means "not found".
- `ref` output queues (`parts`, `nums`) are cleared before they are filled.
- Nothing is ever reported: no function emits a message, and there is no illegal input.

Per function, where the one-line description leaves a choice open:

| Function | Behaviour |
|---|---|
| `split` | An empty `s` gives no parts. Otherwise n separators give n+1 parts, so empty fields and separators at the ends are kept. With `max_parts` > 0 the last part holds the rest of `s`, separators included. |
| `join_str` | Inverse of `split` for the same separator, except that an empty queue and a queue holding one empty string both give `""`. |
| `strip`, `lstrip`, `rstrip` | `chars` is a set of characters, not a prefix or suffix. |
| `find` | An empty `sub` is found at `start` when `start` is not beyond the end of `s`. A `start` beyond the end gives -1, also one of 2**31 or more. |
| `rfind` | An empty `sub` is found at `s.len()`. |
| `replace` | Scans left to right and continues after each replacement, so the result is never rescanned. An empty `from` returns `s` unchanged. |
| `pad` | Right-aligns by default (fill on the left). A string longer than `width` is returned unchanged. Up to 64 blanks are one slice of a stored run of blanks (about 0.07 us on VCS X-2025.06, where one concatenation per blank took 1.2 us for 40); other fill characters and longer runs come from `repeat_str`. |
| `repeat_str` | Doubles its piece at every step: about log2(n) concatenations, not n. |
| `truncate` | The result is never longer than `max_len`. When the ellipsis does not fit (`max_len` not larger than its length) the string is cut without one. |
| `basename`, `dirname` | Follow POSIX: trailing slashes are ignored, `dirname("c.sv")` is `"."`, both return `"/"` for `"/"`. Only `/` is a separator. |
| `scope_slice` | `first` and `last` are inclusive; negative values count from the end (`-1` is the last element). Positions outside the scope are clamped; an empty range gives `""`. |
| `get_numbers` | A run of more than 19 digits may not fit 64 bits; the value then wraps. |
| `natural_cmp` | Digit runs are compared as numbers of any length, everything else by character code. It returns 0 only for identical strings: when two strings differ only in leading zeros, plain string order decides. |
| `natural_sort` | Stable insertion sort; meant for lists of names (hundreds, not millions). |
| `bytes_to_hex` | No trailing space or newline. |
| `simplify_typename` | Purely textual: trims white space, removes a leading `class ` and everything from ` extends ` on. `$typename()` formats differ between simulators; other decorations are left as they are. |

## 5. Configuration

None. `hexk_str::WHITESPACE` (space, tab, newline, carriage return) is the default character
set of the strip functions.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
This module emits no messages.
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_str/hexk_str_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_str_example.sv
//
// Minimal use of hexk_str: take a hierarchical name apart, sort names in natural order,
// and shape strings for a fixed-width log column. Needs only src/core/hexk_core.f.

module hexk_str_example;
   timeunit 1ns / 1ps;

   import hexk_core_pkg::hexk_str;

   localparam string PATH = "uvm_test_top.env.agent_3.drv";

   string fields[$];
   string names [$];

   initial begin
      hexk_str::split(PATH, fields, ".");
      $info("%0d elements, leaf '%s', inside '%s'", fields.size(), fields[$], hexk_str::scope_slice(PATH, 1, -2));

      hexk_str::split("agent_10 agent_2 agent_1", names);
      hexk_str::natural_sort(names);
      $info("natural order: %s", hexk_str::join_str(names, ", "));

      $info("[%s] [%s]", hexk_str::pad("id", 8, 1), hexk_str::truncate(PATH, 12, 1));
      $info("grouped as '%s'", hexk_str::denumber("agent_12.item_7"));
   end

endmodule : hexk_str_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`hexk_str::join(...)`.** `join` is a SystemVerilog keyword; the function is `join_str`,
  like `repeat_str`.
- **Passing a string as separator to `split` or `scope_slice`.** The separator is one `byte`:
  `hexk_str::split(s, parts, ",")` is right, `", "` silently uses only one character. Split on
  the single character and `strip` the parts.
- **Declaring the output queue in the call.** `parts` and `nums` are `ref` arguments and need a
  variable: declare `string parts[$];` first.
- **Treating `chars` of `strip` as a suffix.** `rstrip("tests.sv", ".sv")` removes every
  trailing `.`, `s` and `v` and returns `"test"`, not `"tests"`. To remove a known suffix,
  check it with `ends_with` and cut with `substr`.
- **Using `natural_cmp(a, b) == 0` as a numeric equality test.** `"a01"` and `"a1"` are not
  equal for `natural_cmp`. Compare the values from `get_numbers` instead.
- **Building a regular expression replacement from `replace`.** `replace` matches literal
  text only.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
