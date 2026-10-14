// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_mem_model_example.sv
//
// Minimal use of hexk_mem_model: the reference model of a RAM with 32-bit words and byte
// enables behind a bus with 16-bit addresses. The example writes a word, changes two of its
// bytes with a byte enable, reads the word and one of its bytes, reads a word that was never
// written, which is an error under the default policy, and copies the memory into a second
// one through a file in the format of $readmemh.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_mem_model_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_mem_model;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_ZERO;
   `include "uvm_macros.svh"

   typedef hexk_mem_model#(
       .ADDR_WIDTH(16),
       .DATA_WIDTH(32)
   ) hexk_example_ram_t;

   localparam string IMAGE_FILE = "hexk_mem_model_example.hex";

   hexk_example_ram_t ram;
   hexk_example_ram_t copy;

   // Prints the word at an address of a memory.
   function automatic void show(hexk_example_ram_t mem, bit [15:0] addr);
      `uvm_info("EXAMPLE", $sformatf("%s[0x%04h] = 0x%08h", mem.get_name(), addr, mem.read(addr)), UVM_NONE)
   endfunction : show

   initial begin
      ram = hexk_example_ram_t::type_id::create("ram");
      ram.set_range(16'h1000, 16'h1FFF);

      // A full word, then a write of the two middle bytes only.
      ram.write(16'h1000, 32'h1122_3344);
      ram.write(16'h1000, 32'hFFAA_BBFF, 4'b0110);
      show(ram, 16'h1000);
      // The memory is little endian by default: the byte at the address of the word is its lowest byte.
      `uvm_info("EXAMPLE", $sformatf("byte at 0x1001 = 0x%02h", ram.read_byte(16'h1001)), UVM_NONE)

      // A word that was never written: an error by default, zero under another policy.
      show(ram, 16'h1010);
      ram.uninit_policy = HEXK_MEM_UNINIT_ZERO;
      show(ram, 16'h1010);

      // An access outside the range is an error and is not carried out.
      ram.write(16'h2000, 32'h0000_0001);

      // The content goes to a file and from there into a second memory.
      ram.dump_hex(IMAGE_FILE);
      copy = hexk_example_ram_t::type_id::create("copy");
      copy.load_hex(IMAGE_FILE);
      show(copy, 16'h1000);

      // What a memory reports at the end of a test when it is registered with hexk_eot_registry.
      ram.eot_check();
   end

endmodule : hexk_mem_model_example
