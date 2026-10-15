// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_clk_rst_agent_cfg.sv
//
// Configuration of one hexk_clk_rst_agent: the interface, the mode, the clock at the start
// of the run phase and how the reset pin behaves.
// The parent creates it, assigns vif and what it wants different from the defaults, and
// hands it to the agent before the build phase. The agent reads it in the build phase and at
// the start of the run phase; the library never changes it. What changes during the run,
// the reset and the clock that is being driven, is in the status of the agent
// (hexk_clk_rst_status). A copy shares the interface and nothing else.
// All times are whole picoseconds.
//
//! @module    hexk_clk_rst
//! @since     0.7.0
//! @stability experimental
//! @serves    CFG-1 CFG-9 SEQ-13
//! @emits     HEXK_COPY_TYPE:error
//! @plusargs  (none)

`ifndef HEXK_CLK_RST_AGENT_CFG_SV
`define HEXK_CLK_RST_AGENT_CFG_SV

class hexk_clk_rst_agent_cfg extends uvm_object;

   // The clock of a cfg that was not changed: 100 MHz, half of the period high, no jitter.
   localparam longint unsigned DEFAULT_PERIOD_PS = 10_000;
   localparam int unsigned DEFAULT_DUTY_PERCENT = 50;

   // Divisor of the shorter of the high and the low time that gives the largest legal jitter.
   localparam int unsigned JITTER_DIVISOR = 4;

   // Longest period, so that the products of the legal_values_cstr constraint fit 64 bits.
   localparam longint unsigned MAX_PERIOD_PS = 64'h0000_FFFF_FFFF_FFFF;

   // Picoseconds of the period of a clock of 1 MHz.
   localparam real PS_PER_MHZ_PERIOD = 1.0e6;

   // UVM_PASSIVE: the agent has a monitor only and the interface generates nothing.
   uvm_active_passive_enum is_active      = UVM_ACTIVE;

   // The interface of the agent; mandatory.
   virtual hexk_clk_rst_if vif;

   // Period of the clock.
   rand longint unsigned   period_ps      = DEFAULT_PERIOD_PS;

   // Share of the period in which the clock is high, 1 to 99.
   rand int unsigned       duty_percent   = DEFAULT_DUTY_PERCENT;

   // Largest distance of a rising edge from its ideal time.
   rand longint unsigned   jitter_ps      = 0;

   // Time by which the first start of the clock is delayed.
   rand longint unsigned   phase_ps       = 0;

   // 1: the reset is asserted when the pin is 0.
   bit                     rst_active_low = 1;

   // 1: the clock runs from the start of the run phase; 0: it waits for a start sequence.
   bit                     start_clock    = 1;

   // 1: the reset is asserted from the start of the run phase until a reset sequence releases it.
   bit                     reset_at_start = 1;

   // Seed of the jitter; 0 derives one from the name of the agent and the seed of the simulation.
   int unsigned            jitter_seed    = 0;

   // What every legal cfg keeps: exactly the clocks for which illegal_reason() is empty. The high time is
   // period_ps * duty_percent / 100 rounded down, as high_time_ps() gives it, and the low time is the rest of
   // the period. The lines below say "high time >= 1", "jitter <= high time / JITTER_DIVISOR" and
   // "jitter <= low time / JITTER_DIVISOR" without a division; a low time of at least 1 follows from the duty cycle.
   constraint legal_values_cstr {
      period_ps inside {[2 : MAX_PERIOD_PS]};
      duty_percent inside {[1 : 99]};
      period_ps * 64'(duty_percent) >= 64'd100;
      jitter_ps <= period_ps;
      jitter_ps * 64'(JITTER_DIVISOR) * 64'd100 <= period_ps * 64'(duty_percent);
      period_ps * 64'(duty_percent) + jitter_ps * 64'(JITTER_DIVISOR) * 64'd100 < period_ps * 64'd100 + 64'd100;
   }

   // A plain randomize() keeps the clock of a cfg that was not changed; a test overrides what it wants different.
   constraint default_values_cstr {
      soft period_ps == DEFAULT_PERIOD_PS;
      soft duty_percent == DEFAULT_DUTY_PERCENT;
      soft jitter_ps == 0;
      soft phase_ps == 0;
   }

   `uvm_object_utils(hexk_clk_rst_agent_cfg)

   // Creates a cfg for an active agent with a clock of 100 MHz and a reset that is active low.
   function new(string name = "hexk_clk_rst_agent_cfg");
      super.new(name);
   endfunction : new

   // Sets period_ps from a frequency in MHz, rounded to a whole number of picoseconds.
   function void set_freq_mhz(real freq_mhz);
      if (freq_mhz > 0.0) begin
         period_ps = longint'(PS_PER_MHZ_PERIOD / freq_mhz);
      end
   endfunction : set_freq_mhz

   // The frequency in MHz that period_ps stands for; 0 for a period of 0.
   function real get_freq_mhz();
      return (period_ps == 0) ? 0.0 : PS_PER_MHZ_PERIOD / real'(period_ps);
   endfunction : get_freq_mhz

   // The time in picoseconds for which a clock with this period and duty cycle is high.
   static function longint unsigned high_time_ps(longint unsigned clock_period_ps, int unsigned duty);
      return (clock_period_ps * 64'(duty)) / 100;
   endfunction : high_time_ps

   // What is wrong with a period, a duty cycle and a jitter; empty when they make a legal clock.
   static function string clock_illegal_reason(longint unsigned clock_period_ps, int unsigned duty,
                                               longint unsigned clock_jitter_ps);
      longint unsigned high;
      longint unsigned low;
      longint unsigned shorter;
      if (clock_period_ps < 2 || clock_period_ps > MAX_PERIOD_PS) begin
         return $sformatf("period_ps (%0d) is not in 2 to %0d", clock_period_ps, MAX_PERIOD_PS);
      end
      if (duty < 1 || duty > 99) begin
         return $sformatf("duty_percent (%0d) is not in 1 to 99", duty);
      end
      high = high_time_ps(clock_period_ps, duty);
      low  = clock_period_ps - high;
      if (high == 0 || low == 0) begin
         return
             $sformatf("period_ps (%0d) with duty_percent (%0d) leaves no high or no low time", clock_period_ps, duty);
      end
      shorter = (high < low) ? high : low;
      if (clock_jitter_ps > shorter / 64'(JITTER_DIVISOR)) begin
         return $sformatf(
             "jitter_ps (%0d) is above a quarter of the shorter of the high and the low time (%0d)",
             clock_jitter_ps,
             shorter
         );
      end
      return "";
   endfunction : clock_illegal_reason

   // What is wrong with the clock values of this cfg; empty when they are legal.
   function string illegal_reason();
      return clock_illegal_reason(period_ps, duty_percent, jitter_ps);
   endfunction : illegal_reason

   // The mode, the clock and the settings of the reset, on one line.
   function string convert2string();
      string clock = $sformatf(
          "period_ps=%0d duty_percent=%0d jitter_ps=%0d phase_ps=%0d", period_ps, duty_percent, jitter_ps, phase_ps
      );
      return $sformatf(
          "%s %s active_low=%0b start_clock=%0b reset_at_start=%0b",
          is_active.name(),
          clock,
          rst_active_low,
          start_clock,
          reset_at_start
      );
   endfunction : convert2string

   // UVM hook of copy() and clone(): copies every member; the copy shares the interface.
   function void do_copy(uvm_object rhs);
      hexk_clk_rst_agent_cfg other;
      super.do_copy(rhs);
      if (!$cast(other, rhs)) begin
         `uvm_error("HEXK_COPY_TYPE", $sformatf("%s cannot copy from %s, which is a %s", get_type_name(),
                                                rhs.get_name(), rhs.get_type_name()))
         return;
      end
      is_active      = other.is_active;
      vif            = other.vif;
      period_ps      = other.period_ps;
      duty_percent   = other.duty_percent;
      jitter_ps      = other.jitter_ps;
      phase_ps       = other.phase_ps;
      rst_active_low = other.rst_active_low;
      start_clock    = other.start_clock;
      reset_at_start = other.reset_at_start;
      jitter_seed    = other.jitter_seed;
   endfunction : do_copy

endclass : hexk_clk_rst_agent_cfg

`endif  // HEXK_CLK_RST_AGENT_CFG_SV
