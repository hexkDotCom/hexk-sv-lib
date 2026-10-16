// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_monitor.sv
//
// Watches the register bus and the commit port. Every access goes to ap when it is complete: a write
// at the edge at which the DUT takes it (the first edge that sees the request), a read at its ack,
// when the read data comes. Each item carries the time of the edge at which the DUT took it
// (taken_ps), so that the predictor can tell which words a register write counts for. Every
// committed code word goes to commit_ap. The register model is predicted from ap (explicit
// prediction), and the functional predictor learns the configuration from it: what the DUT really
// got, not what a test meant to write.

`ifndef HEXK_REF_BUS_MONITOR_SV
`define HEXK_REF_BUS_MONITOR_SV

class hexk_ref_bus_monitor extends uvm_monitor;

   // The bus; assigned by the agent.
   virtual hexk_ref_bus_if                   vif;

   // Completed accesses.
   uvm_analysis_port #(hexk_ref_bus_item)    ap;

   // Committed code words.
   uvm_analysis_port #(hexk_ref_commit_item) commit_ap;

   `uvm_component_utils(hexk_ref_bus_monitor)

   // Creates the monitor and its ports.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      ap        = new("ap", this);
      commit_ap = new("commit_ap", this);
   endfunction : new

   // UVM callback: one look at every rising edge. The DUT takes an access at the first edge that sees the
   // request and acks it at the next one.
   task run_phase(uvm_phase phase);
      longint unsigned taken_ps;
      super.run_phase(phase);
      forever begin
         @(vif.mon_cb);
         if (vif.rst_n !== 1'b1) begin
            continue;
         end
         if (vif.mon_cb.req === 1'b1 && vif.mon_cb.ack !== 1'b1) begin
            taken_ps = hexk_wait_util::now_ps();
            if (vif.mon_cb.we === 1'b1) begin
               publish_access(taken_ps);
            end
         end else if (vif.mon_cb.req === 1'b1 && vif.mon_cb.we !== 1'b1) begin
            publish_access(taken_ps);
         end
         if (vif.mon_cb.commit === 1'b1) begin
            publish_commit();
         end
      end
   endtask : run_phase

   // Writes the access on the bus now, taken by the DUT at taken_ps; a read has its data now.
   local function void publish_access(longint unsigned taken_ps);
      hexk_ref_bus_item item = hexk_ref_bus_item::type_id::create("item", this);
      item.we       = vif.mon_cb.we;
      item.addr     = vif.mon_cb.addr;
      item.wdata    = vif.mon_cb.wdata;
      item.wstrb    = vif.mon_cb.wstrb;
      item.rdata    = vif.mon_cb.rdata;
      item.taken_ps = taken_ps;
      `uvm_info("REF_BUS", item.convert2string(), UVM_HIGH)
      ap.write(item);
   endfunction : publish_access

   // Writes the code word that the DUT commits at this edge.
   local function void publish_commit();
      hexk_ref_commit_item commit = hexk_ref_commit_item::type_id::create("commit", this);
      commit.addr = vif.mon_cb.commit_addr;
      commit.code = vif.mon_cb.commit_code;
      commit_ap.write(commit);
   endfunction : publish_commit

endclass : hexk_ref_bus_monitor

`endif  // HEXK_REF_BUS_MONITOR_SV
