// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_eot_registry_example.sv
//
// Minimal use of hexk_eot_registry: a reference model that is a plain object, not a
// component, checks at the end of the test that every request it predicted was consumed.
// The test creates the registry in build_phase by calling get(); the model registers
// itself. Here one prediction is left over, so check_phase ends with one error from the
// model. Needs UVM and src/uvm/hexk_uvm.f.

module hexk_eot_registry_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_checkable;
   import hexk_uvm_pkg::hexk_eot_registry;
   `include "uvm_macros.svh"

   // Reference model without a place in the component tree.
   class hexk_example_model implements hexk_checkable;
      local int unsigned predicted;
      local int unsigned consumed;

      function new();
         hexk_eot_registry registry = hexk_eot_registry::get();
         registry.register(this, "example_model");
      endfunction : new

      function void predict();
         predicted++;
      endfunction : predict

      function void consume();
         consumed++;
      endfunction : consume

      virtual function void eot_check();
         if (predicted != consumed) begin
            `uvm_error("MODEL_LEFTOVER", $sformatf("%0d predictions were never consumed", predicted - consumed))
         end
      endfunction : eot_check
   endclass : hexk_example_model

   class hexk_example_test extends uvm_test;
      hexk_example_model model;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         // The registry must exist before build_phase ends.
         void'(hexk_eot_registry::get());
         model = new();
      endfunction : build_phase

      task run_phase(uvm_phase phase);
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         model.predict();
         model.predict();
         #10ns;
         model.consume();
         phase.drop_objection(this, "stimulus");
      endtask : run_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_eot_registry_example
