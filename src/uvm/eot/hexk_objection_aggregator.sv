// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_objection_aggregator.sv
//
// Component that keeps the run-time phases alive while testbench objects still have work
// outstanding, with one real UVM objection per phase instead of one per object or per item.
// Create one in the base test, hand it to the components that need it, and register every
// object that can be busy. An object either calls raise() when it starts to wait and drop()
// when it is done, or it only implements hexk_objectable::is_busy(): when a phase is ready to
// end, the aggregator asks every registered object, holds the phase while one of them is
// busy and looks again every poll_interval_ps. report_busy() says who is busy and why; it is
// printed when a phase is held back, and hexk_watchdog prints it when a test hangs.
// The aggregator objects on every task phase that is executing: run_phase, and the current
// phase of the UVM run-time schedule (reset, main, ...).
//
//! @module    hexk_objection_aggregator
//! @since     0.7.0
//! @stability experimental
//! @serves    OBJ-2 OBJ-3 OBJ-4
//! @emits     HEXK_OBJECTION_BUSY:info HEXK_OBJECTION_REGISTER:error HEXK_OBJECTION_UNKNOWN:error
//! @emits     HEXK_OBJECTION_IMBALANCE:error HEXK_OBJECTION_POLL:error
//! @plusargs  (none)

`ifndef HEXK_OBJECTION_AGGREGATOR_SV
`define HEXK_OBJECTION_AGGREGATOR_SV

