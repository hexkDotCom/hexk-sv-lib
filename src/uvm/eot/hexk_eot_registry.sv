// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_eot_registry.sv
//
// End-of-test registry: one component that runs the final checks of objects which are not
// components themselves. An object implements hexk_checkable and registers with
// hexk_eot_registry::get(); in check_phase the registry calls eot_check() of every
// registered object, in the order of registration, and says which objects reported errors.
// The registry is a singleton. The first get() creates it, under uvm_test_top when the test
// exists by then, and must come before the end of build_phase, because UVM creates no
// components later: call get() in the build_phase of the base test.
// Components do not need it; they report leftovers in their own check_phase.
//
//! @module    hexk_eot_registry
//! @since     0.7.0
//! @stability experimental
//! @serves    CHK-5
//! @emits     HEXK_EOT_CHECK:info HEXK_EOT_REGISTER:error HEXK_EOT_LATE:fatal
//! @plusargs  (none)

`ifndef HEXK_EOT_REGISTRY_SV
`define HEXK_EOT_REGISTRY_SV

class hexk_eot_registry extends uvm_component;

   local static hexk_eot_registry eot_registry;

   // The registered objects and their names in reports, in the order of registration.
   local hexk_checkable           checkables   [$];
   local string                   labels       [$];

   `uvm_component_utils(hexk_eot_registry)

   // Creates a registry; use get(), which creates the one registry of the simulation.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // The one registry of the simulation; the first call creates it and must come before the end of build_phase.
   static function hexk_eot_registry get();
      if (eot_registry == null) begin
         uvm_root      root = uvm_root::get();
         uvm_domain    common = uvm_domain::get_common_domain();
         uvm_phase     build_node = common.find(uvm_build_phase::get());
         uvm_component parent = null;
         if (build_node.get_state() == UVM_PHASE_DONE) begin
            `hexk_static_fatal("HEXK_EOT_LATE", {
                               "the first hexk_eot_registry::get() comes after build_phase, when UVM creates no ",
                               "components any more; call it in the build_phase of the test"})
         end
         if (root.has_child("uvm_test_top") != 0) begin
            parent = root.get_child("uvm_test_top");
         end
         eot_registry = hexk_eot_registry::type_id::create("eot_registry", parent);
      end
      return eot_registry;
   endfunction : get

   // Registers an object under a name for reports; its eot_check() is called in check_phase.
   function void register(hexk_checkable obj, string name);
      if (obj == null) begin
         `uvm_error("HEXK_EOT_REGISTER", $sformatf("'%s' is a null handle; not registered", name))
         return;
      end
      foreach (checkables[i]) begin
         if (checkables[i] == obj) begin
            `uvm_error("HEXK_EOT_REGISTER", $sformatf("'%s' is already registered as '%s'; not registered again", name,
                                                      labels[i]))
            return;
         end
      end
      checkables.push_back(obj);
      labels.push_back(name);
   endfunction : register

   // Forgets every registered object; for unit tests, which run many tests in one simulation.
   static function void reset_for_test();
      if (eot_registry != null) begin
         eot_registry.checkables.delete();
         eot_registry.labels.delete();
      end
   endfunction : reset_for_test

   // UVM callback: calls eot_check() of every registered object and names those that reported errors.
   function void check_phase(uvm_phase phase);
      uvm_report_server server = uvm_report_server::get_server();
      string            complained                               [$];
      int               errors_before;
      super.check_phase(phase);
      if (checkables.size() == 0) begin
         return;
      end
      foreach (checkables[i]) begin
         errors_before = server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
         checkables[i].eot_check();
         if (server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL) != errors_before) begin
            complained.push_back(labels[i]);
         end
      end
      if (complained.size() == 0) begin
         `uvm_info("HEXK_EOT_CHECK", $sformatf("%0d objects checked, none reported an error", checkables.size()),
                   UVM_MEDIUM)
      end else begin
         `uvm_info("HEXK_EOT_CHECK", $sformatf(
                   "%0d objects checked, %0d reported errors: %s",
                   checkables.size(),
                   complained.size(),
                   hexk_str::join_str(
                       complained, ", "
                   )
                   ), UVM_MEDIUM)
      end
   endfunction : check_phase

endclass : hexk_eot_registry

`endif  // HEXK_EOT_REGISTRY_SV
