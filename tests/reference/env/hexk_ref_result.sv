// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_result.sv
//
// What the DUT holds after a packet: its number (STATUS.PKT_COUNT after it), the CRC, the cycles
// and the stored words. The predictor builds the expected one, the collector of the test reads the
// actual one; both go to the scoreboard wrapped in a hexk_meta_item, keyed by the number.

`ifndef HEXK_REF_RESULT_SV
`define HEXK_REF_RESULT_SV

class hexk_ref_result extends uvm_sequence_item;

   // Number of the packet since the last reset, as STATUS.PKT_COUNT counts it (8 bits).
   bit [ 7:0] number;

   // CRC and cycles of the packet.
   bit [31:0] crc;
   bit [15:0] cycles;

   // The words as stored, from the first to the last.
   bit [31:0] words  [$];

   `uvm_object_utils(hexk_ref_result)

   // Creates a result.
   function new(string name = "hexk_ref_result");
      super.new(name);
   endfunction : new

   // Number, CRC and cycles on one line, then the words as a hex dump (hexk_str).
   // TRN-5 waived: a mismatch of the result scoreboard prints this text, and the words are what it compares.
   function string convert2string();
      byte unsigned bytes[$];
      foreach (words[i]) begin
         for (int unsigned b = 0; b < 4; b++) begin
            bytes.push_back(words[i][8*b+:8]);
         end
      end
      return $sformatf(
          "packet %0d crc=0x%08h cycles=%0d, %0d words:\n%s",
          number,
          crc,
          cycles,
          words.size(),
          hexk_str::bytes_to_hex(
              bytes
          )
      );
   endfunction : convert2string

   // UVM hook of copy() and clone(): every member, the words as a copy of the queue.
   function void do_copy(uvm_object rhs);
      hexk_ref_result other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_fatal("REF_COPY", "do_copy from another class")
         return;
      end
      number = other.number;
      crc    = other.crc;
      cycles = other.cycles;
      words  = other.words;
   endfunction : do_copy

   // UVM hook of compare(): every member, through the comparer, so that a mismatch names the field.
   function bit do_compare(uvm_object rhs, uvm_comparer comparer);
      hexk_ref_result other;
      bit             same;
      if (!$cast(other, rhs)) begin
         return 0;
      end
      same = comparer.compare_field_int("number", 64'(number), 64'(other.number), $bits(number));
      same &= comparer.compare_field_int("crc", 64'(crc), 64'(other.crc), $bits(crc));
      same &= comparer.compare_field_int("cycles", 64'(cycles), 64'(other.cycles), $bits(cycles));
      same &= comparer.compare_field_int("size", 64'(words.size()), 64'(other.words.size()), 32);
      for (int unsigned i = 0; i < words.size() && i < other.words.size(); i++) begin
         same &= comparer.compare_field_int($sformatf("words[%0d]", i), 64'(words[i]), 64'(other.words[i]), 32);
      end
      return same;
   endfunction : do_compare

endclass : hexk_ref_result

// The result as the scoreboard holds it: with its time, ID and source.
typedef hexk_meta_item#(hexk_ref_result) hexk_ref_meta_result_t;

`endif  // HEXK_REF_RESULT_SV
