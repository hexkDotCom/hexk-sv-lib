// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_sb_stream.sv
//
// Storage of one stream of a hexk_scoreboard: the expected and the actual items that wait
// for their partner, per key and oldest first, with the latency stamp of each expected item
// (the time from which its latency counts, given by the scoreboard's get_timestamp_ps()), and
// the statistics of the stream. Internal to hexk_scoreboard, which decides
// what is stored and taken and does all reporting. An entry of a key is removed when its
// last item is taken, so that a scoreboard with a new key per item does not grow.
// A stream that is created without keys holds all items in one queue per side and ignores
// the key arguments: the storage of mode HEXK_SB_IN_ORDER, where a KEY of any type must do,
// also a four-state one whose value without an assignment is X and cannot index an array.
// A stream created with track_waits also keeps the waiting items in the order of their
// writes, with a serial number per item, so that the scoreboard finds the item that has
// waited longest (cfg.max_wait_ps) without a search over all keys.
//
//! @module    hexk_scoreboard
//! @since     0.7.0
//! @stability experimental
//! @serves    CHK-4
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_SB_STREAM_SV
`define HEXK_SB_STREAM_SV

class hexk_sb_stream #(
    type T   = uvm_sequence_item,
    type KEY = int
);

   // Counters of this stream.
   hexk_sb_stats stats;

   // The entries of taken items in the order of the writes are dropped when there are more entries than
   // COMPACT_FACTOR times the waiting items plus COMPACT_SLACK: the entries stay a bounded multiple of the waiting
   // items, and the slack keeps a stream with few items from compacting at every write.
   localparam int unsigned COMPACT_FACTOR = 2;
   localparam int unsigned COMPACT_SLACK = 32;

   // Number of expected and of actual items that are waiting.
   int unsigned num_expected;
   int unsigned num_actual;

   // Set while the stream is above max_outstanding and that has been reported.
   bit outstanding_reported;

   // A waiting item: the item, its latency stamp (the time in picoseconds from which its latency counts; expected
   // items only) and its serial number in the order of the writes (only with track_waits).
   typedef struct {
      T                item;
      longint unsigned stamp_ps;
      longint unsigned serial;
   } entry_t;

   // One write of a stored item: its serial number, the time of the write in picoseconds, its key and its side.
   typedef struct {
      longint unsigned serial;
      longint unsigned written_ps;
      KEY              key;
      bit              is_actual;
   } write_t;

   // 1 when the items are stored per key; 0 when one queue per side holds them all.
   local bit              keyed;

   // The waiting items of a stream with keys, oldest first under each key; their serial numbers grow from the
   // oldest item to the newest.
   local entry_t          expected_by_key[KEY] [$];
   local entry_t          actual_by_key  [KEY] [$];

   // The waiting items of a stream without keys, oldest first.
   local entry_t          expected_queue [  $];
   local entry_t          actual_queue   [  $];

   // 1 when the waiting items are also kept in the order of their writes.
   local bit              track_waits;

   // Serial number of the next item that is stored.
   local longint unsigned next_serial;

   // Every stored item in the order of the writes. The entry of an item that was taken stays until it reaches the
   // front, where oldest_wait() drops it, or until drop_taken_entries().
   local write_t          writes         [  $];

   // Creates an empty stream; without use_keys the key arguments of all functions are ignored. With keep_order
   // the stream keeps the order of the writes for oldest_wait().
   function new(bit use_keys = 1, bit keep_order = 0);
      stats       = new();
      keyed       = use_keys;
      track_waits = keep_order;
   endfunction : new

   // Number of expected items that wait under this key.
   function int unsigned num_expected_for(KEY key);
      if (!keyed) begin
         return expected_queue.size();
      end
      return expected_by_key.exists(key) ? expected_by_key[key].size() : 0;
   endfunction : num_expected_for

   // Number of actual items that wait under this key.
   function int unsigned num_actual_for(KEY key);
      if (!keyed) begin
         return actual_queue.size();
      end
      return actual_by_key.exists(key) ? actual_by_key[key].size() : 0;
   endfunction : num_actual_for

   // The waiting expected item at a position under a key, without taking it.
   function T peek_expected(KEY key, int unsigned position);
      return keyed ? expected_by_key[key][position].item : expected_queue[position].item;
   endfunction : peek_expected

   // The waiting actual item at a position under a key, without taking it.
   function T peek_actual(KEY key, int unsigned position);
      return keyed ? actual_by_key[key][position].item : actual_queue[position].item;
   endfunction : peek_actual

   // Adds an expected item as the newest one under its key, with its latency stamp in picoseconds.
   function void store_expected(KEY key, T item, longint unsigned stamp_ps);
      entry_t entry;
      num_expected++;
      entry.item     = item;
      entry.stamp_ps = stamp_ps;
      entry.serial   = track_waits ? note_write(key, 0) : 0;
      if (!keyed) begin
         expected_queue.push_back(entry);
         return;
      end
      if (!expected_by_key.exists(key)) begin
         expected_by_key[key] = {};
      end
      expected_by_key[key].push_back(entry);
   endfunction : store_expected

   // Adds an actual item as the newest one under its key.
   function void store_actual(KEY key, T item);
      entry_t entry;
      num_actual++;
      entry.item   = item;
      entry.serial = track_waits ? note_write(key, 1) : 0;
      if (!keyed) begin
         actual_queue.push_back(entry);
         return;
      end
      if (!actual_by_key.exists(key)) begin
         actual_by_key[key] = {};
      end
      actual_by_key[key].push_back(entry);
   endfunction : store_actual

   // Removes and returns the expected item at a position under a key, with its latency stamp in picoseconds.
   function T take_expected(KEY key, int unsigned position, output longint unsigned stamp_ps);
      entry_t entry;
      num_expected--;
      if (!keyed) begin
         entry = expected_queue[position];
         expected_queue.delete(position);
      end else begin
         entry = expected_by_key[key][position];
         expected_by_key[key].delete(position);
         if (expected_by_key[key].size() == 0) begin
            expected_by_key.delete(key);
         end
      end
      stamp_ps = entry.stamp_ps;
      return entry.item;
   endfunction : take_expected

   // Removes and returns the actual item at a position under a key.
   function T take_actual(KEY key, int unsigned position);
      entry_t entry;
      num_actual--;
      if (!keyed) begin
         entry = actual_queue[position];
         actual_queue.delete(position);
      end else begin
         entry = actual_by_key[key][position];
         actual_by_key[key].delete(position);
         if (actual_by_key[key].size() == 0) begin
            actual_by_key.delete(key);
         end
      end
      return entry.item;
   endfunction : take_actual

   // Drops every waiting item and returns how many there were.
   function int unsigned clear();
      int unsigned count = num_expected + num_actual;
      expected_by_key.delete();
      actual_by_key.delete();
      expected_queue.delete();
      actual_queue.delete();
      writes.delete();
      num_expected         = 0;
      num_actual           = 0;
      outstanding_reported = 0;
      return count;
   endfunction : clear

   // Collects up to limit waiting expected items and their latency stamps, key by key. It reads only the items it
   // collects.
   function void list_expected(ref T items[$], ref longint unsigned stamps_ps[$], input int unsigned limit);
      int unsigned count;
      foreach (expected_queue[i]) begin
         if (items.size() >= limit) begin
            return;
         end
         items.push_back(expected_queue[i].item);
         stamps_ps.push_back(expected_queue[i].stamp_ps);
      end
      foreach (expected_by_key[key]) begin
         // An index loop and not foreach over the element, for which Verilator 5.046 warns that it may mishandle
         // it (SIDEEFFECT); nothing is copied.
         count = expected_by_key[key].size();
         for (int unsigned i = 0; i < count; i++) begin
            if (items.size() >= limit) begin
               return;
            end
            items.push_back(expected_by_key[key][i].item);
            stamps_ps.push_back(expected_by_key[key][i].stamp_ps);
         end
      end
   endfunction : list_expected

   // Collects up to limit waiting actual items, key by key. It reads only the items it collects.
   function void list_actual(ref T items[$], input int unsigned limit);
      int unsigned count;
      foreach (actual_queue[i]) begin
         if (items.size() >= limit) begin
            return;
         end
         items.push_back(actual_queue[i].item);
      end
      foreach (actual_by_key[key]) begin
         count = actual_by_key[key].size();
         for (int unsigned i = 0; i < count; i++) begin
            if (items.size() >= limit) begin
               return;
            end
            items.push_back(actual_by_key[key][i].item);
         end
      end
   endfunction : list_actual

   // The latency stamp in picoseconds of the oldest waiting expected item, the earliest over the keys; found is 0
   // when none waits.
   function longint unsigned oldest_expected_stamp_ps(output bit found);
      longint unsigned oldest = 0;
      found = 0;
      if (expected_queue.size() != 0) begin
         found = 1;
         return expected_queue[0].stamp_ps;
      end
      foreach (expected_by_key[key]) begin
         if (!found || expected_by_key[key][0].stamp_ps < oldest) begin
            oldest = expected_by_key[key][0].stamp_ps;
            found  = 1;
         end
      end
      return oldest;
   endfunction : oldest_expected_stamp_ps

   // The waiting item that was written first: 1 with its key, side, position under its key and time of the write
   // in picoseconds; 0 when no item waits or the stream was created without track_waits.
   function bit oldest_wait(output KEY key, output bit is_actual, output int unsigned position,
                            output longint unsigned written_ps);
      int found;
      while (writes.size() != 0) begin
         found = position_of(writes[0].key, writes[0].is_actual, writes[0].serial);
         if (found >= 0) begin
            key        = writes[0].key;
            is_actual  = writes[0].is_actual;
            position   = $unsigned(found);
            written_ps = writes[0].written_ps;
            return 1;
         end
         // The item was taken.
         void'(writes.pop_front());
      end
      return 0;
   endfunction : oldest_wait

   // Number of entries in the order of the writes, those of items that were taken included; for tests.
   function int unsigned num_wait_entries();
      return writes.size();
   endfunction : num_wait_entries

   // Notes the write of the item that is stored next in the order of the writes and returns its serial number.
   // The entries of taken items are dropped when they outnumber the waiting items, so that one item that waits for
   // long does not let the entries of all later ones pile up behind it.
   local function longint unsigned note_write(KEY key, bit is_actual);
      write_t entry;
      if (writes.size() > COMPACT_FACTOR * (num_expected + num_actual) + COMPACT_SLACK) begin
         drop_taken_entries();
      end
      entry.serial     = next_serial++;
      entry.written_ps = $time;
      entry.key        = key;
      entry.is_actual  = is_actual;
      writes.push_back(entry);
      return entry.serial;
   endfunction : note_write

   // Keeps only the entries of the order of the writes whose items still wait. The serial numbers of the waiting
   // items are collected first, so that the cost grows with the number of entries and not with its square.
   local function void drop_taken_entries();
      bit     waiting[longint unsigned];
      write_t kept   [$];
      foreach (expected_queue[i]) begin
         waiting[expected_queue[i].serial] = 1;
      end
      foreach (actual_queue[i]) begin
         waiting[actual_queue[i].serial] = 1;
      end
      foreach (expected_by_key[key]) begin
         // An index loop and not foreach over the element, as in list_expected().
         for (int unsigned i = 0; i < expected_by_key[key].size(); i++) begin
            waiting[expected_by_key[key][i].serial] = 1;
         end
      end
      foreach (actual_by_key[key]) begin
         for (int unsigned i = 0; i < actual_by_key[key].size(); i++) begin
            waiting[actual_by_key[key][i].serial] = 1;
         end
      end
      foreach (writes[i]) begin
         if (waiting.exists(writes[i].serial)) begin
            kept.push_back(writes[i]);
         end
      end
      writes = kept;
   endfunction : drop_taken_entries

   // Position under its key of the waiting item with this serial number, or -1 when it was taken. The serial
   // numbers under a key grow, so the search stops at the first one that is not smaller: in the modes that take
   // the oldest item first, that is the first one.
   local function int position_of(KEY key, bit is_actual, longint unsigned serial);
      int unsigned     count = is_actual ? num_actual_for(key) : num_expected_for(key);
      longint unsigned here;
      for (int unsigned i = 0; i < count; i++) begin
         here = serial_at(key, is_actual, i);
         if (here >= serial) begin
            return (here == serial) ? int'(i) : -1;
         end
      end
      return -1;
   endfunction : position_of

   // Serial number of the waiting item at a position under a key, on the actual or the expected side.
   local function longint unsigned serial_at(KEY key, bit is_actual, int unsigned position);
      if (!keyed) begin
         return is_actual ? actual_queue[position].serial : expected_queue[position].serial;
      end
      return is_actual ? actual_by_key[key][position].serial : expected_by_key[key][position].serial;
   endfunction : serial_at

endclass : hexk_sb_stream

`endif  // HEXK_SB_STREAM_SV
