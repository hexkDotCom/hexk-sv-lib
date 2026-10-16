// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref.f - the reference testbench: DUT, interfaces, package and top module. Needs
// $HEXK_SV_LIB_HOME. Compile it after UVM and src/hexk_all.f; the top module is hexk_ref_tb.
//
// rtl/        the DUT, plain RTL without the library
// agents/bus/ the agent of the register bus and the commit port: interface, cfg, item, driver, monitor, adapter
// env/        register model, predictor and models, checkers, cfg and environment
// sequences/  virtual sequences: one packet, a burst, and the scenario of every test
// tests/      base test and tests: configuration, the scenario they start, how they must end
// tb/         top module and the throttle of the input
// vectors/    fixed vectors computed without the library, and the script that makes them

+incdir+${HEXK_SV_LIB_HOME}/tests/reference
+incdir+${HEXK_SV_LIB_HOME}/tests/reference/agents/bus
+incdir+${HEXK_SV_LIB_HOME}/tests/reference/env
+incdir+${HEXK_SV_LIB_HOME}/tests/reference/sequences
+incdir+${HEXK_SV_LIB_HOME}/tests/reference/tests
+incdir+${HEXK_SV_LIB_HOME}/tests/reference/vectors
${HEXK_SV_LIB_HOME}/tests/reference/rtl/hexk_ref_dut.sv
${HEXK_SV_LIB_HOME}/tests/reference/tb/hexk_ref_ready_bfm.sv
${HEXK_SV_LIB_HOME}/tests/reference/agents/bus/hexk_ref_bus_if.sv
${HEXK_SV_LIB_HOME}/tests/reference/hexk_ref_pkg.sv
${HEXK_SV_LIB_HOME}/tests/reference/tb/hexk_ref_tb.sv
