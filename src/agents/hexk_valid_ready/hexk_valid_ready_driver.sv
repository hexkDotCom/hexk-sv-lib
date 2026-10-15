// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_driver.sv
//
// Driver of the valid/ready agent, for both roles: an initiator offers the words of its
// items, a responder accepts transfers, each after the delay of the item or of the cfg.
// It is thin: the signals are driven by tasks of the interface. A reset ends the transfer
// that is going on; the driver goes on when the reset is released. It is created by
// hexk_valid_ready_agent in active mode; a testbench does not use it directly.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-5 CMP-13 CMP-14 IFC-8
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_DRIVER_SV
`define HEXK_VALID_READY_DRIVER_SV

class hexk_valid_ready_driver #(
    int DATA_WIDTH = 32
) extends uvm_driver #(hexk_valid_ready_item #(DATA_WIDTH));

   // The cfg of the agent; assigned by the agent before the connect phase.
   hexk_valid_ready_agent_cfg #(DATA_WIDTH)        cfg;

   local virtual hexk_valid_ready_if #(DATA_WIDTH) vif;

   // Draws the delays of the transfers whose item gives none.
   local hexk_delay                                delay;

   // Items taken from the sequencer and items finished: the driver holds an item while they differ.
   local int unsigned                              items_taken;
   local int unsigned                              items_done;

   `uvm_component_param_utils(hexk_valid_ready_driver#(DATA_WIDTH))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   virtual function string get_type_name();
      return "hexk_valid_ready_driver";
   endfunction : get_type_name

   // Creates the driver.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // UVM callback: takes the interface from the cfg, which the agent has checked, and creates the delay generator.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vif   = cfg.vif;
      delay = new(cfg.delay_cfg, get_full_name());
   endfunction : connect_phase

   // UVM callback: drives the side of the channel that the role of the cfg names, until the phase ends.
   task run_phase(uvm_phase phase);
      if (cfg.role == HEXK_VALID_READY_INITIATOR) begin
         run_initiator();
      end else begin
         run_responder();
      end
   endtask : run_phase

   // 1 while the driver holds an item of a sequence: from get_next_item() to item_done(), also during its delay.
   function bit holds_item();
      return items_taken != items_done;
   endfunction : holds_item

   // The delay of a transfer: that of its item, or one from the cfg when the item gives none or there is no item.
   local function int unsigned delay_of(hexk_valid_ready_item#(DATA_WIDTH) item);
      if (item != null && item.delay_cycles >= 0) begin
         return $unsigned(item.delay_cycles);
      end
      return delay.next();
   endfunction : delay_of

   // Offers the words of the items. valid is taken back only when no item follows in the same time step.
   local task run_initiator();
      bit aborted;
      vif.idle_initiator(cfg.idle_data_x);
      forever begin
         seq_item_port.try_next_item(req);
         if (req == null) begin
            vif.idle_initiator(cfg.idle_data_x);
            seq_item_port.get_next_item(req);
         end
         items_taken++;
         vif.wait_reset_released();
         send_or_abort(req, aborted);
         req.aborted = aborted;
         if (aborted) begin
            vif.idle_initiator(cfg.idle_data_x);
         end
         seq_item_port.item_done();
         items_done++;
      end
   endtask : run_initiator

   // Sends the word of an item; a reset ends the wait, and aborted is 1 then.
   local task send_or_abort(hexk_valid_ready_item#(DATA_WIDTH) item, output bit aborted);
      int unsigned waited;
      bit          sent = 0;
      // The outer fork keeps "disable fork" away from other threads of the driver.
      fork
         begin
            fork
               begin
                  vif.send(item.data, delay_of(item), cfg.idle_data_x, waited);
                  sent = 1;
               end
               vif.wait_reset_asserted();
            join_any
            disable fork;
         end
      join
      item.wait_cycles = waited;
      aborted          = !sent;
   endtask : send_or_abort

   // Accepts transfers for ever: with an item when a sequence has one, otherwise with the delay of the cfg.
   local task run_responder();
      bit aborted;
      vif.idle_responder();
      forever begin
         vif.wait_reset_released();
         seq_item_port.try_next_item(req);
         if (req != null) begin
            items_taken++;
         end
         receive_or_abort(req, aborted);
         if (aborted) begin
            vif.idle_responder();
         end
         if (req != null) begin
            req.aborted = aborted;
            seq_item_port.item_done();
            items_done++;
         end
      end
   endtask : run_responder

   // Accepts one transfer and stores the word in the item, if there is one; a reset ends the wait.
   local task receive_or_abort(hexk_valid_ready_item#(DATA_WIDTH) item, output bit aborted);
      logic        [DATA_WIDTH-1:0] word;
      int unsigned                  waited;
      bit                           received = 0;
      fork
         begin
            fork
               begin
                  vif.receive(delay_of(item), word, waited);
                  received = 1;
               end
               vif.wait_reset_asserted();
            join_any
            disable fork;
         end
      join
      aborted = !received;
      if (item != null && received) begin
         item.data        = word;
         item.wait_cycles = waited;
      end
   endtask : receive_or_abort

endclass : hexk_valid_ready_driver

`endif  // HEXK_VALID_READY_DRIVER_SV
