// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_driver.sv
//
// Drives the register bus: puts the request on the bus at a rising edge and holds it until it
// samples ack, at most max_wait_cycles edges. Without an ack it ends the request, sets the status
// of the item to HEXK_REF_BUS_NO_ACK and reports REF_BUS_NO_ACK, so that a register access never
// waits for ever (the time limit of hexk_csr_util counts between reads, not inside one). Read data
// with X or Z bits keeps the status, but is_ok() is 0 and the register model gets UVM_HAS_X; the
// monitor reports it (REF_BUS_UNKNOWN). The driver hands an item back one edge after its
// ack: by then the monitor has published the access, so a test that looks at the predictor after
// an access sees that access.
// Reset: no access starts while the reset is asserted. A reset during an access ends it at the
// next rising edge at which the driver sees the reset (none comes while the clock is stopped), with
// the bus idle and the status HEXK_REF_BUS_RESET; whether the DUT took it is not known, so the
// register model gets UVM_NOT_OK. Tests let register accesses finish before they reset the DUT.
// The driver is a hexk_objectable: busy from the moment it takes an item until it hands it back,
// so that a wait until nothing is in flight sees an access that did not go through hexk_csr_util.

`ifndef HEXK_REF_BUS_DRIVER_SV
`define HEXK_REF_BUS_DRIVER_SV

class hexk_ref_bus_driver extends uvm_driver #(hexk_ref_bus_item) implements hexk_objectable;

   // The bus; assigned by the agent.
   virtual hexk_ref_bus_if vif;

   // Longest wait for ack, in rising edges; the agent sets it from its cfg.
   int unsigned max_wait_cycles = 50;

   // The item that the driver holds; null between items.
   local hexk_ref_bus_item current;

   `uvm_component_utils(hexk_ref_bus_driver)

   // Creates the driver.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: idles the bus, then carries out the items one after the other.
   task run_phase(uvm_phase phase);
      super.run_phase(phase);
      vif.idle();
      forever begin
         seq_item_port.get_next_item(req);
         current = req;
         drive(req);
         current = null;
         seq_item_port.item_done();
      end
   endtask : run_phase

   // 1 while the driver holds an item.
   virtual function bit is_busy();
      return current != null;
   endfunction : is_busy

   // The access that the driver holds.
   virtual function string busy_reason();
      return (current == null) ? "" : {"access ", current.convert2string()};
   endfunction : busy_reason

   // One access: request, wait for ack, end the request.
   local task drive(hexk_ref_bus_item item);
      int unsigned waited = 0;
      @(vif.cb iff vif.rst_n === 1'b1);
      vif.cb.req   <= 1'b1;
      vif.cb.we    <= item.we;
      vif.cb.addr  <= item.addr;
      vif.cb.wdata <= item.wdata;
      vif.cb.wstrb <= item.wstrb;
      do begin
         @(vif.cb);
         waited++;
      end while (vif.cb.ack !== 1'b1 && waited < max_wait_cycles && vif.rst_n === 1'b1);
      item.rdata = vif.cb.rdata;
      vif.cb.req <= 1'b0;
      if (vif.rst_n !== 1'b1) begin
         item.status = HEXK_REF_BUS_RESET;
         `uvm_info("REF_BUS_RESET", $sformatf("a reset ended the access: %s", item.convert2string()), UVM_LOW)
         return;
      end
      item.status = (vif.cb.ack === 1'b1) ? HEXK_REF_BUS_OK : HEXK_REF_BUS_NO_ACK;
      if (item.status == HEXK_REF_BUS_NO_ACK) begin
         `uvm_error("REF_BUS_NO_ACK", $sformatf("no ack after %0d cycles: %s", waited, item.convert2string()))
      end
      // The monitor publishes a read at its ack edge: one more edge, and it has.
      @(vif.cb);
   endtask : drive

endclass : hexk_ref_bus_driver

`endif  // HEXK_REF_BUS_DRIVER_SV
