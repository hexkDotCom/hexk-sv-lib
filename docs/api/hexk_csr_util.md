# hexk_csr_util

## 1. Summary

Register accesses for tests and sequences, for any `uvm_reg_block`: write and read with the
status checked, read and check a register or a field, poll until a value is read
(spin-wait), check the reset value of every readable field of a block, run the bit-bash
sequence of UVM, and exclude registers, fields and blocks from these checks by a glob on
their name.

## 2. When to use / when not to use

Use it in tests and sequences that work through a register model: one object holds the map,
the parent sequence, the path and the time limits, so that each access is one line, a
failed access is never missed, and a wrong value is reported with the register, the value
read and the value expected. Use the reset check as the first test of a new block, and
`exclude()` for the registers and fields whose value after reset is not a constant.

Do not use it to generate or describe a register model; it works on the one you have. Do not
use it for memories (`uvm_mem`). Do not use it in place of a predictor: it reads and
writes, it does not keep the mirror of the model in step with the DUT.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/csr/hexk_csr_util.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/csr/hexk_csr_util.sv`:

```systemverilog
// The checks that a register, a field or a block can be excluded from.
typedef enum bit [1:0] { HEXK_CSR_RESET_CHECK, HEXK_CSR_BIT_BASH, HEXK_CSR_ALL_CHECKS } hexk_csr_check_e;
// Creates the object with the defaults: default map, no parent sequence, default path.
function new(string name = "hexk_csr_util");
// Writes a register; a status other than UVM_IS_OK is the error HEXK_CSR_STATUS.
task write(uvm_reg rg, uvm_reg_data_t value);
// Reads a register; a status other than UVM_IS_OK is the error HEXK_CSR_STATUS, and value is then what UVM gave.
task read(uvm_reg rg, output uvm_reg_data_t value);
// Writes a field the way UVM writes a field: alone where the map allows it, otherwise read, change, write.
task write_field(uvm_reg_field field, uvm_reg_data_t value);
// Reads the register of a field and gives the value of the field.
task read_field(uvm_reg_field field, output uvm_reg_data_t value);
// Reads a register and checks the bits of mask against exp; a difference is an error with the caller's ID. Counted in hexk_check_stats under that ID; a failed access counts as a failed check.
task read_check(uvm_reg rg, uvm_reg_data_t exp, string id, uvm_reg_data_t mask = '1);
// Reads the register of a field and checks the field against exp; a difference is an error with the caller's ID. Counted in hexk_check_stats under that ID.
task read_field_check(uvm_reg_field field, uvm_reg_data_t exp, string id);
// Reads a register until the bits of mask equal those of exp; seen is 1 when they did. After timeout_ps without that, or when time does not pass between the reads, it is an error with the caller's ID.
task spinwait(uvm_reg rg, uvm_reg_data_t exp, uvm_reg_data_t mask, string id, output bit seen);
// Reads the register of a field until the field equals exp; seen is 1 when it did. As spinwait(). A value that does not fit the field can never be read: an error with the caller's ID at once, without a read.
task spinwait_field(uvm_reg_field field, uvm_reg_data_t exp, string id, output bit seen);
// Reads every register of a block and of its sub-blocks once and compares each field whose reset value can be read back with that value: one error HEXK_CSR_RESET per register with the wrong fields, then the summary HEXK_CSR_RESET_DONE. Left out: excluded registers, fields and blocks, registers that are not in the map, and fields that have no reset value, are volatile, cannot be read or have no check.
task check_reset_values(uvm_reg_block blk);
// Runs the bit-bash sequence of UVM on a block, in the sequence parent; it honours the exclusions and reports under its own ID.
task bit_bash(uvm_reg_block blk);
// Excludes the registers, fields and blocks whose full name matches the glob from a check; also from the register sequences of UVM, which look at the same resources.
static function void exclude (string pattern, hexk_csr_check_e check = HEXK_CSR_ALL_CHECKS);
// 1 when the register, field or block of this full name is excluded from the check, by exclude() or by a resource of UVM.
static function bit is_excluded(string full_name, hexk_csr_check_e check);
// Number of accesses through this object that have started and not ended.
function int unsigned outstanding();
// Forgets the accesses in flight, after a reset that killed the sequences that made them.
function void clear();
// hexk_objectable: 1 while an access is in flight.
virtual function bit is_busy();
// hexk_objectable: the accesses in flight, one per line.
virtual function string busy_reason();
```
<!-- HEXK_GEN:END api -->

The settings are public members; assign them after `create()`:

```systemverilog
hexk_csr_util csr = hexk_csr_util::type_id::create("csr");
csr.map              = env.regmodel.bus_map;   // null: the default map of each register
csr.parent           = this;                   // in a sequence: the accesses belong to it
csr.poll_interval_ps = `hexk_ps(100ns);
csr.timeout_ps       = `hexk_ps(50us);
```

## 4. Behaviour and invariants

Accesses:

- `write()`, `read()`, `write_field()` and `read_field()` call `write()` and `read()` of UVM
  with `path`, `map` and `parent` of the object. A status other than `UVM_IS_OK` is the error
  `HEXK_CSR_STATUS`, with the register and the status; `read()` then gives what UVM gave.
- `read_field()` reads the whole register and gives the bits of the field at bit 0.
  `write_field()` is `write()` of the UVM field: alone where the map allows that, otherwise
  read-modify-write with the mirror of the other fields, as UVM does it; UVM then reports the
  warning `RegModel` "Individual field access not available".
- A null register, field or block is the error `HEXK_CSR_NULL`, and nothing is accessed.
- The object does not change the mirror of the model itself; the model's own prediction
  does (auto-predict of the map or a predictor).
- With `set_check_on_read(1)` on a map, UVM compares every read through it with the mirror
  itself and reports a difference under its own ID. That comparison knows nothing of the
  masks and exclusions of this object: a masked `read_check()` that passes, or a reset check
  that leaves a field out, can still give such an error. Leave check-on-read off for the maps
  this object reads through, or expect those errors.

Checks:

- `read_check(rg, exp, id, mask)` reads the register and compares the bits of `mask` (all
  bits by default) with those of `exp`. A difference is a UVM error with the caller's `id`:
  `<register>: read 'h<value>, expected 'h<exp>`, followed by ` under the mask 'h<mask>` when
  the mask is not all ones. `read_field_check(field, exp, id)` does the same for a field: the
  field read is compared with all of `exp`, so a value that does not fit the field never
  passes.
- Every check is counted in `hexk_check_stats` under the caller's ID, as passed or failed, as
  the check macros do, so that `hexk_base_test` counts it for its verdict. A failed access
  (`HEXK_CSR_STATUS`) or a null register counts as a failed check; it is not reported a
  second time under the caller's ID.

Spin-waits:

- `spinwait(rg, exp, mask, id, seen)` reads the register until the bits of `mask` equal
  those of `exp`; `seen` is 1 when they did. `spinwait_field(field, exp, id, seen)` does the
  same for a field. The first read comes at once. A value that does not fit the field can
  never be read: `spinwait_field()` reports it at once, as an error with the caller's `id`,
  without a read, and `seen` is 0.
- Between two reads it waits `poll_interval_ps`; with 0 it reads again as soon as a read is
  done. The time of each read is that of the access itself.
- `timeout_ps` (default 1 ms, 0 for no limit) counts from the start of the spin-wait. A
  limit after `hexk_wait_util::LAST_PS` is never reached, as for every wait of the library. When a
  read ends at or after it without the value, the spin-wait gives up with a UVM error with
  the caller's `id`: `<name>: 'h<exp> was not read within <timeout_ps>; the last read gave
  'h<value>`. The poll interval is cut short so that the last read comes at the limit, not a
  poll interval after it.
- When reads take no time and `poll_interval_ps` is 0, time cannot pass and the value cannot
  change. Time is counted in whole picoseconds, so reads shorter than 1 ps count as taking
  no time: after `hexk_csr_util::MAX_READS_PER_STEP` (20) such reads in one time step the
  spin-wait gives up with an error with the caller's `id`. On Verilator 5.046 the zero delays
  inside the reads of UVM end the simulation first (`DIDNOTCONVERGE`): give
  `poll_interval_ps` a value there.
- A failed read (`HEXK_CSR_STATUS`) ends the spin-wait with `seen` 0.
- A spin-wait is not counted in `hexk_check_stats`, like the waits of `hexk_wait_macros`.

Reset check:

- `check_reset_values(blk)` reads every register of the block and of its sub-blocks once,
  through `map` (registers that are not in `map`, or whose rights there are `WO`, are left
  out), and compares each field that
  takes part with its reset value of kind `reset_kind` (default `"HARD"`).
- A field takes part when it has a reset value of that kind, is not volatile, has a check
  (`get_compare()` is not `UVM_NO_CHECK`), can be read (its access is not `WO`, `WOC`, `WOS`,
  `WO1` or `NOACCESS`), and is not excluded. A register without such a field is left out.
- A register, a field or a block from the register up to `blk` that is excluded from
  `HEXK_CSR_RESET_CHECK` or from all checks is left out (see Exclusions).
- Per register with a wrong field: one error `HEXK_CSR_RESET`, `<register>: read 'h<value>;
  <field> is 'h<got>, reset 'h<reset>; ...` with every wrong field. Each register that is
  read counts as one check `HEXK_CSR_RESET` in `hexk_check_stats`; a failed read counts as a
  wrong register.
- At the end the info `HEXK_CSR_RESET_DONE` (`UVM_LOW`): `<block>: <n> registers checked,
  <n> with a wrong reset value, <n> left out`.
- The DUT must be in its reset state; the check does not reset it. Reading a field with a
  read side effect (such as `RC`) has that effect.

Bit-bash:

- `bit_bash(blk)` runs `uvm_reg_bit_bash_seq` of UVM on the block, started on no sequencer
  with `parent` as parent sequence. It writes and reads every bit of every register through
  every map of the register, compares with what the access policy of each field predicts,
  and reports a difference as an error with the ID `uvm_reg_bit_bash_seq`. Those errors are
  not counted in `hexk_check_stats`.
- It honours the exclusions of `HEXK_CSR_BIT_BASH` and of all checks, for registers and
  blocks; UVM looks at no field for this. It leaves out the bits of write-only fields and of
  fields without a check.
- It resets the mirror of the model at the start (`reset()` of UVM), not the DUT; start it
  with the DUT in its reset state, and run it before anything else changes the registers.

Exclusions:

- `hexk_csr_util::exclude(pattern, check)` sets the resource `REG::<pattern>` of UVM with the
  name `NO_REG_HW_RESET_TEST` for `HEXK_CSR_RESET_CHECK`, `NO_REG_BIT_BASH_TEST` for
  `HEXK_CSR_BIT_BASH`, or all three of these and `NO_REG_TESTS` for `HEXK_CSR_ALL_CHECKS`
  (default). The pattern is a glob on the full name of a register, a field or a block, as
  the resources of UVM take it: `"top.regmodel.status"`, `"*.status.errors"`, `"*.debug_*"`.
- The checks of this object leave out every register, field and block that such a resource
  excludes, also one set directly with `uvm_resource_db#(bit)::set()`. The register
  sequences of UVM look at the same resources, but not at all of them:

| Excluded | `check_reset_values()` | `uvm_reg_hw_reset_seq` | `bit_bash()`, `uvm_reg_bit_bash_seq` |
|---|---|---|---|
| a block or a register | left out | left out (UVM 1.2 and 2020) | left out (UVM 1.2 and 2020) |
| a field | left out | left out with UVM 2020; still checked with UVM 1.2 | still bashed |
- `hexk_csr_util::is_excluded(full_name, check)` says whether a name is excluded from a
  check; `NO_REG_TESTS` excludes from every check.
- Exclusions are global, like all resources of UVM, and cannot be taken back.

End of test:

- The object implements `hexk_objectable`: `is_busy()` is 1 while an operation through it is
  in flight, and `busy_reason()` gives one line per operation: `read of <name> since <time>`,
  `write of ...`, `bit-bash of <block> ...`, and `spin-wait on <name> ...`. A spin-wait is in
  flight from its start to its end, also between its reads, beside the read it is doing.
  `outstanding()` gives their number. Register the object with an
  `hexk_objection_aggregator` to keep a phase alive while one is.
- An operation whose process is killed, such as by a reset that kills the sequences, stays
  in flight for the object: call `clear()` then. Avoid killing a register access at all: UVM
  keeps the register locked, and the next access to it waits for ever (UVM reports
  `UVM/REG/ZOMBIE`). With a frontdoor sequence, `reset()` of the model gives the lock back
  but the access still does not complete (seen on Questa and VCS with UVM 2020.3.1). Let
  the accesses of a sequence end before a reset ends the sequence.

Messages:

- They go through `reporter`, a component, so that they carry its name; without one, through
  the top of UVM.

## 5. Configuration

| Member | Default | Meaning |
|---|---|---|
| `map` | null | Map of the accesses; null takes the default map of each register. |
| `parent` | null | Sequence the accesses belong to. |
| `path` | `UVM_DEFAULT_PATH` | Path of the accesses; the default is that of the block. |
| `reporter` | null | Component whose name the messages carry. |
| `poll_interval_ps` | 0 | Picoseconds between two reads of a spin-wait. |
| `timeout_ps` | 1_000_000_000 (1 ms) | Longest time of a spin-wait in picoseconds; 0 for no limit. |
| `reset_kind` | `"HARD"` | Kind of reset whose values `check_reset_values()` expects. |

The times are whole numbers of picoseconds (`docs/integration.md`, "Times"): write
`` `hexk_ps(100ns) `` or `100_000`. There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_CSR_NULL` | error |  |
| `HEXK_CSR_RESET` | error |  |
| `HEXK_CSR_RESET_DONE` | info |  |
| `HEXK_CSR_STATUS` | error |  |
<!-- HEXK_GEN:END emits -->

Besides these, `read_check()`, `read_field_check()` and the spin-waits report errors with the
ID the caller gives, and `bit_bash()` lets UVM report under `uvm_reg_bit_bash_seq`.
`HEXK_CSR_RESET_DONE` has verbosity `UVM_LOW`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_csr_util/hexk_csr_util_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_csr_util_example.sv
//
// Minimal use of hexk_csr_util on a register model with two registers: ctrl with the field
// en, and status with the fields done and an error counter that the example excludes from
// the reset check. The registers reach a register file of this module through a frontdoor
// that takes 10 ns per access, in place of a bus agent; the "DUT" sets done 50 ns after en
// was written. The example checks the reset values, starts the DUT, waits for done with a
// spin-wait and checks status with a mask.
// Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_csr_util_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_csr_util;
   import hexk_uvm_pkg::HEXK_CSR_RESET_CHECK;
   `include "uvm_macros.svh"

   // The register file of the DUT: ctrl at 0, status at 4.
   bit [31:0] dut_regs[int unsigned];

   // Frontdoor of one register: 10 ns per access to the register file.
   class hexk_example_frontdoor extends uvm_reg_frontdoor;
      local int unsigned address;

      `uvm_object_utils(hexk_example_frontdoor)

      function new(string name = "hexk_example_frontdoor");
         super.new(name);
      endfunction : new

      // The address of the register in the register file.
      function void set_address(int unsigned value);
         address = value;
      endfunction : set_address

      virtual task body();
         #10ns;
         if (rw_info.kind == UVM_WRITE) begin
            dut_regs[address] = 32'(rw_info.value[0]);
         end else begin
            rw_info.value[0] = 64'(dut_regs[address]);
         end
         rw_info.status = UVM_IS_OK;
      endtask : body
   endclass : hexk_example_frontdoor

   // A register of 32 bits whose fields the block adds.
   class hexk_example_reg extends uvm_reg;
      `uvm_object_utils(hexk_example_reg)

      function new(string name = "hexk_example_reg");
         super.new(name, 32, UVM_NO_COVERAGE);
      endfunction : new
   endclass : hexk_example_reg

   // ctrl: en (RW, bit 0); status: done (RO, bit 0), errors (RO, bits 15:8, reset 0, counts as the DUT runs).
   class hexk_example_block extends uvm_reg_block;
      hexk_example_reg ctrl;
      hexk_example_reg status;
      uvm_reg_field en;
      uvm_reg_field done;
      uvm_reg_field errors;

      `uvm_object_utils(hexk_example_block)

      function new(string name = "hexk_example_block");
         super.new(name, UVM_NO_COVERAGE);
      endfunction : new

      function void build();
         default_map = create_map("map", 0, 4, UVM_LITTLE_ENDIAN);
         ctrl        = new_reg("ctrl", 0);
         en          = new_field(ctrl, "en", 1, 0, "RW");
         status      = new_reg("status", 4);
         done        = new_field(status, "done", 1, 0, "RO");
         errors      = new_field(status, "errors", 8, 8, "RO");
         lock_model();
         // The frontdoors after lock_model(): UVM warns that a map is not initialized when one is set before.
         ctrl.set_frontdoor(new_frontdoor("ctrl", 0));
         status.set_frontdoor(new_frontdoor("status", 4));
      endfunction : build

      local function hexk_example_reg new_reg(string name, int unsigned address);
         hexk_example_reg rg = hexk_example_reg::type_id::create(name);
         rg.configure(this);
         default_map.add_reg(rg, uvm_reg_addr_t'(address), "RW");
         return rg;
      endfunction : new_reg

      local function hexk_example_frontdoor new_frontdoor(string name, int unsigned address);
         hexk_example_frontdoor fd = hexk_example_frontdoor::type_id::create({"fd_", name});
         fd.set_address(address);
         return fd;
      endfunction : new_frontdoor

      local function uvm_reg_field new_field(hexk_example_reg rg, string name, int unsigned width, int unsigned lsb,
                                             string access);
         uvm_reg_field field = uvm_reg_field::type_id::create(name);
         field.configure(rg, width, lsb, access, 0, 0, 1, 1, 0);
         return field;
      endfunction : new_field
   endclass : hexk_example_block

   hexk_example_block regmodel;
   hexk_csr_util csr;

   // The DUT: done 50 ns after en is set; the error counter of a run that went wrong once.
   initial begin
      dut_regs[0] = 0;
      dut_regs[4] = 'h300;
      wait (dut_regs[0][0] == 1'b1);
      #50ns;
      dut_regs[4][0] = 1'b1;
   end

   initial begin
      bit seen;
      regmodel = hexk_example_block::type_id::create("regmodel");
      regmodel.build();
      csr                  = hexk_csr_util::type_id::create("csr");
      csr.poll_interval_ps = `hexk_ps(20ns);
      csr.timeout_ps       = `hexk_ps(1us);

      // The error counter is no reset value but a count; it does not take part in the reset check.
      hexk_csr_util::exclude ("regmodel.status.errors", HEXK_CSR_RESET_CHECK);
      csr.check_reset_values(regmodel);

      // Start the DUT, wait for done, and check that done is set and en still is.
      csr.write(regmodel.ctrl, 1);
      csr.spinwait_field(regmodel.done, 1, "EXAMPLE_DONE", seen);
      `uvm_info("EXAMPLE", $sformatf("done seen: %0b at %0t", seen, $time), UVM_NONE)
      csr.read_check(regmodel.status, 'h1, "EXAMPLE_STATUS", 'hFF);
      csr.read_field_check(regmodel.en, 1, "EXAMPLE_EN");
   end

endmodule : hexk_csr_util_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`rg.read(status, value)` without a look at `status`.** A bus error then reads as a value.
  Use `read()` or `read_check()`, which report it.
- **A spin-wait without a poll interval on a fast frontdoor or a backdoor.** It reads
  thousands of times per microsecond, or not at all while time does not pass. Give
  `poll_interval_ps` the time the DUT needs to change.
- **A spin-wait with `timeout_ps` 0.** A DUT that never sets the bit then holds the test until
  the watchdog ends it, without saying which register it waited for.
- **The reset check after other accesses.** A field that a test has written no longer holds
  its reset value. Run it first, or after a reset of the DUT.
- **Excluding a whole register for one field that is not constant after reset.** Exclude the
  field: `exclude("*.status.errors", HEXK_CSR_RESET_CHECK)`, and the other fields stay checked.
- **Killing a sequence in the middle of an access.** The register stays unusable in UVM, and
  the object stays busy until `clear()`.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.8.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. On Verilator, the test of a
spin-wait whose reads take no time is left out of the build (see section 4).
