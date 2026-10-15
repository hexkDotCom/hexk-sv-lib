// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_csr_util.sv
//
// Register accesses for tests and sequences, for any uvm_reg_block: write and read with the
// status checked, read and check a register or a field, poll until a value is read
// (spin-wait), check the reset value of every readable field of a block, and run the bit-bash
// sequence of UVM. Registers, fields and blocks are excluded from those checks by a glob on
// their full name, through the resources of UVM (REG::<name> with NO_REG_TESTS,
// NO_REG_HW_RESET_TEST or NO_REG_BIT_BASH_TEST), which the register sequences of UVM honour
// as well. One object holds what every access needs: map, parent sequence, path, poll
// interval and time limit. It knows the accesses that are in flight and is a
// hexk_objectable, so an objection aggregator keeps a phase alive while one is.
//
//! @module    hexk_csr_util
//! @since     0.8.0
//! @stability experimental
//! @emits     HEXK_CSR_STATUS:error HEXK_CSR_NULL:error HEXK_CSR_RESET:error HEXK_CSR_RESET_DONE:info
//! @plusargs  (none)

`ifndef HEXK_CSR_UTIL_SV
`define HEXK_CSR_UTIL_SV

// The checks that a register, a field or a block can be excluded from.
typedef enum bit [1:0] {
   // The reset value check: check_reset_values() and uvm_reg_hw_reset_seq of UVM.
   HEXK_CSR_RESET_CHECK,
   // The bit-bash sequence of UVM, which bit_bash() runs.
   HEXK_CSR_BIT_BASH,
   // Every register test, of this class and of UVM.
   HEXK_CSR_ALL_CHECKS
} hexk_csr_check_e;

