# SPDX-License-Identifier: Apache-2.0
# Copyright (c) 2026 HEXK
#
# Makefile - entry points of the self-tests of hexk-sv-lib (Gate 1 and Gate 2, see tests/README.md).
# Runs on Linux (including WSL) with GNU make and bash. Tools are found on PATH;
# every tool variable below can be overridden on the command line.
# 'make test SIM=questa' (Gate 2) also runs on Windows, from Git Bash with a native GNU make.
# 'make test SIM=vcs' (Gate 2) runs on Linux with vcs on PATH and the license set up.

SHELL         := /bin/bash
.SHELLFLAGS   := -eu -o pipefail -c
.DEFAULT_GOAL := help

HEXK_SV_LIB_HOME := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
export HEXK_SV_LIB_HOME

PYTHON         ?= python3
VERIBLE_FORMAT ?= verible-verilog-format
VERIBLE_LINT   ?= verible-verilog-lint
VERILATOR      ?= verilator
FUSESOC        ?= fusesoc
SLANG          ?= $(PYTHON) scripts/hexk_slang.py
SVUNIT         ?= runSVUnit
SVUNIT_BUILD   ?= buildSVUnit
QUESTA_VLIB    ?= vlib
QUESTA_VLOG    ?= vlog
QUESTA_VSIM    ?= vsim
VCS            ?= vcs

# UVM=1.2|2020 selects the UVM sources for 'make elab' and for the targets with SIM=questa or SIM=vcs;
# SIM and TEST are for 'make test'.
UVM  ?= 1.2
SIM  ?= verilator
TEST ?=

BUILD_DIR ?= build
UVM_HOME  ?= $(BUILD_DIR)/uvm/$(UVM)

# UVM is an external dependency and is never vendored: 'make uvm_fetch' downloads it here.
UVM_URL_1.2  := https://www.accellera.org/images/downloads/standards/uvm/uvm-1.2.tar.gz
UVM_URL_2020 := https://github.com/accellera-official/uvm-core/archive/refs/tags/2020.3.1.tar.gz

