// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_busy_group.sv
//
// A named group of hexk_objectable objects, for a wait in the middle of a test: before a
// reset that must lose nothing, before a reconfiguration, after a burst. The test or the
// environment builds a group of the objects that matter for that wait and calls
// wait_idle(), which returns when none of them is busy and, after a time limit, is an error
// with the caller's ID that names who is still busy. The group chooses its members: an
// object that is busy by design at that point (a result that the test has not collected)
// is simply left out. A group is itself a hexk_objectable, so it can be registered with
// hexk_objection_aggregator or put into another group. Seeing the group idle does not stop
// new work: the caller stops its stimulus before the wait.
//
//! @module    hexk_objection_aggregator
//! @since     0.9.0
//! @stability experimental
//! @serves    OBJ-2
//! @emits     HEXK_BUSY_REGISTER:error HEXK_BUSY_POLL:error
//! @plusargs  (none)

`ifndef HEXK_BUSY_GROUP_SV
`define HEXK_BUSY_GROUP_SV

class hexk_busy_group extends uvm_object implements hexk_objectable;

   // Time in picoseconds between two looks at the members while wait_idle() waits (10 ns).
   longint unsigned      poll_interval_ps     = 10_000;

   // The members in the order of registration, with their names.
   local hexk_objectable members         [$];
   local string          labels          [$];

   `uvm_object_utils(hexk_busy_group)

   // Creates an empty group, which is never busy.
   function new(string name = "hexk_busy_group");
      super.new(name);
   endfunction : new

   // Adds an object under a name for the reasons; a null handle, the group itself or a second registration is an error.
   function void register(hexk_objectable obj, string name);
      hexk_objectable self = this;
      if (obj == null) begin
         `uvm_error("HEXK_BUSY_REGISTER", $sformatf("%s: '%s' is a null handle; not added", get_name(), name))
         return;
      end
      if (obj == self) begin
         `uvm_error("HEXK_BUSY_REGISTER", $sformatf("%s: '%s' is the group itself; not added", get_name(), name))
         return;
      end
      foreach (members[i]) begin
         if (members[i] == obj) begin
            `uvm_error("HEXK_BUSY_REGISTER", $sformatf("%s: '%s' is already a member as '%s'; not added again",
                                                       get_name(), name, labels[i]))
            return;
         end
      end
      members.push_back(obj);
      labels.push_back(name);
   endfunction : register

   // Number of members.
   function int unsigned size();
      return members.size();
   endfunction : size

   // 1 while at least one member is busy.
   virtual function bit is_busy();
      foreach (members[i]) begin
         if (members[i].is_busy()) begin
            return 1;
         end
      end
      return 0;
   endfunction : is_busy

   // The busy members, one line "<name>: <reason>" each, a reason of several lines indented; "" when none is busy.
   virtual function string busy_reason();
      string lines[$];
      foreach (members[i]) begin
         if (members[i].is_busy()) begin
            lines.push_back({labels[i], ": ", hexk_str::replace(members[i].busy_reason(), "\n", "\n    ")});
         end
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : busy_reason

   // Waits until no member is busy; idle is 1 when that came. A group that is idle returns at once, without time
   // passing. After timeout_ps without that it is an error with the caller's ID that names the busy members; a
   // timeout_ps of 0 waits without a limit, as does one that would end after hexk_wait_util::LAST_PS. A
   // poll_interval_ps of 0 is the error HEXK_BUSY_POLL, without a wait.
   task wait_idle(longint unsigned timeout_ps, string id, output bit idle);
      longint unsigned start_ps = hexk_wait_util::now_ps();
      longint unsigned elapsed_ps;
      bit              limited = timeout_ps != 0 && !hexk_wait_util::ends_after_last(timeout_ps, start_ps);
      idle = 0;
      forever begin
         if (!is_busy()) begin
            idle = 1;
            return;
         end
         elapsed_ps = hexk_wait_util::now_ps() - start_ps;
         if (limited && elapsed_ps >= timeout_ps) begin
            `uvm_error(id, $sformatf("%s: still busy after %s:\n%s", get_name(), hexk_wait_util::format_ps(timeout_ps),
                                     busy_reason()))
            return;
         end
         if (poll_interval_ps == 0) begin
            `uvm_error("HEXK_BUSY_POLL", $sformatf("%s: poll_interval_ps is 0, so time cannot pass; busy:\n%s",
                                                   get_name(), busy_reason()))
            return;
         end
         // The last look comes at the limit, not a poll interval after it.
         if (limited && poll_interval_ps > timeout_ps - elapsed_ps) begin
            hexk_wait_util::wait_ps(timeout_ps - elapsed_ps);
         end else begin
            hexk_wait_util::wait_ps(poll_interval_ps);
         end
      end
   endtask : wait_idle

endclass : hexk_busy_group

`endif  // HEXK_BUSY_GROUP_SV
