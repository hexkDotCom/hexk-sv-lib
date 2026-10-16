// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_ref_predictor.sv
//
// Reference model of the packet store, built from library models and fed only by monitors:
// - the words from the input agent (ap) and the edges at which they were accepted (cycle_ap);
// - the configuration from the observed register writes (CTRL, BASE, DEBUG, INJ_*, MEM);
// - the reset from the clock and reset agent (on_reset()).
// For every packet it computes the CRC (hexk_crc), the scrambled words (hexk_lfsr), the code words
// (hexk_ecc) and the cycles, and writes:
// - every expected commit into a hexk_delay_analysis_fifo that releases it at the edge at which
//   the DUT commits the word; run_phase then applies it to the RAM model and hands it on (commit_ap);
// - the expected result of a packet, wrapped in a hexk_meta_item with a hexk_uid, to result_ap when
//   its last word is committed: the words of the result are what the RAM then holds.
// It keeps the RAM as the DUT should hold it: the data in a hexk_mem_model, the raw code words
// here, and from them predicts what every observed read of the MEM window returns and how the
// error counters move; it checks each such read itself.
//
// Order at an edge: the monitors report the words, the edge and the register writes of one edge in
// an order that the simulator chooses. So the predictor handles the words of an edge at the next
// edge, when everything of the edge has arrived, and a register write counts only for words
// accepted after the edge at which the DUT took it (hexk_ref_bus_item::taken_ps), as in the DUT.
// The tests do not read or write a word of the RAM while a commit to it is in flight.

`ifndef HEXK_REF_PREDICTOR_SV
`define HEXK_REF_PREDICTOR_SV

