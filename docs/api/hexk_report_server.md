# hexk_report_server

## 1. Summary

UVM report server with a configurable line layout, stack traces and marker lines on
selected messages, message listeners, and an end-of-test summary table per severity and ID.

## 2. When to use / when not to use

Use it as the report server of a testbench when the default UVM lines are hard to read or
grep, when a stack trace on certain messages saves a debug iteration, or when something
outside UVM has to know about every error (a waveform marker, a log for a tool). Classes
keep reporting with the `` `uvm_* `` macros; nothing changes at the call sites.

Do not use it to count or expect errors in negative tests; that is `hexk_report_catcher`. Do
not format messages in the server that should have been written better at the source (guide
rule MSG-8). If only the default UVM text is wanted, there is no need to install it.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/report/hexk_msg_listener.sv`
- `src/uvm/report/hexk_report_cfg.sv`
- `src/uvm/report/hexk_report_server.sv`
- `src/uvm/report/hexk_warning_audit.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/report/hexk_msg_listener.sv`:

```systemverilog
// Called by hexk_report_server for every warning, error and fatal message that is issued. The formatter breaks a pure virtual prototype over three lines. verilog_format: off
pure virtual function void on_message(uvm_report_message msg);
```

From `src/uvm/report/hexk_report_cfg.sv`:

```systemverilog
// Layout of a report line: UVM's own, the fixed-column layout of the library, or the fields listed in the cfg.
typedef enum bit [1:0] { HEXK_FMT_UVM, HEXK_FMT_COMPACT, HEXK_FMT_CUSTOM } hexk_report_style_e;
// One column of a report line.
typedef enum bit [2:0] { HEXK_FLD_SEVERITY, HEXK_FLD_COUNTER, HEXK_FLD_TIME, HEXK_FLD_FILE_LINE, HEXK_FLD_ID, HEXK_FLD_CONTEXT, HEXK_FLD_MESSAGE } hexk_report_field_e;
// Unit of the time column of a report line.
typedef enum bit [2:0] { HEXK_TIME_FS, HEXK_TIME_PS, HEXK_TIME_NS, HEXK_TIME_US, HEXK_TIME_MS, HEXK_TIME_S } hexk_time_unit_e;
// Creates a cfg with the default values listed above.
function new(string name = "hexk_report_cfg");
// Overrides fields from the command line; see the plusarg table in docs/api/hexk_report_server.md.
function void apply_plusargs();
// Text of a unit as the time column shows it, such as "ns".
static function string time_unit_text(hexk_time_unit_e unit);
// The unit with this short name (fs, ps, ns, us, ms, s, in any case); 0 when the text names no unit.
static function bit time_unit_of(string text, output hexk_time_unit_e unit);
// Power of ten of a unit in seconds: -9 for HEXK_TIME_NS. The one table of the units.
static function int unit_exponent(hexk_time_unit_e unit);
// Number of picoseconds in one of a unit: 0.001 for HEXK_TIME_FS.
static function real ps_per_unit(hexk_time_unit_e unit);
// One-line summary of the layout settings, for log messages.
function string convert2string();
// UVM hook of copy() and clone(): copies every member.
function void do_copy(uvm_object rhs);
```

From `src/uvm/report/hexk_report_server.sv`:

```systemverilog
// Creates a server that prints UVM's own layout until set_cfg is called.
function new(string name = "hexk_report_server");
// Creates a server, gives it cfg (UVM layout when null) and makes it the report server of the simulation.
static function hexk_report_server install(hexk_report_cfg cfg = null);
// The report server of the simulation if it is a hexk_report_server, otherwise null.
static function hexk_report_server get_installed();
// Takes a copy of a configuration: a later change of cfg has no effect until set_cfg is called again. A null cfg is ignored.
function void set_cfg(hexk_report_cfg cfg);
// Returns a copy of the configuration in use; change it and give it to set_cfg.
function hexk_report_cfg get_cfg();
// Registers an object that is told about every warning, error and fatal message.
function void add_listener(hexk_msg_listener listener);
// Number of messages of this ID and severity that were issued.
function int unsigned get_count(string id, uvm_severity severity);
// Text of the summary: one line per severity and ID, the noisiest IDs, and the first error.
function string summary();
// True when the cfg asks for a stack trace on this message.
function bit gets_stacktrace(uvm_report_message report_message);
// True when the cfg asks for a marker line in front of this message.
function bit gets_marker(uvm_report_message report_message);
// Builds the text of one report line in the configured layout.
function string compose_report_message(uvm_report_message report_message, string report_object_name = "");
// Counts the message, adds marker line and stack trace, tells the listeners, then lets UVM act on it.
function void execute_report_message(uvm_report_message report_message, string composed_message);
// Prints UVM's summary and then the summary table of this server; with a file other than the default, the table is also written to that file.
function void report_summarize(UVM_FILE file = `HEXK_UVM_SUMMARY_FILE);
```

From `src/uvm/report/hexk_warning_audit.sv`:

```systemverilog
// Allows the warnings whose ID matches id_regex, an expression as hexk_regex takes it ("^ID$" for one ID).
function void allow(string id_regex);
// Number of warnings that were not allowed, since the start or the last clear().
function int unsigned num_unexpected();
// The unexpected warnings, one per line ("ID: message"), the first MAX_KEPT of them, then how many more came.
function string unexpected_text();
// Forgets the unexpected warnings; the allowed IDs stay.
function void clear();
// hexk_msg_listener: notes a warning unless its ID is allowed.
virtual function void on_message(uvm_report_message msg);
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

