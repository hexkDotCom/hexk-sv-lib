// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_agent_cfg.sv
//
// Configuration of one hexk_valid_ready_agent: the interface, the mode and the role, the
// delays of the driver and which of checks and coverage the agent has.
// The parent creates it, assigns vif and what it wants different from the defaults, and
// hands it to the agent before the build phase. delay_cfg is a hexk_delay_cfg that is
// created with this object and randomized with it: for an initiator it describes the gaps
// before valid, for a responder the clock cycles before ready.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    CFG-1 CFG-3
//! @emits     HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_AGENT_CFG_SV
`define HEXK_VALID_READY_AGENT_CFG_SV

class hexk_valid_ready_agent_cfg #(
    int DATA_WIDTH = 32
) extends uvm_object;

   // UVM_PASSIVE: the agent has a monitor, and coverage if has_coverage is set, and drives nothing.
   uvm_active_passive_enum                   is_active    = UVM_ACTIVE;

   // Which side of the channel an active agent drives.
   hexk_valid_ready_role_e                   role         = HEXK_VALID_READY_INITIATOR;

   // The interface of the agent; mandatory.
   virtual hexk_valid_ready_if #(DATA_WIDTH) vif;

   // The delays of the driver: gaps before valid for an initiator, clock cycles before ready for a responder.
   rand hexk_delay_cfg                       delay_cfg;

   // 1: an initiator drives X on data while valid is 0; 0: data keeps its last value.
   bit                                       idle_data_x  = 1;

   // 1: the protocol assertions of the interface are on.
   bit                                       has_checks   = 1;

   // 1: the agent has a hexk_handshake_coverage on its cycle_ap.
   bit                                       has_coverage = 1;

   `uvm_object_param_utils(hexk_valid_ready_agent_cfg#(DATA_WIDTH))

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   virtual function string get_type_name();
      return "hexk_valid_ready_agent_cfg";
   endfunction : get_type_name

   // Creates a cfg for an active initiator with uniform delays of 0 to 4, checks and coverage.
   function new(string name = "hexk_valid_ready_agent_cfg");
      super.new(name);
      delay_cfg = hexk_delay_cfg::type_id::create("delay_cfg");
   endfunction : new

   // The mode, the role, the switches and the delays, on one line.
   function string convert2string();
      string delays = "none";
      if (delay_cfg != null) begin
         delays = delay_cfg.convert2string();
      end
      return $sformatf(
          "%s %s idle_data_x=%0b has_checks=%0b has_coverage=%0b delays: %s",
          is_active.name(),
          role.name(),
          idle_data_x,
          has_checks,
          has_coverage,
          delays
      );
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member; the copy shares the interface and has a delay_cfg of its
   // own, a clone of that of the original with its class, or none when the original has none.
   function void do_copy(uvm_object rhs);
      hexk_valid_ready_agent_cfg #(DATA_WIDTH) other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      is_active    = other.is_active;
      role         = other.role;
      vif          = other.vif;
      idle_data_x  = other.idle_data_x;
      has_checks   = other.has_checks;
      has_coverage = other.has_coverage;
      delay_cfg    = null;
      if (other.delay_cfg != null) begin
         void'($cast(delay_cfg, other.delay_cfg.clone()));
      end
   endfunction : do_copy

endclass : hexk_valid_ready_agent_cfg

`endif  // HEXK_VALID_READY_AGENT_CFG_SV
