// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_analysis_fifo.sv
//
// Analysis FIFO whose items become visible some time after they were written: it models the
// latency of a pipeline between a monitor and whatever reads the FIFO, for example a
// predictor that must see an input only when the DUT has it at its output stage.
// write() never blocks and never waits; the item is kept aside and enters the FIFO when its
// delay is over. The delay is latency_ps picoseconds, or latency_cycles triggers of the event
// given with set_clock(), not counting a trigger in the time step of the write. Items leave
// in the order in which they were written.
// It is a uvm_tlm_analysis_fifo in every other respect: connect analysis_export, read with
// get() or the get/peek exports. It implements hexk_objectable, so that it can be
// registered with hexk_objection_aggregator and no item is lost at the end of a phase: it is
// busy while an item waits for the end of its delay or is visible and not yet read.
//
//! @module    hexk_delay_analysis_fifo
//! @since     0.7.0
//! @stability experimental
//! @serves    OBJ-2
//! @emits     HEXK_DELAY_FIFO_CLOCK:error
//! @plusargs  (none)

`ifndef HEXK_DELAY_ANALYSIS_FIFO_SV
`define HEXK_DELAY_ANALYSIS_FIFO_SV

class hexk_delay_analysis_fifo #(
    type T = int
) extends uvm_tlm_analysis_fifo #(T) implements hexk_objectable;

   // Time in picoseconds after which a written item becomes visible; used for an item when latency_cycles is 0.
   longint unsigned       latency_ps          = 0;

   // Number of clock events after which a written item becomes visible; 0 selects latency_ps.
   int unsigned           latency_cycles      = 0;

   // The items that are not visible yet, oldest first, when each was written, and when it
   // becomes visible: at a time in picoseconds, or at a count of clock events.
   local T                waiting_items  [$];
   local longint unsigned written_times  [$];
   local bit              waits_for_cycle[$];
   local longint unsigned due_times      [$];
   local longint unsigned due_cycles     [$];

   // The clock event, whether one was given, and how many of its triggers have been seen.
   // The count has 64 bits: with any latency_cycles, the count at which an item is due does not wrap.
   local event            clock;
   local bit              has_clock;
   local longint unsigned cycle_count;

   // Triggered when an item was written, and when a clock event was counted.
   local event            item_written;
   local event            cycle_counted;

   // Incremented by flush(), so that the releasing thread drops the item it was waiting for,
   // and the event that ends that wait.
   local int unsigned     flush_count;
   local event            flushed;

   // Set when the missing clock has been reported, so that it is reported once.
   local bit              clock_reported;

   `uvm_component_param_utils(hexk_delay_analysis_fifo#(T))

   // Creates the FIFO; without a latency it behaves like uvm_tlm_analysis_fifo.
   function new(string name, uvm_component parent = null);
      super.new(name, parent);
   endfunction : new

   // Gives the event whose triggers count as cycles for latency_cycles.
   function void set_clock(event clock_event);
      clock     = clock_event;
      has_clock = 1;
   endfunction : set_clock

   // Number of items that were written and are not visible yet.
   function int unsigned num_in_flight();
      return waiting_items.size();
   endfunction : num_in_flight

   // UVM FIFO method behind write() and put(): keeps the item aside until its delay is over.
   virtual function bit try_put(input T t);
      bit              by_cycles = (latency_cycles != 0);
      longint unsigned delay_ps = by_cycles ? 0 : latency_ps;
      if (by_cycles && !has_clock) begin
         if (!clock_reported) begin
            `uvm_error("HEXK_DELAY_FIFO_CLOCK",
                       $sformatf(
                           "latency_cycles is %0d, but no clock was given with set_clock(); items are not delayed",
                           latency_cycles))
            clock_reported = 1;
         end
         by_cycles = 0;
      end
      // No delay and nothing ahead in the queue: the item is visible at once.
      if (!by_cycles && delay_ps == 0 && waiting_items.size() == 0) begin
         return super.try_put(t);
      end
      waiting_items.push_back(t);
      written_times.push_back($time);
      waits_for_cycle.push_back(by_cycles);
      due_times.push_back($time + delay_ps);
      due_cycles.push_back(cycle_count + 64'(latency_cycles));
      ->item_written;
      return 1;
   endfunction : try_put

   // UVM FIFO method: as try_put(). UVM's own put() goes to the FIFO directly; the FIFO has no size limit, so
   // this one never waits either.
   virtual task put(input T t);
      void'(try_put(t));
   endtask : put

   // UVM FIFO method: empties the FIFO and drops the items that are not visible yet.
   virtual function void flush();
      waiting_items.delete();
      written_times.delete();
      waits_for_cycle.delete();
      due_times.delete();
      due_cycles.delete();
      flush_count++;
      ->flushed;
      super.flush();
   endfunction : flush

   // hexk_objectable: 1 while items are waiting for the end of their delay or are visible and not yet read.
   virtual function bit is_busy();
      return waiting_items.size() != 0 || used() != 0;
   endfunction : is_busy

   // hexk_objectable: how many items are waiting and how many are visible and not yet read.
   virtual function string busy_reason();
      return $sformatf(
          "%0d items are waiting for the end of their delay, %0d are visible and not yet read",
          waiting_items.size(),
          used()
      );
   endfunction : busy_reason

   // UVM callback: counts the clock events and moves the items into the FIFO when their delay is over.
   task run_phase(uvm_phase phase);
      fork
         count_cycles();
         release_items();
      join
   endtask : run_phase

   // Counts the triggers of the clock event.
   // A trigger in the time step of a write must not count for that item, whichever of the two the simulator
   // runs first. An item written after this thread ran starts from the new count. An item written before it,
   // in this time step, started from the old one: its count is moved on by one here.
   local task count_cycles();
      wait (has_clock);
      forever begin
         @(clock);
         cycle_count++;
         // The newest items are at the end of the queue.
         for (int i = waiting_items.size() - 1; i >= 0; i--) begin
            if (written_times[i] != $time) begin
               break;
            end
            if (waits_for_cycle[i]) begin
               due_cycles[i]++;
            end
         end
         ->cycle_counted;
      end
   endtask : count_cycles

   // Waits for the delay of the oldest item, then makes it visible; one item after the other, in order.
   // A flush ends the wait at once, so that an item written after it does not wait for the delay of a dropped one.
   local task release_items();
      int unsigned flushes;
      T            item;
      forever begin
         while (waiting_items.size() == 0) begin
            @(item_written);
         end
         flushes = flush_count;
         if (waits_for_cycle[0]) begin
            while (flushes == flush_count && cycle_count < due_cycles[0]) begin
               @(cycle_counted or flushed);
            end
         end else if ($time < due_times[0]) begin
            // This thread has no other children, so "disable fork" ends only the branch that lost.
            fork
               #(due_times[0] - $time);
               @(flushed);
            join_any
            disable fork;
         end
         // A flush during the wait removed the item.
         if (flushes != flush_count) begin
            continue;
         end
         item = waiting_items.pop_front();
         void'(written_times.pop_front());
         void'(waits_for_cycle.pop_front());
         void'(due_times.pop_front());
         void'(due_cycles.pop_front());
         void'(super.try_put(item));
      end
   endtask : release_items

endclass : hexk_delay_analysis_fifo

`endif  // HEXK_DELAY_ANALYSIS_FIFO_SV