Installing:

- `hexk_report_server::install(cfg)` creates the server and makes it the report server of
  the simulation. Call it before `run_test()`. The severity and ID counts that UVM has kept
  so far are carried over (`get_severity_count`, `get_id_count`). The counts by severity and
  ID that `get_count()` and the summary table show, and the first error, start with the
  install: a message from before it is in the counts of UVM only.
- Without a cfg (`install()`), and on a server created directly, the layout is
  `HEXK_FMT_UVM`. A cfg created by the user starts with `HEXK_FMT_COMPACT`.
- `set_cfg` takes a copy of the cfg, including the trigger lists, at that moment: a later
  change of the cfg object changes neither the layout nor the triggers. After changing a cfg
  object, call `set_cfg` again. `get_cfg` returns a copy of the cfg in use.
- `set_cfg` corrects one value in its copy, with the warning `HEXK_REPORT_CFG`: a
  `time_precision` that would show digits below 1 fs is cut to the largest the unit has (0
  for `fs`, 3 for `ps`, 6 for `ns`, 9 for `us`, 12 for `ms`, 15 for `s`).
- `time_unit` is a `hexk_time_unit_e`. Its text comes in through
  `hexk_report_cfg::time_unit_of(text, unit)`, which takes `fs` to `s` in any case and is
  also what `+hexk_timeout` of `hexk_watchdog` uses, and goes out through
  `hexk_report_cfg::time_unit_text(unit)`, which gives the unit as the time column prints
  it. `ps_per_unit(unit)` is the number of picoseconds in one of the unit. What follows from the cfg alone, the
  list of columns and the scale of the time column, is worked out once in `set_cfg` and
  not for every message.
- Messages are counted per ID with one counter per severity; `get_count(id, severity)`
  reads one of them.
- `hexk_report_server::get_installed()` returns the installed server, or null when the report
  server of the simulation is not a `hexk_report_server`. Use it to add a listener from
  code that did not install the server.

Layouts, for an error reported at 120.5 ns by `uvm_test_top.env.sb` from
`my_scoreboard.sv` line 120:

| Style | Line |
|---|---|
| `HEXK_FMT_UVM` | exactly the text of UVM's own report server |
| `HEXK_FMT_COMPACT` | `E3        120.500ns my_scoreboard.sv:120  SB_MISMATCH  env.sb  expected 5, got 4` with the columns padded to their widths |
| `HEXK_FMT_CUSTOM` | the columns listed in `cfg.fields`, in that order; the compact columns when the list is empty |

Columns:

| Field | Content |
|---|---|
| `HEXK_FLD_SEVERITY` | `I`, `W`, `E`, `F`, with the running number of that severity for warnings, errors and fatals (`E3` is the third error); or the UVM name when `severity_letter` is 0 |
| `HEXK_FLD_COUNTER` | the running number of that severity alone |
| `HEXK_FLD_TIME` | simulation time in `time_unit` with `time_precision` digits, right-aligned in 14 characters; independent of `$timeformat` |
| `HEXK_FLD_FILE_LINE` | file name without directory, a colon and the line |
| `HEXK_FLD_ID` | the message ID |
| `HEXK_FLD_CONTEXT` | hierarchical name of the reporter, without `uvm_test_top.` unless `strip_test_top` is 0, followed by `@@` and the context string if the message has one |
| `HEXK_FLD_MESSAGE` | the message text, then the message elements if any |

A column with a width is padded to it. A longer value is shortened with `..`: file:line and
context keep their right end, the ID keeps its left end. A width of 0 means no padding and
no shortening. Columns are separated by one space.

Stack traces and markers:

