# Using hexk-sv-lib with AI assistants

AI coding assistants read an instruction file in your project (`CLAUDE.md`, `AGENTS.md` or
similar). Paste the snippet into that file so the assistant uses the library instead of
writing its own helpers, and knows where the contracts are.

```markdown
## hexk-sv-lib

This project uses hexk-sv-lib ($HEXK_SV_LIB_HOME), a SystemVerilog/UVM utility library.

- Before using a library module, read its contract: $HEXK_SV_LIB_HOME/llms.txt lists them,
  one file per module under $HEXK_SV_LIB_HOME/docs/api/. Do not guess an API from its name.
- Do not write a helper that the library already has. Do not copy library code into this
  project; depend on it.
- Never edit files under $HEXK_SV_LIB_HOME.
- In every file that uses a library macro: `include "hexk_macros.svh" at the top, outside
  the package or module.
- String handling (split, join, strip, pad, truncate, natural sort, paths): use hexk_str
  from hexk_core_pkg instead of writing loops over characters.
- Text to enum, enum to text, legal-value checks, list of members: use
  hexk_enum_util #(my_enum_e) from hexk_core_pkg, not a case statement over names.
- CRC: use hexk_crc (presets or the six catalogue parameters); never hand-write a CRC loop.
  Hardware-exact pseudo-random sequences: use hexk_lfsr.
- Hamming SECDED check bits, syndromes and error injection: use hexk_ecc, and compare one
  code word with the DUT first (the layout is an argument of new()).
- Random values in modules, interfaces and BFMs: one hexk_rand_stream per consumer, seeded
  explicitly; not $urandom. Class stimulus keeps using rand variables and constraints.
- Plusargs outside UVM code: hexk_plusarg::get_int/get_str/get_bit/get_list with a default,
  not $value$plusargs or $test$plusargs directly.
- Alignment, clamp, log2, popcount, parity, bit reversal, sign extension, range overlap:
  use hexk_math from hexk_core_pkg.
- Do not test simulator defines (VCS, QUESTA, XCELIUM); use HEXK_SIM_NAME and
  HEXK_STACKTRACE from hexk_sim_compat.svh.
- Checks: `hexk_check_eq(act, exp, "STATIC_ID", "what") and the other `hexk_check_* macros
  instead of if + `uvm_error; value under test first, no semicolon after the macro.
  Every randomize(): `hexk_randomize_or_fatal / `hexk_randomize_with_or_fatal.
- Waiting for the DUT: `hexk_wait_timeout(cond, 10us, "STATIC_ID") or
  `hexk_spinwait(statements;, 1ms, "STATIC_ID"), never a bare wait() that can hang and
  never a hand-written fork/join_any/disable fork.
- Reporting: `uvm_info/warning/error/fatal in classes. Only in static methods, modules and
  interfaces use `hexk_static_info/warning/error/fatal; never $display.
- Negative tests: declare provoked messages with hexk_report_catcher::expect_msg (anchor
  the ID with ^ and $) and call check_expectations() in check_phase; never lower the
  severity of an error another way. A provoked failure of a library check or of a
  scoreboard comparison still counts as a failed check: also declare it with
  hexk_check_stats::expect_failures(id, count), or a test on hexk_base_test fails.
- Report layout, stack traces on selected messages, end-of-test summary: install
  hexk_report_server before run_test(); keep reporting with the `uvm_* macros.
- Pattern matching on strings in UVM code: hexk_regex::match (1 means match), not
  uvm_re_match (0 means match).
- Do not test UVM version macros; use HEXK_UVM_VERSION_1_2 and HEXK_UVM_VERSION_IEEE.
- Names starting with hexk_ or HEXK_ belong to the library. Do not create new ones in this
  project: the macros declare local variables with such names (hexk_check_act, ...), and a
  variable of the same name passed to a macro silently reads the macro's own copy.
```

The snippet covers the modules a project usually needs first. `llms.txt` lists every
module with its contract.
