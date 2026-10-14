// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uvm_regex_dpi.cc
//
// Build glue for running the UVM-layer unit tests on Verilator: compiles only the regular
// expression part of the UVM DPI library. The other parts (HDL access, command line) have
// no Verilator backend and are switched off with +define+UVM_HDL_NO_DPI and
// +define+UVM_CMDLINE_NO_DPI. The include directory is <UVM>/src/dpi.

extern "C" {
#include <stdlib.h>
#include "uvm_dpi.h"
#include "uvm_common.c"
#include "uvm_regex.cc"
}
