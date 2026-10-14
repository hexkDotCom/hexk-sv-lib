# hexk_uid

## 1. Summary

Hierarchical unique IDs for transactions and other objects created at run time, such as
`seq_wr:000012/item:000003`, numbered per label under their parent.

## 2. When to use / when not to use

Use it to make messages traceable: a scoreboard mismatch that prints the ID of the item says
which item of which sequence failed, and the same ID can be searched for in the driver and
monitor messages. Give a sequence an ID from the pool, and every item it creates a child of
that ID. `hexk_meta_item` carries an ID next to an item, and `hexk_scoreboard` prints it.

Do not use the ID as data that the DUT sees, and do not use it as a key for matching in a
scoreboard: it identifies an object of the testbench, not a transaction on the bus. Do not
build IDs for objects that are never reported; the ID is cheap but not free.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/data/hexk_uid.sv`
- `src/uvm/data/hexk_uid_pool.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/data/hexk_uid.sv`:

```systemverilog
// Creates an ID; use hexk_uid_pool::new_uid() and new_child(), which choose the number.
function new(hexk_uid uid_parent, string uid_label, int unsigned uid_number);
// Creates the next child ID with this label: the children of one ID are numbered per label, from 0.
function hexk_uid new_child(string child_label);
// The text of the ID: the text of the parent, a slash, then "<label>:<number>".
function string convert2string();
// The ID this one was created under; null for a top-level ID.
function hexk_uid get_parent();
// The label of this ID.
function string get_label();
// The number of this ID among the IDs with its label under its parent.
function int unsigned get_number();
// Number of characters of convert2string().
function int unsigned get_length();
// Reports a label with one of the two characters that the text of an ID puts between its parts. Called for the first ID of a label, so that the IDs after it cost nothing.
static function void check_label(string uid_label);
```

From `src/uvm/data/hexk_uid_pool.sv`:

```systemverilog
// Creates the next top-level ID with this label: top-level IDs are numbered per label, from 0.
function hexk_uid new_uid(string label);
```
<!-- HEXK_GEN:END api -->

## 4. Behaviour and invariants

- `hexk_uid_pool::get()` returns the one pool. `new_uid(label)` creates a top-level ID. The
  top-level IDs with one label are numbered 0, 1, 2 and so on in the order of creation;
  every label has its own numbers.
- `new_child(label)` creates an ID below another. The children of one ID are numbered per
  label in the same way. The numbers of different parents do not depend on each other.
- The text of an ID is `<label>:<number>`, with the number padded with zeros to six digits
  and never cut, after the text of its parent and a slash:
  `seq_wr:000012/item:000003`. `convert2string()` builds it on every call; an ID stores only
  its parent, label and number.
- An ID never changes. Two IDs with the same text can only come from two pools, that is from
  before and after `reset_for_test()`, or from a label that holds `:` or `/`.
- A label with `:` or `/`, the two characters that separate the parts of the text, is the
  error `HEXK_UID_LABEL`: the texts of two different IDs could then be equal. The ID is
  created with the label as given. The check is made for the first ID of a label, in the
  pool and under each parent, so that the IDs after it cost nothing.
- `get_length()` is the number of characters of the text, without building it.
- A child whose text would be longer than `max_length` of the pool is the error
  `HEXK_UID_LENGTH`. The ID that `new_child()` returns then has no parent, so that the text
  cannot grow without limit. The usual cause is an object that is reused and takes a child
  of its own old ID each time; it should take a child of the ID of its creator.
- A top-level ID whose text is longer than `max_length` is the error `HEXK_UID_LENGTH` too;
  `new_uid()` still returns it. That takes a label of nearly `max_length` characters, or a
  `max_length` that is too small for the labels in use.
- `hexk_uid_pool::reset_for_test()` replaces the pool by a new one with all numbers at 0.
  It is for unit tests that run several tests in one simulation.
- The constructor of `hexk_uid` is public because the pool needs it; code outside the
  library uses `new_uid()` and `new_child()`.

## 5. Configuration

| Member of `hexk_uid_pool` | Default | Meaning |
|---|---|---|
| `max_length` | 256 | Longest text an ID may have. |

There are no plusargs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_UID_LABEL` | error |  |
| `HEXK_UID_LENGTH` | error |  |
<!-- HEXK_GEN:END emits -->

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_uid/hexk_uid_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uid_example.sv
//
// Minimal use of hexk_uid: two write sequences each take an ID from the pool and give every
// item they create a child of it. A message that prints the ID of an item then says which
// item of which sequence it is, however the two sequences are interleaved.
// Needs UVM and src/uvm/hexk_uvm.f.

module hexk_uid_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_uid;
   import hexk_uvm_pkg::hexk_uid_pool;
   `include "uvm_macros.svh"

   // Stands for a sequence: it has an ID, and its items get children of that ID.
   class hexk_example_sequence;
      hexk_uid uid;

      function new();
         hexk_uid_pool pool = hexk_uid_pool::get();
         uid = pool.new_uid("seq_wr");
      endfunction : new

      // Creates the ID of the next item of this sequence and reports it.
      function void send_item();
         hexk_uid item_uid = uid.new_child("item");
         `uvm_info("EXAMPLE", $sformatf("sending %s", item_uid.convert2string()), UVM_NONE)
      endfunction : send_item
   endclass : hexk_example_sequence

   initial begin
      hexk_example_sequence first;
      hexk_example_sequence second;
      first  = new();
      second = new();
      first.send_item();
      second.send_item();
      first.send_item();
      first.send_item();
      second.send_item();
   end

endmodule : hexk_uid_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **`item.uid = item.uid.new_child("item")` on an item that is reused.** The ID gets one
  level deeper with every use, until `HEXK_UID_LENGTH`. Take the child from the ID of the
  sequence.
- **A new top-level ID per item.** All items are then `item:000000`, `item:000001` and so on
  with no link to their sequence. Use children.
- **A label with a variable part** (the address, the time). The numbers then no longer
  count anything, and the counters of the parent grow with every label. Keep labels to a
  few fixed words; put variable data into the message.
- **Calling `convert2string()` for every item** when no message is printed. Build the text
  where it is reported.
- **Comparing IDs to decide which item came first across sequences.** The numbers are per
  parent and label; use a timestamp for order.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`.
