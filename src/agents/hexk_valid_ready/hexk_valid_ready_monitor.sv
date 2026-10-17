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
// a reset. An item whose word has an X or Z bit has the status UVM_HAS_X. With the assertions of
// the interface off (has_checks 0), the monitor itself reports a valid or ready without a level,
// or data with an X or Z bit while valid is 1, as HEXK_VALID_READY_UNKNOWN in every clock cycle
// out of reset (guide TRN-6). It is created by hexk_valid_ready_agent in every mode.
// Its run_phase never returns: an extension replaces run_phase and does not call super.run_phase() (CMP-4).
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    CMP-5 CMP-12
//! @emits     HEXK_VALID_READY_UNKNOWN:error
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

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_valid_ready_monitor";
   endfunction : get_type_name

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
      super.run_phase(phase);
      seen_resets = vif.get_reset_count();
      forever begin
         vif.sample(reset_active, valid, ready, data);
         reset_since = (vif.get_reset_count() != seen_resets);
         seen_resets = vif.get_reset_count();
         cycle.reset_began = (reset_active && !was_in_reset) || reset_since;
         cycle.in_reset = reset_active;
         cycle.valid = valid;
         cycle.ready = ready;
         // CMP-5 waived: cycle_ap publishes a record of every edge, also during the reset; the record says so
         // (in_reset, reset_began), and the coverage of the handshake needs the edges at which a reset begins.
         cycle_ap.write(cycle);
         if (reset_active || reset_since) begin
            waiting = 0;
         end
         was_in_reset = reset_active;
         if (reset_active) begin
            continue;
         end
         // The interface assertion known_a reports the same while it is on; one of the two reports, never both.
         if (!vif.get_checks() && vif.has_unknown()) begin
            `uvm_error("HEXK_VALID_READY_UNKNOWN",
                       "valid or ready has no level, or data has an X or Z bit while valid is 1")
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
      // Under the name of the monitor, so that a factory override of one agent's items can name its path.
      hexk_valid_ready_item #(DATA_WIDTH) item = hexk_valid_ready_item#(DATA_WIDTH)::type_id::create("item", this);
      item.data        = data;
      item.wait_cycles = waiting;
      item.status      = $isunknown(data) ? UVM_HAS_X : UVM_IS_OK;
      ap.write(item);
   endfunction : publish

endclass : hexk_valid_ready_monitor

`endif  // HEXK_VALID_READY_MONITOR_SV