- A stack trace (the `HEXK_STACKTRACE` macro of `hexk_sim_compat`) is printed for a message
  when one of these holds: it is a fatal and `stacktrace_on_fatal` is set; it is an error
  and `stacktrace_on_error` is set; it is a warning, error or fatal issued from a file whose
  name starts with `uvm_` and `stacktrace_on_uvm_internal` is set; it matches one of the
  `stacktrace_triggers`.
- A trigger that ends in a colon and decimal digits, with a name before the colon, is a file
  name and line (`my_driver.sv:120`), compared with the message's file name without
  directory. It is recognised by a small parser, not by a regular expression, so it works
  also when UVM is compiled without its regex DPI code. Any other trigger is a regular expression
  (`hexk_regex`) matched against the ID and against the text. Every such trigger costs
  two matches per message; without triggers no expression is matched. With many messages
  and UVM 2020, `+define+UVM_ENABLE_RE_MATCH_CACHE` makes the matches about three times
  cheaper (measured on Questa, see `hexk_regex`, section 4).
- Cost per message, besides the output of UVM: the text of each column of the layout, one
  count per ID and severity, the listeners for warnings, errors and fatals, and the triggers
  above. The layout and the time scale are worked out once per `set_cfg()`. The column
  texts that repeat are built once and kept: the severity column per severity (unless it
  has a running number), the time column per time step, file:line per file and line, the ID
  column per ID, the context column per reporter (for a message without a context string of
  its own). Whether a trigger matches the ID is kept per ID; whether one matches the text is
  decided for every message. Each store is emptied when it reaches `STORE_LIMIT` (4096)
  entries, so IDs or reporter names made at run time cannot fill the memory; `set_cfg()`
  empties them all. `make bench` measures a message with the default cfg and one with four
  marker and four stack trace triggers; the numbers are in section 9.
- The stack trace is printed before the message line, because a fatal ends the simulation
  while UVM handles it.
- A message that matches one of the `marker_triggers` is printed with the line
  `HEXK_MARKER: <ID>` in front of it.
- `gets_stacktrace` and `gets_marker` tell what the server would do for a message.

Counts, listeners, summary:

- Every message that UVM lets through (after verbosity filtering and report catchers) is
  counted by severity and ID; `get_count` reads a count.
- Listeners are called for warnings, errors and fatals, in the order they were added, before
  the message is printed.
- `hexk_warning_audit` is a listener for a test that wants a clean log: `allow(id_regex)`
  allows warnings by their ID (`hexk_regex`), `num_unexpected()` counts the others,
  `unexpected_text()` gives the first 20 as "ID: message" lines and the number of the rest,
  `clear()` forgets them. It reports nothing itself; `hexk_base_test` reports what it
  collected when `fail_on_warnings` is set.
- At the end of the test UVM calls `report_summarize`; the server prints UVM's summary and
  then its own (`summary()`) as the info `HEXK_REPORT_SUMMARY`: one line per severity and
  ID from fatal to info, the five IDs with the most messages (digit runs replaced by `#`, so
  `agent_1.DRV` and `agent_2.DRV` count together), and time, ID and text of the first error
  or fatal. When UVM writes its summary to a file other than the default, the table of the
  server is written to that file as well.

## 5. Configuration

Fields of `hexk_report_cfg`:

| Field | Default | Meaning |
|---|---|---|
| `style` | `HEXK_FMT_COMPACT` | layout of a line |
| `fields` | empty | columns of the custom layout |
| `file_line_width` | 28 | width of the file:line column, 0 for no limit |
| `id_width` | 24 | width of the ID column, 0 for no limit |
| `context_width` | 40 | width of the context column, 0 for no limit |
| `time_unit` | `HEXK_TIME_NS` | unit of the time column: `HEXK_TIME_FS`, `HEXK_TIME_PS`, `HEXK_TIME_NS`, `HEXK_TIME_US`, `HEXK_TIME_MS` or `HEXK_TIME_S` |
| `time_precision` | 3 | digits after the decimal point; none below 1 fs |
| `severity_letter` | 1 | one letter instead of the UVM severity name |
| `numbered` | 1 | running number after the severity letter |
| `strip_test_top` | 1 | drop `uvm_test_top.` from the context |
| `color` | 0 | ANSI colours on the severity column |
| `stacktrace_on_fatal` | 1 | stack trace for every fatal |
| `stacktrace_on_error` | 0 | stack trace for every error |
| `stacktrace_on_uvm_internal` | 1 | stack trace for warnings and worse from UVM's own files |
| `stacktrace_triggers` | empty | messages that get a stack trace |
| `marker_triggers` | empty | messages that get a marker line |

Plusargs, read by `cfg.apply_plusargs()` only:

