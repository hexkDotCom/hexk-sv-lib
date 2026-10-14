// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uvm.f - hexk_uvm_pkg and the core it depends on. Needs $HEXK_SV_LIB_HOME.
// UVM itself (1.2 or IEEE 1800.2) comes from your flow and is compiled before this list.

-f ${HEXK_SV_LIB_HOME}/src/core/hexk_core.f
+incdir+${HEXK_SV_LIB_HOME}/src/uvm
${HEXK_SV_LIB_HOME}/src/uvm/hexk_uvm_pkg.sv