class hexk_objection_aggregator extends uvm_component;

   // Time in picoseconds between two looks at is_busy() while the end of a phase is held back (100 ns).
   longint unsigned            poll_interval_ps                   = 100_000;

   // The registered objects in the order of registration, and the same by object for raise() and drop().
   local hexk_objection_member members         [              $];
   local hexk_objection_member by_obj          [hexk_objectable];

   // Number of raise() calls over all objects that are not matched by a drop() yet.
   local int unsigned          raised_total;

   // A task phase that is executing: whether an objection is held on it, whether a thread is polling for it, and a
   // serial number that tells a polling thread that its phase has ended.
   typedef struct {
      uvm_phase    phase;
      bit          held;
      bit          polling;
      int unsigned serial;
   } active_t;

   // The task phases that are executing.
   local active_t     active      [$];
   local int unsigned last_serial;

   `uvm_component_utils(hexk_objection_aggregator)

   // Creates the aggregator; it does nothing until objects are registered.
   function new(string name, uvm_component parent);
      super.new(name, parent);
   endfunction : new

   // Registers an object under a name for reports; from then on its is_busy() is asked at the end of phases.
   function void register(hexk_objectable obj, string name);
      hexk_objection_member member;
      if (obj == null) begin
         `uvm_error("HEXK_OBJECTION_REGISTER", $sformatf("'%s' is a null handle; not registered", name))
         return;
      end
      if (by_obj.exists(obj)) begin
         `uvm_error("HEXK_OBJECTION_REGISTER", $sformatf("'%s' is already registered as '%s'; not registered again",
                                                         name, by_obj[obj].label))
         return;
      end
      member       = new();
      member.obj   = obj;
      member.label = name;
      members.push_back(member);
      by_obj[obj] = member;
   endfunction : register

   // Says that a registered object has work outstanding; the phases stay alive until the matching drop().
   function void raise(hexk_objectable obj, string why = "");
      hexk_objection_member member = find_member(obj);
      if (member == null) begin
         `uvm_error("HEXK_OBJECTION_UNKNOWN", $sformatf("raise(%s) for an object that is not registered; ignored", why))
         return;
      end
      member.raise_count++;
      member.why = why;
      raised_total++;
      update_objections(member.label, why);
   endfunction : raise

   // Takes back one raise() of a registered object; the phases may end when nothing is raised or busy.
   function void drop(hexk_objectable obj, string why = "");
      hexk_objection_member member = find_member(obj);
      if (member == null) begin
         `uvm_error("HEXK_OBJECTION_UNKNOWN", $sformatf("drop(%s) for an object that is not registered; ignored", why))
         return;
      end
      if (member.raise_count == 0) begin
         `uvm_error("HEXK_OBJECTION_IMBALANCE", $sformatf("%s: drop(%s) without a raise(); ignored", member.label, why))
         return;
      end
      member.raise_count--;
      if (member.raise_count == 0) begin
         member.why = "";
      end
      raised_total--;
      update_objections(member.label, why);
   endfunction : drop

   // Who is busy and why, one line per reason; "nothing is busy" when nobody is.
   function string report_busy();
      string lines  [$];
      string reason;
      foreach (members[i]) begin
         if (members[i].raise_count == 1) begin
            lines.push_back(describe({members[i].label, ": raised"}, members[i].why));
         end else if (members[i].raise_count > 1) begin
            lines.push_back(
                describe($sformatf("%s: raised %0d times", members[i].label, members[i].raise_count), members[i].why));
         end
         if (members[i].obj.is_busy()) begin
            reason = hexk_str::replace(members[i].obj.busy_reason(), "\n", "\n    ");
            lines.push_back(describe({members[i].label, ": busy"}, reason));
         end
      end
      if (lines.size() == 0) begin
         return "nothing is busy";
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : report_busy

   // UVM callback: a task phase starts; objects that are raised keep it alive from the start.
   function void phase_started(uvm_phase phase);
      active_t entry;
      super.phase_started(phase);
      if (!is_task_phase(phase) || find_phase(phase) >= 0) begin
         return;
      end
      last_serial++;
      entry.phase   = phase;
      entry.held    = 0;
      entry.polling = 0;
      entry.serial  = last_serial;
      active.push_back(entry);
      update_objections("raised before the phase started", "");
   endfunction : phase_started

   // UVM callback: nothing objects to the end of the phase any more; busy objects hold it back.
   function void phase_ready_to_end(uvm_phase phase);
      int          index = find_phase(phase);
      int unsigned serial;
      super.phase_ready_to_end(phase);
      if (index < 0 || active[index].polling || !is_any_busy()) begin
         return;
      end
      if (poll_interval_ps == 0) begin
         `uvm_error("HEXK_OBJECTION_POLL", $sformatf("poll_interval_ps is 0; phase '%s' is not held back for:\n%s",
                                                     phase.get_name(), report_busy()))
         return;
      end
      `uvm_info("HEXK_OBJECTION_BUSY", $sformatf(
                "phase '%s' is held back, waiting for:\n%s", phase.get_name(), report_busy()), UVM_LOW)
      if (!active[index].held) begin
         phase.raise_objection(this, "registered objects are busy");
         active[index].held = 1;
      end
      active[index].polling = 1;
      serial                = active[index].serial;
      fork
         hold_until_idle(phase, serial);
      join_none
   endfunction : phase_ready_to_end

   // UVM callback: a task phase has ended, also by a jump, which removes every objection.
   function void phase_ended(uvm_phase phase);
      int index = find_phase(phase);
      super.phase_ended(phase);
      if (index < 0) begin
         return;
      end
      active.delete(index);
   endfunction : phase_ended

   // UVM callback: reports objects whose raise() calls were never matched by drop().
   function void check_phase(uvm_phase phase);
      super.check_phase(phase);
      foreach (members[i]) begin
         if (members[i].raise_count != 0) begin
            `uvm_error("HEXK_OBJECTION_IMBALANCE", $sformatf("%s: %0d raise() without a drop() at the end of the test",
                                                             members[i].label, members[i].raise_count))
         end
      end
   endfunction : check_phase

   // Looks at the busy objects every poll_interval_ps and lets the phase go when none is left.
   local task hold_until_idle(uvm_phase phase, int unsigned serial);
      int index;
      forever begin
         hexk_wait_util::wait_ps(poll_interval_ps);
         index = find_phase(phase);
         // The phase ended meanwhile, by a jump: its objections are gone already.
         if (index < 0 || active[index].serial != serial) begin
            return;
         end
         if (!is_any_busy()) begin
            break;
         end
      end
      active[index].polling = 0;
      if (raised_total == 0) begin
         phase.drop_objection(this, "registered objects are no longer busy");
         active[index].held = 0;
      end
   endtask : hold_until_idle

   // Raises or drops the objection on every executing task phase to match the raise() calls.
   // The description of the objection is "<what>: <detail>"; it is put together only when an objection changes.
   local function void update_objections(string what, string detail);
      bit wanted = raised_total != 0;
      foreach (active[i]) begin
         if (wanted && !active[i].held) begin
            active[i].phase.raise_objection(this, describe(what, detail));
            active[i].held = 1;
         end else if (!wanted && active[i].held && !active[i].polling) begin
            active[i].phase.drop_objection(this, describe(what, detail));
            active[i].held = 0;
         end
      end
   endfunction : update_objections

   // 1 when is_busy() of at least one registered object is 1.
   local function bit is_any_busy();
      foreach (members[i]) begin
         if (members[i].obj.is_busy()) begin
            return 1;
         end
      end
      return 0;
   endfunction : is_any_busy

   // The entry of a registered object, or null.
   local function hexk_objection_member find_member(hexk_objectable obj);
      if (obj == null || !by_obj.exists(obj)) begin
         return null;
      end
      return by_obj[obj];
   endfunction : find_member

   // Index of the phase among the executing task phases, or -1.
   local function int find_phase(uvm_phase phase);
      foreach (active[i]) begin
         if (active[i].phase == phase) begin
            return i;
         end
      end
      return -1;
   endfunction : find_phase

   // 1 for run_phase and the phases of the run-time schedule, which consume time and take objections.
   local function bit is_task_phase(uvm_phase phase);
      uvm_task_phase task_imp;
      return $cast(task_imp, phase.get_imp()) != 0;
   endfunction : is_task_phase

   // "<what>: <detail>", or only <what> when there is no detail.
   local function string describe(string what, string detail);
      if (detail.len() == 0) begin
         return what;
      end
      return {what, ": ", detail};
   endfunction : describe

endclass : hexk_objection_aggregator

`endif  // HEXK_OBJECTION_AGGREGATOR_SV