SV_FILES      := $(shell find src tests examples \( -name '*.sv' -o -name '*.svh' \) | sort)
EXAMPLES      := $(sort $(wildcard examples/*/*.sv))
# Examples that do not mention UVM compile against the core filelist alone.
CORE_EXAMPLES := $(if $(EXAMPLES),$(shell grep -L -E 'uvm_pkg|hexk_uvm_pkg|hexk_macros' $(EXAMPLES)))
UVM_EXAMPLES  := $(filter-out $(CORE_EXAMPLES),$(EXAMPLES))
# Code written the way a user writes it, linted with the core like an example (tests/lint/README.md).
CORE_LINT_CASES := tests/lint/hexk_core_enum_lint.sv
ALL_UNIT_TESTS := $(sort $(wildcard tests/unit/*/*_unit_test.sv))
UNIT_TESTS    := $(sort $(wildcard tests/unit/$(if $(TEST),$(TEST),*)/*_unit_test.sv))
# Unit tests that mention UVM are simulated with UVM compiled in; the others with the core alone.
UVM_UNIT_TESTS  := $(if $(UNIT_TESTS),$(shell grep -l -E 'uvm_pkg|hexk_uvm_pkg|hexk_macros' $(UNIT_TESTS)))
CORE_UNIT_TESTS := $(filter-out $(UVM_UNIT_TESTS),$(UNIT_TESTS))
# UVM release for simulating the UVM-layer unit tests on Verilator, which cannot compile UVM 1.2.
# Only the regex part of the UVM DPI library is built (tests/unit/hexk_uvm_regex_dpi.cc).
UVM_SIM_HOME  ?= $(BUILD_DIR)/uvm/2020
# SVUnit is an external dependency like UVM; SVUNIT_INSTALL points at its checkout.
SVUNIT_SOURCES = +incdir+$(SVUNIT_INSTALL)/svunit_base \
                 $(SVUNIT_INSTALL)/svunit_base/junit-xml/junit_xml.sv $(SVUNIT_INSTALL)/svunit_base/svunit_pkg.sv
SVUNIT_QUIET   = --suppress-warnings '$(SVUNIT_INSTALL)/...' --suppress-macro-warnings '$(SVUNIT_INSTALL)/...'
# Where SVUnit builds and runs. On WSL, point it at the Linux file system (for example
# SVUNIT_OUT=$HOME/.cache/hexk-sv-lib/svunit): compiling on a Windows drive is several times slower.
SVUNIT_OUT    ?= $(abspath $(BUILD_DIR))/svunit
# The exit status of runSVUnit does not say whether the tests passed, so 'make test' reads
# the summary line of the log. Library code reports illegal arguments with $error, which
# stops a Verilator simulation unless the limit is raised; unit tests call such code on purpose.
SVUNIT_RUN_ARGS = -r_arg "+verilator+error+limit+1000000"
# Build the simulation with all processor cores. The time scale is the default for the code
# that declares no time unit, as on the other simulators; without it Verilator reports every
# such module once an interface of the library declares its own.
SVUNIT_COMPILE_ARGS = -c_arg "-j 0" -c_arg "--timescale 1ns/1ps"
# Plusargs that unit tests expect on the command line: tests/unit/<module>/<name>.plusargs,
# one per line; lines that do not start with '+' are comments.
PLUSARG_FILES  := $(sort $(wildcard tests/unit/$(if $(TEST),$(TEST),*)/*.plusargs))
SVUNIT_PLUSARGS = $(foreach arg,$(shell cat $(PLUSARG_FILES) /dev/null | grep '^+'),-r_arg "$(arg)")
# Questa (Gate 2). SVUnit only generates the test runner; vlog and vsim are called directly.
# UVM is compiled from $(UVM_HOME) with its DPI code, so a C compiler must be on PATH.
SIM_PLUSARGS    = $(shell cat $(PLUSARG_FILES) /dev/null | grep '^+')
# The tests and the example of the HDL access macros reach signals of their own module by
# path, which Questa allows only for the modules named here.
QUESTA_ACCESS   = $(if $(filter %/hexk_hdl_macros_unit_test.sv,$(UVM_UNIT_TESTS)),-voptargs=-access=rw+hexk_hdl_macros_unit_test)
HDL_ACCESS_EXAMPLES := hexk_hdl_macros_example
# Examples with a DUT that drives a pin of hexk_pins_if through a port: Verilator rejects a
# tristate driver of a net of another scope, so its lint leaves them out. slang elaborates
# them and 'make examples' runs them.
PIN_MODEL_EXAMPLES  := hexk_pins_example
VERILATOR_UVM_EXAMPLES = $(filter-out $(foreach name,$(PIN_MODEL_EXAMPLES),%/$(name).sv),$(UVM_EXAMPLES))
ifeq ($(OS),Windows_NT)
# The Windows tools cannot open the MSYS paths (/d/...) that SVUnit writes into its filelist.
QUESTA_FIX_PATHS = sed -i -E 's\#(^|\+incdir\+)/([a-z])/\#\1\2:/\#'
# MinGW-w64 has no POSIX regex.h, which the UVM DPI code includes: tests/unit/mingw_compat
# supplies one on top of the C++ library, which the link step then needs.
QUESTA_CCFLAGS   = -DQUESTA -I$(HEXK_SV_LIB_HOME)/tests/unit/mingw_compat
QUESTA_LDFLAGS   = -ldflags -lstdc++
else
QUESTA_FIX_PATHS = true
QUESTA_CCFLAGS   = -DQUESTA
QUESTA_LDFLAGS   =
endif
# VCS (Gate 2, Linux). SVUnit only generates the test runner; vcs compiles and simv runs.
# UVM is compiled from $(UVM_HOME) with its DPI code. The time scale is the default for the
# code that declares no time unit, as in the other flows.
VCS_FLAGS       ?= -full64 -sverilog -timescale=1ns/1ps
VCS_UVM_ARGS     = +incdir+$(abspath $(UVM_HOME))/src $(abspath $(UVM_HOME))/src/uvm_pkg.sv \
                   -f $(HEXK_SV_LIB_HOME)/src/hexk_all.f $(abspath $(UVM_HOME))/src/dpi/uvm_dpi.cc -CFLAGS -DVCS
# Read and write access to signals by path, which the tests and the example of the HDL access
# macros need; it is given only to the simulations that hold them.
VCS_ACCESS_FLAGS ?= -debug_access+r+w+f
VCS_ACCESS       = $(if $(filter %/hexk_hdl_macros_unit_test.sv,$(UVM_UNIT_TESTS)),$(VCS_ACCESS_FLAGS))
# An example or a smoke test that is still running after this many seconds of the wall clock
# is stopped and fails. VCS has no option that ends a simulation at a time and tells whether
# it would have gone on, which the Questa flow uses (EXAMPLES_RUN_TIME, SMOKE_RUN_TIME).
VCS_RUN_TIMEOUT  ?= 300
# Where 'make examples' builds, and how long an example may simulate before it is stopped.
EXAMPLES_OUT      ?= $(abspath $(BUILD_DIR))/examples_$(SIM)
EXAMPLES_RUN_TIME ?= 10 ms
# The smoke testbench: its filelist, where 'make smoke' builds, and how long a test may simulate.
SMOKE_FILELIST    := tests/smoke/hexk_smoke.f
SMOKE_OUT         ?= $(abspath $(BUILD_DIR))/smoke_$(SIM)
SMOKE_RUN_TIME    ?= 10 ms
# Where 'make rebrand_check' writes the rebranded copy that it elaborates.
REBRAND_OUT       ?= $(abspath $(BUILD_DIR))/rebrand_check
# The benchmarks: the file, where 'make bench' builds, and each case with its count of operations.
BENCH_FILE        := tests/bench/hexk_bench.sv
BENCH_OUT         ?= $(abspath $(BUILD_DIR))/bench_$(SIM)
BENCH_CASES       ?= sb_in_order:5000000 sb_ooo_1:2000000 sb_ooo_16:200000 sb_ooo_256:20000 \
                     sb_ooo_256_partner:200000 delay_uniform:2000000 delay_weighted:2000000 report:200000 \
                     report_triggers:200000 report_uvm:200000 time_step:200000
CORES         := hexkdotcom:hexk:core hexkdotcom:hexk:uvm hexkdotcom:hexk:clk_rst hexkdotcom:hexk:valid_ready hexkdotcom:hexk:pins \
                 hexkdotcom:hexk:sv_lib

.PHONY: help tools pre_sim ci version version_check format format_check lint lint_verible lint_verilator \
        style_check rebrand_rules rebrand_check docs docs_check elab elab_all cores_check test examples smoke bench uvm_fetch clean

help:
	@echo "hexk-sv-lib $$(cat VERSION) - Gate 1 targets"
	@echo "  make pre_sim                 everything below, in order (Gate 1)"
	@echo "  make ci                      the static part of Gate 1, without Verilator (what CI runs)"
	@echo "  make tools                   show which Gate 1 tools are on PATH"
	@echo "  make version                 rewrite the files derived from VERSION"
	@echo "  make format                  reformat all SystemVerilog files in place (Verible)"
	@echo "  make lint                    Verible lint and Verilator lint (lint_verible, lint_verilator)"
	@echo "  make style_check             library style rules (scripts/hexk_style_check.py)"
	@echo "  make rebrand_check           prefix rules (rebrand_rules), and a rebranded copy that must elaborate and pass its unit tests"
	@echo "  make docs                    regenerate docs/api blocks and check doc coverage"
	@echo "  make elab UVM=1.2|2020       slang elaboration of everything against that UVM"
	@echo "  make cores_check             FuseSoC can read the .core files"
	@echo "  make test SIM=verilator [TEST=<module>]   unit tests on Verilator (UVM layer with UVM 2020)"
	@echo "  make test SIM=questa|vcs UVM=1.2|2020 [TEST=<module>]   unit tests on Questa or VCS (Gate 2)"
	@echo "  make examples SIM=questa|vcs UVM=1.2|2020   compile and run every example (Gate 2)"
	@echo "  make smoke SIM=questa|vcs UVM=1.2|2020      the three tests of the smoke testbench (Gate 2)"
	@echo "  make bench SIM=questa|vcs UVM=1.2|2020      cost of one operation of the paths that run per transaction"
	@echo "  make uvm_fetch               download UVM 1.2 and 2020 sources into $(BUILD_DIR)/uvm"

# Gate 1 ---------------------------------------------------------------------------------

pre_sim: tools version_check format_check lint style_check rebrand_check docs_check elab_all cores_check test

# The static part of Gate 1: no Verilator and no simulation. CI runs it on every push to main.
ci: version_check format_check lint_verible style_check rebrand_rules docs_check elab_all cores_check
	@echo "pre_sim: Gate 1 passed"

tools:
	@echo "== tools"
	@missing=0; \
	for tool in $(PYTHON) $(VERIBLE_FORMAT) $(VERIBLE_LINT) $(VERILATOR) z3 $(FUSESOC) $(SVUNIT); do \
	   if command -v $$tool > /dev/null; then printf "  %-24s %s\n" $$tool "$$(command -v $$tool)"; \
	   else printf "  %-24s MISSING\n" $$tool; missing=1; fi; \
	done; \
	if $(PYTHON) -c "import pyslang" 2> /dev/null; then \
	   printf "  %-24s %s\n" pyslang "$$($(PYTHON) -c 'import pyslang; print(pyslang.__version__)')"; \
	else printf "  %-24s MISSING (pip install pyslang)\n" pyslang; missing=1; fi; \
	exit $$missing

version:
	@$(PYTHON) scripts/hexk_gen_version.py

version_check:
	@echo "== version_check"
	@$(PYTHON) scripts/hexk_gen_version.py --check

format:
	@$(VERIBLE_FORMAT) --flagfile=tests/lint/.verible-format --inplace $(SV_FILES)

format_check:
	@echo "== format_check (verible-verilog-format --verify)"
	@$(VERIBLE_FORMAT) --flagfile=tests/lint/.verible-format --inplace --verify $(SV_FILES)
	@echo "format_check: $(words $(SV_FILES)) files, no diff"

lint: lint_verible lint_verilator

lint_verible:
	@echo "== lint (verible-verilog-lint)"
	@$(VERIBLE_LINT) --rules_config=tests/lint/.rules.verible_lint --waiver_files=tests/lint/verible.waiver $(SV_FILES)
	@echo "lint: verible: $(words $(SV_FILES)) files, no violations"

lint_verilator:
	@echo "== lint (verilator --lint-only -Wall, core)"
	@for example in $(CORE_EXAMPLES) $(CORE_LINT_CASES); do \
	   $(VERILATOR) --lint-only -Wall --timescale 1ns/1ps tests/lint/verilator.vlt \
	      -f src/core/hexk_core.f $$example --top-module $$(basename $$example .sv); \
	   echo "lint: verilator: core + $$example clean"; \
	done
	@echo "== lint (verilator --lint-only -Wall, UVM layer with UVM from $(UVM_SIM_HOME))"
	@# UNUSEDSIGNAL is off here: every example is linted with the whole package, and the public
	@# fields of the classes that an example does not use would all be reported as unused.
	@mkdir -p $(BUILD_DIR)
	@# UVM is waived by its absolute path and by the path as given, which Verilator may print instead. A
	@# waiver without a rule does not cover INITIALDLY, which uvm_wait_for_nba_region() of UVM gives when a wait
	@# macro runs in an initial block.
	@printf '%s\n' '`verilator_config' 'lint_off -file "$(abspath $(UVM_SIM_HOME))/*"' \
	   'lint_off -file "$(UVM_SIM_HOME)/*"' 'lint_off -rule INITIALDLY -file "*/uvm_globals.svh"' \
	   > $(BUILD_DIR)/uvm_quiet.vlt
	@for example in $(VERILATOR_UVM_EXAMPLES); do \
	   $(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL --timing --timescale 1ns/1ps \
	      tests/lint/verilator.vlt $(BUILD_DIR)/uvm_quiet.vlt \
	      +incdir+$(UVM_SIM_HOME)/src +define+UVM_HDL_NO_DPI +define+UVM_CMDLINE_NO_DPI $(UVM_SIM_HOME)/src/uvm_pkg.sv \
	      -f src/hexk_all.f $$example --top-module $$(basename $$example .sv); \
	   echo "lint: verilator: UVM layer + $$example clean"; \
	done
	@$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL --timing --timescale 1ns/1ps \
	   tests/lint/verilator.vlt $(BUILD_DIR)/uvm_quiet.vlt \
	   +incdir+$(UVM_SIM_HOME)/src +define+UVM_HDL_NO_DPI +define+UVM_CMDLINE_NO_DPI $(UVM_SIM_HOME)/src/uvm_pkg.sv \
	   -f src/hexk_all.f -f $(SMOKE_FILELIST) --top-module hexk_smoke_tb
	@echo "lint: verilator: UVM layer + smoke testbench clean"
	@$(VERILATOR) --lint-only -Wall -Wno-UNUSEDSIGNAL --timing --timescale 1ns/1ps \
	   tests/lint/verilator.vlt $(BUILD_DIR)/uvm_quiet.vlt \
	   +incdir+$(UVM_SIM_HOME)/src +define+UVM_HDL_NO_DPI +define+UVM_CMDLINE_NO_DPI $(UVM_SIM_HOME)/src/uvm_pkg.sv \
	   -f src/hexk_all.f $(BENCH_FILE) --top-module hexk_bench
	@echo "lint: verilator: UVM layer + benchmarks clean"

style_check:
	@echo "== style_check"
	@$(PYTHON) scripts/hexk_style_check.py

# The prefix rules, then the proof that they are enough: the tree is written again
# with the prefix zzz_, the copy must hold no trace of the old prefix outside the keep-list
# (the script checks that), slang must elaborate it against both UVM versions, and its unit
# tests must pass on Verilator. The tests find what no rule and no elaboration can: code or
# an expected text that depends on the length of the prefix.
# The prefix rules alone, without the rebranded copy.
rebrand_rules:
	@echo "== rebrand_rules"
	@$(PYTHON) scripts/hexk_rebrand.py --check

rebrand_check:
	@echo "== rebrand_check"
	@$(PYTHON) scripts/hexk_rebrand.py --check
	@$(PYTHON) scripts/hexk_rebrand.py --prefix zzz --out $(REBRAND_OUT) --force
	@echo "-- elaboration of the copy with the prefix zzz_ ($(REBRAND_OUT))"
	@$(MAKE) --no-print-directory -C $(REBRAND_OUT) elab_all BUILD_DIR=$(abspath $(BUILD_DIR))
	@echo "-- unit tests of the copy on Verilator"
	@$(MAKE) --no-print-directory -C $(REBRAND_OUT) test SIM=verilator TEST= BUILD_DIR=$(abspath $(BUILD_DIR)) 	   SVUNIT_OUT=$(SVUNIT_OUT)/rebrand

docs:
	@$(PYTHON) scripts/hexk_gen_api_docs.py

docs_check:
	@echo "== docs_check"
	@$(PYTHON) scripts/hexk_gen_api_docs.py --check

elab:
	@echo "== elab UVM=$(UVM) (slang, $(UVM_HOME))"
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "elab: no UVM $(UVM) sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	@test -z "$(ALL_UNIT_TESTS)" || test -f "$(SVUNIT_INSTALL)/svunit_base/svunit_pkg.sv" || \
	   { echo "elab: unit tests need SVUnit; set SVUNIT_INSTALL to its checkout"; exit 1; }
	@$(SLANG) -f tests/lint/slang.f \
	   --suppress-warnings '$(UVM_HOME)/src/...' --suppress-macro-warnings '$(UVM_HOME)/src/...' \
	   $(if $(ALL_UNIT_TESTS),$(SVUNIT_QUIET)) \
	   +incdir+$(UVM_HOME)/src $(UVM_HOME)/src/uvm_pkg.sv -f src/hexk_all.f \
	   $(if $(ALL_UNIT_TESTS),$(SVUNIT_SOURCES)) $(EXAMPLES) $(ALL_UNIT_TESTS) -f $(SMOKE_FILELIST) $(BENCH_FILE)

elab_all:
	@$(MAKE) --no-print-directory elab UVM=1.2
	@$(MAKE) --no-print-directory elab UVM=2020

cores_check:
	@echo "== cores_check (fusesoc)"
	@mkdir -p $(BUILD_DIR) && touch $(BUILD_DIR)/FUSESOC_IGNORE
	@for core in $(CORES); do \
	   $(FUSESOC) --cores-root . core show $$core > /dev/null; \
	   echo "cores_check: $$core ok"; \
	done

# Unit tests -----------------------------------------------------------------------------
# SIM=verilator runs the unit tests with SVUnit (Gate 1) in two simulations: the core tests
# without UVM, and the UVM-layer tests with UVM 2020. SIM=questa and SIM=vcs (Gate 2) run the
# same two groups, the UVM layer with the UVM selected by UVM=1.2|2020. Xcelium is not wired
# up.

# Fails unless the UVM errors and fatals in a log of unit tests are exactly the ones that
# tests/unit/expected_uvm_errors.txt lists for the suites that ran on this simulator. SVUnit
# alone passes a test whose code reports an error it does not check.
# $(1) log, $(2) simulator, $(3) unit test files
define check_uvm_errors
	@{ grep -E '^(# )?UVM_(ERROR|FATAL) .* @ [0-9]+: [^ ]+ \[[A-Za-z_0-9]+\]' $(1) || true; } \
	   | sed -E 's/^(# )?(UVM_[A-Z]+) .* @ [0-9]+: [^ ]+ \[([A-Za-z_0-9]+)\].*/\2 \3/' | LC_ALL=C sort | uniq -c \
	   | awk '{print $$2, $$3, $$1}' | LC_ALL=C sort > $(1).seen
	@awk -v sim=$(2) -v suites=" $(foreach test,$(3),$(notdir $(patsubst %/,%,$(dir $(test))))) " \
	   '!/^#/ && NF >= 5 && index(suites, " " $$1 " ") && ($$2 == "all" || index("," $$2 ",", "," sim ",")) \
	   {print $$3, $$4, $$5}' tests/unit/expected_uvm_errors.txt | LC_ALL=C sort > $(1).expected
	@diff $(1).expected $(1).seen > $(1).diff || \
	   { echo "test: UVM errors and fatals differ from tests/unit/expected_uvm_errors.txt (< expected, > seen):"; \
	     cat $(1).diff; echo "test: log: $(1)"; exit 1; }
endef

# Runs one group of unit tests in its own simulation and fails unless SVUnit reports PASSED
# and the UVM errors are the expected ones.
# $(1) group name, $(2) unit test files, $(3) options for runSVUnit
define run_svunit
	@command -v $(SVUNIT) > /dev/null || { echo "test: $(SVUNIT) (SVUnit) is not on PATH"; exit 1; }
	@rm -f $(SVUNIT_OUT)/$(1)/test.log
	@cd tests/unit && $(SVUNIT) -s verilator -o $(SVUNIT_OUT)/$(1) \
	   $(foreach test,$(2),--directory $(notdir $(patsubst %/,%,$(dir $(test))))) $(3) \
	   $(SVUNIT_COMPILE_ARGS) $(SVUNIT_RUN_ARGS) $(SVUNIT_PLUSARGS) > $(SVUNIT_OUT)/$(1)/test.log 2>&1 || true
	@grep -E '^%Error|^%Warning|^ERROR|FAILED|tests passing|suites passing' $(SVUNIT_OUT)/$(1)/test.log || true
	@grep -q '\[testrunner\]: PASSED' $(SVUNIT_OUT)/$(1)/test.log || \
	   { echo "test: $(1) tests FAILED (log: $(SVUNIT_OUT)/$(1)/test.log)"; exit 1; }
	$(call check_uvm_errors,$(SVUNIT_OUT)/$(1)/test.log,verilator,$(2))
endef

# Runs one group of unit tests on Questa and fails unless SVUnit reports PASSED and the UVM
# errors are the expected ones. Prints the fatals and the warnings of the simulation; its
# errors are the $error calls of library code that the tests run into on purpose.
# $(1) group name, $(2) unit test files, $(3) vlog arguments, $(4) vsim arguments
define run_questa
	@command -v $(SVUNIT_BUILD) > /dev/null || { echo "test: $(SVUNIT_BUILD) (SVUnit) is not on PATH"; exit 1; }
	@command -v $(QUESTA_VSIM) > /dev/null || { echo "test: $(QUESTA_VSIM) (Questa) is not on PATH"; exit 1; }
	@rm -rf $(SVUNIT_OUT)/$(1) && mkdir -p $(SVUNIT_OUT)/$(1)
	@cd tests/unit && $(SVUNIT_BUILD) -o $(SVUNIT_OUT)/$(1) \
	   $(foreach test,$(2),--directory $(notdir $(patsubst %/,%,$(dir $(test))))) > $(SVUNIT_OUT)/$(1)/build.log 2>&1
	@$(QUESTA_FIX_PATHS) $(SVUNIT_OUT)/$(1)/.svunit.f
	@cd $(SVUNIT_OUT)/$(1) && $(QUESTA_VLIB) work > /dev/null && \
	   { $(QUESTA_VLOG) -sv -quiet -l compile.log -timescale 1ns/1ps $(3) -f .svunit.f > /dev/null 2>&1 || \
	     { grep -E '^\*\* (Error|Fatal)' compile.log; echo "test: $(1): compilation failed (log: $(SVUNIT_OUT)/$(1)/compile.log)"; exit 1; }; }
	@cd $(SVUNIT_OUT)/$(1) && { $(QUESTA_VSIM) -c -lib work -do "run -all; quit -f" -l test.log $(4) \
	   $(SIM_PLUSARGS) testrunner > /dev/null 2>&1 || true; }
	@{ grep -E '^# \*\* (Fatal|Warning)' $(SVUNIT_OUT)/$(1)/test.log || true; } | sort | uniq -c
	@grep -E 'FAILED|tests passing|suites passing' $(SVUNIT_OUT)/$(1)/test.log || true
	@grep -q '\[testrunner\]: PASSED' $(SVUNIT_OUT)/$(1)/test.log || \
	   { echo "test: $(1) tests FAILED (log: $(SVUNIT_OUT)/$(1)/test.log)"; exit 1; }
	$(call check_uvm_errors,$(SVUNIT_OUT)/$(1)/test.log,questa,$(2))
endef

test:
	@echo "== test SIM=$(SIM)$(if $(TEST), TEST=$(TEST))"
ifeq ($(strip $(UNIT_TESTS)),)
	@echo "test: no unit tests under tests/unit$(if $(TEST),/$(TEST))"; exit 1
endif
ifeq ($(SIM),verilator)
ifneq ($(strip $(CORE_UNIT_TESTS)),)
	@echo "-- core tests: $(words $(CORE_UNIT_TESTS)) suites, no UVM"
	@mkdir -p $(SVUNIT_OUT)/core
	$(call run_svunit,core,$(CORE_UNIT_TESTS),-f $(HEXK_SV_LIB_HOME)/src/core/hexk_core.f)
endif
ifneq ($(strip $(UVM_UNIT_TESTS)),)
	@echo "-- UVM tests: $(words $(UVM_UNIT_TESTS)) suites, UVM from $(UVM_SIM_HOME)"
	@test -f $(UVM_SIM_HOME)/src/uvm_pkg.sv || \
	   { echo "test: no UVM sources in $(UVM_SIM_HOME); run 'make uvm_fetch' or set UVM_SIM_HOME"; exit 1; }
	@mkdir -p $(SVUNIT_OUT)/uvm
	@printf '%s\n' '`verilator_config' 'lint_off -file "$(abspath $(UVM_SIM_HOME))/*"' > $(SVUNIT_OUT)/uvm/uvm_quiet.vlt
	@printf '%s\n' '+incdir+$(abspath $(UVM_SIM_HOME))/src' '+define+UVM_HDL_NO_DPI' '+define+UVM_CMDLINE_NO_DPI' \
	   '$(abspath $(UVM_SIM_HOME))/src/uvm_pkg.sv' '-f $(HEXK_SV_LIB_HOME)/src/hexk_all.f' \
	   '$(HEXK_SV_LIB_HOME)/tests/unit/hexk_uvm_regex_dpi.cc' '$(SVUNIT_OUT)/uvm/uvm_quiet.vlt' \
	   > $(SVUNIT_OUT)/uvm/hexk_uvm_sim.f
	$(call run_svunit,uvm,$(UVM_UNIT_TESTS),-f $(SVUNIT_OUT)/uvm/hexk_uvm_sim.f \
	   -c_arg "-CFLAGS -I$(abspath $(UVM_SIM_HOME))/src/dpi")
endif
else ifeq ($(SIM),questa)
ifneq ($(strip $(CORE_UNIT_TESTS)),)
	@echo "-- core tests: $(words $(CORE_UNIT_TESTS)) suites, no UVM"
	$(call run_questa,questa_core,$(CORE_UNIT_TESTS),-f $(HEXK_SV_LIB_HOME)/src/core/hexk_core.f,)
endif
ifneq ($(strip $(UVM_UNIT_TESTS)),)
	@echo "-- UVM tests: $(words $(UVM_UNIT_TESTS)) suites, UVM from $(UVM_HOME)"
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "test: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	$(call run_questa,questa_uvm_$(UVM),$(UVM_UNIT_TESTS),+incdir+$(abspath $(UVM_HOME))/src \
	   $(abspath $(UVM_HOME))/src/uvm_pkg.sv -f $(HEXK_SV_LIB_HOME)/src/hexk_all.f \
	   $(abspath $(UVM_HOME))/src/dpi/uvm_dpi.cc -ccflags "$(QUESTA_CCFLAGS)",$(QUESTA_LDFLAGS) $(QUESTA_ACCESS))
endif
else ifeq ($(SIM),vcs)
ifneq ($(strip $(CORE_UNIT_TESTS)),)
	@echo "-- core tests: $(words $(CORE_UNIT_TESTS)) suites, no UVM"
	$(call run_vcs,vcs_core,$(CORE_UNIT_TESTS),-f $(HEXK_SV_LIB_HOME)/src/core/hexk_core.f)
endif
ifneq ($(strip $(UVM_UNIT_TESTS)),)
	@echo "-- UVM tests: $(words $(UVM_UNIT_TESTS)) suites, UVM from $(UVM_HOME)"
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "test: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	$(call run_vcs,vcs_uvm_$(UVM),$(UVM_UNIT_TESTS),$(VCS_UVM_ARGS) $(VCS_ACCESS))
endif
else
	@echo "test: SIM=$(SIM) is not wired up; use verilator, questa or vcs"; exit 1
endif

# Runs one group of unit tests on VCS and fails unless SVUnit reports PASSED and the UVM
# errors are the expected ones. Prints the kinds of warnings of the compilation with their
# counts.
# $(1) group name, $(2) unit test files, $(3) vcs arguments
define run_vcs
	@command -v $(SVUNIT_BUILD) > /dev/null || { echo "test: $(SVUNIT_BUILD) (SVUnit) is not on PATH"; exit 1; }
	@command -v $(VCS) > /dev/null || { echo "test: $(VCS) (VCS) is not on PATH"; exit 1; }
	@rm -rf $(SVUNIT_OUT)/$(1) && mkdir -p $(SVUNIT_OUT)/$(1)
	@cd tests/unit && $(SVUNIT_BUILD) -o $(SVUNIT_OUT)/$(1) \
	   $(foreach test,$(2),--directory $(notdir $(patsubst %/,%,$(dir $(test))))) > $(SVUNIT_OUT)/$(1)/build.log 2>&1
	@cd $(SVUNIT_OUT)/$(1) && \
	   { $(VCS) $(VCS_FLAGS) -l compile.log $(3) -f .svunit.f -top testrunner -o simv > /dev/null 2>&1 || \
	     { grep -A4 -E '^Error-\[' compile.log || tail -n 5 compile.log; \
	       echo "test: $(1): compilation failed (log: $(SVUNIT_OUT)/$(1)/compile.log)"; exit 1; }; }
	@{ grep -o -E '^Warning-\[[A-Z_0-9]+\]' $(SVUNIT_OUT)/$(1)/compile.log || true; } | { grep -v LINX_KRNL || true; } | sort | uniq -c
	@cd $(SVUNIT_OUT)/$(1) && { ./simv -l test.log $(SIM_PLUSARGS) > /dev/null 2>&1 || true; }
	@grep -E 'FAILED|tests passing|suites passing' $(SVUNIT_OUT)/$(1)/test.log || true
	@grep -q '\[testrunner\]: PASSED' $(SVUNIT_OUT)/$(1)/test.log || \
	   { echo "test: $(1) tests FAILED (log: $(SVUNIT_OUT)/$(1)/test.log)"; exit 1; }
	$(call check_uvm_errors,$(SVUNIT_OUT)/$(1)/test.log,vcs,$(2))
endef

# Examples on a simulator ----------------------------------------------------------------
# 'make examples SIM=questa' (Gate 2) compiles and runs every example. The unit tests pass
# plain variables to the library; the examples use it the way a testbench does, which is
# how the first Questa-only compile error was found. An example passes when it compiles and
# its simulation ends by itself: several examples provoke errors or a fatal on purpose, so
# messages are not counted. An example that is still running after EXAMPLES_RUN_TIME fails
# (scripts/hexk_example_run.do), and so does one that calls run_test() and never gets to the
# report summary of UVM: both are stuck. Plusargs of an example are in <example>.plusargs
# next to it. The examples in HDL_ACCESS_EXAMPLES run with read and write access to the
# signals of their module.

# $(1) example files, $(2) vlog arguments, $(3) vsim arguments
define run_questa_examples
	@for example in $(1); do \
	   name=$$(basename $$example .sv); out=$(EXAMPLES_OUT)/$$name; plusargs=; access=; \
	   case " $(HDL_ACCESS_EXAMPLES) " in *" $$name "*) access="-voptargs=-access=rw+$$name";; esac; \
	   if [ -f $${example%.sv}.plusargs ]; then plusargs=$$(grep '^+' $${example%.sv}.plusargs | tr '\n' ' '); fi; \
	   rm -rf $$out && mkdir -p $$out; \
	   ( cd $$out && $(QUESTA_VLIB) work > /dev/null && \
	     $(QUESTA_VLOG) -sv -quiet -l compile.log -timescale 1ns/1ps $(2) \
	        $(HEXK_SV_LIB_HOME)/$$example > /dev/null 2>&1 ) || \
	      { grep -E '^\*\* (Error|Fatal)' $$out/compile.log || true; \
	        echo "examples: $$name: compilation FAILED (log: $$out/compile.log)"; exit 1; }; \
	   ( cd $$out && $(QUESTA_VSIM) -c -lib work \
	        -do "do $(HEXK_SV_LIB_HOME)/scripts/hexk_example_run.do $(EXAMPLES_RUN_TIME)" -l run.log $(3) \
	        $$access $$plusargs $$name > /dev/null 2>&1 ) || true; \
	   if grep -q -E '^# \*\* Fatal: \(vsim|Error loading design' $$out/run.log || \
	      ! grep -q '^# End time' $$out/run.log; then \
	      grep -E '^# \*\* (Error|Fatal)' $$out/run.log | head -5 || true; \
	      echo "examples: $$name: simulation FAILED (log: $$out/run.log)"; exit 1; \
	   fi; \
	   if grep -q 'HEXK_EXAMPLE_STILL_RUNNING' $$out/run.log; then \
	      echo "examples: $$name: still running after $(EXAMPLES_RUN_TIME), FAILED (log: $$out/run.log)"; exit 1; \
	   fi; \
	   if grep -q -E '^[^/]*run_test *\(' $(HEXK_SV_LIB_HOME)/$$example && \
	      ! grep -q 'UVM Report Summary' $$out/run.log; then \
	      echo "examples: $$name: the UVM test did not end, FAILED (log: $$out/run.log)"; exit 1; \
	   fi; \
	   echo "examples: $(SIM): $$name ran"; \
	done
endef

# The same on VCS. A simulation that is still running after VCS_RUN_TIMEOUT seconds is
# stopped by 'timeout', whose exit status 124 says so.
# $(1) example files, $(2) vcs arguments
define run_vcs_examples
	@for example in $(1); do \
	   name=$$(basename $$example .sv); out=$(EXAMPLES_OUT)/$$name; plusargs=; access=; \
	   case " $(HDL_ACCESS_EXAMPLES) " in *" $$name "*) access="$(VCS_ACCESS_FLAGS)";; esac; \
	   if [ -f $${example%.sv}.plusargs ]; then plusargs=$$(grep '^+' $${example%.sv}.plusargs | tr '\n' ' '); fi; \
	   rm -rf $$out && mkdir -p $$out; \
	   ( cd $$out && $(VCS) $(VCS_FLAGS) -l compile.log $(2) $$access $(HEXK_SV_LIB_HOME)/$$example \
	        -top $$name -o simv > /dev/null 2>&1 ) || \
	      { grep -A4 -E '^Error-\[' $$out/compile.log || tail -n 5 $$out/compile.log; \
	        echo "examples: $$name: compilation FAILED (log: $$out/compile.log)"; exit 1; }; \
	   status=0; \
	   ( cd $$out && timeout $(VCS_RUN_TIMEOUT) ./simv -l run.log $$plusargs > /dev/null 2>&1 ) || status=$$?; \
	   if [ $$status -eq 124 ]; then \
	      echo "examples: $$name: still running after $(VCS_RUN_TIMEOUT) s, FAILED (log: $$out/run.log)"; exit 1; \
	   fi; \
	   if ! grep -q 'V C S   S i m u l a t i o n   R e p o r t' $$out/run.log; then \
	      echo "examples: $$name: the simulation did not run, FAILED (log: $$out/run.log)"; exit 1; \
	   fi; \
	   if grep -q -E '^[^/]*run_test *\(' $(HEXK_SV_LIB_HOME)/$$example && \
	      ! grep -q 'UVM Report Summary' $$out/run.log; then \
	      echo "examples: $$name: the UVM test did not end, FAILED (log: $$out/run.log)"; exit 1; \
	   fi; \
	   echo "examples: $(SIM): $$name ran"; \
	done
endef

examples:
	@echo "== examples SIM=$(SIM)"
ifeq ($(SIM),questa)
	@command -v $(QUESTA_VSIM) > /dev/null || { echo "examples: $(QUESTA_VSIM) (Questa) is not on PATH"; exit 1; }
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "examples: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	@echo "-- core examples: $(words $(CORE_EXAMPLES)), no UVM"
	$(call run_questa_examples,$(CORE_EXAMPLES),-f $(HEXK_SV_LIB_HOME)/src/core/hexk_core.f,)
	@echo "-- UVM examples: $(words $(UVM_EXAMPLES)), UVM from $(UVM_HOME)"
	$(call run_questa_examples,$(UVM_EXAMPLES),+incdir+$(abspath $(UVM_HOME))/src \
	   $(abspath $(UVM_HOME))/src/uvm_pkg.sv -f $(HEXK_SV_LIB_HOME)/src/hexk_all.f \
	   $(abspath $(UVM_HOME))/src/dpi/uvm_dpi.cc -ccflags "$(QUESTA_CCFLAGS)",$(QUESTA_LDFLAGS))
else ifeq ($(SIM),vcs)
	@command -v $(VCS) > /dev/null || { echo "examples: $(VCS) (VCS) is not on PATH"; exit 1; }
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "examples: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	@echo "-- core examples: $(words $(CORE_EXAMPLES)), no UVM"
	$(call run_vcs_examples,$(CORE_EXAMPLES),-f $(HEXK_SV_LIB_HOME)/src/core/hexk_core.f)
	@echo "-- UVM examples: $(words $(UVM_EXAMPLES)), UVM from $(UVM_HOME)"
	$(call run_vcs_examples,$(UVM_EXAMPLES),$(VCS_UVM_ARGS))
else
	@echo "examples: SIM=$(SIM) is not wired up; the examples are elaborated by 'make elab' and 'make lint'"; exit 1
endif

# Smoke testbench on a simulator ---------------------------------------------------------
# 'make smoke SIM=questa' (Gate 2) compiles the smoke testbench of tests/smoke once and runs
# its three tests. Each must end the way it is meant to: one passes, one fails with data
# errors that the scoreboard reports, one hangs and is ended by the watchdog. A test that is
# still running after SMOKE_RUN_TIME fails, as an example does.

# Runs one smoke test and checks how it ended.
# $(1) test, $(2) and $(3) texts that its log must hold, $(4) a text that it must not hold
define run_questa_smoke
	@( cd $(SMOKE_OUT) && $(QUESTA_VSIM) -c -lib work $(QUESTA_LDFLAGS) \
	     -do "do $(HEXK_SV_LIB_HOME)/scripts/hexk_example_run.do $(SMOKE_RUN_TIME)" -l $(1).log \
	     +UVM_TESTNAME=$(1) hexk_smoke_tb > /dev/null 2>&1 ) || true
	@if grep -q -E '^# \*\* Fatal: \(vsim|Error loading design' $(SMOKE_OUT)/$(1).log || \
	    ! grep -q '^# End time' $(SMOKE_OUT)/$(1).log; then \
	   echo "smoke: $(1): the simulation did not run (log: $(SMOKE_OUT)/$(1).log)"; exit 1; fi
	@if grep -q 'HEXK_EXAMPLE_STILL_RUNNING' $(SMOKE_OUT)/$(1).log; then \
	   echo "smoke: $(1): still running after $(SMOKE_RUN_TIME) (log: $(SMOKE_OUT)/$(1).log)"; exit 1; fi
	@for text in '$(2)' '$(3)'; do \
	   grep -q "$$text" $(SMOKE_OUT)/$(1).log || \
	      { echo "smoke: $(1): '$$text' is not in the log (log: $(SMOKE_OUT)/$(1).log)"; exit 1; }; \
	done
	@if grep -q '$(4)' $(SMOKE_OUT)/$(1).log; then \
	   echo "smoke: $(1): '$(4)' is in the log (log: $(SMOKE_OUT)/$(1).log)"; exit 1; fi
	@echo "smoke: $(SIM): $(1) ended as expected"
endef

# The same on VCS.
# $(1) test, $(2) and $(3) texts that its log must hold, $(4) a text that it must not hold
define run_vcs_smoke
	@status=0; \
	   ( cd $(SMOKE_OUT) && timeout $(VCS_RUN_TIMEOUT) ./simv -l $(1).log +UVM_TESTNAME=$(1) > /dev/null 2>&1 ) || status=$$?; \
	   if [ $$status -eq 124 ]; then \
	      echo "smoke: $(1): still running after $(VCS_RUN_TIMEOUT) s (log: $(SMOKE_OUT)/$(1).log)"; exit 1; fi
	@if ! grep -q 'V C S   S i m u l a t i o n   R e p o r t' $(SMOKE_OUT)/$(1).log; then \
	   echo "smoke: $(1): the simulation did not run (log: $(SMOKE_OUT)/$(1).log)"; exit 1; fi
	@for text in '$(2)' '$(3)'; do \
	   grep -q "$$text" $(SMOKE_OUT)/$(1).log || \
	      { echo "smoke: $(1): '$$text' is not in the log (log: $(SMOKE_OUT)/$(1).log)"; exit 1; }; \
	done
	@if grep -q '$(4)' $(SMOKE_OUT)/$(1).log; then \
	   echo "smoke: $(1): '$(4)' is in the log (log: $(SMOKE_OUT)/$(1).log)"; exit 1; fi
	@echo "smoke: $(SIM): $(1) ended as expected"
endef

smoke:
	@echo "== smoke SIM=$(SIM)"
ifeq ($(SIM),questa)
	@command -v $(QUESTA_VSIM) > /dev/null || { echo "smoke: $(QUESTA_VSIM) (Questa) is not on PATH"; exit 1; }
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "smoke: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	@echo "-- smoke testbench, UVM from $(UVM_HOME)"
	@rm -rf $(SMOKE_OUT) && mkdir -p $(SMOKE_OUT)
	@( cd $(SMOKE_OUT) && $(QUESTA_VLIB) work > /dev/null && \
	   $(QUESTA_VLOG) -sv -quiet -l compile.log -timescale 1ns/1ps +incdir+$(abspath $(UVM_HOME))/src \
	      $(abspath $(UVM_HOME))/src/uvm_pkg.sv -f $(HEXK_SV_LIB_HOME)/src/hexk_all.f \
	      -f $(HEXK_SV_LIB_HOME)/$(SMOKE_FILELIST) $(abspath $(UVM_HOME))/src/dpi/uvm_dpi.cc \
	      -ccflags "$(QUESTA_CCFLAGS)" > /dev/null 2>&1 ) || \
	   { grep -E '^\*\* (Error|Fatal)' $(SMOKE_OUT)/compile.log || true; \
	     echo "smoke: compilation FAILED (log: $(SMOKE_OUT)/compile.log)"; exit 1; }
	$(call run_questa_smoke,hexk_smoke_pass_test,TEST PASSED,20 matched,TEST FAILED)
	$(call run_questa_smoke,hexk_smoke_error_test,TEST FAILED,HEXK_SB_MISMATCH,TEST PASSED)
	$(call run_questa_smoke,hexk_smoke_hang_test,HEXK_WATCHDOG,no heartbeat for,TEST PASSED)
else ifeq ($(SIM),vcs)
	@command -v $(VCS) > /dev/null || { echo "smoke: $(VCS) (VCS) is not on PATH"; exit 1; }
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "smoke: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	@echo "-- smoke testbench, UVM from $(UVM_HOME)"
	@rm -rf $(SMOKE_OUT) && mkdir -p $(SMOKE_OUT)
	@( cd $(SMOKE_OUT) && $(VCS) $(VCS_FLAGS) -l compile.log $(VCS_UVM_ARGS) \
	      -f $(HEXK_SV_LIB_HOME)/$(SMOKE_FILELIST) -top hexk_smoke_tb -o simv > /dev/null 2>&1 ) || \
	   { grep -A4 -E '^Error-\[' $(SMOKE_OUT)/compile.log || tail -n 5 $(SMOKE_OUT)/compile.log; \
	     echo "smoke: compilation FAILED (log: $(SMOKE_OUT)/compile.log)"; exit 1; }
	$(call run_vcs_smoke,hexk_smoke_pass_test,TEST PASSED,20 matched,TEST FAILED)
	$(call run_vcs_smoke,hexk_smoke_error_test,TEST FAILED,HEXK_SB_MISMATCH,TEST PASSED)
	$(call run_vcs_smoke,hexk_smoke_hang_test,HEXK_WATCHDOG,no heartbeat for,TEST PASSED)
else
	@echo "smoke: SIM=$(SIM) is not wired up; the smoke testbench is elaborated by 'make elab'"; exit 1
endif

# Benchmarks on a simulator --------------------------------------------------------------
# 'make bench SIM=questa|vcs' compiles tests/bench/hexk_bench.sv once and runs each case of
# BENCH_CASES three times: twice with a count of 0 and once with its count. The time of the
# run with the count, less the shorter of the two runs without work, divided by the count is
# the cost of one operation, printed in microseconds; start-up, which differs from run to
# run (Questa compiles a DPI wrapper at every start), is left out that way. The numbers depend
# on the machine and on its load: they compare paths and versions, they are not a gate.

# Runs every case. $(1) the command that runs the simulation, to which the plusargs are added.
define run_bench_cases
	@for entry in $(BENCH_CASES); do \
	   name=$${entry%%:*}; count=$${entry##*:}; times=; \
	   for run in 0 1 2; do \
	      if [ $$run -eq 2 ]; then n=$$count; else n=0; fi; \
	      before=$$(date +%s.%N); \
	      ( cd $(BENCH_OUT) && $(1) +hexk_bench=$$name +hexk_bench_count=$$n > $$name.$$run.log 2>&1 ) || true; \
	      after=$$(date +%s.%N); \
	      grep -q "HEXK_BENCH_DONE $$name" $(BENCH_OUT)/$$name.$$run.log || \
	         { echo "bench: $$name did not run (log: $(BENCH_OUT)/$$name.$$run.log)"; exit 1; }; \
	      times="$$times $$before $$after"; \
	   done; \
	   echo $$times | awk -v n=$$name -v c=$$count \
	      '{ idle = $$2 - $$1; if ($$4 - $$3 < idle) idle = $$4 - $$3; \
	         printf "bench: %-18s %8d operations, %9.3f us each\n", n, c, (($$6 - $$5) - idle) * 1e6 / c }'; \
	done
endef

bench:
	@echo "== bench SIM=$(SIM) UVM=$(UVM)"
	@test -f $(UVM_HOME)/src/uvm_pkg.sv || \
	   { echo "bench: no UVM sources in $(UVM_HOME); run 'make uvm_fetch' or set UVM_HOME"; exit 1; }
	@rm -rf $(BENCH_OUT) && mkdir -p $(BENCH_OUT)
ifeq ($(SIM),questa)
	@command -v $(QUESTA_VSIM) > /dev/null || { echo "bench: $(QUESTA_VSIM) (Questa) is not on PATH"; exit 1; }
	@( cd $(BENCH_OUT) && $(QUESTA_VLIB) work > /dev/null && \
	   $(QUESTA_VLOG) -sv -quiet -l compile.log -timescale 1ns/1ps +incdir+$(abspath $(UVM_HOME))/src \
	      $(abspath $(UVM_HOME))/src/uvm_pkg.sv -f $(HEXK_SV_LIB_HOME)/src/hexk_all.f \
	      $(HEXK_SV_LIB_HOME)/$(BENCH_FILE) $(abspath $(UVM_HOME))/src/dpi/uvm_dpi.cc \
	      -ccflags "$(QUESTA_CCFLAGS)" > /dev/null 2>&1 ) || \
	   { grep -E '^\*\* (Error|Fatal)' $(BENCH_OUT)/compile.log || true; \
	     echo "bench: compilation FAILED (log: $(BENCH_OUT)/compile.log)"; exit 1; }
	$(call run_bench_cases,$(QUESTA_VSIM) -c -lib work -do 'run -all; quit -f' $(QUESTA_LDFLAGS) hexk_bench)
else ifeq ($(SIM),vcs)
	@command -v $(VCS) > /dev/null || { echo "bench: $(VCS) (VCS) is not on PATH"; exit 1; }
	@( cd $(BENCH_OUT) && $(VCS) $(VCS_FLAGS) -l compile.log $(VCS_UVM_ARGS) $(HEXK_SV_LIB_HOME)/$(BENCH_FILE) \
	      -top hexk_bench -o simv > /dev/null 2>&1 ) || \
	   { grep -A4 -E '^Error-\[' $(BENCH_OUT)/compile.log || tail -n 5 $(BENCH_OUT)/compile.log; \
	     echo "bench: compilation FAILED (log: $(BENCH_OUT)/compile.log)"; exit 1; }
	$(call run_bench_cases,./simv)
else
	@echo "bench: SIM=$(SIM) is not wired up"; exit 1
endif

# Setup and housekeeping -----------------------------------------------------------------

uvm_fetch:
	@for version in 1.2 2020; do \
	   dir=$(BUILD_DIR)/uvm/$$version; \
	   if [ -f $$dir/src/uvm_pkg.sv ]; then echo "uvm_fetch: UVM $$version already in $$dir"; continue; fi; \
	   if [ $$version = 1.2 ]; then url=$(UVM_URL_1.2); else url=$(UVM_URL_2020); fi; \
	   echo "uvm_fetch: UVM $$version from $$url"; \
	   mkdir -p $$dir && curl -sSfL $$url | tar -xz -C $$dir --strip-components=1; \
	done

clean:
	@rm -rf $(BUILD_DIR)/svunit $(BUILD_DIR)/examples_questa $(BUILD_DIR)/smoke_questa \
	   $(BUILD_DIR)/examples_vcs $(BUILD_DIR)/smoke_vcs $(BUILD_DIR)/rebrand_check $(BUILD_DIR)/bench_questa \
	   $(BUILD_DIR)/bench_vcs obj_dir
