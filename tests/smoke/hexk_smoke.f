// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_smoke.f - the smoke testbench: DUT, package and top module. Needs $HEXK_SV_LIB_HOME.
// Compile it after UVM and src/hexk_all.f; the top module is hexk_smoke_tb.

+incdir+${HEXK_SV_LIB_HOME}/tests/smoke
${HEXK_SV_LIB_HOME}/tests/smoke/hexk_smoke_dut.sv
${HEXK_SV_LIB_HOME}/tests/smoke/hexk_smoke_pkg.sv
${HEXK_SV_LIB_HOME}/tests/smoke/hexk_smoke_tb.sv
