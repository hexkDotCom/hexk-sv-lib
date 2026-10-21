# hexk_scoreboard

## 1. Summary

Generic matcher and checker: pairs every actual item with an expected item, in order, out of
order by key, or in order per key, compares the two, and reports mismatches, unexpected items
and leftovers, with statistics and a latency measurement. Every comparison of a pair counts
as a check in `hexk_check_stats`.

## 2. When to use / when not to use

Use it for end-to-end data checks in an env (guide rules CHK-2 and CHK-3): a predictor or a
reference monitor writes what should come out, the DUT monitor writes what did. Derive a
small class when items are matched by a key or need their own comparison; a plain in-order
check needs no derived class. One scoreboard with several streams serves several independent
channels of the same item type.

Do not use it for protocol checks on signals; those are assertions (CHK-1). Do not use it
where "expected" needs state that only a model has, such as memory contents: the model
predicts, and the scoreboard compares what the model wrote. Do not put the prediction itself
into `compare_items()`. It is not a prediction framework: both sides have the item type `T`,
and `transform_expected()` turns one item into at most one. When the input and the output of
the DUT have different types, or one input gives several outputs, a predictor in front of
the scoreboard writes the expected items of type `T`;
`examples/hexk_scoreboard/hexk_scoreboard_predictor_example.sv` shows one, with the time and
the ID of each request carried in a `hexk_meta_item` and a reset in the middle of the
traffic.

## 3. API

<!-- HEXK_GEN:BEGIN files -->
- `src/uvm/check/hexk_sb_stats.sv`
- `src/uvm/check/hexk_sb_stream.sv`
- `src/uvm/check/hexk_scoreboard.sv`
- `src/uvm/check/hexk_scoreboard_cfg.sv`
<!-- HEXK_GEN:END files -->

<!-- HEXK_GEN:BEGIN api -->
From `src/uvm/check/hexk_sb_stats.sv`:

```systemverilog
// Notes the latency in picoseconds of one matched pair.
function void add_latency_ps(longint unsigned latency_ps);
// Mean latency of the matched pairs in picoseconds, rounded down; 0 when there is none.
function longint unsigned latency_avg_ps();
// Adds the counts of another stream to these.
function void add(hexk_sb_stats other);
// The counts on one line, without the latency.
function string convert2string();
```

From `src/uvm/check/hexk_sb_stream.sv`:

```systemverilog
// Creates an empty stream; without use_keys the key arguments of all functions are ignored. With keep_order the stream keeps the order of the writes for oldest_wait().
function new(bit use_keys = 1, bit keep_order = 0);
// Number of expected items that wait under this key.
function int unsigned num_expected_for(KEY key);
// Number of actual items that wait under this key.
function int unsigned num_actual_for(KEY key);
// The waiting expected item at a position under a key, without taking it.
function T peek_expected(KEY key, int unsigned position);
// The waiting actual item at a position under a key, without taking it.
function T peek_actual(KEY key, int unsigned position);
// Adds an expected item as the newest one under its key, with its latency stamp in picoseconds.
function void store_expected(KEY key, T item, longint unsigned stamp_ps);
// Adds an actual item as the newest one under its key, with the time in picoseconds at which it arrived.
function void store_actual(KEY key, T item, longint unsigned arrived_ps);
// Removes and returns the expected item at a position under a key, with its latency stamp in picoseconds.
function T take_expected(KEY key, int unsigned position, output longint unsigned stamp_ps);
// Removes and returns the actual item at a position under a key, with the time in picoseconds at which it arrived.
function T take_actual(KEY key, int unsigned position, output longint unsigned arrived_ps);
// Drops every waiting item and returns how many there were.
function int unsigned clear();
// Collects up to limit waiting expected items and their latency stamps, key by key. It reads only the items it collects.
function void list_expected(ref T items[$], ref longint unsigned stamps_ps[$], input int unsigned limit);
// Collects up to limit waiting actual items, key by key. It reads only the items it collects.
function void list_actual(ref T items[$], input int unsigned limit);
// The latency stamp in picoseconds of the oldest waiting expected item, the earliest over the keys; found is 0 when none waits.
function longint unsigned oldest_expected_stamp_ps(output bit found);
// The waiting item that was written first: 1 with its key, side, position under its key and time of the write in picoseconds; 0 when no item waits or the stream was created without track_waits.
function bit oldest_wait(output KEY key, output bit is_actual, output int unsigned position, output longint unsigned written_ps);
// Number of entries in the order of the writes, those of items that were taken included; for tests.
function int unsigned num_wait_entries();
```

