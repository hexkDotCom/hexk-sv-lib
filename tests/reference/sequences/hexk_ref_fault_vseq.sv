// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_fault_vseq.sv
//
// A fault of the DUT, then one packet of four words at word 0. HEXK_REF_FAULT_HANG sets
// DEBUG.HANG: the DUT takes the packet and never sets DONE. HEXK_REF_FAULT_STALL drives the strap
// pin STALL_PIN (through hexk_pins_if; Questa and VCS): the input's ready stays 0 and the DUT never
// takes a word, so the sequence waits for ever. The negative tests start it and say how the run
// must end.

`ifndef HEXK_REF_FAULT_VSEQ_SV
`define HEXK_REF_FAULT_VSEQ_SV

// The faults of hexk_ref_fault_vseq.
typedef enum bit {
   HEXK_REF_FAULT_HANG,
   HEXK_REF_FAULT_STALL
} hexk_ref_fault_e;

class hexk_ref_fault_vseq extends hexk_ref_scenario_vseq;

   // The fault.
   hexk_ref_fault_e fault = HEXK_REF_FAULT_HANG;

   `uvm_object_utils(hexk_ref_fault_vseq)

   // Creates the sequence.
   function new(string name = "hexk_ref_fault_vseq");
      super.new(name);
   endfunction : new

   // The fault, then the packet.
   task body();
      case (fault)
         // The whole register: CORRUPT_READ and HANG share a byte and are not individually accessible, so a
         // write of one of them would be a write of the whole register anyway, with a warning of UVM.
         HEXK_REF_FAULT_HANG: env.csr.write(env.regs.debug, 1 << env.regs.debug_hang.get_lsb_pos(), this);
         default:             env.cfg.strap_vif.drive_pin(hexk_ref_env_cfg::STALL_PIN, 1'b1);
      endcase
      send_packet(4, 0, 6'd0);
   endtask : body

endclass : hexk_ref_fault_vseq

`endif  // HEXK_REF_FAULT_VSEQ_SV
