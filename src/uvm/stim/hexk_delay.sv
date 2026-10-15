// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay.sv
//
// Delay generator: produces the next delay of a driver, a sequence or a monitor according to
// a hexk_delay_cfg, as a plain count. next() returns the count; the caller uses it as clock
// cycles or as a time, or lets wait_cycles() and wait_time() do the waiting. Typical uses:
// back-pressure of a driver, the gap between two items of a sequence, the time a responder
// takes.
// Each hexk_delay draws from a random stream of its own. Its seed is the one given to new(),
// or one that UVM derives from the name and the seed of the simulation, so the delays of one
// instance do not change when other code draws more or fewer random numbers.
// The cfg is read at every call; a change of the cfg takes effect at the next delay. A burst
// of mode HEXK_DELAY_BURSTY that is going on ends when a call finds another mode, other burst
// limits or an illegal cfg.
//
//! @module    hexk_delay
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_DELAY_CFG:error
//! @plusargs  (none)

`ifndef HEXK_DELAY_SV
`define HEXK_DELAY_SV

class hexk_delay;

   local hexk_delay_cfg   delay_cfg;
   local string           label;
   local hexk_rand_stream stream;

   // Mode HEXK_DELAY_BURSTY: whether a burst is going on, and how many delays of 0 it still has.
   local bit              in_burst;
   local int unsigned     burst_left;

   // The burst limits of the cfg when the burst that is going on started.
   local int unsigned     burst_on_min;
   local int unsigned     burst_on_max;
   local int unsigned     burst_off_min;
   local int unsigned     burst_off_max;

   // The value of the knob perf_mode, once it has been read.
   local bit              perf_known;
   local bit              perf_mode;

   // Set when an illegal cfg has been reported, so that it is reported once.
   local bit              cfg_reported;

   // Creates a generator for cfg; name is used for messages and for the seed, which is derived when seed is 0.
   function new(hexk_delay_cfg cfg, string name, int unsigned seed = 0);
      delay_cfg = cfg;
      label     = name;
      stream    = new(name);
      stream.seed((seed != 0) ? seed : uvm_create_random_seed("hexk_delay", name));
      if (cfg == null) begin
         `uvm_error("HEXK_DELAY_CFG", $sformatf("%s: the cfg is null; every delay is 0", name))
         cfg_reported = 1;
      end
   endfunction : new

   // The next delay as a count without a unit: clock cycles, or a number of time steps.
   function int unsigned next();
      int              drawn;
      longint unsigned weights_total;
      if (!is_usable(weights_total)) begin
         in_burst = 0;
         return 0;
      end
      if (is_perf_mode()) begin
         return 0;
      end
      if (in_burst && !burst_is_current()) begin
         in_burst = 0;
      end
      case (delay_cfg.mode)
         HEXK_DELAY_CONSTANT: return delay_cfg.fixed_value;
         HEXK_DELAY_UNIFORM:  return 32'(stream.uniform(longint'(delay_cfg.lo), longint'(delay_cfg.hi)));
         HEXK_DELAY_NORMAL: begin
            drawn = stream.normal(int'(delay_cfg.mean), int'(delay_cfg.std_dev));
            return (drawn < 0) ? 0 : $unsigned(drawn);
         end
         HEXK_DELAY_EXPONENTIAL: begin
            if (delay_cfg.mean == 0) begin
               return 0;
            end
            drawn = stream.exponential(int'(delay_cfg.mean));
            return (drawn < 0) ? 0 : $unsigned(drawn);
         end
         HEXK_DELAY_BURSTY: begin
            if (!in_burst) begin
               in_burst      = 1;
               burst_on_min  = delay_cfg.burst_on_min;
               burst_on_max  = delay_cfg.burst_on_max;
               burst_off_min = delay_cfg.burst_off_min;
               burst_off_max = delay_cfg.burst_off_max;
               burst_left    = draw(delay_cfg.burst_on_min, delay_cfg.burst_on_max);
            end
            if (burst_left != 0) begin
               burst_left--;
               return 0;
            end
            in_burst = 0;
            return draw(delay_cfg.burst_off_min, delay_cfg.burst_off_max);
         end
         HEXK_DELAY_WEIGHTED: return draw_weighted(weights_total);
         default:             return 0;
      endcase
   endfunction : next

   // Waits for next() triggers of the event; with a delay of 0 it returns at once.
   task wait_cycles(event clk);
      repeat (next()) begin
         @(clk);
      end
   endtask : wait_cycles

   // Waits for next() times unit_ps picoseconds; with a delay of 0 it returns at once.
   task wait_time(longint unsigned unit_ps);
      longint unsigned count = 64'(next());
      // A product past the largest number is the largest number, which hexk_wait_util never reaches.
      hexk_wait_util::wait_ps((unit_ps != 0 && count > ~64'd0 / unit_ps) ? ~64'd0 : count * unit_ps);
   endtask : wait_time

   // The name of the generator and the settings of its cfg, on one line.
   function string convert2string();
      return {label, ": ", (delay_cfg == null) ? "no cfg" : delay_cfg.convert2string()};
   endfunction : convert2string

   // 1 when there is a cfg and it is legal; an illegal cfg is reported once. In mode HEXK_DELAY_WEIGHTED it also
   // gives the sum of the weights: the cfg is legal when it is above 0, so one pass checks and adds them.
   local function bit is_usable(output longint unsigned weights_total);
      string reason;
      weights_total = 0;
      if (delay_cfg == null) begin
         return 0;
      end
      if (delay_cfg.mode == HEXK_DELAY_WEIGHTED) begin
         weights_total = delay_cfg.total_weight();
      end
      if (weights_total == 0) begin
         reason = delay_cfg.illegal_reason();
      end
      if (reason.len() == 0) begin
         cfg_reported = 0;
         return 1;
      end
      if (!cfg_reported) begin
         `uvm_error("HEXK_DELAY_CFG", $sformatf("%s: %s (%s); every delay is 0 until the cfg is legal", label, reason,
                                                delay_cfg.convert2string()))
         cfg_reported = 1;
      end
      return 0;
   endfunction : is_usable

   // 1 when the cfg still has the mode and the burst limits that the burst going on started with.
   local function bit burst_is_current();
      return delay_cfg.mode == HEXK_DELAY_BURSTY && delay_cfg.burst_on_min == burst_on_min &&
          delay_cfg.burst_on_max == burst_on_max && delay_cfg.burst_off_min == burst_off_min &&
          delay_cfg.burst_off_max == burst_off_max;
   endfunction : burst_is_current

   // 1 when the cfg honours the knob perf_mode and that knob exists and is set.
   local function bit is_perf_mode();
      hexk_knobs knobs;
      if (!delay_cfg.honor_perf_knob) begin
         return 0;
      end
      if (!perf_known) begin
         knobs = hexk_knobs::get();
         // Knobs are final once they can be read, so the value is read once.
         if (knobs.has("perf_mode")) begin
            perf_mode  = knobs.get_bit("perf_mode");
            perf_known = 1;
         end
      end
      return perf_mode;
   endfunction : is_perf_mode

   // A value uniformly distributed over lo to hi.
   local function int unsigned draw(int unsigned lo, int unsigned hi);
      return 32'(stream.uniform(longint'(lo), longint'(hi)));
   endfunction : draw

   // A value of delay_cfg.weights, picked with a probability proportional to its weight. The weights are read
   // in place, in the order of the values; total is their sum, which is_usable() found above 0.
   local function int unsigned draw_weighted(longint unsigned total);
      longint unsigned drawn;
      longint unsigned weight;
      drawn = $unsigned(stream.uniform(0, longint'(total - 1)));
      foreach (delay_cfg.weights[value]) begin
         weight = $unsigned(longint'(delay_cfg.weights[value]));
         if (drawn < weight) begin
            return value;
         end
         drawn -= weight;
      end
      return 0;
   endfunction : draw_weighted

endclass : hexk_delay

`endif  // HEXK_DELAY_SV