From `src/uvm/check/hexk_scoreboard.sv`:

```systemverilog
// Name of the class in messages and printouts; without it UVM has none for a class with parameters.
function string get_type_name();
// Creates the scoreboard; streams and exports are created in build_phase.
function new(string name, uvm_component parent);
// UVM callback: takes the cfg that was assigned, else the one in uvm_config_db under "cfg", else one with the defaults; then creates the streams and their exports.
function void build_phase(uvm_phase phase);
// UVM callback: registers with the aggregator when cfg.hold_objection is set.
function void end_of_elaboration_phase(uvm_phase phase);
// UVM callback: with cfg.max_wait_ps, drops every item when it has waited that long for its partner, with an error. It sleeps until the oldest waiting item reaches the limit, or until an item starts to wait.
task run_phase(uvm_phase phase);
// UVM callback: reports the items that were left over on either side, and the summary.
function void check_phase(uvm_phase phase);
// Hook: the key of an item for the modes that match by key; the default gives every item the same key.
virtual function KEY get_key(T item);
// Hook: 1 when the actual item is what the expected item asks for; diff may explain a difference. The default gives in diff what the comparer noted: the fields that differ, for an item whose do_compare() uses it.
virtual function bit compare_items(T exp, T act, output string diff);
// Hook of mode HEXK_SB_OUT_OF_ORDER: 1 when the actual item is the partner of the expected item, both with the same key. The scoreboard pairs an item with the oldest waiting item for which it is 1 and then calls compare_items() on the pair. The default is compare_items(): the partner is an equal item, and that pair is not compared again. Override it to pair by an ID, so that a wrong payload is reported as a mismatch.
virtual function bit is_partner(T exp, T act);
// Hook: turns an item written to an expected export into the item to wait for; null means nothing is expected. It must not change item, which the publisher may keep: return a clone to change it (TLM-5).
virtual function T transform_expected(T item);
// Hook: the time in picoseconds from which the latency of an expected item counts; the default is the time of the write. An override returns a time in picoseconds, such as hexk_meta_item::timestamp_ps.
virtual function longint unsigned get_timestamp_ps(T item);
// Hook: the unique ID of an item for messages; the default is none.
virtual function hexk_uid get_uid(T item);
// Hook: the text of an item in messages; the default is convert2string(), or sprint() for an item without one.
virtual function string item_text(T item);
// Analysis write of an expected export: the item waits for its actual item, or meets one that came early.
function void write_expected_idx(int idx, T t);
// Analysis write of an actual export: the item is compared with the expected item it belongs to.
function void write_actual_idx(int idx, T t);
// Reset of the DUT: drops all waiting items when cfg.flush_on_reset is set.
function void on_reset();
// A copy of the counters of one stream, or of all streams together when stream is below 0; later items do not change it. A stream that does not exist is an error and gives counters that are all 0.
function hexk_sb_stats get_stats(int stream = -1);
// hexk_objectable: 1 while items are waiting and cfg.hold_objection is set.
virtual function bit is_busy();
// hexk_objectable: per stream, how many items are waiting and since when.
virtual function string busy_reason();
```

From `src/uvm/check/hexk_scoreboard_cfg.sv`:

```systemverilog
// How a hexk_scoreboard pairs an actual item with an expected one.
typedef enum bit [1:0] { HEXK_SB_IN_ORDER, HEXK_SB_OUT_OF_ORDER, HEXK_SB_IN_ORDER_PER_KEY } hexk_sb_mode_e;
// Creates a cfg with the defaults.
function new(string name = "hexk_scoreboard_cfg");
// All settings on one line.
function string convert2string();
// UVM hook of copy() and clone(): copies every member.
function void do_copy(uvm_object rhs);
// UVM hook of compare(): compares every member.
function bit do_compare(uvm_object rhs, uvm_comparer comparer);
// UVM hook of print() and sprint(): every member.
function void do_print(uvm_printer printer);
```
<!-- HEXK_GEN:END api -->

`hexk_sb_stream` is internal. `build_phase`, `end_of_elaboration_phase` and `check_phase` are
UVM callbacks; `is_busy` and `busy_reason` implement `hexk_objectable`. The classes
`hexk_analysis_imp_indexed_expected_idx` and `hexk_analysis_imp_indexed_actual_idx` are the
types of the exports.

## 4. Behaviour and invariants

Setting up:

- Type parameters: `T` is the item class, derived from `uvm_object`; `KEY` is the type of
  the key, any type that can index an associative array. In the two keyed modes a key with
  an X or Z bit cannot be stored, which is a rule of the language for the index of an
  associative array: use a two-state type, a string or a class as `KEY`, or make sure that
  `get_key()` returns no such bit. Mode `HEXK_SB_IN_ORDER` does not use `KEY` at all. The
  defaults are `uvm_sequence_item` for `T` and `int` for `KEY`.
- Assign `cfg` before the build phase of the scoreboard, or set it in `uvm_config_db` under
  `"cfg"` for the scoreboard, as for the agents of the library:
  `uvm_config_db#(hexk_scoreboard_cfg)::set(this, "<scoreboard path>", "cfg", cfg)`. An
  assigned cfg comes first; without either, a cfg with the defaults is created. `cfg.mode`, `cfg.num_streams` and `cfg.max_wait_ps` are read in the
  build phase; a later change of them has no effect. The build phase creates `cfg.num_streams` streams and, per stream,
  the exports `expected_exports[i]` and `actual_exports[i]`. `expected_export` and
  `actual_export` are those of stream 0.
- A write to an export of stream `i` calls `write_expected_idx(i, item)` or
  `write_actual_idx(i, item)`. The two functions can also be called directly.
- The scoreboard keeps the items it is given and does not copy them; the writer must not
  change them afterwards (`docs/integration.md`, "Items after they are published").

Three questions are answered apart, each by its own hooks:

- **Identity: which waiting items may be the partner.** Those with the same key,
  `get_key(item)`; in mode `HEXK_SB_IN_ORDER` keys are not used. In mode
  `HEXK_SB_OUT_OF_ORDER` also `is_partner(expected, actual)`.
- **Order: which of them it is.** The mode:

| `cfg.mode` | An actual item is paired with |
|---|---|
| `HEXK_SB_IN_ORDER` | the oldest waiting expected item |
| `HEXK_SB_IN_ORDER_PER_KEY` | the oldest waiting expected item with the same key |
| `HEXK_SB_OUT_OF_ORDER` | the oldest waiting expected item with the same key for which `is_partner()` is 1; if there is none, the oldest with that key, or with `cfg.allow_unexpected` none: the actual item waits |

- **Equality: whether the pair agrees.** `compare_items(expected, actual, diff)`. Equal: the
  pair is counted as matched and its latency is noted. Not equal: the error
  `HEXK_SB_MISMATCH` with both items as `item_text()` prints them, their unique IDs if
  `get_uid()` returns one, and `diff` if it is not empty. Both items are gone after that.