class hexk_csr_util extends uvm_object implements hexk_objectable;

   // Largest number of reads of a spin-wait in one time step; more means that time cannot pass. Small: a read
   // of UVM runs zero delays, and Verilator stops a simulation after 100 of them in one time step.
   localparam int unsigned MAX_READS_PER_STEP = 20;

   // The map of the accesses; null takes the default map of each register.
   uvm_reg_map            map;

   // The sequence the accesses belong to, for their priority and their messages; null for none.
   uvm_sequence_base      parent;

   // The path of the accesses; UVM_DEFAULT_PATH takes that of the register block.
   uvm_path_e             path                         = UVM_DEFAULT_PATH;

   // The component whose name the messages carry; null reports through the top of UVM.
   uvm_component          reporter;

   // Picoseconds between two reads of a spin-wait; 0 reads again as soon as a read is done.
   longint unsigned       poll_interval_ps             = 0;

   // Longest time in picoseconds that a spin-wait polls; 0 means no limit.
   longint unsigned       timeout_ps                   = 1_000_000_000;

   // Kind of reset whose values check_reset_values() expects.
   string                 reset_kind                   = "HARD";

   // The accesses in flight by serial number: what, and since when.
   local string           in_flight[longint unsigned];

   // Serial number of the next access.
   local longint unsigned next_serial;

   `uvm_object_utils(hexk_csr_util)

   // Creates the object with the defaults: default map, no parent sequence, default path.
   function new(string name = "hexk_csr_util");
      super.new(name);
   endfunction : new

   // Writes a register; a status other than UVM_IS_OK is the error HEXK_CSR_STATUS.
   task write(uvm_reg rg, uvm_reg_data_t value);
      uvm_status_e     status;
      longint unsigned serial;
      if (rg == null) begin
         report_null("write", "register");
         return;
      end
      serial = start_access("write of", rg.get_full_name());
      rg.write(status, value, path, map, parent);
      finish_access(serial);
      void'(status_ok(status, "write", rg.get_full_name()));
   endtask : write

   // Reads a register; a status other than UVM_IS_OK is the error HEXK_CSR_STATUS, and value is then what UVM gave.
   task read(uvm_reg rg, output uvm_reg_data_t value);
      bit ok;
      value = 0;
      if (rg == null) begin
         report_null("read", "register");
         return;
      end
      read_reg(rg, value, ok);
   endtask : read

   // Writes a field the way UVM writes a field: alone where the map allows it, otherwise read, change, write.
   task write_field(uvm_reg_field field, uvm_reg_data_t value);
      uvm_status_e     status;
      longint unsigned serial;
      if (field == null) begin
         report_null("write_field", "field");
         return;
      end
      serial = start_access("write of", field.get_full_name());
      field.write(status, value, path, map, parent);
      finish_access(serial);
      void'(status_ok(status, "write", field.get_full_name()));
   endtask : write_field

   // Reads the register of a field and gives the value of the field.
   task read_field(uvm_reg_field field, output uvm_reg_data_t value);
      bit ok;
      value = 0;
      if (field == null) begin
         report_null("read_field", "field");
         return;
      end
      read_reg(field.get_parent(), value, ok);
      value = field_value(field, value);
   endtask : read_field

   // Reads a register and checks the bits of mask against exp; a difference is an error with the caller's ID.
   // Counted in hexk_check_stats under that ID; a failed access counts as a failed check.
   task read_check(uvm_reg rg, uvm_reg_data_t exp, string id, uvm_reg_data_t mask = '1);
      uvm_reg_data_t value;
      bit            ok;
      if (rg == null) begin
         report_null("read_check", "register");
         hexk_check_stats::record_fail(id);
         return;
      end
      read_reg(rg, value, ok);
      if (ok && (value & mask) == (exp & mask)) begin
         hexk_check_stats::record_pass(id);
         return;
      end
      hexk_check_stats::record_fail(id);
      if (ok) begin
         report(UVM_ERROR, id, $sformatf(
                "%s: read 'h%0h, expected 'h%0h%s", rg.get_full_name(), value, exp, mask_text(mask)));
      end
   endtask : read_check

   // Reads the register of a field and checks the field against exp; a difference is an error with the caller's
   // ID. Counted in hexk_check_stats under that ID.
   task read_field_check(uvm_reg_field field, uvm_reg_data_t exp, string id);
      uvm_reg_data_t value;
      bit            ok;
      if (field == null) begin
         report_null("read_field_check", "field");
         hexk_check_stats::record_fail(id);
         return;
      end
      read_reg(field.get_parent(), value, ok);
      value = field_value(field, value);
      if (ok && value == exp) begin
         hexk_check_stats::record_pass(id);
         return;
      end
      hexk_check_stats::record_fail(id);
      if (ok) begin
         report(UVM_ERROR, id, $sformatf("%s: read 'h%0h, expected 'h%0h", field.get_full_name(), value, exp));
      end
   endtask : read_field_check

   // Reads a register until the bits of mask equal those of exp; seen is 1 when they did. After timeout_ps
   // without that, or when time does not pass between the reads, it is an error with the caller's ID.
   task spinwait(uvm_reg rg, uvm_reg_data_t exp, uvm_reg_data_t mask, string id, output bit seen);
      seen = 0;
      if (rg == null) begin
         report_null("spinwait", "register");
         return;
      end
      poll(rg, exp & mask, mask, 0, rg.get_full_name(), id, seen);
   endtask : spinwait

   // Reads the register of a field until the field equals exp; seen is 1 when it did. As spinwait(). A value that
   // does not fit the field can never be read: an error with the caller's ID at once, without a read.
   task spinwait_field(uvm_reg_field field, uvm_reg_data_t exp, string id, output bit seen);
      uvm_reg_data_t mask;
      seen = 0;
      if (field == null) begin
         report_null("spinwait_field", "field");
         return;
      end
      if (field_value(field, exp << field.get_lsb_pos()) != exp) begin
         report(UVM_ERROR, id, $sformatf(
                "%s: 'h%0h does not fit the %0d bits of the field", field.get_full_name(), exp, field.get_n_bits()));
         return;
      end
      mask = field_value(field, '1) << field.get_lsb_pos();
      poll(field.get_parent(), (exp << field.get_lsb_pos()) & mask, mask, field.get_lsb_pos(), field.get_full_name(),
           id, seen);
   endtask : spinwait_field

   // Reads every register of a block and of its sub-blocks once and compares each field whose reset value can be
   // read back with that value: one error HEXK_CSR_RESET per register with the wrong fields, then the summary
   // HEXK_CSR_RESET_DONE. Left out: excluded registers, fields and blocks, registers that are not in the map,
   // and fields that have no reset value, are volatile, cannot be read or have no check.
   task check_reset_values(uvm_reg_block blk);
      uvm_reg      regs        [$];
      bit          was_checked;
      bit          was_wrong;
      int unsigned checked;
      int unsigned wrong;
      int unsigned left_out;
      if (blk == null) begin
         report_null("check_reset_values", "block");
         return;
      end
      blk.get_registers(regs);
      foreach (regs[i]) begin
         check_reset_of(regs[i], blk, was_checked, was_wrong);
         if (was_checked) begin
            checked++;
            wrong += was_wrong;
         end else begin
            left_out++;
         end
      end
      report(UVM_INFO, "HEXK_CSR_RESET_DONE", $sformatf(
             "%s: %0d registers checked, %0d with a wrong reset value, %0d left out",
             blk.get_full_name(),
             checked,
             wrong,
             left_out
             ), UVM_LOW);
   endtask : check_reset_values

   // Runs the bit-bash sequence of UVM on a block, in the sequence parent; it honours the exclusions and reports
   // under its own ID.
   task bit_bash(uvm_reg_block blk);
      uvm_reg_bit_bash_seq bit_bash_seq;
      longint unsigned     serial;
      if (blk == null) begin
         report_null("bit_bash", "block");
         return;
      end
      bit_bash_seq       = uvm_reg_bit_bash_seq::type_id::create("bit_bash_seq");
      bit_bash_seq.model = blk;
      serial             = start_access("bit-bash of", blk.get_full_name());
      bit_bash_seq.start(null, parent);
      finish_access(serial);
   endtask : bit_bash

   // Excludes the registers, fields and blocks whose full name matches the glob from a check; also from the
   // register sequences of UVM, which look at the same resources.
   static function void exclude (string pattern, hexk_csr_check_e check = HEXK_CSR_ALL_CHECKS);
      uvm_resource_db#(bit)::set({"REG::", pattern}, resource_name(check), 1);
      // All checks also set the resources of the single checks: the reset sequence of UVM 2020 looks at a field for
      // NO_REG_HW_RESET_TEST only.
      if (check == HEXK_CSR_ALL_CHECKS) begin
         uvm_resource_db#(bit)::set({"REG::", pattern}, resource_name(HEXK_CSR_RESET_CHECK), 1);
         uvm_resource_db#(bit)::set({"REG::", pattern}, resource_name(HEXK_CSR_BIT_BASH), 1);
      end
   endfunction : exclude

   // 1 when the register, field or block of this full name is excluded from the check, by exclude() or by a
   // resource of UVM.
   static function bit is_excluded(string full_name, hexk_csr_check_e check);
      string scope = {"REG::", full_name};
      if (uvm_resource_db#(bit)::get_by_name(scope, "NO_REG_TESTS", 0) != null) begin
         return 1;
      end
      return check != HEXK_CSR_ALL_CHECKS && uvm_resource_db#(bit)::get_by_name(scope, resource_name(check), 0) != null;
   endfunction : is_excluded

   // Number of accesses through this object that have started and not ended.
   function int unsigned outstanding();
      return in_flight.size();
   endfunction : outstanding

   // Forgets the accesses in flight, after a reset that killed the sequences that made them.
   function void clear();
      in_flight.delete();
   endfunction : clear

   // hexk_objectable: 1 while an access is in flight.
   virtual function bit is_busy();
      return in_flight.size() != 0;
   endfunction : is_busy

   // hexk_objectable: the accesses in flight, one per line.
   virtual function string busy_reason();
      string lines[$];
      foreach (in_flight[serial]) begin
         lines.push_back(in_flight[serial]);
      end
      return hexk_str::join_str(lines, "\n");
   endfunction : busy_reason

   // Checks the reset value of one register: checked is 0 when it is left out, wrong is 1 when a field differs or
   // the read failed.
   local task check_reset_of(uvm_reg rg, uvm_reg_block top, output bit checked, output bit wrong);
      uvm_reg_field  fields   [$];
      uvm_reg_field  used     [$];
      string         diffs    [$];
      uvm_reg_data_t value;
      uvm_reg_data_t got;
      uvm_reg_data_t expected;
      bit            ok;
      checked = 0;
      wrong   = 0;
      if (!reset_readable_reg(rg, top)) begin
         return;
      end
      rg.get_fields(fields);
      foreach (fields[i]) begin
         if (reset_readable(fields[i])) begin
            used.push_back(fields[i]);
         end
      end
      if (used.size() == 0) begin
         return;
      end
      checked = 1;
      read_reg(rg, value, ok);
      if (!ok) begin
         hexk_check_stats::record_fail("HEXK_CSR_RESET");
         wrong = 1;
         return;
      end
      foreach (used[i]) begin
         got      = field_value(used[i], value);
         expected = used[i].get_reset(reset_kind);
         if (got != expected) begin
            diffs.push_back($sformatf("%s is 'h%0h, reset 'h%0h", used[i].get_name(), got, expected));
         end
      end
      if (diffs.size() == 0) begin
         hexk_check_stats::record_pass("HEXK_CSR_RESET");
         return;
      end
      hexk_check_stats::record_fail("HEXK_CSR_RESET");
      wrong = 1;
      report(UVM_ERROR, "HEXK_CSR_RESET", $sformatf(
             "%s: read 'h%0h; %s", rg.get_full_name(), value, hexk_str::join_str(diffs, "; ")));
   endtask : check_reset_of

   // A spin-wait, which is in flight from its start to its end, also between its reads.
   local task poll(uvm_reg rg, uvm_reg_data_t want, uvm_reg_data_t mask, int unsigned lsb, string name, string id,
                   output bit seen);
      longint unsigned serial = start_access("spin-wait on", name);
      poll_reads(rg, want, mask, lsb, name, id, seen);
      finish_access(serial);
   endtask : poll

   // The reads of a spin-wait: until the bits of mask are want (already masked), the time limit, or a failed read.
   local task poll_reads(uvm_reg rg, uvm_reg_data_t want, uvm_reg_data_t mask, int unsigned lsb, string name, string id,
                         output bit seen);
      uvm_reg_data_t   value;
      bit              ok;
      longint unsigned start_ps = $time;
      longint unsigned before_ps;
      longint unsigned elapsed_ps;
      int unsigned     reads_in_step;
      // A limit after hexk_wait_util::LAST_PS is never reached, as for every wait of the library.
      bit              limited = timeout_ps != 0 && !hexk_wait_util::ends_after_last(timeout_ps, start_ps);
      seen = 0;
      forever begin
         before_ps = $time;
         read_reg(rg, value, ok);
         if (!ok) begin
            return;
         end
         if ((value & mask) == want) begin
            seen = 1;
            return;
         end
         elapsed_ps = $time - start_ps;
         if (limited && elapsed_ps >= timeout_ps) begin
            report(UVM_ERROR, id, $sformatf(
                   "%s: 'h%0h was not read within %0t; the last read gave 'h%0h",
                   name,
                   want >> lsb,
                   timeout_ps,
                   (value & mask) >> lsb
                   ));
            return;
         end
         reads_in_step = ($time == before_ps && poll_interval_ps == 0) ? reads_in_step + 1 : 0;
         if (reads_in_step >= MAX_READS_PER_STEP) begin
            report(UVM_ERROR, id, $sformatf(
                   "%s: %0d reads took no time and poll_interval_ps is 0, so time cannot pass; %s",
                   name,
                   reads_in_step,
                   "give poll_interval_ps a value"
                   ));
            return;
         end
         // The last read comes at the limit, not a poll interval after it.
         if (limited && poll_interval_ps > timeout_ps - elapsed_ps) begin
            hexk_wait_util::wait_ps(timeout_ps - elapsed_ps);
         end else begin
            hexk_wait_util::wait_ps(poll_interval_ps);
         end
      end
   endtask : poll_reads

   // Reads a register with the settings of this object; ok is 0 after a status other than UVM_IS_OK.
   local task read_reg(uvm_reg rg, output uvm_reg_data_t value, output bit ok);
      uvm_status_e     status;
      longint unsigned serial = start_access("read of", rg.get_full_name());
      rg.read(status, value, path, map, parent);
      finish_access(serial);
      ok = status_ok(status, "read", rg.get_full_name());
   endtask : read_reg

   // 1 for UVM_IS_OK; otherwise the error HEXK_CSR_STATUS and 0.
   local function bit status_ok(uvm_status_e status, string kind, string name);
      if (status == UVM_IS_OK) begin
         return 1;
      end
      report(UVM_ERROR, "HEXK_CSR_STATUS", $sformatf("%s of %s: status %s", kind, name, status.name()));
      return 0;
   endfunction : status_ok

   // The error HEXK_CSR_NULL for a null argument.
   local function void report_null(string task_name, string what);
      report(UVM_ERROR, "HEXK_CSR_NULL", $sformatf("%s: the %s is null", task_name, what));
   endfunction : report_null

   // 1 when a register takes part in the reset check of top: it and its blocks up to top are not excluded, it is in
   // the map, and its rights there allow a read.
   local function bit reset_readable_reg(uvm_reg rg, uvm_reg_block top);
      if (is_excluded(rg.get_full_name(), HEXK_CSR_RESET_CHECK) || block_excluded(rg.get_parent(), top)) begin
         return 0;
      end
      if (map != null && !rg.is_in_map(map)) begin
         return 0;
      end
      return rg.get_rights(map) != "WO";
   endfunction : reset_readable_reg

   // 1 when a field takes part in the reset check: it has a reset value of reset_kind, is not volatile, can be
   // read, is compared, and is not excluded.
   local function bit reset_readable(uvm_reg_field field);
      // A variable and not an operand of &&: Verilator 5.046 miscompiles "inside" as an operand of a logical operator.
      bit write_only = field.get_access(map) inside {"WO", "WOC", "WOS", "WO1", "NOACCESS"};
      if (write_only || !field.has_reset(
              reset_kind
          ) || field.is_volatile() || field.get_compare() == UVM_NO_CHECK) begin
         return 0;
      end
      return !is_excluded(field.get_full_name(), HEXK_CSR_RESET_CHECK);
   endfunction : reset_readable

   // 1 when a block from blk up to top is excluded from the reset check.
   local function bit block_excluded(uvm_reg_block blk, uvm_reg_block top);
      while (blk != null) begin
         if (is_excluded(blk.get_full_name(), HEXK_CSR_RESET_CHECK)) begin
            return 1;
         end
         if (blk == top) begin
            return 0;
         end
         blk = blk.get_parent();
      end
      return 0;
   endfunction : block_excluded

   // The bits of a field in a register value, at bit 0.
   local function uvm_reg_data_t field_value(uvm_reg_field field, uvm_reg_data_t value);
      // A field of all UVM_REG_DATA_WIDTH bits shifts the 1 out, and 0 - 1 is then the mask of all bits.
      uvm_reg_data_t ones = (uvm_reg_data_t'(1) << field.get_n_bits()) - 1;
      return (value >> field.get_lsb_pos()) & ones;
   endfunction : field_value

   // " under the mask 'h<mask>", or nothing for a mask of all bits.
   local function string mask_text(uvm_reg_data_t mask);
      return (mask == '1) ? "" : $sformatf(" under the mask 'h%0h", mask);
   endfunction : mask_text

   // Notes an access as in flight and returns its serial number.
   local function longint unsigned start_access(string kind, string name);
      longint unsigned serial = next_serial;
      next_serial       = next_serial + 1;
      in_flight[serial] = $sformatf("%s %s since %0t", kind, name, $time);
      return serial;
   endfunction : start_access

   // Notes that an access has ended.
   local function void finish_access(longint unsigned serial);
      in_flight.delete(serial);
   endfunction : finish_access

   // Reports a message through reporter, or through the top of UVM without one.
   local function void report(uvm_severity severity, string id, string text, int verbosity = UVM_NONE);
      uvm_report_object target = reporter;
      if (target == null) begin
         target = uvm_root::get();
      end
      if (target.uvm_report_enabled(verbosity, severity, id) != 0) begin
         target.uvm_report(severity, id, text, verbosity, `uvm_file, `uvm_line, "", 1);
      end
   endfunction : report

   // The name of the resource of UVM for a check.
   local static function string resource_name(hexk_csr_check_e check);
      case (check)
         HEXK_CSR_RESET_CHECK: return "NO_REG_HW_RESET_TEST";
         HEXK_CSR_BIT_BASH:    return "NO_REG_BIT_BASH_TEST";
         default:              return "NO_REG_TESTS";
      endcase
   endfunction : resource_name

endclass : hexk_csr_util

`endif  // HEXK_CSR_UTIL_SV
