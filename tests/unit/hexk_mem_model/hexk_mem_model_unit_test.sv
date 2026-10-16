// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_mem_model_unit_test.sv
//
// SVUnit tests of hexk_mem_model, with a memory of 16 address bits and words of 32 bits.
// Every test gets a fresh memory. Errors of the memory are demoted by a report catcher and
// counted. The tests of load_hex() and dump_hex() write their files into the directory of
// the simulation and read them back.
// Results are compared as text (see tests/unit/README.md).
// Needs UVM. Runs on Verilator with UVM 2020: make test SIM=verilator TEST=hexk_mem_model.

`include "svunit_defines.svh"

module hexk_mem_model_unit_test;
   import svunit_pkg::svunit_testcase;
   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_mem_model;
   import hexk_uvm_pkg::hexk_mem_uninit_e;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_ERROR;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_RANDOM;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_ZERO;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_PATTERN;
   import hexk_uvm_pkg::HEXK_MEM_UNINIT_X;
   import hexk_uvm_pkg::hexk_report_catcher;

   typedef hexk_mem_model#(
       .ADDR_WIDTH(16),
       .DATA_WIDTH(32)
   ) hexk_ut_mem_t;

   // File that the tests of load_hex() and dump_hex() write, in the directory of the simulation.
   localparam string HEX_FILE = "hexk_ut_mem_model.hex";

   // The unwritten bytes next to the written ones of partly_written_round_trip().
   localparam bit [15:0] HOLES[6] = '{16'h0044, 16'h0045, 16'h0047, 16'h0100, 16'h0102, 16'h0103};

   string              name = "hexk_mem_model_ut";
   svunit_testcase     svunit_ut;

   hexk_report_catcher catcher;
   hexk_ut_mem_t       mem;

   function automatic void build();
      svunit_ut = new(name);
      catcher   = hexk_report_catcher::add_global();
   endfunction : build

   task automatic setup();
      svunit_ut.setup();
      catcher.clear();
      catcher.expect_msg("^HEXK_MEM_UNINIT$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_MEM_RANGE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_MEM_FILE$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_MEM_WIDTH$", UVM_ERROR, "", 0, -1, UVM_INFO);
      catcher.expect_msg("^HEXK_MEM_UNKNOWN$", UVM_ERROR, "", 0, -1, UVM_INFO);
      mem = new("ut_mem");
   endtask : setup

   task automatic teardown();
      svunit_ut.teardown();
      catcher.clear();
   endtask : teardown

   // The word at an address in hexadecimal.
   function automatic string word_at(bit [15:0] addr);
      return $sformatf("%h", mem.read(addr));
   endfunction : word_at

   // The byte at an address in hexadecimal.
   function automatic string byte_at(bit [15:0] addr);
      return $sformatf("%h", mem.read_byte(addr));
   endfunction : byte_at

   // Reads a word and ignores what it holds.
   function automatic void touch_word(bit [15:0] addr);
      void'(mem.read(addr));
   endfunction : touch_word

   // Reads a byte and ignores what it holds.
   function automatic void touch_byte(bit [15:0] addr);
      void'(mem.read_byte(addr));
   endfunction : touch_byte

   // Errors of the memory in this test, as "<uninit> <range> <file> <width> <unknown>".
   function automatic string errors();
      return $sformatf(
          "%0d %0d %0d %0d %0d",
          catcher.get_count(
              "^HEXK_MEM_UNINIT$"
          ),
          catcher.get_count(
              "^HEXK_MEM_RANGE$"
          ),
          catcher.get_count(
              "^HEXK_MEM_FILE$"
          ),
          catcher.get_count(
              "^HEXK_MEM_WIDTH$"
          ),
          catcher.get_count(
              "^HEXK_MEM_UNKNOWN$"
          )
      );
   endfunction : errors

   // The word at a four-state address in hexadecimal.
   function automatic string word_at_logic(logic [15:0] addr);
      return $sformatf("%h", mem.read(addr));
   endfunction : word_at_logic

   // Number of errors HEXK_MEM_UNKNOWN.
   function automatic string unknown_errors();
      return $sformatf("%0d", catcher.get_count("^HEXK_MEM_UNKNOWN$"));
   endfunction : unknown_errors

   // "<bytes written> <reads of unwritten bytes>".
   function automatic string counts();
      return $sformatf("%0d %0d", mem.num_written(), mem.num_uninit_reads());
   endfunction : counts

   // Sets the policy for reads of unwritten bytes.
   function automatic void set_policy(hexk_mem_uninit_e policy);
      mem.uninit_policy = policy;
   endfunction : set_policy

   // Makes the memory big endian.
   function automatic void use_big_endian();
      mem.big_endian = 1;
   endfunction : use_big_endian

   // Sets the byte of policy HEXK_MEM_UNINIT_PATTERN.
   function automatic void set_pattern(logic [7:0] pattern);
      mem.uninit_pattern = pattern;
   endfunction : set_pattern

   // Under the random policy: "<two reads of one address are equal> <two addresses read the same>".
   function automatic string random_reads();
      logic [31:0] first = mem.read(16'h0200);
      logic [31:0] again = mem.read(16'h0200);
      logic [31:0] other = mem.read(16'h0300);
      return $sformatf("%0d %0d", first === again, first === other);
   endfunction : random_reads

   // Writes text lines to the test file.
   function automatic void write_file(string lines[$]);
      int handle = $fopen(HEX_FILE, "w");
      foreach (lines[i]) begin
         $fdisplay(handle, "%s", lines[i]);
      end
      $fclose(handle);
   endfunction : write_file

   // The lines of the test file, joined with " | ".
   function automatic string file_text();
      int    handle = $fopen(HEX_FILE, "r");
      string line;
      string text;
      while ($fgets(
          line, handle
      ) != 0) begin
         line = hexk_core_pkg::hexk_str::rstrip(line);
         text = (text.len() == 0) ? line : {text, " | ", line};
      end
      $fclose(handle);
      return text;
   endfunction : file_text

   // Loads a file that uses everything the format allows.
   function automatic void load_rich_file(bit [15:0] base);
      string lines[$] = '{
          "// two words from address 0",
          "11223344 55_66_77_88",
          "/* a comment",
          "   over two lines */ @10",
          "0000beef // word 0x10",
          "@4 a5 /* short word */ dead_xxxx"
      };
      write_file(lines);
      mem.load_hex(HEX_FILE, base);
   endfunction : load_rich_file

   // Loads a file in which block comments stand between two words, with and without blanks around them.
   function automatic void load_comment_file();
      string lines[$] = '{"11/*gap*/22", "33/* over", "two lines */44", "/* only a comment */", "55 /**/ 66"};
      write_file(lines);
      mem.load_hex(HEX_FILE);
   endfunction : load_comment_file

   // Loads a file of words with fewer digits than the word has, with and without an x or z as the first digit.
   function automatic void load_short_word_file();
      string lines[$] = '{"x", "z", "xa", "1x", "Z5", "a"};
      write_file(lines);
      mem.load_hex(HEX_FILE);
   endfunction : load_short_word_file

   // "<is_written of the last word that fits> <is_written of a word that would go on at address 0>".
   function automatic string written_at_the_top();
      return $sformatf("%0d %0d", mem.is_written(16'hFFFC), mem.is_written(16'hFFFE));
   endfunction : written_at_the_top

   // Loads a file with one token that is not a word, and one address that is not one.
   function automatic void load_bad_file();
      string lines[$] = '{"11223344", "hello", "@zz", "123456789", "55667788"};
      write_file(lines);
      mem.load_hex(HEX_FILE);
   endfunction : load_bad_file

   // Loads a file whose lines end as those of a text file from Windows do; \015 is CR.
   function automatic void load_windows_file();
      string lines[$] = '{"11223344\015", "@4\015", "55667788 \015", "// the end\015"};
      write_file(lines);
      mem.load_hex(HEX_FILE);
   endfunction : load_windows_file

   // Loads a file of three words, then two words from index 0x4000 and one at index 1, from the given base.
   function automatic void load_long_file(bit [15:0] base);
      string lines[$] = '{"11223344 55667788 99aabbcc", "@4000 deadbeef 0badc0de", "@1 cafef00d"};
      write_file(lines);
      mem.load_hex(HEX_FILE, base);
   endfunction : load_long_file

   // A memory of 8 address bits and words of 3 bytes, whose last word starts at the top address 0xff: bytes at
   // 0x00, 0x01 and 0xff are written, dumped, cleared and loaded again. "<file> / <bytes> <0x00> <0x01> <0xff>
   // <errors>"; unwritten bytes read as 00.
   function automatic string top_word_round_trip(bit big);
      hexk_mem_model #(
          .ADDR_WIDTH(8),
          .DATA_WIDTH(24)
      ) top_mem = new(
          "ut_small_mem"
      );
      string parts[$];
      top_mem.big_endian    = big;
      top_mem.uninit_policy = HEXK_MEM_UNINIT_ZERO;
      top_mem.write_byte(8'h00, 8'h11);
      top_mem.write_byte(8'h01, 8'h22);
      top_mem.write_byte(8'hFF, 8'hAA);
      top_mem.dump_hex(HEX_FILE);
      parts.push_back(file_text());
      top_mem.clear();
      top_mem.load_hex(HEX_FILE);
      // One statement per part: the order in which the arguments of a call are evaluated is not defined.
      parts.push_back($sformatf("/ %0d", top_mem.num_written()));
      parts.push_back($sformatf("%h", top_mem.read_byte(8'h00)));
      parts.push_back($sformatf("%h", top_mem.read_byte(8'h01)));
      parts.push_back($sformatf("%h", top_mem.read_byte(8'hFF)));
      parts.push_back(errors());
      return hexk_core_pkg::hexk_str::join_str(parts, " ");
   endfunction : top_word_round_trip

   // As top_word_round_trip with words of 5 bytes, little endian, and bytes at 0x00 and 0xff only.
   function automatic string top_word_round_trip_40();
      hexk_mem_model #(
          .ADDR_WIDTH(8),
          .DATA_WIDTH(40)
      ) top_mem = new(
          "ut_small_mem_40"
      );
      string parts[$];
      top_mem.uninit_policy = HEXK_MEM_UNINIT_ZERO;
      top_mem.write_byte(8'h00, 8'h11);
      top_mem.write_byte(8'hFF, 8'hAA);
      top_mem.dump_hex(HEX_FILE);
      parts.push_back(file_text());
      top_mem.clear();
      top_mem.load_hex(HEX_FILE);
      parts.push_back($sformatf("/ %0d", top_mem.num_written()));
      parts.push_back($sformatf("%h", top_mem.read_byte(8'h00)));
      parts.push_back($sformatf("%h", top_mem.read_byte(8'hFF)));
      parts.push_back(errors());
      return hexk_core_pkg::hexk_str::join_str(parts, " ");
   endfunction : top_word_round_trip_40

   // A file whose last word starts at 0xff and has real bytes beyond the top, loaded into a memory of 8 address
   // bits and words of 3 bytes: "<bytes> <0xff> <errors>".
   function automatic string load_past_the_top();
      hexk_mem_model #(
          .ADDR_WIDTH(8),
          .DATA_WIDTH(24)
      ) top_mem = new(
          "ut_small_mem"
      );
      string lines[$] = '{"@55 112233"};
      string parts[$];
      write_file(lines);
      top_mem.load_hex(HEX_FILE);
      parts.push_back($sformatf("%0d", top_mem.num_written()));
      parts.push_back($sformatf("%h", top_mem.read_byte(8'hFF)));
      parts.push_back(errors());
      return hexk_core_pkg::hexk_str::join_str(parts, " ");
   endfunction : load_past_the_top

   // Writes a whole word and single bytes of two other words, dumps, clears and loads again, with policy zero for
   // the unwritten bytes: "<bytes written> <the bytes at 0x40..0x43, 0x46 and 0x101> <reads of unwritten bytes>
   // <the same after a read of each unwritten byte next to the written ones>".
   function automatic string partly_written_round_trip();
      string parts[$];
      mem.write(16'h0040, 32'h1122_3344);
      mem.write_byte(16'h0046, 8'hC3);
      mem.write_byte(16'h0101, 8'h5A);
      dump_and_reload();
      mem.uninit_policy = HEXK_MEM_UNINIT_ZERO;
      // One statement per part: the order in which the arguments of a call are evaluated is not defined.
      parts.push_back($sformatf("%0d", mem.num_written()));
      parts.push_back(byte_at(16'h0040));
      parts.push_back(byte_at(16'h0041));
      parts.push_back(byte_at(16'h0042));
      parts.push_back(byte_at(16'h0043));
      parts.push_back(byte_at(16'h0046));
      parts.push_back(byte_at(16'h0101));
      parts.push_back($sformatf("%0d", mem.num_uninit_reads()));
      foreach (HOLES[i]) begin
         touch_byte(HOLES[i]);
      end
      parts.push_back($sformatf("%0d", mem.num_uninit_reads()));
      return hexk_core_pkg::hexk_str::join_str(parts, " ");
   endfunction : partly_written_round_trip

   // Dumps the memory to the test file, clears it and loads the file again.
   function automatic void dump_and_reload();
      mem.dump_hex(HEX_FILE);
      mem.clear();
      mem.load_hex(HEX_FILE);
   endfunction : dump_and_reload

   // A memory with one address bit and words of four bytes: "<width errors> <word written> <bytes written>".
   function automatic string tiny_memory();
      hexk_mem_model #(
          .ADDR_WIDTH(1),
          .DATA_WIDTH(32)
      ) tiny = new(
          "ut_tiny_mem"
      );
      tiny.write(1'b0, 32'h1122_3344);
      return $sformatf("%0d %0d %0d", catcher.get_count("^HEXK_MEM_WIDTH$"), tiny.is_written(1'b0), tiny.num_written());
   endfunction : tiny_memory

   // A clone of a memory with a word, a range, the big-endian order, a policy, a pattern, a seed and one read of
   // an unwritten word, written to afterwards, and the original: "<clone> | <original>", the clone as "<word>
   // <bytes written> <settings> <an unwritten word> <seed> <range errors after a read outside its range>", the
   // original as "<word> <bytes written> <range errors after a read outside its range>".
   function automatic string cloned_memory();
      hexk_ut_mem_t copy;
      string        parts[$];
      mem.uninit_policy  = HEXK_MEM_UNINIT_PATTERN;
      mem.uninit_pattern = 8'h3C;
      mem.seed           = 32'h1234_5678;
      mem.big_endian     = 1;
      mem.set_range(16'h0100, 16'h01FF);
      mem.write(16'h0100, 32'hCAFE_F00D);
      touch_word(16'h0110);
      if (!$cast(copy, mem.clone())) begin
         return "clone failed";
      end
      copy.write(16'h0104, 32'h1234_5678);
      mem.write(16'h0100, 32'h0BAD_0BAD);
      // One statement per part: the order in which the arguments of a call are evaluated is not defined.
      parts.push_back($sformatf("%h", copy.read(16'h0100)));
      parts.push_back($sformatf("%0d", copy.num_written()));
      parts.push_back(copy.convert2string());
      parts.push_back($sformatf("%h", copy.read(16'h0108)));
      parts.push_back($sformatf("%h", copy.seed));
      // The range holds in both: a read outside it is an error. Counted, not printed: on Verilator its X reads as 0.
      void'(copy.read(16'h0200));
      parts.push_back($sformatf("%0d", catcher.get_count("^HEXK_MEM_RANGE$")));
      parts.push_back($sformatf("| %h", mem.read(16'h0100)));
      parts.push_back($sformatf("%0d", mem.num_written()));
      void'(mem.read(16'h0200));
      parts.push_back($sformatf("%0d", catcher.get_count("^HEXK_MEM_RANGE$")));
      return hexk_core_pkg::hexk_str::join_str(parts, " ");
   endfunction : cloned_memory

   // A memory with the default address width of 64 bits: a word that ends at the top address, then a write and a
   // read of a word one byte higher, which would go on at address 0. "<word at the top> <bytes written>
   // <is_written at address 0> <range errors>".
   function automatic string top_of_64_bit_addresses();
      hexk_mem_model #(.DATA_WIDTH(32)) wide = new("ut_wide_mem");
      string parts[$];
      wide.write(64'hFFFF_FFFF_FFFF_FFFC, 32'h1122_3344);
      wide.write(64'hFFFF_FFFF_FFFF_FFFD, 32'h5566_7788);
      void'(wide.read(64'hFFFF_FFFF_FFFF_FFFD));
      parts.push_back($sformatf("%h", wide.read(64'hFFFF_FFFF_FFFF_FFFC)));
      parts.push_back($sformatf("%0d", wide.num_written()));
      parts.push_back($sformatf("%0d", wide.is_written(64'h0)));
      parts.push_back($sformatf("%0d", catcher.get_count("^HEXK_MEM_RANGE$")));
      return hexk_core_pkg::hexk_str::join_str(parts, " ");
   endfunction : top_of_64_bit_addresses

   // Number of HEXK_MEM_WIDTH errors when a memory with words of 12 bits is created.
   function automatic string odd_width_errors();
      hexk_mem_model #(
          .ADDR_WIDTH(8),
          .DATA_WIDTH(12)
      ) odd = new(
          "ut_odd_mem"
      );
      return $sformatf("%0d %0d", catcher.get_count("^HEXK_MEM_WIDTH$"), odd.num_written());
   endfunction : odd_width_errors

   // The SVUnit macros open a task body that Verible cannot see, so the formatter would
   // lay the statements out as module items.
   // verilog_format: off
   `SVUNIT_TESTS_BEGIN

   `SVTEST(a_written_word_reads_back)
      mem.write(16'h0100, 32'hDEADBEEF);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "deadbeef")
      `FAIL_UNLESS_STR_EQUAL(counts(), "4 0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", mem.is_written(16'h0100)), "1")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END

   `SVTEST(little_endian_has_the_low_byte_at_the_low_address)
      mem.write(16'h0100, 32'hDEADBEEF);
      `FAIL_UNLESS_STR_EQUAL({byte_at(16'h0100), byte_at(16'h0101), byte_at(16'h0102), byte_at(16'h0103)},
         "efbeadde")
   `SVTEST_END

   `SVTEST(big_endian_has_the_high_byte_at_the_low_address)
      use_big_endian();
      mem.write(16'h0100, 32'hDEADBEEF);
      `FAIL_UNLESS_STR_EQUAL({byte_at(16'h0100), byte_at(16'h0101), byte_at(16'h0102), byte_at(16'h0103)},
         "deadbeef")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "deadbeef")
   `SVTEST_END

   `SVTEST(byte_enables_select_the_bytes_that_are_written)
      mem.write(16'h0100, 32'h11223344);
      mem.write(16'h0100, 32'hAABBCCDD, 4'b0101);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "11bb33dd")
      mem.write(16'h0200, 32'hAABBCCDD, 4'b1000);
      `FAIL_UNLESS_STR_EQUAL(counts(), "5 0")
   `SVTEST_END

   `SVTEST(big_endian_byte_enables_select_bytes_by_their_place_in_the_data)
      use_big_endian();
      mem.write(16'h0100, 32'h11223344);
      mem.write(16'h0100, 32'hAABBCCDD, 4'b0101);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "11bb33dd")
      `FAIL_UNLESS_STR_EQUAL({byte_at(16'h0100), byte_at(16'h0101), byte_at(16'h0102), byte_at(16'h0103)},
         "11bb33dd")
      mem.write(16'h0200, 32'hAABBCCDD, 4'b1000);
      `FAIL_UNLESS_STR_EQUAL(byte_at(16'h0200), "aa")
      `FAIL_UNLESS_STR_EQUAL(counts(), "5 0")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END

   `SVTEST(unaligned_words_and_bytes_see_the_same_memory)
      mem.write(16'h0100, 32'h44332211);
      mem.write(16'h0104, 32'h88776655);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0102), "66554433")
      mem.write_byte(16'h0103, 8'hFF);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "ff332211")
      `FAIL_UNLESS_STR_EQUAL(byte_at(16'h0105), "66")
   `SVTEST_END

   `SVTEST(a_read_of_an_unwritten_byte_is_an_error_by_default)
      mem.write(16'h0100, 32'h11223344, 4'b0111);
      touch_word(16'h0100);
      touch_byte(16'h0400);
      `FAIL_UNLESS_STR_EQUAL(errors(), "2 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(counts(), "3 2")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", mem.is_written(16'h0100)), "0")
   `SVTEST_END

   `SVTEST(policy_zero_reads_unwritten_bytes_as_zero_without_an_error)
      set_policy(HEXK_MEM_UNINIT_ZERO);
      mem.write(16'h0100, 32'h11223344, 4'b0110);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "00223300")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(counts(), "2 1")
   `SVTEST_END

   `SVTEST(policy_pattern_reads_unwritten_bytes_as_the_pattern)
      set_policy(HEXK_MEM_UNINIT_PATTERN);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "a5a5a5a5")
      set_pattern(8'h3C);
      mem.write_byte(16'h0101, 8'h00);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "3c3c003c")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END

   `SVTEST(policy_random_reads_the_same_value_at_every_read_of_an_address)
      set_policy(HEXK_MEM_UNINIT_RANDOM);
      `FAIL_UNLESS_STR_EQUAL(random_reads(), "1 0")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END

   // Variables have two states on Verilator, so the test of the X that a read returns runs on
   // four-state simulators only.
`ifndef VERILATOR
   `SVTEST(policy_x_reads_unwritten_bytes_as_x_without_an_error)
      set_policy(HEXK_MEM_UNINIT_X);
      mem.write_byte(16'h0100, 8'h77);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0100), "xxxxxx77")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END

   `SVTEST(a_byte_reads_x_where_a_word_reads_x)
      set_policy(HEXK_MEM_UNINIT_X);
      mem.write(16'h0100, 32'h0000_5Axx, 4'b0011);
      `FAIL_UNLESS_STR_EQUAL({byte_at(16'h0100), byte_at(16'h0101), byte_at(16'h0102)}, "xx5axx")
      mem.write_byte(16'h0200, 8'b1010_zzxx);
      `FAIL_UNLESS_STR_EQUAL($sformatf("%b %b", mem.read_byte(16'h0200), mem.read(16'h0200)),
         "1010zzxx xxxxxxxxxxxxxxxxxxxxxxxx1010zzxx")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END
`endif

   `SVTEST(clear_forgets_everything)
      mem.write(16'h0100, 32'h11223344);
      touch_word(16'h0200);
      mem.clear();
      `FAIL_UNLESS_STR_EQUAL(counts(), "0 0")
      `FAIL_UNLESS_STR_EQUAL($sformatf("%0d", mem.is_written(16'h0100)), "0")
   `SVTEST_END

   `SVTEST(an_access_outside_the_range_is_an_error_and_is_not_carried_out)
      mem.set_range(16'h0100, 16'h01FF);
      mem.write(16'h01FC, 32'h11223344);
      mem.write(16'h01FD, 32'h55667788);
      mem.write(16'h00FF, 32'h55667788);
      mem.write_byte(16'h0200, 8'h99);
      touch_word(16'h0200);
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 4 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(counts(), "4 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h01FC), "11223344")
   `SVTEST_END

`ifndef VERILATOR
   // Verilator has no X or Z.
   `SVTEST(an_address_or_byte_enable_with_x_or_z_is_an_error_and_is_not_carried_out)
      mem.write(16'h01x0, 32'h11223344);
      mem.write(16'h0100, 32'h11223344, 4'b1z11);
      mem.write_byte(16'hx000, 8'h99);
      `FAIL_UNLESS_STR_EQUAL(word_at_logic(16'h0x00), "xxxxxxxx")
      `FAIL_UNLESS_STR_EQUAL(unknown_errors(), "4")
      `FAIL_UNLESS_STR_EQUAL(counts(), "0 0")
   `SVTEST_END
`endif

   `SVTEST(a_word_that_would_go_on_at_address_0_is_an_error_and_is_not_carried_out)
      mem.write(16'hFFFE, 32'h11223344);
      touch_word(16'hFFFD);
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 2 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(counts(), "0 0")
      mem.write(16'hFFFC, 32'h55667788);
      mem.write_byte(16'hFFFF, 8'h99);
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 2 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'hFFFC), "99667788")
      `FAIL_UNLESS_STR_EQUAL(written_at_the_top(), "1 0")
   `SVTEST_END

   `SVTEST(load_hex_takes_a_block_comment_as_the_end_of_a_word)
      load_comment_file();
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0000), "00000011")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0004), "00000022")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0008), "00000033")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h000C), "00000044")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0010), "00000055")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0014), "00000066")
      `FAIL_UNLESS_STR_EQUAL(counts(), "24 0")
   `SVTEST_END

   `SVTEST(load_hex_reads_words_addresses_comments_and_underscores)
      load_rich_file(16'h0000);
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0000), "11223344")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0040), "0000beef")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0010), "000000a5")
      // Five words, but the two bytes of xx in dead_xxxx are not written.
      `FAIL_UNLESS_STR_EQUAL(counts(), "18 0")
   `SVTEST_END

   `SVTEST(load_hex_puts_word_n_at_the_base_plus_n_words)
      load_rich_file(16'h1000);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h1004), "55667788")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h1040), "0000beef")
   `SVTEST_END

`ifndef VERILATOR
   `SVTEST(load_hex_leaves_a_byte_of_two_x_digits_unwritten)
      load_rich_file(16'h0000);
      `FAIL_UNLESS_STR_EQUAL(counts(), "18 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0014), "deadxxxx")
   `SVTEST_END

   `SVTEST(load_hex_extends_a_short_word_with_its_first_digit_when_that_is_x_or_z)
      load_short_word_file();
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(counts(), "17 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0000), "xxxxxxxx")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0004), "zzzzzzzz")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0008), "xxxxxxxa")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h000C), "0000001x")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0010), "zzzzzzz5")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0014), "0000000a")
   `SVTEST_END
`endif

   `SVTEST(load_hex_reports_what_is_not_a_word_and_loads_the_rest)
      load_bad_file();
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 3 0 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0000), "11223344")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h000c), "55667788")
   `SVTEST_END

   `SVTEST(load_hex_reads_a_file_with_windows_line_ends)
      load_windows_file();
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL({word_at(16'h0000), word_at(16'h0010)}, "1122334455667788")
      `FAIL_UNLESS_STR_EQUAL(counts(), "8 0")
   `SVTEST_END

   `SVTEST(load_hex_reports_a_word_beyond_the_address_space_and_does_not_wrap)
      load_long_file(16'h0000);
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 1 0 0")
      `FAIL_UNLESS_STR_EQUAL({word_at(16'h0000), word_at(16'h0004), word_at(16'h0008)}, "11223344cafef00d99aabbcc")
      `FAIL_UNLESS_STR_EQUAL(counts(), "12 0")
   `SVTEST_END

   `SVTEST(load_hex_reports_a_base_that_puts_words_beyond_the_address_space)
      load_long_file(16'hFFFC);
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 3 0 0")
      `FAIL_UNLESS_STR_EQUAL(word_at(16'hFFFC), "11223344")
      `FAIL_UNLESS_STR_EQUAL(counts(), "4 0")
   `SVTEST_END

   `SVTEST(a_file_that_does_not_exist_is_an_error)
      mem.load_hex("hexk_ut_no_such_file.hex");
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 1 0 0")
   `SVTEST_END

   `SVTEST(dump_hex_writes_the_words_with_addresses_where_they_jump)
      mem.write(16'h0000, 32'h11223344);
      mem.write(16'h0004, 32'h55667788);
      mem.write(16'h0040, 32'h0000BEEF);
      mem.write_byte(16'h0046, 8'hC3);
      mem.dump_hex(HEX_FILE);
      `FAIL_UNLESS_STR_EQUAL(file_text(), "@0 | 11223344 | 55667788 | @10 | 0000beef | xxc3xxxx")
   `SVTEST_END

   `SVTEST(a_dump_loads_back_to_the_same_memory)
      mem.write(16'h0000, 32'h11223344);
      mem.write(16'h0100, 32'hCAFEF00D);
      mem.write(16'h0104, 32'h0BADC0DE);
      dump_and_reload();
      `FAIL_UNLESS_STR_EQUAL({word_at(16'h0000), word_at(16'h0100), word_at(16'h0104)}, "11223344cafef00d0badc0de")
      `FAIL_UNLESS_STR_EQUAL(counts(), "12 0")
   `SVTEST_END

   `SVTEST(a_dump_of_partly_written_words_loads_back_to_the_same_bytes)
      `FAIL_UNLESS_STR_EQUAL(partly_written_round_trip(), "6 44 33 22 11 c3 5a 0 6")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END

`ifndef VERILATOR
   `SVTEST(a_dump_keeps_a_digit_that_is_all_z_and_a_partly_z_digit_loads_back_all_z)
      mem.write(16'h0000, {8'h12, 8'hz5, 8'bzz01_0101, 8'h34});
      mem.dump_hex(HEX_FILE);
      `FAIL_UNLESS_STR_EQUAL(file_text(), "@0 | 12z5Z534")
      mem.clear();
      mem.load_hex(HEX_FILE);
      `FAIL_UNLESS_STR_EQUAL(word_at(16'h0000), "12z5z534")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 0 0 0 0")
   `SVTEST_END
`endif

   `SVTEST(the_last_word_below_the_top_address_dumps_and_loads_without_wrapping)
      `FAIL_UNLESS_STR_EQUAL(top_word_round_trip(0), "@0 | xx2211 | @55 | xxxxaa / 3 11 22 aa 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(top_word_round_trip(1), "@0 | 1122xx | @55 | aaxxxx / 3 11 22 aa 0 0 0 0 0")
      `FAIL_UNLESS_STR_EQUAL(top_word_round_trip_40(), "@0 | xxxxxxxx11 | @33 | xxxxxxxxaa / 2 11 aa 0 0 0 0 0")
   `SVTEST_END

   `SVTEST(load_hex_reports_real_bytes_beyond_the_top_and_loads_those_below)
      `FAIL_UNLESS_STR_EQUAL(load_past_the_top(), "1 33 0 0 1 0 0")
   `SVTEST_END

   `SVTEST(convert2string_says_what_the_memory_holds)
      mem.write(16'h0100, 32'h11223344);
      `FAIL_UNLESS_STR_EQUAL(mem.convert2string(),
         "4 bytes written, 0 reads of bytes that were never written, policy HEXK_MEM_UNINIT_ERROR, little endian")
   `SVTEST_END

   `SVTEST(a_word_that_does_not_fit_the_address_space_is_an_error_and_nothing_is_stored)
      `FAIL_UNLESS_STR_EQUAL(tiny_memory(), "1 0 0")
   `SVTEST_END

   `SVTEST(the_type_name_has_no_parameters)
      `FAIL_UNLESS_STR_EQUAL(mem.get_type_name(), "hexk_mem_model")
   `SVTEST_END

   `SVTEST(a_clone_holds_the_bytes_and_settings_and_is_independent)
      `FAIL_UNLESS_STR_EQUAL(cloned_memory(),
         {"cafef00d 8 8 bytes written, 1 reads of bytes that were never written, policy HEXK_MEM_UNINIT_PATTERN, ",
          "big endian 3c3c3c3c 12345678 1 | 0bad0bad 4 2"})
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 2 0 0 0")
   `SVTEST_END

   `SVTEST(with_the_default_64_address_bits_a_word_may_end_at_the_top_and_never_goes_on_at_address_0)
      `FAIL_UNLESS_STR_EQUAL(top_of_64_bit_addresses(), "11223344 4 0 2")
      `FAIL_UNLESS_STR_EQUAL(errors(), "0 2 0 0 0")
   `SVTEST_END

   `SVTEST(a_word_width_that_is_not_a_multiple_of_8_is_an_error)
      `FAIL_UNLESS_STR_EQUAL(odd_width_errors(), "1 0")
   `SVTEST_END

   `SVUNIT_TESTS_END
   // verilog_format: on

endmodule : hexk_mem_model_unit_test
