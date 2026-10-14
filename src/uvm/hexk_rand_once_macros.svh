// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 HEXK
//
// hexk_rand_once_macros.svh
//
// Macro that makes a class "randomize once": it declares the hexk_rand_once_guard member
// rand_once and a pre_randomize() that asks the guard. Write `hexk_rand_once_guard_decl in
// the body of a class that extends uvm_object, without a semicolon. A class that needs a
// pre_randomize() of its own does not use the macro: it declares the member and calls
// rand_once.on_pre_randomize() from its pre_randomize() itself.
// Include this file through hexk_macros.svh.
//
//! @module    hexk_rand_once
//! @since     0.7.0
//! @stability experimental
//! @emits     (none)
//! @plusargs  (none)

`ifndef HEXK_RAND_ONCE_MACROS_SVH
`define HEXK_RAND_ONCE_MACROS_SVH

// Declares the member rand_once, a pre_randomize() that reports every randomization after a successful one, and a
// post_randomize() that notes a successful one.
`define hexk_rand_once_guard_decl \
   hexk_uvm_pkg::hexk_rand_once_guard rand_once = new(this); \
   function void pre_randomize(); \
      super.pre_randomize(); \
      rand_once.on_pre_randomize(); \
   endfunction : pre_randomize \
   function void post_randomize(); \
      super.post_randomize(); \
      rand_once.on_post_randomize(); \
   endfunction : post_randomize

`endif  // HEXK_RAND_ONCE_MACROS_SVH
