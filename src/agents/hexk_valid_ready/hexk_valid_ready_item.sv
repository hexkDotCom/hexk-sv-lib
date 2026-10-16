// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_valid_ready_item.sv
//
// Item of the valid/ready agent: one transfer of one word.
// For an initiator it is the word to send, for a responder the transfer to accept, which
// comes back with the word that was received; the monitor writes one per transfer it saw.
// delay_cycles lets a sequence set the timing of one transfer; below 0, the default, the
// driver takes the delay from the cfg of the agent.
//
//! @module    hexk_valid_ready
//! @since     0.7.0
//! @stability experimental
//! @serves    TRN-2 TRN-5 CMP-14
//! @emits     HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_VALID_READY_ITEM_SV
`define HEXK_VALID_READY_ITEM_SV

class hexk_valid_ready_item #(
    int DATA_WIDTH = 32
) extends uvm_sequence_item;

   // The word of the transfer: what an initiator sends, and what a responder or the monitor saw.
   rand logic   [DATA_WIDTH-1:0] data;

   // Clock cycles before the driver offers the transfer; below 0 the driver takes the delay of the cfg.
   rand int                      delay_cycles;

   // Set by the monitor and by a driver: clock cycles for which valid waited for ready.
   int unsigned                  wait_cycles;

   // Set by a driver: 1 when a reset ended the item before its transfer.
   bit                           aborted;

   `uvm_object_param_utils(hexk_valid_ready_item#(DATA_WIDTH))

   // A plain randomize() leaves the delay to the cfg of the agent.
   constraint default_values_cstr {soft delay_cycles == -1;}

   // Name of the class in messages and printouts; without it UVM has none for a class with parameters.
   function string get_type_name();
      return "hexk_valid_ready_item";
   endfunction : get_type_name

   // Creates an item; the delay is that of the cfg until it is randomized or assigned.
   function new(string name = "hexk_valid_ready_item");
      super.new(name);
      delay_cycles = -1;
   endfunction : new

   // The word and the timing of the transfer, on one line.
   function string convert2string();
      string text = $sformatf("data=0x%0h delay_cycles=%0d wait_cycles=%0d", data, delay_cycles, wait_cycles);
      // A conditional operator on string literals of different lengths would pad the shorter one.
      if (aborted) begin
         text = {text, " aborted"};
      end
      return text;
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member.
   function void do_copy(uvm_object rhs);
      hexk_valid_ready_item #(DATA_WIDTH) other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      data         = other.data;
      delay_cycles = other.delay_cycles;
      wait_cycles  = other.wait_cycles;
      aborted      = other.aborted;
   endfunction : do_copy

   // UVM hook of compare(): the words are equal, X and Z bits included; the timing is not compared.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_valid_ready_item #(DATA_WIDTH) other;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      // Through the comparer, so that a mismatch names the field; it compares with !==, so X and Z count.
      return comparer.compare_field("data", uvm_bitstream_t'(data), uvm_bitstream_t'(other.data), DATA_WIDTH);
   endfunction : do_compare

   // UVM hook of print() and sprint(): the word and the timing.
   function void do_print(uvm_printer printer);
      super.do_print(printer);
      printer.print_field("data", uvm_bitstream_t'(data), DATA_WIDTH, UVM_HEX);
      printer.print_field_int("delay_cycles", 64'(delay_cycles), 32, UVM_DEC);
      printer.print_field_int("wait_cycles", 64'(wait_cycles), 32, UVM_DEC);
      printer.print_field_int("aborted", 64'(aborted), 1, UVM_BIN);
   endfunction : do_print

   // UVM hook of pack(): every member, in the order of the declarations; X and Z bits of the word become 0.
   function void do_pack(uvm_packer packer);
      super.do_pack(packer);
      packer.pack_field(uvm_bitstream_t'(data), DATA_WIDTH);
      packer.pack_field_int(64'(delay_cycles), 32);
      packer.pack_field_int(64'(wait_cycles), 32);
      packer.pack_field_int(64'(aborted), 1);
   endfunction : do_pack

   // UVM hook of unpack(): the members in the order in which do_pack() wrote them.
   function void do_unpack(uvm_packer packer);
      super.do_unpack(packer);
      data         = packer.unpack_field(DATA_WIDTH) [DATA_WIDTH-1:0];
      delay_cycles = int'(packer.unpack_field_int(32));
      wait_cycles  = 32'(packer.unpack_field_int(32));
      aborted      = packer.unpack_field_int(1) [0];
   endfunction : do_unpack

endclass : hexk_valid_ready_item

`endif  // HEXK_VALID_READY_ITEM_SV
