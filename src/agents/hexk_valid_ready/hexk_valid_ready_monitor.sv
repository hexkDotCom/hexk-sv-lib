// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_monitor.sv
//
// Monitor of the valid/ready agent: writes one item per transfer to the analysis port ap,
// with the word and the number of clock cycles for which valid waited for ready, and one
// hexk_handshake_cycle_t per rising edge of the clock to cycle_ap, for coverage and other
// observers of the handshake.
// It samples the channel at every rising edge of the clock, as the DUT does, and knows
// whether a transfer is waiting, which the agent reports as "busy". It writes no item during
// a reset. It is created by hexk_valid_ready_agent in every mode.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-5 CMP-12
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_MONITOR_SV
`define HEXK_VALID_READY_MONITOR_SV

class hexk_valid_ready_monitor #(
    int DATA_WIDTH = 32
) extends uvm_monitor;

   // The cfg of the agent; assigned by the agent before the connect phase.
   hexk_valid_ready_agent_cfg #(DATA_WIDTH)                 cfg;

   // One item per transfer.
   uvm_analysis_port #(hexk_valid_ready_item #(DATA_WIDTH)) ap;

   // One record per rising edge of the clock, also during a reset.
   uvm_analysis_port #(hexk_handshake_cycle_t)              cycle_ap;

   local virtual hexk_valid_ready_if #(DATA_WIDTH)          vif;

   // Rising edges for which the valid that is on the channel has waited for ready; 0 when none waits.
   local int unsigned                                       waiting;

   // The number of resets that the interface had counted at the latest rising edge.
   local int unsigned                                       seen_resets;

   `uvm_component_param_utils(hexk_valid_ready_monitor#(DATA_WIDTH))

   // Creates the monitor and its ports.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      ap       = new("ap", this);
      cycle_ap = new("cycle_ap", this);
   endfunction : new

   // UVM callback: takes the interface from the cfg; the agent has checked both.
   function void connect_phase(uvm_phase phase);
      super.connect_phase(phase);
      vif = cfg.vif;
   endfunction : connect_phase

   // UVM callback: looks at the channel at every rising edge of the clock.
   // A reset that came and went between two rising edges is not seen there: the interface counts the
   // assertions of the reset, and a count that changed stands for such a reset.
   task run_phase(uvm_phase phase);
      bit                                     reset_active;
      bit                                     reset_since;
      bit                                     was_in_reset = 0;
      bit                                     valid;
      bit                                     ready;
      logic                  [DATA_WIDTH-1:0] data;
      hexk_handshake_cycle_t                  cycle;
      seen_resets = vif.get_reset_count();
      forever begin
         vif.sample(reset_active, valid, ready, data);
         reset_since = (vif.get_reset_count() != seen_resets);
         seen_resets = vif.get_reset_count();
         cycle.reset_began = (reset_active && !was_in_reset) || reset_since;
         cycle.in_reset = reset_active;
         cycle.valid = valid;
         cycle.ready = ready;
         cycle_ap.write(cycle);
         if (reset_active || reset_since) begin
            waiting = 0;
         end
         was_in_reset = reset_active;
         if (reset_active) begin
            continue;
         end
         if (valid && ready) begin
            publish(data);
            waiting = 0;
         end else if (valid) begin
            waiting++;
         end else begin
            waiting = 0;
         end
      end
   endtask : run_phase

   // Number of clock cycles for which a valid has waited for ready so far; 0 when none waits, during a reset
   // and after a reset until the next rising edge.
   function int unsigned num_waiting_cycles();
      return (vif == null || vif.in_reset() || vif.get_reset_count() != seen_resets) ? 0 : waiting;
   endfunction : num_waiting_cycles

   // Writes the item of a transfer to the port.
   local function void publish(logic [DATA_WIDTH-1:0] data);
      hexk_valid_ready_item #(DATA_WIDTH) item = hexk_valid_ready_item#(DATA_WIDTH)::type_id::create("item");
      item.data        = data;
      item.wait_cycles = waiting;
      ap.write(item);
   endfunction : publish

endclass : hexk_valid_ready_monitor

`endif  // HEXK_VALID_READY_MONITOR_SV
