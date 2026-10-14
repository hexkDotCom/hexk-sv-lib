// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst.f - the clock and reset agent: hexk_clk_rst_if and hexk_clk_rst_pkg.
// Needs $HEXK_SV_LIB_HOME. Compile it after src/uvm/hexk_uvm.f, which it does not include,
// so that a flow with several agents compiles the packages below them once; src/hexk_all.f
// has everything in the right order.

+incdir+${HEXK_SV_LIB_HOME}/src/agents/hexk_clk_rst
${HEXK_SV_LIB_HOME}/src/agents/hexk_clk_rst/hexk_clk_rst_if.sv
${HEXK_SV_LIB_HOME}/src/agents/hexk_clk_rst/hexk_clk_rst_pkg.sv
