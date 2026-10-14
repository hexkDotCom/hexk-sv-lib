// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_sb_stream.sv
//
// Storage of one stream of a hexk_scoreboard: the expected and the actual items that wait
// for their partner, per key and oldest first, with the time each expected item was
// written, and the statistics of the stream. Internal to hexk_scoreboard, which decides
// what is stored and taken and does all reporting. An entry of a key is removed when its
// last item is taken, so that a scoreboard with a new key per item does not grow.
// A stream that is created without keys holds all items in one queue per side and ignores
// the key arguments: the storage of mode HEXK_SB_IN_ORDER, where a KEY of any type must do,
// also a four-state one whose value without an assignment is X and cannot index an array.
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
   hexk_sb_stats          stats;

   // Number of expected and of actual items that are waiting.
   int unsigned           num_expected;
   int unsigned           num_actual;

   // Set while the stream is above max_outstanding and that has been reported.
   bit                    outstanding_reported;

   // 1 when the items are stored per key; 0 when one queue per side holds them all.
   local bit              keyed;

   // The items of a stream with keys.
   local T                expected_items       [KEY] [$];
   local longint unsigned expected_times       [KEY] [$];
   local T                actual_items         [KEY] [$];

   // The items of a stream without keys.
   local T                expected_queue       [  $];
   local longint unsigned expected_queue_times [  $];
   local T                actual_queue         [  $];

   // Creates an empty stream; without use_keys the key arguments of all functions are ignored.
   function new(bit use_keys = 1);
      stats = new();
      keyed = use_keys;
   endfunction : new

   // Number of expected items that wait under this key.
   function int unsigned num_expected_for(KEY key);
      if (!keyed) begin
         return expected_queue.size();
      end
      return expected_items.exists(key) ? expected_items[key].size() : 0;
   endfunction : num_expected_for

   // Number of actual items that wait under this key.
   function int unsigned num_actual_for(KEY key);
      if (!keyed) begin
         return actual_queue.size();
      end
      return actual_items.exists(key) ? actual_items[key].size() : 0;
   endfunction : num_actual_for

   // The waiting expected item at a position under a key, without taking it.
   function T peek_expected(KEY key, int unsigned position);
      return keyed ? expected_items[key][position] : expected_queue[position];
   endfunction : peek_expected

   // The waiting actual item at a position under a key, without taking it.
   function T peek_actual(KEY key, int unsigned position);
      return keyed ? actual_items[key][position] : actual_queue[position];
   endfunction : peek_actual

   // Adds an expected item as the newest one under its key.
   function void store_expected(KEY key, T item, longint unsigned stamp_ps);
      num_expected++;
      if (!keyed) begin
         expected_queue.push_back(item);
         expected_queue_times.push_back(stamp_ps);
         return;
      end
      if (!expected_items.exists(key)) begin
         expected_items[key] = {};
         expected_times[key] = {};
      end
      expected_items[key].push_back(item);
      expected_times[key].push_back(stamp_ps);
   endfunction : store_expected

   // Adds an actual item as the newest one under its key.
   function void store_actual(KEY key, T item);
      num_actual++;
      if (!keyed) begin
         actual_queue.push_back(item);
         return;
      end
      if (!actual_items.exists(key)) begin
         actual_items[key] = {};
      end
      actual_items[key].push_back(item);
   endfunction : store_actual

   // Removes and returns the expected item at a position under a key, with the time it was written.
   function T take_expected(KEY key, int unsigned position, output longint unsigned stamp_ps);
      T item;
      num_expected--;
      if (!keyed) begin
         item = expected_queue[position];
         stamp_ps = expected_queue_times[position];
         expected_queue.delete(position);
         expected_queue_times.delete(position);
         return item;
      end
      item = expected_items[key][position];
      stamp_ps = expected_times[key][position];
      expected_items[key].delete(position);
      expected_times[key].delete(position);
      if (expected_items[key].size() == 0) begin
         expected_items.delete(key);
         expected_times.delete(key);
      end
      return item;
   endfunction : take_expected

   // Removes and returns the actual item at a position under a key.
   function T take_actual(KEY key, int unsigned position);
      T item;
      num_actual--;
      if (!keyed) begin
         item = actual_queue[position];
         actual_queue.delete(position);
         return item;
      end
      item = actual_items[key][position];
      actual_items[key].delete(position);
      if (actual_items[key].size() == 0) begin
         actual_items.delete(key);
      end
      return item;
   endfunction : take_actual

   // Drops every waiting item and returns how many there were.
   function int unsigned clear();
      int unsigned count = num_expected + num_actual;
      expected_items.delete();
      expected_times.delete();
      actual_items.delete();
      expected_queue.delete();
      expected_queue_times.delete();
      actual_queue.delete();
      num_expected         = 0;
      num_actual           = 0;
      outstanding_reported = 0;
      return count;
   endfunction : clear

   // Collects up to limit waiting expected items and the times they were written, key by key. It reads only the
   // items it collects.
   function void list_expected(ref T items[$], ref longint unsigned stamps_ps[$], input int unsigned limit);
      int unsigned count;
      foreach (expected_queue[i]) begin
         if (items.size() >= limit) begin
            return;
         end
         items.push_back(expected_queue[i]);
         stamps_ps.push_back(expected_queue_times[i]);
      end
      foreach (expected_items[key]) begin
         // An index loop and not foreach over the element, which one tool mishandles; nothing is copied.
         count = expected_items[key].size();
         for (int unsigned i = 0; i < count; i++) begin
            if (items.size() >= limit) begin
               return;
            end
            items.push_back(expected_items[key][i]);
            stamps_ps.push_back(expected_times[key][i]);
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
         items.push_back(actual_queue[i]);
      end
      foreach (actual_items[key]) begin
         count = actual_items[key].size();
         for (int unsigned i = 0; i < count; i++) begin
            if (items.size() >= limit) begin
               return;
            end
            items.push_back(actual_items[key][i]);
         end
      end
   endfunction : list_actual

   // The earliest time in picoseconds at which a waiting expected item was written; found is 0 when none waits.
   function longint unsigned oldest_expected_time_ps(output bit found);
      longint unsigned oldest = 0;
      found = 0;
      if (expected_queue_times.size() != 0) begin
         found = 1;
         return expected_queue_times[0];
      end
      foreach (expected_times[key]) begin
         if (!found || expected_times[key][0] < oldest) begin
            oldest = expected_times[key][0];
            found  = 1;
         end
      end
      return oldest;
   endfunction : oldest_expected_time_ps

endclass : hexk_sb_stream

`endif  // HEXK_SB_STREAM_SV
