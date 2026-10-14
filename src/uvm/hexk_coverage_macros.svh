// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_coverage_macros.svh
//
// Macro that creates a covergroup of a class only when functional coverage is wanted.
// Write `hexk_cg_new(my_cg) in the constructor of the class that declares the covergroup
// my_cg, without a semicolon, where "my_cg = new();" would stand. The covergroup is created
// unless the knob coverage of hexk_knobs exists and is 0, and gets the instance name
// "<full name of the object>.my_cg". When it is not created the variable stays null, so the
// class samples with "if (my_cg != null) my_cg.sample();".
// The covergroup has no constructor arguments, and its declaration sets
// option.per_instance = 1 itself, and option.get_inst_coverage = 1 when the coverage of the
// instance is read: the language allows these two options in the declaration only.
// The class has get_full_name(), as every uvm_object and uvm_component has.
// Include this file through hexk_macros.svh.
//
//! @module    hexk_coverage
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_COVERAGE_MACROS_SVH
`define HEXK_COVERAGE_MACROS_SVH

// Creates the covergroup CG of the calling class unless the knob coverage is 0, and names the instance.
`define hexk_cg_new(CG) \
   begin \
      var automatic hexk_uvm_pkg::hexk_knobs hexk_cg_knobs = hexk_uvm_pkg::hexk_knobs::get(); \
      if (!hexk_cg_knobs.has("coverage") || hexk_cg_knobs.get_bit("coverage")) begin \
         CG = new(); \
         CG.option.name = {get_full_name(), ".", `"CG`"}; \
      end \
   end

`endif  // HEXK_COVERAGE_MACROS_SVH
