// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_handshake_coverage.sv
//
// Functional coverage of a valid/ready handshake: what the two signals say in a clock cycle
// (idle, wait, stall, active) and every pair of consecutive cycles, among them the
// back-to-back transfer. It fits any interface with a valid and a ready, not only
// hexk_valid_ready.
// It is a subscriber of hexk_handshake_cycle_t, one record per rising edge of the clock:
// connect it to a monitor port that writes them, such as cycle_ap of hexk_valid_ready_agent.
// A monitor of another interface may instead call sample(valid, ready) once per clock cycle
// in which the interface is out of reset, and on_reset() when a reset begins. The two
// covergroups, one of the states and one of the pairs, are created with `hexk_cg_new, so the
// knob coverage of hexk_knobs switches them off; sample() then only counts. Each is half of
// get_coverage(). The pair covergroup is sampled only when there was a cycle before, rather
// than through an iff, which Questa 2024.1 counts wrong from the second instance on. The two
// pairs in which valid is taken back during a stall are not part of the coverage: that is a
// protocol error, which assertions check.
//
//! @module    hexk_coverage
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_HANDSHAKE_COVERAGE_SV
`define HEXK_HANDSHAKE_COVERAGE_SV

// What valid and ready say in one clock cycle.
typedef enum {
   // Neither valid nor ready.
   HEXK_HANDSHAKE_IDLE,
   // Ready without valid: the receiver waits for data.
   HEXK_HANDSHAKE_WAIT,
   // Valid without ready: the sender is held.
   HEXK_HANDSHAKE_STALL,
   // Valid and ready: a transfer.
   HEXK_HANDSHAKE_ACTIVE
} hexk_handshake_state_e;

// One rising edge of the clock of a handshake, as a monitor saw it: whether a reset began since the
// edge before (also one that came and went between the two edges), whether the reset is asserted
// now, and valid and ready, which mean nothing while the reset is asserted.
typedef struct packed {
   bit reset_began;
   bit in_reset;
   bit valid;
   bit ready;
} hexk_handshake_cycle_t;

class hexk_handshake_coverage extends uvm_subscriber #(hexk_handshake_cycle_t);

   // The state of the cycle before, and whether there was one since the creation or the last reset.
   local hexk_handshake_state_e previous;
   local bit                    has_previous;

   local int unsigned           samples;

   `uvm_component_utils(hexk_handshake_coverage)

   // The tool that does not build covergroups reports each part of one, and what it makes of the rest.
   // verilator lint_off COVERIGN
   // verilator lint_off DECLFILENAME
   // verilator lint_off UNDRIVEN
   // What valid and ready say in a cycle.
   covergroup state_cg with function sample (hexk_handshake_state_e state);
      option.per_instance = 1;
      // Without this option get_inst_coverage() returns the coverage of all instances together.
      option.get_inst_coverage = 1;
      state_cp: coverpoint state;
   endgroup : state_cg

   // Every pair of consecutive cycles; the two coverpoints count only as the sides of the cross.
   covergroup pair_cg with function sample (hexk_handshake_state_e state, hexk_handshake_state_e state_before);
      option.per_instance = 1;
      option.get_inst_coverage = 1;
      state_cp: coverpoint state {option.weight = 0; type_option.weight = 0;}
      before_cp: coverpoint state_before {option.weight = 0; type_option.weight = 0;}
      transition_cross: cross before_cp, state_cp{
         bins back_to_back = binsof (before_cp) intersect {HEXK_HANDSHAKE_ACTIVE} && binsof (state_cp) intersect {
            HEXK_HANDSHAKE_ACTIVE
         };
         ignore_bins valid_taken_back = binsof (before_cp) intersect {HEXK_HANDSHAKE_STALL} &&
                                        binsof (state_cp) intersect {
            HEXK_HANDSHAKE_IDLE, HEXK_HANDSHAKE_WAIT
         };
      }
   endgroup : pair_cg
   // verilator lint_on UNDRIVEN
   // verilator lint_on DECLFILENAME
   // verilator lint_on COVERIGN

   // Creates the component, and its covergroups unless the knob coverage is 0.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      `hexk_cg_new(state_cg)
      `hexk_cg_new(pair_cg)
   endfunction : new

   // The state that the two signals stand for.
   static function hexk_handshake_state_e state_of(bit valid, bit ready);
      case ({
         valid, ready
      })
         2'b00:   return HEXK_HANDSHAKE_IDLE;
         2'b01:   return HEXK_HANDSHAKE_WAIT;
         2'b10:   return HEXK_HANDSHAKE_STALL;
         default: return HEXK_HANDSHAKE_ACTIVE;
      endcase
   endfunction : state_of

   // Analysis write: one rising edge; a reset that began forgets the cycle before, a cycle out of reset is sampled.
   function void write(hexk_handshake_cycle_t t);
      if (t.reset_began) begin
         on_reset();
      end
      if (!t.in_reset) begin
         sample (t.valid, t.ready);
      end
   endfunction : write

   // Samples one clock cycle; call it once per cycle in which the interface is out of reset.
   function void sample (bit valid, bit ready);
      hexk_handshake_state_e state = state_of(valid, ready);
      samples++;
      if (state_cg != null) begin
         state_cg.sample(state);
         if (has_previous) begin
            pair_cg.sample(state, previous);
         end
      end
      previous     = state;
      has_previous = 1;
   endfunction : sample

   // Forgets the cycle before, so that no pair is counted across a reset.
   function void on_reset();
      has_previous = 0;
   endfunction : on_reset

   // 1 when the covergroups exist, which they do unless the knob coverage was 0 at creation.
   function bit is_enabled();
      return state_cg != null;
   endfunction : is_enabled

   // Coverage of this instance in percent, the states and the pairs half each; 0 when the covergroups do not exist.
   function real get_coverage();
      // An if and not ?:, on which VCS X-2025.06 ends with an internal error.
      if (state_cg == null) begin
         return 0.0;
      end
      return (state_cg.get_inst_coverage() + pair_cg.get_inst_coverage()) / 2.0;
   endfunction : get_coverage

   // Number of calls of sample(), also through write().
   function int unsigned num_samples();
      return samples;
   endfunction : num_samples

endclass : hexk_handshake_coverage

`endif  // HEXK_HANDSHAKE_COVERAGE_SV