- The default `is_partner()` is `compare_items()`: the partner is an equal item, and the
  pair that the search found equal is not compared again. Override `is_partner()` to pair by
  a transaction ID, with a tolerance, or by any rule that is not equality; then
  `compare_items()` checks the pair it chose, and a wrong payload is a mismatch of the right
  pair instead of a mismatch of the oldest item. Where items arrive in order per transaction
  ID, mode `HEXK_SB_IN_ORDER_PER_KEY` with `get_key()` returning the ID does the same without
  an override: the oldest item of the ID is its partner, compared once.
- So `compare_items()` is called once for the pair that is finished, and with the default
  `is_partner()` also once per candidate that the search looks at. When no candidate is a
  partner, the oldest one is compared, for the mismatch report.
- Every comparison of a pair is recorded in `hexk_check_stats` under the ID
  `HEXK_SB_MISMATCH`, as passed or failed, so a test whose only checker is a scoreboard
  counts checks for the verdict of `hexk_base_test`. An unexpected or a leftover item is no
  comparison and is not recorded.
- The default `compare_items()` uses one `uvm_comparer` per scoreboard for all comparisons;
  `compare()` starts it afresh each time (seen on UVM 1.2 and 2020, also after a mismatch).
  On a mismatch it gives in `diff` what the comparer noted, one line per field that
  differs, such as `expected.data: lhs = 'h5a : rhs = 'h5b` (the same text on UVM 1.2 and
  2020). An item whose `do_compare()` does not use the comparer leaves `diff` empty. The
  items of the library use it.
- **An actual item without an expected item** to pair with is the error
  `HEXK_SB_UNEXPECTED` and is dropped. With `cfg.allow_unexpected` it waits instead, and an
  expected item that is written later is paired with it by the same rules.
- **In mode `HEXK_SB_OUT_OF_ORDER` with `cfg.allow_unexpected`**, an actual item for which no
  waiting expected item is a partner waits for one that comes later, instead of being
  compared with the oldest one with its key: with early actual items allowed, a missing
  partner may still come. So no mismatch is reported in that mode; an item that never gets
  its partner is a leftover, or times out with `cfg.max_wait_ps`.
- **An expected item** is paired with a waiting actual item only when that one is its
  partner (in the two in-order modes: the oldest waiting actual item with its key); otherwise
  it waits. It is never compared with an actual item that is not its partner.
- Waiting items are stored in queues (CHK-4): one per side of a stream in mode
  `HEXK_SB_IN_ORDER`, one per key in the keyed modes.
- Cost per item: in the two in-order modes a constant (one lookup of the key, one queue
  operation, one comparison); in mode `HEXK_SB_OUT_OF_ORDER` up to one `is_partner()` per
  waiting item of the same key, so a key that many items share makes every write slower.
  `make bench` measures both; the numbers are in section 9.

Hooks, all virtual:

| Hook | Default | Purpose |
|---|---|---|
| `get_key(item)` | the same key for every item | the key for the two keyed modes |
| `is_partner(exp, act)` | `compare_items()` | in mode `HEXK_SB_OUT_OF_ORDER`, which waiting item is the partner |
| `compare_items(exp, act, diff)` | `exp.compare(act)`, without messages of the comparer; `diff` is what the comparer noted | what "equal" means; may explain a difference in `diff` |
| `transform_expected(item)` | the item itself | simple prediction: return another item, or null to expect nothing; never change `item` itself, return a clone to change it |
| `get_timestamp_ps(item)` | the time of the write in picoseconds | where the latency of an expected item starts; an override returns picoseconds, such as `timestamp_ps` of a `hexk_meta_item` |
| `get_uid(item)` | null | the `hexk_uid` of an item for messages |
| `item_text(item)` | `item.convert2string()`, or `item.sprint()` when that is empty | how an item is printed |

Limits and reports:

- **Latency** of a matched pair is the time from the timestamp of the expected item
  (`get_timestamp_ps()`) to the arrival of the actual item, in picoseconds: the moment the pair
  is complete, or, when the actual item came first, the moment it arrived. A timestamp after
  that arrival, as the default timestamp of an expected item written after its actual item
  is, gives 0. With
  `cfg.max_latency_ps` above 0, a larger latency is the error `HEXK_SB_LATENCY`; the pair still counts as
  matched. The limit is checked when the pair is complete, not while an item waits.