| Plusarg | Effect |
|---|---|
| `+hexk_report_style=uvm\|compact\|custom` | sets `style`; another text, also an empty one, is the warning `HEXK_REPORT_CFG` and changes nothing |
| `+hexk_report_fields=<f>,<f>,...` | sets `fields`; names are `severity`, `counter`, `time`, `file_line`, `id`, `context`, `message` |
| `+hexk_report_time_unit=fs\|ps\|ns\|us\|ms\|s` | sets `time_unit`; another text, also an empty one, is the warning `HEXK_REPORT_CFG` and changes nothing |
| `+hexk_report_color` | sets `color`; `+hexk_report_color=0` clears it; a value that is not a bit value is the warning `HEXK_REPORT_CFG` and keeps `color` |
| `+hexk_stacktrace=<trigger>,<trigger>,...` | adds to `stacktrace_triggers` |
| `+hexk_marker=<trigger>,<trigger>,...` | adds to `marker_triggers` |

A trigger given on the command line cannot contain a comma.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | fatal |  |
| `HEXK_REPORT_CFG` | warning |  |
| `HEXK_REPORT_CLONE` | fatal |  |
| `HEXK_REPORT_SUMMARY` | info |  |
<!-- HEXK_GEN:END emits -->

| ID | Meaning |
|---|---|
| `HEXK_REPORT_CFG` | a plusarg value or a cfg field is not legal; the previous or default value is used |
| `HEXK_REPORT_SUMMARY` | the summary table at the end of the test |
| `HEXK_COPY_TYPE` | `copy()` of a `hexk_report_cfg` from an object of another class; nothing is copied |
| `HEXK_REPORT_CLONE` | `set_cfg` or `get_cfg` could not clone the cfg as a `hexk_report_cfg` (a factory override that is not one) |

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_report_server/hexk_report_server_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_report_server_example.sv
//
// Minimal use of hexk_report_server: build a cfg, let the command line override it, install
// the server, report through the usual UVM macros, and print the summary table.
// In a real testbench the install comes before run_test(), and UVM prints the summary at
// the end of the test by itself. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_report_server_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_report_cfg;
   import hexk_uvm_pkg::hexk_report_server;
   `include "uvm_macros.svh"

   localparam int unsigned CONTEXT_WIDTH = 20;

   hexk_report_cfg    cfg;
   hexk_report_server server;

   initial begin
      cfg               = hexk_report_cfg::type_id::create("cfg");
      cfg.context_width = CONTEXT_WIDTH;
      cfg.stacktrace_triggers.push_back("^SB_MISMATCH$");
      cfg.apply_plusargs();
      server = hexk_report_server::install(cfg);

      `uvm_info("EXAMPLE", "printed in the compact layout", UVM_NONE)
      `uvm_warning("EXAMPLE", "warnings, errors and fatals get a running number")
      $info("\n%s", server.summary());
   end

endmodule : hexk_report_server_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Installing after `run_test()` has started.** Messages printed earlier have the old
  layout. Install in the testbench top before `run_test()`.
- **Changing the cfg object after installing and expecting an effect.** The server works
  on the copy that `set_cfg` took. Call `server.set_cfg(cfg)` again.
- **Parsing the compact layout in scripts.** Widths and columns are meant to change per
  project. For tools, register a `hexk_msg_listener` or use `+hexk_marker`.
- **A listener that reports through UVM.** `on_message` is called from inside the report
  server; reporting from it re-enters the server. Record the event and report later.
- **A trigger without anchors that matches too much.** `+hexk_stacktrace=SB` also matches
  message texts containing "SB". Use `^SB_MISMATCH$` for an ID.
- **Expecting a stack trace on every simulator.** `HEXK_STACKTRACE` has no effect where the
  simulator offers no such task; see `hexk_sim_compat`.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.

Cost of one message without the output of UVM (`compose_report_message`, `gets_marker` and
`gets_stacktrace`), with time advancing by 1 ps before every message so that the time column
is new each time, measured with `make bench` on VCS X-2025.06 with UVM 2020.3.1 (Linux in WSL,
2026-10-14):

| Case | Time |
|---|---|
| compact layout, no triggers | 2.2 us |
| compact layout, 4 marker and 4 stack trace triggers that do not match | 6.1 us |
| layout of UVM (`style` `uvm`), no triggers | 1.2 us |

Before the column texts were kept and `hexk_str::pad` took its blanks from a stored run
(versions before 0.7.0), the first two cases took 7.6 to 9.0 us and 13 to 15 us.
The triggers cost about 0.5 us each, because the text of every message is matched against
them. On Questa 2024.1 (Windows) one run gave 2.7 us, 2.6 us and 1.4 us; timings vary by a
factor of two to three between runs on that machine.
