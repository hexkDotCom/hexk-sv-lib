// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_bus_seq.sv
//
// One access of the register bus, outside the register model: for byte writes into the RAM, which
// a register of the model cannot express. The starter assigns the members and starts it on the
// sequencer of the bus agent; after it, rdata holds the data of a read and ok says whether the
// access ended well (ack, and read data without X or Z bits). write() and read() do one access in
// one call, started below the calling sequence (parent; null from a test); an address outside the
// bus (above 'h1FC) or not word-aligned is the error REF_BUS_ADDR, and nothing is accessed. The
// driver reports an access that did not end well.

`ifndef HEXK_REF_BUS_SEQ_SV
`define HEXK_REF_BUS_SEQ_SV

class hexk_ref_bus_seq extends uvm_sequence #(hexk_ref_bus_item);

   // The access; set by the starter.
   bit          we;
   bit   [ 8:0] addr;
   bit   [31:0] wdata;
   bit   [ 3:0] wstrb  = 4'hF;

   // After the sequence: the data of a read, four-state as the bus gave it, and whether the access ended well.
   logic [31:0] rdata;
   bit          ok;

   `uvm_object_utils(hexk_ref_bus_seq)

   // Creates the sequence.
   function new(string name = "hexk_ref_bus_seq");
      super.new(name);
   endfunction : new

   // Sends the one access.
   task body();
      req = hexk_ref_bus_item::type_id::create("req", null, get_sequencer().get_full_name());
      start_item(req);
      `hexk_randomize_with_or_fatal(req, "REF_RAND",
                                    this.we == local::we; this.addr == local::addr; this.wdata == local::wdata;
                                    this.wstrb == local::wstrb;)
      finish_item(req);
      rdata = req.rdata;
      ok    = req.is_ok();
   endtask : body

   // A write of data to byte_addr, with the byte enables strobe, on the sequencer of a bus agent, below parent.
   static task write(uvm_sequence_base parent, uvm_sequencer#(hexk_ref_bus_item) sqr, int unsigned byte_addr,
                     bit [31:0] data, bit [3:0] strobe = 4'hF);
      hexk_ref_bus_seq bus_write_seq = hexk_ref_bus_seq::type_id::create("bus_write_seq");
      if (!is_bus_address(byte_addr) || !randomized(bus_write_seq)) begin
         return;
      end
      bus_write_seq.we    = 1;
      bus_write_seq.addr  = 9'(byte_addr);
      bus_write_seq.wdata = data;
      bus_write_seq.wstrb = strobe;
      bus_write_seq.start(sqr, parent);
   endtask : write

   // A read of byte_addr on the sequencer of a bus agent, below parent; data as the bus gave it.
   static task read(uvm_sequence_base parent, uvm_sequencer#(hexk_ref_bus_item) sqr, int unsigned byte_addr,
                    output logic [31:0] data);
      hexk_ref_bus_seq bus_read_seq = hexk_ref_bus_seq::type_id::create("bus_read_seq");
      data = 'x;
      if (!is_bus_address(byte_addr) || !randomized(bus_read_seq)) begin
         return;
      end
      bus_read_seq.we   = 0;
      bus_read_seq.addr = 9'(byte_addr);
      bus_read_seq.start(sqr, parent);
      data = bus_read_seq.rdata;
   endtask : read

   // Randomizes a sequence before its start, as every sequence is; a failure is the fatal REF_RAND.
   static function bit randomized(hexk_ref_bus_seq seq);
      if (seq.randomize() != 1) begin
         `hexk_static_fatal("REF_RAND", "randomization of a bus sequence failed")
         return 0;
      end
      return 1;
   endfunction : randomized

   // 1 when byte_addr is a word address of the bus (9 bits); otherwise the error REF_BUS_ADDR.
   static function bit is_bus_address(longint unsigned byte_addr);
      if (byte_addr > 'h1FC || byte_addr % 4 != 0) begin
         `hexk_static_error("REF_BUS_ADDR", $sformatf("'h%0h is not a word address of the bus ('h000 to 'h1FC)",
                                                      byte_addr))
         return 0;
      end
      return 1;
   endfunction : is_bus_address

endclass : hexk_ref_bus_seq

`endif  // HEXK_REF_BUS_SEQ_SV