- **Waiting time.** With `cfg.max_wait_ps` above 0, an item may wait that long for its
  partner, counted from its write to the scoreboard. One picosecond later it is overdue: it
  is the error `HEXK_SB_TIMEOUT`, with the item, and is dropped. It no longer keeps the
  scoreboard busy and is counted as `timed_out`; a partner that comes later is matched like
  any other item, so it is unexpected, or waits itself with `cfg.allow_unexpected`, or meets
  another waiting item. A partner that comes at the limit itself still matches. A time out
  that would come after `hexk_wait_util::LAST_PS` (about 2.56 hours of simulation) never
  comes, as for every wait of the library.
- The limit applies to expected items and, with `cfg.allow_unexpected`, to actual items that
  wait. Each item has its own limit from its own write; the items of a stream time out in the
  order of their writes, over all keys. `run_phase` watches them: it sleeps until the oldest
  waiting item is overdue, or until an item starts to wait, so it costs nothing while no item
  waits. Every write also drops the overdue items of its stream before it is matched, so the
  result does not depend on which of the two runs first in a time step. A derived class that
  overrides `run_phase` calls `super.run_phase(phase)`.
  Without the limit an item that never gets a partner waits until the check phase, where it
  is a leftover; `busy_reason()` shows how long it has waited.
- With `cfg.max_outstanding` above 0, more waiting items in one stream is the error
  `HEXK_SB_OUTSTANDING`, once each time the count goes above the limit.
- The first `cfg.max_errors` errors with items are printed in full; later ones are one line
  without the items, and `item_text()` and `get_uid()` are not called for them. Every error
  is reported and counted. The leftovers of `check_phase` have their own limit,
  `cfg.leftover_print_limit`.
- **`check_phase`** reports, per stream, the expected items that never got an actual item
  and the actual items that never got an expected one (CHK-5), as `HEXK_SB_LEFTOVER` with up
  to `cfg.leftover_print_limit` items each, and then the summary `HEXK_SB_SUMMARY`: the
  counters and the latency of every stream.
- A stream number that does not exist, a write before the build phase, and
  `cfg.num_streams` of 0 are `HEXK_SB_STREAM`.

End of test and reset:

- The scoreboard implements `hexk_objectable`: with `cfg.hold_objection` it is busy while
  any item waits (OBJ-2). In `end_of_elaboration_phase` it registers with the aggregator in
  the member `aggregator`; without one it reports the warning `HEXK_SB_AGGREGATOR` and
  holds nothing. A `hold_objection` set only after the end of elaboration does not register
  it, so it then holds nothing.
- `on_reset()` drops all waiting items of all streams when `cfg.flush_on_reset` is set
  (CHK-6); they are counted as dropped. Call it from the reset handling of the env.

Statistics:

- `get_stats(i)` returns a copy of the counters of stream `i`, `get_stats()` a new object
  with the sum over all streams; later items change neither, so call it again for newer
  counts. A stream
  number of 0 or more that does not exist is the error `HEXK_SB_STREAM` and gives counters
  that are all 0.
  `hexk_sb_stats` has `expected_count`, `actual_count`, `matched`, `mismatched`,
  `unexpected`, `dropped`, `late`, `timed_out`, `leftover_expected`, `leftover_actual`, and
  `latency_min_ps`, `latency_max_ps`, `latency_sum_ps` and `latency_avg_ps()` (rounded down).
  The leftover counts are set in `check_phase`.

## 5. Configuration

The members of `hexk_scoreboard_cfg`:

| Member | Default | Meaning |
|---|---|---|
| `mode` | `HEXK_SB_IN_ORDER` | How items are paired. |
| `num_streams` | 1 | Number of independent stream pairs. |
| `max_errors` | 10 | Errors that are printed with their items. |
| `max_outstanding` | 0 (no limit) | Largest number of waiting items per stream. |
| `max_latency_ps` | 0 (no limit) | Longest latency of a matched pair in picoseconds; checked when the pair is matched. |
| `max_wait_ps` | 0 (no limit) | Longest time in picoseconds an item may wait for its partner; a longer wait is an error and drops the item. |
| `allow_unexpected` | 0 | An actual item may come before its expected item. |
| `hold_objection` | 1 | Busy for the aggregator while items wait. |
| `flush_on_reset` | 1 | `on_reset()` drops the waiting items. |
| `leftover_print_limit` | 20 | Leftover items printed per stream and direction. |
| `clone_expected` | 0 | Keep a clone of an expected item that has to wait instead of its handle. |

`max_latency_ps` and `max_wait_ps` are whole numbers of picoseconds (`docs/integration.md`,
"Times"): write `` `hexk_ps(200ns) `` or `200_000`. There are no plusargs.

`clone_expected` is for a producer that reuses or changes an expected item after writing
it. The scoreboard then clones every expected item that has to wait, at the cost of one
`clone()` per item; an item that is matched at once is not cloned. An actual item is never
cloned. A class that `clone()` cannot create is the error `HEXK_SB_CLONE`, and the item
itself is kept. The clone is as deep as the `do_copy()` of the class: a `hexk_meta_item`
copies the handle of the item it wraps, so its clone still shares that item; a producer that
changes the wrapped item must wrap a clone of it.

`max_latency_ps` is no deadline; `max_wait_ps` is. Without `max_wait_ps`, an expected item
whose actual item never comes is reported only in the check phase, as a leftover, and a
scoreboard that holds the phase through the aggregator keeps it alive while the item waits:
such a test needs `hexk_watchdog`, which ends it and names the scoreboard as busy. With
`max_wait_ps`, the item is reported when its limit has passed and the phase can end. Set
`max_wait_ps` above the longest latency the DUT may have, with a margin; `max_latency_ps`
can then stay 0 or be the tighter limit for the matched pairs.

## 6. Messages emitted

<!-- HEXK_GEN:BEGIN emits -->
| ID | Severity | Meaning |
|---|---|---|
| `HEXK_COPY_TYPE` | fatal |  |
| `HEXK_SB_AGGREGATOR` | warning |  |
| `HEXK_SB_CLONE` | error |  |
| `HEXK_SB_FLUSH` | info |  |
| `HEXK_SB_LATENCY` | error |  |
| `HEXK_SB_LEFTOVER` | error |  |
| `HEXK_SB_MISMATCH` | error |  |
| `HEXK_SB_OUTSTANDING` | error |  |
| `HEXK_SB_STREAM` | error |  |
| `HEXK_SB_SUMMARY` | info |  |
| `HEXK_SB_TIMEOUT` | error |  |
| `HEXK_SB_UNEXPECTED` | error |  |
<!-- HEXK_GEN:END emits -->

`HEXK_SB_SUMMARY` has verbosity `UVM_LOW`, `HEXK_SB_FLUSH` has `UVM_MEDIUM`.

## 7. Minimal example

<!-- HEXK_GEN:BEGIN example -->
`examples/hexk_scoreboard/hexk_scoreboard_example.sv`, elaborated in Gate 1:

```systemverilog
// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_scoreboard_example.sv
//
// Minimal use of hexk_scoreboard: a DUT answers requests out of order, so the scoreboard
// matches by the tag of the response. The class derived from the scoreboard says what the
// key of an item is and how an item is printed; everything else is the cfg. The test writes
// four expected responses, then the actual ones in another order with some delay; the
// scoreboard keeps the run phase alive until the last response has arrived, or reports one
// that is overdue. check_phase prints the summary, and the test checks that four pairs
// matched. Needs UVM and src/uvm/hexk_uvm.f.

