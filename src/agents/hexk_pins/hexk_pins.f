// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_pins.f - the pins interface hexk_pins_if. Needs $HEXK_SV_LIB_HOME.
// Compile it after src/uvm/hexk_uvm.f, which it does not include: the interface reports its
// errors through UVM with the macros of hexk_macros.svh. src/hexk_all.f has everything in
// the right order.

${HEXK_SV_LIB_HOME}/src/agents/hexk_pins/hexk_pins_if.sv
