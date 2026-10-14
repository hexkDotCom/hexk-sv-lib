# hexk_meta_item

## 1. Summary

An item together with what the testbench knows about it: the time it was seen, its unique ID
and where it came from.

## 2. When to use / when not to use

Use it where the receiver of an item needs more than the item: a scoreboard that measures
latency needs the time, a message needs an ID, a component with several inputs needs the
source. Wrapping keeps that out of the item class, which then holds only what is on the bus,
and it works for item classes that cannot be changed, such as those of third-party VIP.
`hexk_delay_analysis_fifo` and the latency statistics of `hexk_scoreboard` use it.

Do not use it when the item class is yours and the data belongs to every item anyway, such
as a transaction ID of the protocol; make that a field of the item. Do not use the meta data
to carry results of checks.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/data/hexk_meta_item.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/data/hexk_meta_item.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
virtual function string get_type_name();
// Creates an empty meta item.
function new(string name = "hexk_meta_item");
// Creates a meta item through the factory for the given item, stamped with the current simulation time.
static function hexk_meta_item#(T) wrap(T wrapped_item, string item_source = "", hexk_uid item_uid = null);
// ID, time, source and the text of the item, on one line.
function string convert2string();
// UVM hook of compare(): compares the wrapped items; timestamp, ID and source are not compared.
function bit do_compare(uvm_object rhs, uvm_comparer comparer);
// UVM hook of print() and sprint(): ID, time, source and the item with its own fields.
function void do_print(uvm_printer printer);
// UVM hook of copy() and clone(): the copy refers to the same item and ID.
function void do_copy(uvm_object rhs);
```
<!-- HEXK_GEN:END api -->

`do_compare`, `do_copy` and `do_print` are the UVM hooks behind `compare()`, `copy()`,
`clone()`, `print()` and `sprint()`.

## 4. Behaviour and invariants

- `T` is the class of the item, derived from `uvm_object`. The default is `uvm_object`.
- `wrap(item, source, uid)` creates a meta item through the factory, so a type override
  applies to it; its `timestamp_ps` is the simulation time of the call in picoseconds. The
  item is referred to, not copied.
- `timestamp_ps` is a whole number of picoseconds (`docs/integration.md`, "Times"), so the
  difference of two timestamps is a latency in picoseconds whatever the time unit of the
  scope that reads them; compare it with `hexk_wait_util::now_ps()`, not with `$time`.
- `compare()` compares the two wrapped items with their own `compare()`. Timestamp, ID and
  source are not compared. Two meta items without an item are equal; one with and one
  without are different.
- `convert2string()` is `<id> @<time> from <source>: <item>`. The ID and the source are left
  out when they are not set; an item that is missing prints as `null`.
- `print()` and `sprint()` show `uid`, `timestamp_ps`, `source` and the item with its own
  fields; `get_type_name()` is `hexk_meta_item`, without the parameter.
- `copy()` and `clone()` give a meta item that refers to the same item and the same ID: a
  shallow copy. For an independent item, clone the item itself. The rules for items after
  they are published are in `docs/integration.md`, "Items after they are published".

## 5. Configuration

| Member | Meaning |
|---|---|
| `item` | The wrapped item. |
| `timestamp_ps` | Time in picoseconds at which the item was wrapped; the creator may overwrite it, for example with the time of the first beat. |
| `uid` | `hexk_uid` of the item; may be null. |
| `source` | Where the item came from, such as the full name of the monitor. |

There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | error |  |
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_meta_item/hexk_meta_item_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_meta_item_example.sv
//
// Minimal use of hexk_meta_item: a monitor wraps each packet it sees together with the
// time, an ID and its own name. The receiver compares two meta items, which compares the
// packets, and uses the timestamps for the latency between request and response.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_meta_item_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_meta_item;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   `include "uvm_macros.svh"

   class hexk_example_packet extends uvm_object;
      int unsigned data;

      `uvm_object_utils(hexk_example_packet)

      function new(string name = "hexk_example_packet");
         super.new(name);
      endfunction : new

      function void set_data(int unsigned value);
         data = value;
      endfunction : set_data

      virtual function string convert2string();
         return $sformatf("data=%0d", data);
      endfunction : convert2string

      virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_example_packet other;
         return $cast(other, rhs) && other.data == data;
      endfunction : do_compare
   endclass : hexk_example_packet

   typedef hexk_meta_item#(hexk_example_packet) hexk_example_meta_packet_t;

   // Stands for a monitor: wraps a packet with the time, an ID and a source name.
   function automatic hexk_example_meta_packet_t observe(string monitor, int unsigned data);
      hexk_uid_pool       pool = hexk_uid_pool::get();
      hexk_example_packet packet = hexk_example_packet::type_id::create("packet");
      packet.set_data(data);
      return hexk_example_meta_packet_t::wrap(packet, monitor, pool.new_uid("pkt"));
   endfunction : observe

   initial begin
      hexk_example_meta_packet_t request;
      hexk_example_meta_packet_t response;
      request = observe("env.in_monitor", 42);
      #30ns;
      response = observe("env.out_monitor", 42);
      `uvm_info("EXAMPLE", request.convert2string(), UVM_NONE)
      `uvm_info("EXAMPLE", response.convert2string(), UVM_NONE)
      if (request.compare(response)) begin
         `uvm_info("EXAMPLE", $sformatf("match after %0d ps", response.timestamp_ps - request.timestamp_ps), UVM_NONE)
      end else begin
         `uvm_error("EXAMPLE", "the packets differ")
      end
   end

endmodule : hexk_meta_item_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Wrapping at the receiver.** The timestamp is then the time of reception, and every
  receiver has its own. Wrap where the item is observed, in the monitor.
- **Reusing one meta item for every item.** Receivers that keep the handle see it change.
  Create one per item; it is small.
- **Comparing timestamps with `==` to match items.** Two items seen in the same time step
  are equal, and latency makes equal items differ. Match by the content or by a key.
- **Putting the source into the ID or the ID into the source.** The source says where an
  item was seen, the ID which item it is; an item seen at two places has one ID and two
  sources.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