`include "hexk_macros.svh"

module hexk_scoreboard_example;
   timeunit 1ns / 1ps;

   import uvm_pkg::*;
   import hexk_uvm_pkg::hexk_scoreboard;
   import hexk_uvm_pkg::hexk_scoreboard_cfg;
   import hexk_uvm_pkg::hexk_sb_stats;
   import hexk_uvm_pkg::hexk_objection_aggregator;
   import hexk_uvm_pkg::HEXK_SB_OUT_OF_ORDER;
   `include "uvm_macros.svh"

   class hexk_example_response extends uvm_sequence_item;
      local int unsigned tag;
      local int unsigned data;

      `uvm_object_utils(hexk_example_response)

      function new(string name = "hexk_example_response");
         super.new(name);
      endfunction : new

      function void set(int unsigned response_tag, int unsigned response_data);
         tag  = response_tag;
         data = response_data;
      endfunction : set

      function int unsigned get_tag();
         return tag;
      endfunction : get_tag

      function string convert2string();
         return $sformatf("tag=%0d data=0x%0h", tag, data);
      endfunction : convert2string

      function bit do_compare(uvm_object rhs, uvm_comparer comparer);
         hexk_example_response other;
         bit                   same;
         if (!$cast(other, rhs)) begin
            return 0;
         end
         // Through the comparer, so that a mismatch names the fields that differ. compare_field_int() takes 64-bit
         // values; both fields are compared.
         same = comparer.compare_field_int("tag", 64'(tag), 64'(other.tag), $bits(tag));
         same &= comparer.compare_field_int("data", 64'(data), 64'(other.data), $bits(data));
         return same;
      endfunction : do_compare
   endclass : hexk_example_response

   // Scoreboard for responses: the key is the tag. An item is printed on one line by the default item_text(), which
   // calls convert2string() of the item.
   class hexk_example_scoreboard extends hexk_scoreboard #(
       .T  (hexk_example_response),
       .KEY(int unsigned)
   );
      `uvm_component_utils(hexk_example_scoreboard)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      virtual function int unsigned get_key(hexk_example_response item);
         return item.get_tag();
      endfunction : get_key
   endclass : hexk_example_scoreboard

   class hexk_example_test extends uvm_test;
      hexk_objection_aggregator                  objections;
      hexk_scoreboard_cfg                        scoreboard_cfg;
      hexk_example_scoreboard                    scoreboard;
      uvm_analysis_port #(hexk_example_response) predictor_port;
      uvm_analysis_port #(hexk_example_response) monitor_port;

      `uvm_component_utils(hexk_example_test)

      function new(string name, uvm_component parent);
         super.new(name, parent);
      endfunction : new

      function void build_phase(uvm_phase phase);
         super.build_phase(phase);
         objections                  = hexk_objection_aggregator::type_id::create("objections", this);
         objections.poll_interval_ps = `hexk_ps(10ns);
         scoreboard_cfg              = hexk_scoreboard_cfg::type_id::create("scoreboard_cfg");
         scoreboard_cfg.mode         = HEXK_SB_OUT_OF_ORDER;
         // A response that never comes is an error after 1 us, instead of a run phase that never ends.
         scoreboard_cfg.max_wait_ps  = `hexk_ps(1us);
         scoreboard                  = hexk_example_scoreboard::type_id::create("scoreboard", this);
         scoreboard.cfg              = scoreboard_cfg;
         scoreboard.aggregator       = objections;
         predictor_port              = new("predictor_port", this);
         monitor_port                = new("monitor_port", this);
      endfunction : build_phase

      function void connect_phase(uvm_phase phase);
         super.connect_phase(phase);
         predictor_port.connect(scoreboard.expected_export);
         monitor_port.connect(scoreboard.actual_export);
      endfunction : connect_phase

      // A response with the given tag; the data follows from the tag.
      function hexk_example_response response(int unsigned tag);
         hexk_example_response item = hexk_example_response::type_id::create("item");
         item.set(tag, 32'hC0DE_0000 + tag);
         return item;
      endfunction : response

      task run_phase(uvm_phase phase);
         int unsigned answer_order[4] = '{2, 0, 3, 1};
         super.run_phase(phase);
         phase.raise_objection(this, "stimulus");
         for (int unsigned tag = 0; tag < 4; tag++) begin
            predictor_port.write(response(tag));
         end
         phase.drop_objection(this, "stimulus");
         // The DUT answers later and in its own order; the scoreboard holds the phase until then.
         foreach (answer_order[i]) begin
            #20ns;
            monitor_port.write(response(answer_order[i]));
         end
      endtask : run_phase

      // An empty scoreboard reports nothing either: the test checks that its four responses were compared.
      function void check_phase(uvm_phase phase);
         hexk_sb_stats stats = scoreboard.get_stats();
         super.check_phase(phase);
         `hexk_check_eq(stats.matched, 4, "EXAMPLE_MATCHED")
      endfunction : check_phase
   endclass : hexk_example_test

   initial begin
      run_test("hexk_example_test");
   end

