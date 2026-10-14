// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_uid_pool.sv
//
// Root of all hexk_uid: a singleton that hands out the top-level IDs, numbered per label,
// and holds the length limit for all IDs. A sequence takes its ID from the pool,
// hexk_uid_pool::get().new_uid("seq_wr"), and gives its items children of that ID.
//
//! @module    hexk_uid
//! @since     0.7.0
//! @stability experimental
//! @emits     HEXK_UID_LENGTH:error HEXK_UID_LABEL:error
//! @plusargs  (none)

`ifndef HEXK_UID_POOL_SV
`define HEXK_UID_POOL_SV

class hexk_uid_pool;

   // Longest text an ID may have; a longer one is an error, and a child that is too long starts a new chain.
   int unsigned       max_length      = 256;

   // Next number per label for the top-level IDs.
   local int unsigned counts[string];

   `hexk_singleton_decl(hexk_uid_pool)

   // Creates the next top-level ID with this label: top-level IDs are numbered per label, from 0.
   function hexk_uid new_uid(string label);
      hexk_uid uid;
      if (!counts.exists(label)) begin
         hexk_uid::check_label(label);
         counts[label] = 0;
      end
      uid = new(null, label, counts[label]);
      counts[label]++;
      if (uid.get_length() > max_length) begin
         `uvm_error("HEXK_UID_LENGTH",
                    $sformatf("%s is %0d characters long, the limit is %0d; use a shorter label or raise max_length",
                              uid.convert2string(), uid.get_length(), max_length))
      end
      return uid;
   endfunction : new_uid

endclass : hexk_uid_pool

`endif  // HEXK_UID_POOL_SV
