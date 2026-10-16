// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_delay_cfg.sv
//
// Configuration of one hexk_delay: which kind of delays it produces and with which
// parameters. It is a randomizable uvm_object that lives in the cfg tree of the testbench,
// next to the cfg of the agent or sequence whose delays it describes. The same object may
// be given to several hexk_delay objects, which then produce different delays of the same
// kind. Delays are plain counts; the user of hexk_delay decides whether a count is clock
// cycles or a time. Without randomization and without changes the cfg describes uniform
// delays of 0 to 4.
//
//! @module    hexk_delay
//! @since     0.7.0
//! @stability experimental
//! @serves    CFG-3
//! @emits     HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_DELAY_CFG_SV
`define HEXK_DELAY_CFG_SV

// Kind of delays a hexk_delay produces.
typedef enum bit [2:0] {
   // Always 0.
   HEXK_DELAY_NONE,
   // Always fixed_value.
   HEXK_DELAY_CONSTANT,
   // Uniformly distributed over lo to hi.
   HEXK_DELAY_UNIFORM,
   // Normally distributed around mean with std_dev; values below 0 become 0.
   HEXK_DELAY_NORMAL,
   // Exponentially distributed with the given mean.
   HEXK_DELAY_EXPONENTIAL,
   // Bursts of delays of 0, with one longer delay between two bursts.
   HEXK_DELAY_BURSTY,
   // One of the values in weights, picked with a probability proportional to its weight.
   HEXK_DELAY_WEIGHTED
} hexk_delay_mode_e;

class hexk_delay_cfg extends uvm_object;

   // Largest mean and standard deviation: the distribution functions take signed 32-bit values.
   localparam int unsigned MAX_MEAN = 32'h7FFF_FFFF;

   // Kind of delays.
   rand hexk_delay_mode_e mode                   = HEXK_DELAY_UNIFORM;

   // The delay of mode HEXK_DELAY_CONSTANT.
   rand int unsigned      fixed_value            = 1;

   // Smallest and largest delay of mode HEXK_DELAY_UNIFORM.
   rand int unsigned      lo                     = 0;
   rand int unsigned      hi                     = 4;

   // Mean of the modes HEXK_DELAY_NORMAL and HEXK_DELAY_EXPONENTIAL.
   rand int unsigned      mean                   = 2;

   // Standard deviation of mode HEXK_DELAY_NORMAL.
   rand int unsigned      std_dev                = 1;

   // Mode HEXK_DELAY_BURSTY: smallest and largest number of delays of 0 in one burst.
   rand int unsigned      burst_on_min           = 1;
   rand int unsigned      burst_on_max           = 4;

   // Mode HEXK_DELAY_BURSTY: smallest and largest delay between two bursts.
   rand int unsigned      burst_off_min          = 1;
   rand int unsigned      burst_off_max          = 8;

   // Mode HEXK_DELAY_WEIGHTED: weight per delay value; a weight of 0 excludes the value.
   int unsigned           weights[int unsigned];

   // When set, the bit knob perf_mode of hexk_knobs makes every delay 0.
   bit                    honor_perf_knob        = 1;

   `uvm_object_utils(hexk_delay_cfg)

   // What every legal cfg keeps.
   constraint legal_values_cstr {
      lo <= hi;
      burst_on_min <= burst_on_max;
      burst_off_min <= burst_off_max;
      mean <= MAX_MEAN;
      std_dev <= MAX_MEAN;
   }

   // A plain randomize() gives uniform delays of 0 to 4; a test overrides what it wants different.
   constraint default_values_cstr {
      soft mode == HEXK_DELAY_UNIFORM;
      soft fixed_value == 1;
      soft lo == 0;
      soft hi == 4;
      soft mean == 2;
      soft std_dev == 1;
      soft burst_on_min == 1;
      soft burst_on_max == 4;
      soft burst_off_min == 1;
      soft burst_off_max == 8;
   }

   // Creates a cfg for uniform delays of 0 to 4.
   function new(string name = "hexk_delay_cfg");
      super.new(name);
   endfunction : new

   // What is wrong with the values for the current mode; empty when the cfg is legal.
   function string illegal_reason();
      case (mode)
         HEXK_DELAY_NONE, HEXK_DELAY_CONSTANT: ;
         HEXK_DELAY_UNIFORM: begin
            if (lo > hi) begin
               return $sformatf("lo (%0d) is above hi (%0d)", lo, hi);
            end
         end
         HEXK_DELAY_NORMAL, HEXK_DELAY_EXPONENTIAL: begin
            if (mean > MAX_MEAN || std_dev > MAX_MEAN) begin
               return $sformatf("mean (%0d) or std_dev (%0d) is above %0d", mean, std_dev, MAX_MEAN);
            end
         end
         HEXK_DELAY_BURSTY: begin
            if (burst_on_min > burst_on_max) begin
               return $sformatf("burst_on_min (%0d) is above burst_on_max (%0d)", burst_on_min, burst_on_max);
            end
            if (burst_off_min > burst_off_max) begin
               return $sformatf("burst_off_min (%0d) is above burst_off_max (%0d)", burst_off_min, burst_off_max);
            end
         end
         HEXK_DELAY_WEIGHTED: begin
            if (total_weight() == 0) begin
               return "weights has no value with a weight above 0";
            end
         end
         default: return $sformatf("mode (%0d) is not a value of hexk_delay_mode_e", mode);
      endcase
      return "";
   endfunction : illegal_reason

   // Sum of the weights of mode HEXK_DELAY_WEIGHTED, in 64 bits so that it does not wrap; 0 when no value has
   // a weight above 0.
   function longint unsigned total_weight();
      longint unsigned total = 0;
      foreach (weights[value]) begin
         total += 64'(weights[value]);
      end
      return total;
   endfunction : total_weight

   // The mode and the values that the mode uses, on one line.
   function string convert2string();
      string items[$];
      case (mode)
         HEXK_DELAY_CONSTANT:    return $sformatf("mode=%s fixed_value=%0d", mode.name(), fixed_value);
         HEXK_DELAY_UNIFORM:     return $sformatf("mode=%s lo=%0d hi=%0d", mode.name(), lo, hi);
         HEXK_DELAY_NORMAL:      return $sformatf("mode=%s mean=%0d std_dev=%0d", mode.name(), mean, std_dev);
         HEXK_DELAY_EXPONENTIAL: return $sformatf("mode=%s mean=%0d", mode.name(), mean);
         HEXK_DELAY_BURSTY: begin
            return $sformatf(
                "mode=%s burst_on=%0d..%0d burst_off=%0d..%0d",
                mode.name(),
                burst_on_min,
                burst_on_max,
                burst_off_min,
                burst_off_max
            );
         end
         HEXK_DELAY_WEIGHTED: begin
            foreach (weights[value]) begin
               items.push_back($sformatf("%0d:%0d", value, weights[value]));
            end
            return $sformatf("mode=%s weights={%s}", mode.name(), hexk_str::join_str(items, ", "));
         end
         default:                return $sformatf("mode=%s", mode.name());
      endcase
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member.
   function void do_copy(uvm_object rhs);
      hexk_delay_cfg other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      mode            = other.mode;
      fixed_value     = other.fixed_value;
      lo              = other.lo;
      hi              = other.hi;
      mean            = other.mean;
      std_dev         = other.std_dev;
      burst_on_min    = other.burst_on_min;
      burst_on_max    = other.burst_on_max;
      burst_off_min   = other.burst_off_min;
      burst_off_max   = other.burst_off_max;
      weights         = other.weights;
      honor_perf_knob = other.honor_perf_knob;
   endfunction : do_copy

endclass : hexk_delay_cfg

`endif  // HEXK_DELAY_CFG_SV
