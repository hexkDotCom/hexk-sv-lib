// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_all.f - the whole library: core, UVM layer and the agents.
// Needs $HEXK_SV_LIB_HOME. Add one line to your flow:
//    -f $HEXK_SV_LIB_HOME/src/hexk_all.f

-f ${HEXK_SV_LIB_HOME}/src/uvm/hexk_uvm.f
-f ${HEXK_SV_LIB_HOME}/src/agents/hexk_clk_rst/hexk_clk_rst.f
-f ${HEXK_SV_LIB_HOME}/src/agents/hexk_valid_ready/hexk_valid_ready.f
-f ${HEXK_SV_LIB_HOME}/src/agents/hexk_pins/hexk_pins.f
