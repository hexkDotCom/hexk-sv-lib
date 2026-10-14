// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_util_macros.svh
//
// Small declaration macros for patterns that every testbench writes again:
// `hexk_singleton_decl(TYPE) gives a class the functions get() and reset_for_test();
// `hexk_analysis_imp_indexed_decl(SUFFIX) declares an analysis imp that tells the component
// which of many ports an item came from; `hexk_vif_set and `hexk_vif_get_or_fatal hand a
// virtual interface from the testbench module to a component through uvm_config_db, with the
// check that must follow every get; `hexk_constraint_no_overlap declares a constraint that
// keeps address ranges apart.
// Include this file through hexk_macros.svh.
//
//! @module    hexk_util_macros
//! @since     0.7.0
//! @stability experimental
//! @serves    CFG-4 CFG-6
//! @emits     HEXK_VIF_GET:fatal
//! @plusargs  (none)

`ifndef HEXK_UTIL_MACROS_SVH
`define HEXK_UTIL_MACROS_SVH

// Makes TYPE a singleton: declares the static functions get(), which creates the one object, and reset_for_test().
`define hexk_singleton_decl(TYPE) \
   local static TYPE hexk_singleton; \
   static function TYPE get(); \
      if (hexk_singleton == null) begin \
         hexk_singleton = new(); \
      end \
      return hexk_singleton; \
   endfunction : get \
   static function void reset_for_test(); \
      hexk_singleton = null; \
   endfunction : reset_for_test

// Declares class hexk_analysis_imp_indexed_<SUFFIX> #(T, IMP): its write(t) calls write_<SUFFIX>(index, t) of IMP.
`define hexk_analysis_imp_indexed_decl(SUFFIX) \
   class hexk_analysis_imp_indexed_``SUFFIX #(type T = int, type IMP = int) \
      extends uvm_pkg::uvm_port_base #(uvm_pkg::uvm_tlm_if_base #(T, T)); \
      local IMP imp_parent; \
      int       index; \
      function new(string imp_name, IMP imp_owner, int imp_index = 0); \
         super.new(imp_name, imp_owner, uvm_pkg::UVM_IMPLEMENTATION, 1, 1); \
         imp_parent = imp_owner; \
         index      = imp_index; \
         m_if_mask  = `UVM_TLM_ANALYSIS_MASK; \
      endfunction : new \
      virtual function string get_type_name(); \
         return `"hexk_analysis_imp_indexed_``SUFFIX`"; \
      endfunction : get_type_name \
      function void write(input T t); \
         imp_parent.write_``SUFFIX(index, t); \
      endfunction : write \
   endclass : hexk_analysis_imp_indexed_``SUFFIX

// Puts virtual interface VIF of interface type TYPE into uvm_config_db under NAME, for the components that match PATH.
`define hexk_vif_set(TYPE, PATH, NAME, VIF) \
   uvm_pkg::uvm_config_db #(virtual TYPE)::set(null, PATH, NAME, VIF);

// Gets the virtual interface NAME of interface type TYPE for this component into VIF; fatal when there is none.
`define hexk_vif_get_or_fatal(TYPE, NAME, VIF) \
   begin \
      if (!uvm_pkg::uvm_config_db #(virtual TYPE)::get(this, "", NAME, VIF) || VIF == null) begin \
         `uvm_fatal("HEXK_VIF_GET", $sformatf("no virtual interface '%s' of type %s was set for %s", \
            NAME, `"TYPE`", get_full_name())) \
      end \
   end

// Declares constraint <LO_ARRAY>_no_overlap_cstr: the ranges LO_ARRAY[i]..HI_ARRAY[i] are in order and share no value.
// The pragma comments silence a lint that takes the loop variables for signals without a driver.
`define hexk_constraint_no_overlap(LO_ARRAY, HI_ARRAY) \
   /* verilator lint_off UNDRIVEN */ \
   constraint LO_ARRAY``_no_overlap_cstr { \
      foreach (LO_ARRAY[hexk_range_a]) { \
         LO_ARRAY[hexk_range_a] <= HI_ARRAY[hexk_range_a]; \
         foreach (LO_ARRAY[hexk_range_b]) { \
            (hexk_range_b > hexk_range_a) -> ((HI_ARRAY[hexk_range_a] < LO_ARRAY[hexk_range_b]) || \
                                              (HI_ARRAY[hexk_range_b] < LO_ARRAY[hexk_range_a])); \
         } \
      } \
   } \
   /* verilator lint_on UNDRIVEN */

`endif  // HEXK_UTIL_MACROS_SVH