endmodule : hexk_scoreboard_example
```
<!-- HEXK_GEN:END example -->

## 8. Anti-patterns

- **Out-of-order mode without `get_key()`.** Every item then has the same key, and each
  write compares with all waiting items. Return what identifies an item on the bus.
- **A key that is not on the bus**, such as a counter of the testbench. The actual item
  cannot have it. Use the tag, ID or address of the protocol.
- **`allow_unexpected` to silence errors.** It means "actual items may come first"; an
  actual item that never gets an expected one is still an error, in `check_phase`.
- **Passing a test because the scoreboard reported nothing.** Nothing written is also
  nothing reported. Check `get_stats().matched` against what the test sent (TST-6).
- **Changing an item after writing it**, or writing one object twice. The scoreboard holds
  the handle. Clone in the monitor, or set `cfg.clone_expected` for the expected side.
- **A fixed delay before the end of the test "so the scoreboard drains".** Give it the
  aggregator and leave `hold_objection` set.
- **One scoreboard class per channel.** Use streams.
- **Not calling `on_reset()`.** Items from before the reset then mismatch everything after
  it.
- **Pairing by a transaction ID inside `compare_items()`.** In mode `HEXK_SB_OUT_OF_ORDER` a
  `compare_items()` that is 1 for "same ID" makes every pair equal, and a wrong payload goes
  unnoticed. Pair by the ID in `is_partner()` and compare the payload in `compare_items()`.
- **`$time` in an override of `get_timestamp_ps()`.** It is in the time unit of the scope of
  the override. Return `hexk_wait_util::now_ps()` or a timestamp of a meta item.

## 9. Status

<!-- HEXK_GEN:BEGIN status -->
| Stability | Since |
|---|---|
| experimental | 0.7.0 |
<!-- HEXK_GEN:END status -->

Where it has been tested: see the top-level `README.md`. The unit tests call the
phase functions themselves; `run_test()` with the example runs in `make examples` on
Questa and VCS.

Cost per pair (an expected and an actual item), measured with `make bench` on VCS X-2025.06 with UVM 2020.3.1 (Linux in WSL, 2026-10-14; two runs, which agreed within 15 percent):

| Case | Time |
|---|---|
| in order | 0.7 us |
| out of order, 1 item waiting under the key | 2.0 us |
| out of order, 16 items waiting under the key | 40 us |
| out of order, 256 items waiting under the key | 650 to 770 us |
| out of order, 256 waiting, `is_partner()` that compares one field | 12 us |

A comparison through `compare()` of UVM costs about 2.5 us, so a key that many waiting items
share makes every write expensive: give the items a key that few items share, or override
`is_partner()` with a cheap test. On Questa 2024.1 (Windows) the same cases took 1.7 to
4.8 us, 3.7 to 13 us, 44 to 79 us and 515 to 844 us in three runs; wall-clock times vary too
much on that machine for more than the order of magnitude.