// The analysis imps of the three inputs of the predictor; the macro declares a class for each, so this file holds more
// than the class it is named after.
// verilator lint_off DECLFILENAME
`hexk_analysis_imp_indexed_decl(ref_word)
`hexk_analysis_imp_indexed_decl(ref_cycle)
`hexk_analysis_imp_indexed_decl(ref_bus)
// verilator lint_on DECLFILENAME

class hexk_ref_predictor extends uvm_component implements hexk_objectable;

   typedef hexk_valid_ready_item#(32) word_item_t;

   // A word that the DUT accepted, and the time in picoseconds of the edge that accepted it.
   typedef struct {
      bit [31:0]       data;
      longint unsigned at_ps;
   } accepted_word_t;

   // A packet whose words are not all committed yet, counted from its first word on: its result, its first word
   // address, the words received so far, those of them not yet committed, and whether its last word came.
   typedef struct {
      hexk_ref_result result;
      bit [5:0]       first_addr;
      int unsigned    len;
      int unsigned    uncommitted;
      bit             received;
   } packet_t;

   // Pipeline depth of the DUT: a word accepted at an edge is committed this many edges later.
   localparam int unsigned PIPE_DEPTH = 3;
   localparam bit [15:0] LFSR_TAPS = 16'hB400;
   localparam bit [15:0] LFSR_SEED = 16'hACE1;

   // Inputs: the words and edges of the input agent and the accesses of the bus monitor. Each export is the only one
   // of its kind, so the index that it passes is always 0.
   hexk_analysis_imp_indexed_ref_word #(word_item_t, hexk_ref_predictor) word_export;
   hexk_analysis_imp_indexed_ref_cycle #(hexk_handshake_cycle_t, hexk_ref_predictor) cycle_export;
   hexk_analysis_imp_indexed_ref_bus #(hexk_ref_bus_item, hexk_ref_predictor) bus_export;

   // Expected results of the packets, and the expected commits at the edges of the commits.
   uvm_analysis_port #(hexk_ref_meta_result_t) result_ap;
   uvm_analysis_port #(hexk_ref_commit_item) commit_ap;

   // The RAM as the DUT should hold it; registered with hexk_eot_registry by the environment.
   hexk_ref_mem_model mem;

   // Gets a heartbeat for every packet that the DUT completed and for every access of the bus.
   hexk_watchdog watchdog;

   // 0 for a test that cannot collect the result of every packet: the results are not written to result_ap, and
   // the test compares last_result itself.
   bit publish_results = 1;

   // The expected result of the last completed packet.
   hexk_ref_result last_result;

   // Number of words the DUT accepted since the start.
   int unsigned num_words;

   // Number of packets completed since the start.
   int unsigned num_packets;

   // Expected error counters of the DUT (ERR), saturating at 255 as the DUT's do.
   int unsigned corrected;
   int unsigned uncorrectable;

   // The configuration as the DUT got it.
   local bit scramble;
   local bit [3:0] len_field;
   local bit [5:0] base;
   local bit corrupt_read;
   local bit [38:0] inj_mask;
   local bit inj_armed;
   local bit irq_en;

   // Register writes that the DUT took and that no word has needed yet, oldest first.
   local hexk_ref_bus_item pending_writes[$];

   // Models.
   local hexk_crc crc;
   local hexk_lfsr lfsr;
   local hexk_ecc ecc;
   local bit [38:0] raw[hexk_ref_regs::MEM_WORDS];

   // Rising edges seen since the start, and the accepted words that are not yet handled, oldest first.
   local longint unsigned edges;
   local accepted_word_t accepted_words[$];

   // The packet being received: its result so far, its first edge, the word address and the index of its next word
   // (the DUT's 5-bit word counter).
   local hexk_ref_result current;
   local longint unsigned first_edge;
   local bit [5:0] next_addr;
   local bit [4:0] word_index;
   local int unsigned packet_number;

   // Packets that are not completely committed yet, the one being received included, oldest first.
   local packet_t packets[$];

   // Triggered at every rising edge: the clock of the commit FIFO.
   event edge_seen;
   hexk_delay_analysis_fifo #(hexk_ref_commit_item) commit_fifo;

   // IDs of the results.
   local hexk_uid uids;

   // What one packet covered: its length, its mode and whether interrupts were on.
   local int unsigned cov_len;
   local bit cov_scramble;
   local bit cov_irq;
   covergroup packet_cg;
      len_cp: coverpoint cov_len {
         bins one = {1}; bins short_lens = {[2 : 8]}; bins long_lens = {[9 : 15]}; bins full = {16};
      }
      scramble_cp: coverpoint cov_scramble;
      irq_cp: coverpoint cov_irq;
      len_x_scramble: cross len_cp, scramble_cp;
   endgroup : packet_cg

   `uvm_component_utils(hexk_ref_predictor)

   // Creates the predictor, its models and ports.
   function new(string name, uvm_component parent);
      super.new(name, parent);
      word_export  = new("word_export", this);
      cycle_export = new("cycle_export", this);
      bus_export   = new("bus_export", this);
      result_ap    = new("result_ap", this);
      commit_ap    = new("commit_ap", this);
      crc          = hexk_crc::crc32();
      lfsr         = new(16, LFSR_TAPS, LFSR_SEED);
      ecc          = new(32);
      mem          = hexk_ref_mem_model::type_id::create("mem", this);
      uids         = hexk_uid_pool::get().new_uid("ref_packet");
      `hexk_cg_new(packet_cg)
      reset_state();
   endfunction : new

   // UVM callback: the commit FIFO, counted in rising edges. A word is handled one edge after the edge that
   // accepted it, so the FIFO holds it one edge less than the pipeline of the DUT.
   function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      commit_fifo = hexk_delay_analysis_fifo#(hexk_ref_commit_item)::type_id::create("commit_fifo", this);
      commit_fifo.latency_cycles = PIPE_DEPTH - 1;
      commit_fifo.set_clock(edge_seen);
   endfunction : build_phase

   // UVM callback: applies every commit to the RAM model when the FIFO releases it, and hands it on.
   task run_phase(uvm_phase phase);
      hexk_ref_commit_item item;
      super.run_phase(phase);
      forever begin
         commit_fifo.get(item);
         commit_word(item);
         commit_ap.write(item);
      end
   endtask : run_phase

   // A reset of the DUT: the pipeline, the partial packet and the configuration are gone; the RAM keeps
   // its content.
   function void on_reset();
      commit_fifo.flush();
      reset_state();
   endfunction : on_reset

   // Input agent: a word was accepted at this edge; it is handled at the next one.
   function void write_ref_word(int index, word_item_t item);
      accepted_words.push_back('{data: item.data, at_ps: hexk_wait_util::now_ps()});
      num_words++;
   endfunction : write_ref_word

   // Input agent: one rising edge. Everything of the edge before has arrived by now, and the DUT accepts at most
   // one word per edge: a word not yet handled was accepted at that edge, number edges. It is handled first.
   function void write_ref_cycle(int index, hexk_handshake_cycle_t cycle);
      longint unsigned now_ps = hexk_wait_util::now_ps();
      accepted_word_t  word;
      while (accepted_words.size() != 0 && accepted_words[0].at_ps < now_ps) begin
         word = accepted_words.pop_front();
         apply_writes_before(word.at_ps);
         process_word(word.data, edges);
      end
      apply_writes_before(now_ps);
      edges++;
      ->edge_seen;
   endfunction : write_ref_cycle

   // Bus monitor: an access that the DUT took. A register write counts for the words accepted after it; an
   // access of the MEM window is applied to the RAM model and, for a read, checked.
   function void write_ref_bus(int index, hexk_ref_bus_item item);
      // A register access is progress too: a test of registers alone gives the watchdog its heartbeats this way.
      if (watchdog != null) begin
         watchdog.heartbeat("bus");
      end
      if (item.addr >= hexk_ref_regs::MEM_BASE) begin
         apply_writes_before(item.taken_ps + 1);
         mem_access(item);
      end else if (item.we) begin
         pending_writes.push_back(item);
      end
   endfunction : write_ref_bus

   // hexk_objectable: busy while a packet is partly received or a word is not yet committed.
   virtual function bit is_busy();
      return current != null || accepted_words.size() != 0 || packets.size() != 0 || commit_fifo.is_busy();
   endfunction : is_busy

   // hexk_objectable: why it is busy.
   virtual function string busy_reason();
      if (current != null) begin
         return $sformatf("packet %0d has %0d words", packet_number + 1, packets[$].len);
      end
      if (packets.size() != 0) begin
         return $sformatf("%0d packets wait for commits", packets.size());
      end
      return commit_fifo.busy_reason();
   endfunction : busy_reason

   // The decoder of the library gives known data for a known code word. The prediction keeps two-state values, in
   // which an X would pass as 0, so it is checked here.
   local function void check_decoded(bit [38:0] code, hexk_core_pkg::hexk_bits_t decoded);
      `hexk_check(!$isunknown(decoded[31:0]), "REF_PRED_DECODE", $sformatf(
                  "hexk_ecc decoded the code word 39'h%010h to data with X or Z bits", code))
   endfunction : check_decoded

   // An error that the test put into the RAM by itself (by HDL access): the code word of a word changes.
   function void inject(int unsigned word, bit [38:0] mask);
      hexk_core_pkg::hexk_bits_t decoded;
      int unsigned               syndrome;
      raw[word%hexk_ref_regs::MEM_WORDS] ^= mask;
      void'(ecc.decode(raw[word%hexk_ref_regs::MEM_WORDS], decoded, syndrome));
      check_decoded(raw[word%hexk_ref_regs::MEM_WORDS], decoded);
      mem.write(8'(4 * (word % hexk_ref_regs::MEM_WORDS)), 32'(decoded));
   endfunction : inject

   // 1 when the word of the RAM was written at least once, so that its content is known.
   function bit is_known(int unsigned word);
      return mem.is_written(8'(4 * (word % hexk_ref_regs::MEM_WORDS)));
   endfunction : is_known

   // The code word that the RAM holds at a word, as the DUT should hold it.
   function bit [38:0] expected_code(int unsigned word);
      return raw[word%hexk_ref_regs::MEM_WORDS];
   endfunction : expected_code

   // The data that a read of a word of the RAM returns now, as the DUT should return it (without CORRUPT_READ).
   function bit [31:0] expected_word(int unsigned word);
      return 32'(mem.read(8'(4 * (word % hexk_ref_regs::MEM_WORDS))));
   endfunction : expected_word

   // Forgets the configuration and everything in flight, as a reset of the DUT does; the RAM stays.
   local function void reset_state();
      scramble      = 0;
      len_field     = 4;
      base          = 0;
      corrupt_read  = 0;
      inj_mask      = 0;
      inj_armed     = 0;
      irq_en        = 0;
      current       = null;
      packet_number = 0;
      corrected     = 0;
      uncorrectable = 0;
      pending_writes.delete();
      accepted_words.delete();
      packets.delete();
   endfunction : reset_state

   // Applies the register writes that the DUT took before a time.
   local function void apply_writes_before(longint unsigned time_ps);
      while (pending_writes.size() != 0 && pending_writes[0].taken_ps < time_ps) begin
         register_write(pending_writes.pop_front());
      end
   endfunction : apply_writes_before

   // One accepted word: CRC, scrambling, code word into the commit FIFO and, at the end of a packet, the packet. As in
   // the DUT, the configuration counts as it is at each word: a packet ends at the word that reaches LEN as it is then.
   local function void process_word(bit [31:0] data, longint unsigned at_edge);
      hexk_ref_commit_item        commit;
      bit                  [31:0] stored;
      bit                  [15:0] state;
      bit                  [ 4:0] len_now = (len_field == 0) ? 5'd16 : {1'b0, len_field};
      if (current == null) begin
         current    = hexk_ref_result::type_id::create("current");
         first_edge = at_edge;
         next_addr  = base;
         word_index = 0;
         crc.reset();
         lfsr.set_state(LFSR_SEED);
         cov_scramble = scramble;
         cov_irq      = irq_en;
         // Its first commits may come before its last word: they are counted against it from now on.
         packets.push_back('{result: current, first_addr: base, len: 0, uncommitted: 0, received: 0});
      end
      for (int unsigned b = 0; b < 4; b++) begin
         crc.update_byte(data[8*b+:8]);
      end
      state       = 16'(lfsr.next());
      stored      = scramble ? (data ^ {state, state}) : data;
      commit      = hexk_ref_commit_item::type_id::create("commit");
      commit.addr = next_addr;
      commit.code = 39'(ecc.encode(stored));
      void'(commit_fifo.try_put(commit));
      next_addr++;
      packets[$].len++;
      packets[$].uncommitted++;
      if (word_index + 5'd1 == len_now) begin
         packet_received(at_edge);
      end else begin
         word_index++;
      end
   endfunction : process_word

   // The last word of a packet was accepted: its number, CRC and cycles are known; its words when it is committed.
   local function void packet_received(longint unsigned last_edge);
      packet_number++;
      current.number      = 8'(packet_number);
      current.crc         = 32'(crc.get());
      // Committed PIPE_DEPTH edges after the last word, DONE one edge later.
      current.cycles      = 16'(last_edge - first_edge + PIPE_DEPTH + 1);
      packets[$].received = 1;
      cov_len             = packets[$].len;
      current             = null;
      if (packet_cg != null) begin
         packet_cg.sample();
      end
   endfunction : packet_received

   // A word reaches the RAM: an armed injection changes its code word; the oldest packet is complete when its last
   // word came and all its words are committed.
   local function void commit_word(hexk_ref_commit_item commit);
      hexk_core_pkg::hexk_bits_t decoded;
      int unsigned               syndrome;
      apply_writes_before(hexk_wait_util::now_ps());
      if (inj_armed) begin
         commit.code ^= inj_mask;
         inj_armed = 0;
      end
      raw[commit.addr] = commit.code;
      void'(ecc.decode(commit.code, decoded, syndrome));
      check_decoded(commit.code, decoded);
      mem.write(8'(4 * commit.addr), 32'(decoded));
      if (packets.size() != 0) begin
         packets[0].uncommitted--;
         if (packets[0].received && packets[0].uncommitted == 0) begin
            packet_completed(packets.pop_front());
         end
      end
   endfunction : commit_word

   // The last word of a packet is committed: the result gets the words that the RAM now holds; a heartbeat.
   local function void packet_completed(packet_t packet);
      for (int unsigned i = 0; i < packet.len; i++) begin
         packet.result.words.push_back(expected_word(packet.first_addr + i));
      end
      last_result = packet.result;
      num_packets++;
      if (publish_results) begin
         result_ap.write(hexk_ref_meta_result_t::wrap(packet.result, "predictor", uids.new_child("packet")));
      end
      if (watchdog != null) begin
         watchdog.heartbeat("predictor");
      end
   endfunction : packet_completed

   // A register write: the configuration of the DUT changes.
   local function void register_write(hexk_ref_bus_item item);
      bit [31:0] data = item.wdata;
      case (item.addr)
         hexk_ref_regs::CTRL_OFFSET: begin
            if (item.wstrb[0]) begin
               scramble  = data[1];
               irq_en    = data[2];
               len_field = data[7:4];
            end
         end
         hexk_ref_regs::BASE_OFFSET: if (item.wstrb[0]) base = data[5:0];
         hexk_ref_regs::DEBUG_OFFSET: if (item.wstrb[0]) corrupt_read = data[0];
         hexk_ref_regs::INJ_LO_OFFSET: begin
            for (int unsigned b = 0; b < 4; b++) begin
               if (item.wstrb[b]) begin
                  inj_mask[8*b+:8] = data[8*b+:8];
               end
            end
         end
         hexk_ref_regs::INJ_HI_OFFSET: if (item.wstrb[0]) inj_mask[38:32] = data[6:0];
         hexk_ref_regs::INJ_CTRL_OFFSET: if (item.wstrb[0]) inj_armed = data[0];
         default: ;
      endcase
   endfunction : register_write

   // An access of the MEM window: the DUT decodes the stored code word, counts what it corrected and,
   // for a write, merges the bytes and encodes the word again.
   local function void mem_access(hexk_ref_bus_item item);
      int unsigned                      word = (item.addr - hexk_ref_regs::MEM_BASE) / 4;
      bit                        [31:0] data;
      hexk_ecc::status_e                ecc_status;
      int unsigned                      syndrome;
      hexk_core_pkg::hexk_bits_t        decoded;
      if (!is_known(word)) begin
         if (item.we && item.wstrb == 4'hF) begin
            // A write of the whole word needs nothing of the old one and makes the word known; the DUT decodes the
            // unknown old code word, and an unknown result counts nothing in ERR.
            mem.write(8'(4 * word), item.wdata);
            raw[word] = 39'(ecc.encode(item.wdata));
            return;
         end
         `uvm_error("REF_PRED_UNKNOWN", $sformatf("access of RAM word %0d, which this test never wrote", word))
         return;
      end
      ecc_status = ecc.decode(raw[word], decoded, syndrome);
      check_decoded(raw[word], decoded);
      data = 32'(decoded);
      count(ecc_status);
      if (item.we) begin
         // The RAM model merges the enabled bytes into the corrected word; the code word is that of the result.
         mem.write(8'(4 * word), item.wdata, item.wstrb);
         raw[word] = 39'(ecc.encode(mem.read(8'(4 * word))));
         return;
      end
      `hexk_check_eq(item.rdata, data ^ {31'd0, corrupt_read}, "REF_MEM_READ", $sformatf("read of RAM word %0d", word))
   endfunction : mem_access

   // Counts a decode in the expected error counters, which saturate as the DUT's do.
   local function void count(hexk_ecc::status_e ecc_status);
      if (ecc_status == hexk_ecc::HEXK_ECC_CORRECTED && corrected < 255) begin
         corrected++;
      end
      if (ecc_status == hexk_ecc::HEXK_ECC_UNCORRECTABLE && uncorrectable < 255) begin
         uncorrectable++;
      end
   endfunction : count

endclass : hexk_ref_predictor

`endif  // HEXK_REF_PREDICTOR_SV
